# tofu/ — worker K8s dạng code + hướng dẫn bật/tắt homelab

- [1. Scale worker](#1-scale-worker-như-replicas)
- [2. Bật/tắt homelab](#2-bậttắt-homelab)
- [3. Kiểm tra sau khi bật](#3-kiểm-tra-sau-khi-bật)
- [4. Sự cố thường gặp](#4-sự-cố-thường-gặp)
- [5. Tofu quản lý gì](#5-tofu-quản-lý-gì)
- [6. Thành phần ngoài Git](#6-thành-phần-ngoài-git)

Mọi lệnh dưới đây chạy **trên laptop NixOS** (`ssh dwcks@192.168.101.14` hoặc terminal trên máy).

---

## 1. Scale worker (như `replicas`)

```bash
cd ~/Projects/homelab/tofu
nvim terraform.tfvars      # workers = 3   (0..4)
tofu plan                  # xem trước: tạo/xoá VM nào
tofu apply                 # gõ yes
```

| Worker thứ i | Tên | VMID | IP | Tài nguyên |
|---|---|---|---|---|
| 1..4 | `k8s-worker-<i>` | `210+i` | `10.10.10.(20+i)` | 2 vCPU, 3GB RAM, 30GB |

- **Tăng**: tạo đĩa từ cloud image Ubuntu (`images.tf`, `disk.import_from`) → cloud-init (`local:snippets/k8s-worker.yaml`) cài containerd/kubeadm → `kubeadm join` → đợi node Ready → gắn nhãn `node-role.kubernetes.io/worker`. (~3–4 phút)
- **Giảm** (bỏ số lớn nhất trước): `kubectl drain` + `kubectl delete node` → xoá VM. (~10 giây)
- Control-plane `k8s-cp1` (VM 201) cũng do tofu quản lý (`cp.tf`, **import** từ VM tạo tay), có `prevent_destroy`: mọi plan muốn xoá/tạo lại cp1 sẽ bị chặn. Không scale được (chỉ 1 control-plane).
- **Đừng** tạo/xoá worker bằng `qm` hay web UI: state của tofu sẽ lệch với thực tế.

Hàm shell `tofu` (khai báo trong `nixos/homelab.nix`) tự nạp API token cho riêng lệnh đó.

---

## 2. Bật/tắt homelab

### Bức tranh: ai bật/tắt ai

```
Laptop NixOS (host)
 └─ Proxmox VE (các service pve-*)
     └─ pve-guests.service
          ├─ lúc BOOT : "startall" -> bật mọi VM có onboot=1   (201, 211, 212 đều onboot=1)
          └─ lúc TẮT  : tắt lần lượt từng VM qua ACPI/qemu-guest-agent, đợi xong mới tắt host
              └─ VM 201 k8s-cp1        (etcd, API server)
              └─ VM 211..21N workers   (pod của bạn)
```

=> Tắt/bật **laptop** là đủ, Proxmox tự lo tắt/bật VM đúng cách. Chỉ cần làm tay khi muốn
tắt cluster mà **giữ laptop chạy**.

### Kịch bản A — Tắt hẳn laptop (không dùng nữa)

```bash
sudo systemctl poweroff
```

Diễn biến: pve-guests gửi lệnh shutdown cho từng VM → Ubuntu trong VM tắt sạch
(containerd dừng container, etcd ghi đĩa) → host tắt. Mất ~1–2 phút. **Không** cần drain.

> Không rút điện / giữ nút nguồn khi đang chạy: etcd của control-plane có thể hỏng dữ liệu.

**Bật lại**: bấm nút nguồn. Laptop tự vào WiFi → Proxmox lên → pve-guests bật 3 VM →
~2–3 phút sau cluster Ready. Nếu bật máy và đăng nhập GNOME không cần thiết: máy vẫn chạy
server bình thường ở màn hình đăng nhập.

### Kịch bản B — Tắt cluster K8s, giữ laptop chạy (để giải phóng ~10GB RAM)

```bash
# Tắt: worker trước, control-plane sau cùng
for id in 212 211 201; do sudo qm shutdown $id --timeout 180; done

# Bật: control-plane trước, đợi API server lên rồi mới bật worker
sudo qm start 201
until kubectl get --raw=/readyz >/dev/null 2>&1; do sleep 5; done
for id in 211 212; do sudo qm start $id; done
```

Vì sao có thứ tự? Worker phụ thuộc vào control-plane (API server, etcd). Tắt worker trước
để pod dừng khi control-plane còn ghi nhận được; bật control-plane trước để worker lên là
đăng ký được ngay (bật ngược thứ tự vẫn tự hồi phục, chỉ chậm hơn và log nhiều lỗi).

> Worker là VM do tofu quản lý (`started = true` mặc định). Nếu đang tắt mà chạy `tofu apply`,
> tofu sẽ **bật chúng lên lại** — đó là tofu "sửa lệch" về đúng code, không phải lỗi.

Danh sách VMID hiện tại: `sudo qm list` (worker = 211.. theo `workers`).

### Kịch bản C — Bỏ hẳn worker (xoá VM, tiết kiệm cả RAM lẫn ổ đĩa)

```bash
cd ~/Projects/homelab/tofu
nvim terraform.tfvars      # workers = 0
tofu apply
```

Pod sẽ Pending vì control-plane có taint `NoSchedule`. Muốn chạy pod trên mỗi control-plane:

```bash
kubectl taint node k8s-cp1 node-role.kubernetes.io/control-plane:NoSchedule-   # gỡ taint
kubectl taint node k8s-cp1 node-role.kubernetes.io/control-plane:NoSchedule    # đặt lại
```

Muốn có lại worker: `workers = 2` rồi `tofu apply` (VM mới, ổ đĩa mới; PVC local-path trên
worker cũ **mất**).

### Kịch bản D — Khởi động lại laptop (sau khi rebuild NixOS đổi kernel, ...)

```bash
sudo systemctl reboot
```

Như A rồi tự bật lại. Chỉ cần thiết khi đổi kernel/driver; đổi config bình thường thì
`rebuild` là đủ, không phải reboot.

### Không muốn VM tự bật khi mở laptop

```bash
# cả cp1 lẫn worker đều do tofu quản lý: sửa on_boot = false trong cp.tf / workers.tf rồi tofu apply
# (đừng dùng qm set: lần tofu apply sau sẽ sửa lại cho khớp code)
```

### Tóm tắt

| Muốn | Lệnh | Tiết kiệm |
|---|---|---|
| Tắt hết | `sudo systemctl poweroff` | Điện, toàn bộ |
| Tắt cluster, giữ host | `for id in 212 211 201; do sudo qm shutdown $id; done` | ~10GB RAM |
| Bỏ worker | `workers = 0` + `tofu apply` | RAM + ổ đĩa (xoá VM) |
| Bật lại cluster | `qm start 201` → đợi `/readyz` → `qm start 211 212` | |

---

## 3. Kiểm tra sau khi bật

```bash
sudo qm list                                   # VM: running
kubectl get nodes                              # tất cả Ready (đợi 1–3 phút)
kubectl get pods -A | grep -vE "Running|Completed"   # chỉ còn dòng tiêu đề là tốt
curl -s -o /dev/null -w "%{http_code}\n" http://10.10.10.50/   # Traefik: 404 là đúng (chưa khớp host)
tofu plan                                      # "No changes" = VM khớp code
```

Từ máy khác trong LAN: http://hello.192.168.101.14.nip.io, Proxmox UI https://192.168.101.14:8006.

---

## 4. Sự cố thường gặp

| Triệu chứng | Nguyên nhân hay gặp | Cách xử lý |
|---|---|---|
| Node `NotReady` vài phút sau khi bật | kubelet/Calico đang khởi động | Đợi 2–3 phút; vẫn vậy: `ssh -J dwcks@192.168.101.14 dwcks@10.10.10.2x sudo journalctl -u kubelet -n 50` |
| `kubectl` báo `connection refused` | VM 201 chưa lên / API server chưa sẵn sàng | `sudo qm status 201`; đợi `kubectl get --raw=/readyz` trả `ok` |
| Máy khác trong LAN không vào được `192.168.101.14` | Router cấp IP DHCP khác cho laptop | Xem `ip -4 addr show wlp2s0`; đặt DHCP reservation trên router |
| `qm shutdown` treo tới timeout | qemu-guest-agent trong VM không trả lời | `sudo qm stop <id>` (như rút điện VM — tránh dùng với 201) |
| `tofu apply` muốn tạo lại/bật VM | Ai đó sửa VM bằng `qm`/web UI | Xem `tofu plan` kỹ; sửa code cho khớp hoặc để tofu đưa về đúng code |
| Worker mới không join | Token trong snippet bị xoá | `./gen-worker-snippet.sh` rồi tạo lại worker đó |

Chứng chỉ của cluster kubeadm hết hạn sau **1 năm** (từ 2026-11-26). Tắt lâu rồi bật lại
quá hạn đó sẽ lỗi TLS — gia hạn: trên cp1 `sudo kubeadm certs renew all` rồi restart các pod static.
Xem hạn: `ssh -J dwcks@192.168.101.14 dwcks@10.10.10.11 sudo kubeadm certs check-expiration`.

---

## 5. Tofu quản lý gì

| File | Resource |
|---|---|
| `storage.tf` | Storage `local` (import), bật content `import` |
| `images.tf` | Cloud image Ubuntu 24.04 (pin ngày + sha256) |
| `cp.tf` | VM 201 `k8s-cp1` (import, `prevent_destroy`) |
| `workers.tf` | VM worker `k8s-worker-<i>` (`workers = N`) |

Không do tofu quản lý (cố ý): Proxmox/mạng/host (NixOS flake), snippet `k8s-node.yaml` (NixOS chép từ `nixos/k8s-node.yaml` mỗi lần rebuild), user/token `tofu@pve` (tofu cần nó để chạy), snippet `k8s-worker.yaml` (chứa token join).

## 6. Thành phần ngoài Git

| Thứ | Ở đâu | Tạo lại |
|---|---|---|
| API token `tofu@pve!tofu` | `~/.config/proxmox/tofu.token` (600) | `sudo pveum user token remove tofu@pve tofu` rồi `sudo pveum user token add tofu@pve tofu --privsep 0` (ghi giá trị vào file trên) |
| Snippet join (có bootstrap token) | `/var/lib/vz/snippets/k8s-worker.yaml` (root 600) | `./gen-worker-snippet.sh` |
| State | `terraform.tfstate` (gitignore) | Mất thì `tofu import` lại từng VM |
