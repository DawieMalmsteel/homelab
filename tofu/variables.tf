variable "workers" {
  description = "Số VM worker K8s. Giống replicas: tăng -> tạo VM + tự join; giảm -> drain + xoá node + xoá VM (bỏ từ số lớn nhất)."
  type        = number
  default     = 2
  validation {
    condition     = var.workers >= 0 && var.workers <= 4
    error_message = "0..4 worker (laptop 23GB RAM; control-plane + host cũng cần RAM)."
  }
}

variable "worker_cores" {
  type    = number
  default = 2
}

variable "worker_memory_mb" {
  description = "RAM mỗi worker (MB). 4 worker x 3072 + cp 4096 ~ 16GB, còn ~7GB cho host."
  type        = number
  default     = 3072
}

variable "worker_disk_gb" {
  type    = number
  default = 30
}

variable "ssh_public_keys" {
  description = "Public key được đăng nhập user dwcks trong VM (public key, không phải secret)."
  type        = list(string)
}

# --- Thông số hạ tầng cố định (đổi khi đổi Proxmox/mạng) ---
variable "node_name" {
  type    = string
  default = "nixos" # tên node Proxmox (pvesh get /nodes)
}

