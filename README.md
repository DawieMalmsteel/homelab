# homelab

Laptop NixOS chạy Proxmox VE (proxmox-nixos), trên đó là cluster K8s 3 node (kubeadm) quản lý bằng ArgoCD.
Repo này là nguồn sự thật cho cả HOST (NixOS flake) lẫn CLUSTER (ArgoCD).

```
flake.nix / flake.lock  cấu hình host dạng flake; lock khoá chính xác nixpkgs + proxmox-nixos
nixos/
  configuration.nix       config gốc (từ bộ cài NixOS), import 2 file dưới
  hardware-configuration.nix  ổ đĩa, kernel module (sinh bởi nixos-generate-config)
  homelab.nix             Proxmox, mạng NAT vmbr0, port forward, fcitx5, bàn phím, tools
  k8s-node.yaml           cloud-init snippet cho VM K8s (/var/lib/vz/snippets/)
argocd/
  root.yaml               app-of-apps, apply tay MỘT lần để bootstrap
  apps/*.yaml             mỗi file = 1 Application con (ArgoCD tự đọc)
tofu/                   OpenTofu: số VM worker K8s (workers = N), xem tofu/README.md
k8s/                    manifest thật mà các Application trỏ tới
  demo/  metallb/  argocd/  traefik/  monitoring/ (helm values kube-prometheus-stack)
```

## Host (NixOS flake)

```bash
rebuild                                   # = sudo nixos-rebuild switch --flake ~/Projects/homelab#nixos
nixos-rebuild build --flake .#nixos && nix store diff-closures /run/current-system ./result   # xem trước thay đổi
nix flake update && rebuild               # nâng cấp nixpkgs/proxmox-nixos (commit flake.lock sau đó)
sudo nixos-rebuild switch --rollback      # quay lại generation trước
```

Lưu ý: flake chỉ thấy file đã `git add`. Tạo file .nix mới mà quên add -> lỗi "path does not exist".
`/etc/nixos` không còn dùng (bản cũ ở `/etc/nixos.pre-flake`).

## Luồng GitOps

```
sửa file trong k8s/ -> git push -> ArgoCD (poll ~3 phút) thấy commit mới -> sync lên cluster
```

Thêm app mới: tạo `k8s/<app>/` + `argocd/apps/<app>.yaml`, push. `root` tự tạo Application mới.

## Addon cài tay (chưa qua ArgoCD)

| Thành phần | Cách cài |
|---|---|
| Calico v3.33.1 | tigera-operator + custom-resources (pod CIDR 10.244.0.0/16) |
| local-path-provisioner v0.0.37 | manifest chính thức, đặt làm default StorageClass |
| metrics-server v0.9.1 | manifest chính thức + `--kubelet-insecure-tls` |
| MetalLB v0.16.2 | metallb-native.yaml (config pool nằm trong `k8s/metallb/`) |
| Traefik chart 43.0.0 | `helm upgrade --install traefik traefik/traefik -n traefik -f k8s/traefik/values.yaml` |
| ArgoCD v3.6.3 | install.yaml (server-side apply) + `server.insecure=true` |
| kube-prometheus-stack 93.11.1 | `helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 93.11.1 -n monitoring -f k8s/monitoring/values.yaml` (Secret `grafana-admin` tạo tay) |
