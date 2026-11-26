terraform {
  required_version = ">= 1.8"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.123" # cho phép 0.123.x, không tự nhảy lên 0.124 (có thể đổi schema)
    }
  }
}

provider "proxmox" {
  endpoint = "https://127.0.0.1:8006/" # chạy tofu ngay trên host Proxmox
  insecure = true                      # Proxmox dùng chứng chỉ tự ký
  # Token KHÔNG ghi ở đây: provider tự đọc biến môi trường PROXMOX_VE_API_TOKEN
  # (xem tofu/README.md: export PROXMOX_VE_API_TOKEN="$(cat ~/.config/proxmox/tofu.token)")
}
