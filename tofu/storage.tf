# Storage "local" (/var/lib/vz) là storage mặc định Proxmox tự có (không nằm trong /etc/pve/storage.cfg).
# Đưa vào tofu để bật thêm content "import": cần cho disk.import_from (tạo đĩa VM thẳng từ cloud image).
import {
  to = proxmox_storage_directory.local
  id = "local"
}

resource "proxmox_storage_directory" "local" {
  id      = "local"
  path    = "/var/lib/vz"
  shared  = false # thư mục trên đĩa laptop, không phải storage dùng chung (NFS/Ceph)
  content = ["backup", "images", "import", "iso", "rootdir", "snippets", "vztmpl"]
}
