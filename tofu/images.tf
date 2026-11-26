# Cloud image Ubuntu 24.04 — pin theo bản phát hành có ngày + checksum (không dùng "current" vì đổi hằng ngày).
# Đổi bản: sửa ubuntu_image_release + checksum (lấy ở https://cloud-images.ubuntu.com/noble/<ngày>/SHA256SUMS).
locals {
  ubuntu_image_release = "20261017"
  ubuntu_image_sha256  = "04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94"
}

resource "proxmox_download_file" "ubuntu_noble" {
  node_name    = var.node_name
  datastore_id = proxmox_storage_directory.local.id
  content_type = "import" # để dùng làm disk.import_from
  url          = "https://cloud-images.ubuntu.com/noble/${local.ubuntu_image_release}/noble-server-cloudimg-amd64.img"
  # File .img của Ubuntu thực chất là qcow2; content "import" chỉ nhận đuôi .qcow2/.raw/.vmdk
  file_name          = "noble-server-cloudimg-amd64-${local.ubuntu_image_release}.qcow2"
  checksum           = local.ubuntu_image_sha256
  checksum_algorithm = "sha256"
  upload_timeout     = 1800
}
