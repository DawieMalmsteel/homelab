{
  description = "homelab: laptop NixOS chạy Proxmox VE + cluster K8s (ArgoCD)";

  # Nguyên liệu. Phiên bản CHÍNH XÁC của từng cái được ghi trong flake.lock.
  #   Cập nhật: nix flake update            (tất cả)
  #             nix flake update nixpkgs    (chỉ nixpkgs)
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Không cho proxmox-nixos "follows" nixpkgs của mình: README dự án chỉ test với nixpkgs-stable của họ.
    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";
  };

  outputs = { self, nixpkgs, proxmox-nixos, ... }: {
    # Build:  sudo nixos-rebuild switch --flake ~/Projects/homelab#nixos
    #                                                              ^^^^^ tên output dưới đây
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      # Biến truyền thêm vào mọi module (homelab.nix nhận proxmox-nixos qua đây).
      specialArgs = { inherit proxmox-nixos; };
      modules = [
        ./nixos/configuration.nix # import tiếp hardware-configuration.nix + homelab.nix

        {
          # `nixos-version --configuration-revision` cho biết hệ thống đang chạy build từ commit nào.
          system.configurationRevision = self.rev or self.dirtyRev or null;

          # Cho các lệnh cũ (nix-shell -p, <nixpkgs>) và lệnh mới (nix shell nixpkgs#...)
          # dùng CÙNG nixpkgs đã khoá trong flake.lock, thay vì channel trên máy.
          nix.nixPath = [ "nixpkgs=${nixpkgs}" ];
          nix.registry.nixpkgs.flake = nixpkgs;
        }
      ];
    };
  };
}
