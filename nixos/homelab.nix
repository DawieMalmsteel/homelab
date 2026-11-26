# Module homelab: laptop NixOS chạy Proxmox VE (qua dự án proxmox-nixos).
# Được import từ nixos/configuration.nix; flake.nix truyền proxmox-nixos vào qua specialArgs.
#
# Mạng: laptop chỉ có WiFi, mà WiFi không bridge được -> VM nằm trong mạng NAT riêng:
#
#   Internet <-> router 192.168.101.1 <-> wlp2s0 (192.168.101.14)
#                                            | NAT (masquerade)
#                                         vmbr0 (10.10.10.1/24) <-> VM 10.10.10.x (DHCP từ dnsmasq)
{ config, pkgs, lib, proxmox-nixos, ... }:
let
  bridgeIP = "10.10.10.1";
in
{
  imports = [ proxmox-nixos.nixosModules.proxmox-ve ];

  # ---------- Laptop chạy như server ----------
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };
  services.displayManager.gdm.autoSuspend = false;

  # ---------- Quyền ----------
  # User wheel (dwcks) sudo không cần password, để Claude tự quản lý máy qua SSH.
  # Đánh đổi: ai có SSH key của dwcks là có root. Muốn tắt: xoá dòng này rồi rebuild.
  security.sudo.wheelNeedsPassword = false;

  # ---------- Proxmox VE ----------
  services.proxmox-ve = {
    enable = true;
    # IP mà hostname của node trỏ tới (pve-cluster yêu cầu không phải 127.0.0.1).
    # Dùng IP bridge vì nó cố định, không đổi theo DHCP của WiFi.
    ipAddress = bridgeIP;
    bridges = [ "vmbr0" ]; # cho bridge hiện trong giao diện web
  };
  nixpkgs.overlays = [ proxmox-nixos.overlays.x86_64-linux ];

  # Cloud-init snippet cho VM K8s: NixOS chép file trong repo vào storage "local" mỗi lần rebuild.
  # (Proxmox không có API upload snippet -> để host, nơi đã do NixOS quản lý, đặt file.)
  # Activation script chạy mỗi lần switch + boot -> luôn ghi đè bằng bản trong repo.
  # (Không dùng systemd.tmpfiles C/C+: chúng chỉ chép khi file đích CHƯA tồn tại.)
  # k8s-worker.yaml (chứa token join) KHÔNG ở đây: sinh bởi tofu/gen-worker-snippet.sh.
  system.activationScripts.k8sNodeSnippet = ''
    install -D -m 0644 -o root -g root ${./k8s-node.yaml} /var/lib/vz/snippets/k8s-node.yaml
  '';

  # proxmox-nixos chỉ đưa genisoimage/bash vào PATH của vài service. Thiếu chúng thì service không tạo
  # được ổ cloud-init khi bật VM. Đã gặp (2026-11-26): `qm reboot 201` tắt VM xong nhưng qmeventd
  # (service lo bước "bật lại") lỗi "No such file or directory" -> VM nằm stopped, API K8s down.
  # KHÔNG thêm pve-guests: đổi unit của nó -> NixOS restart nó -> ExecStop TẮT TOÀN BỘ VM.
  systemd.services = lib.genAttrs [ "qmeventd" "pvedaemon" "pvescheduler" ] (_: {
    path = [ pkgs.bash pkgs.cdrkit pkgs.qemu-utils ];
  });

  # Cache build sẵn của proxmox-nixos (không có thì phải tự compile, rất lâu).
  nix.settings = {
    # Bật lệnh nix mới (nix build/run/shell/flake ...) và flakes.
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [ "https://cache.saumon.network/proxmox-nixos" ];
    trusted-public-keys = [ "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM=" ];
  };

  # ---------- Mạng cho VM ----------
  # Bridge không gắn card vật lý nào; VM cắm vào đây qua tap interface.
  networking.bridges.vmbr0.interfaces = [ ];
  networking.interfaces.vmbr0.ipv4.addresses = [ { address = bridgeIP; prefixLength = 24; } ];
  # Để NetworkManager không đụng vào bridge (nó chỉ quản lý WiFi).
  networking.networkmanager.unmanaged = [ "vmbr0" ];

  # NAT: VM đi ra Internet qua WiFi bằng IP của laptop.
  networking.nat = {
    enable = true;
    internalInterfaces = [ "vmbr0" ];
    externalInterface = "wlp2s0";
    # Port forward từ LAN vào VM (DNAT): gọi 192.168.101.14:<sourcePort> -> VM.
    forwardPorts = [
      # Kubernetes API của control-plane k8s-cp1 -> dùng kubectl từ máy Ubuntu
      { sourcePort = 6443; destination = "10.10.10.11:6443"; proto = "tcp"; }
      # HTTP/HTTPS -> Traefik ingress (IP cố định do MetalLB cấp, xem k8s/traefik-values.yaml)
      { sourcePort = 80; destination = "10.10.10.50:80"; proto = "tcp"; }
      { sourcePort = 443; destination = "10.10.10.50:443"; proto = "tcp"; }
    ];
  };

  # DHCP + DNS cho VM trên vmbr0 (VM tự nhận IP 10.10.10.100-200).
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false; # không thay DNS của chính laptop
    settings = {
      interface = "vmbr0";
      bind-interfaces = true;
      dhcp-range = "10.10.10.100,10.10.10.200,12h";
      dhcp-option = [ "option:router,${bridgeIP}" "option:dns-server,${bridgeIP}" ];
    };
  };

  # ---------- Tailscale (VPN riêng) ----------
  # Laptop vào tailnet: ở ngoài nhà vẫn ssh / mở Proxmox UI qua tên "nixos" (MagicDNS).
  # App trong K8s KHÔNG đi qua đây mà qua Tailscale Kubernetes Operator (argocd/apps/tailscale-operator.yaml).
  services.tailscale = {
    enable = true;
    openFirewall = true; # UDP 41641: kết nối trực tiếp P2P thay vì đi vòng qua relay (DERP)
  };

  # ---------- Monitoring ----------
  # node-exporter trên chính laptop: Prometheus (trong K8s) scrape 10.10.10.1:9100 để theo dõi RAM/CPU/disk
  # của HOST — giới hạn thật của cả homelab (VM nào cũng lấy RAM từ đây).
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = bridgeIP; # chỉ nghe trên vmbr0, không lộ ra WiFi/LAN
    enabledCollectors = [ "systemd" ];
  };

  # ---------- Firewall ----------
  networking.firewall = {
    allowedTCPPorts = [
      8006 # Proxmox web UI (https://192.168.101.14:8006)
      6443 # forward vào Kubernetes API (k8s-cp1)
      80   # forward vào Traefik
      443  # forward vào Traefik
    ];
    interfaces.vmbr0.allowedUDPPorts = [ 53 67 ]; # DNS + DHCP cho VM
    interfaces.vmbr0.allowedTCPPorts = [ 53 9100 ]; # DNS, node-exporter (Prometheus trong K8s scrape)
  };

  # ---------- Gõ tiếng Việt: fcitx5 + Bamboo ----------
  # GNOME mặc định dùng IBus; đặt type = "fcitx5" thì NixOS thay IBus bằng fcitx5
  # và tự set biến môi trường (XMODIFIERS, QT_IM_MODULE...) + autostart fcitx5 khi đăng nhập.
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = [ pkgs.fcitx5-bamboo ]; # bộ gõ tiếng Việt (Telex/VNI), thay cho Unikey
    # Profile mặc định: 2 bộ gõ, chuyển qua lại bằng Ctrl+Space.
    # Đây là mặc định hệ thống (/etc/xdg/fcitx5); chỉnh trong fcitx5-configtool sẽ lưu vào ~/.config/fcitx5 và được ưu tiên.
    fcitx5.settings.inputMethod = {
      GroupOrder."0" = "Default";
      "Groups/0" = {
        Name = "Default";
        "Default Layout" = "us";
        DefaultIM = "bamboo";
      };
      "Groups/0/Items/0".Name = "keyboard-us";
      "Groups/0/Items/1".Name = "bamboo";
    };
  };
  # Module fcitx5 chỉ đặt các biến này trong shell (/etc/set-environment), session GNOME không đọc file đó.
  # sessionVariables đi qua PAM (/etc/pam/environment) -> áp cho cả gnome-session + systemd --user.
  environment.sessionVariables = {
    GTK_IM_MODULE = "fcitx";
    QT_IM_MODULE = "fcitx";
    XMODIFIERS = "@im=fcitx";
  };
  # GNOME (Wayland) không có khay hệ thống: extension Kimpanel (cài ở systemPackages bên dưới)
  # hiện icon + trạng thái bộ gõ trên thanh trên cùng.
  # Bật sẵn extension cho mọi user (giá trị mặc định; user tự đổi trong app Extensions vẫn được).
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/shell".enabled-extensions = [ "kimpanel@kde.org" ];
      # Caps Lock -> Escape (GNOME Wayland đọc xkb-options từ dconf, không đọc services.xserver.xkb)
      settings."org/gnome/desktop/input-sources".xkb-options = [ "caps:escape" ];
    }
  ];

  # Caps Lock -> Escape cho màn hình đăng nhập GDM (X11/xkb) và TTY (Ctrl+Alt+F3...).
  services.xserver.xkb.options = "caps:escape";
  console.useXkbConfig = true;

  # ---------- Công cụ dòng lệnh ----------
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
  programs.fzf.keybindings = true;

  # kubectl: gõ "k" thay cho "kubectl", Tab vẫn gợi ý được (namespace, pod, ...).
  programs.bash.interactiveShellInit = ''
    alias k=kubectl
    # Áp dụng config từ repo (flake). Dùng: rebuild   hoặc   rebuild --show-trace
    alias rebuild="sudo nixos-rebuild switch --flake ~/Projects/homelab#nixos"
    source <(kubectl completion bash)
    complete -o default -F __start_kubectl k
    # tofu: tự nạp token Proxmox cho RIÊNG lệnh này (không export vào shell)
    tofu() { PROXMOX_VE_API_TOKEN="$(cat ~/.config/proxmox/tofu.token)" command tofu "$@"; }
  '';

  environment.systemPackages = with pkgs; [
    yazi
    ripgrep
    kubectl
    k9s
    kubernetes-helm # helm: cài chart (Traefik, kube-prometheus-stack)
    kitty # terminal emulator (GPU)
    wl-clipboard # wl-copy / wl-paste: clipboard trên GNOME Wayland
    opentofu # IaC (fork mã nguồn mở của Terraform), quản lý VM worker trong tofu/
    jq
    openssl
    # proxmox-nixos chỉ đưa 2 tool này vào PATH của service, không vào shell.
    # Thiếu chúng thì lệnh `qm` chạy tay không tạo được ổ cloud-init.
    cdrkit     # genisoimage
    qemu-utils # qemu-img
    gnomeExtensions.kimpanel # panel cho fcitx5 trên GNOME
    git
    gh # GitHub CLI: gh auth login, gh repo create
  ];
}
