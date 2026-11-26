# Worker thứ i (i = 1..workers):
#   tên k8s-worker-<i>  |  VMID 210+i  |  IP 10.10.10.(20+i)
locals {
  workers = {
    for i in range(1, var.workers + 1) : "k8s-worker-${i}" => {
      vm_id = 210 + i
      ip    = "10.10.10.${20 + i}"
    }
  }
}

resource "proxmox_virtual_environment_vm" "worker" {
  # for_each theo TÊN (không dùng count): bỏ worker-4 không làm worker-1..3 bị đánh số lại/tạo lại.
  for_each = local.workers

  name      = each.key # cloud-init cũng dùng tên này làm hostname -> tên node K8s
  node_name = var.node_name
  vm_id     = each.value.vm_id
  tags      = ["k8s", "worker", "tofu"]
  on_boot   = true # tự bật cùng host (như VM 201)


  agent { enabled = true } # qemu-guest-agent: tắt VM sạch, Proxmox thấy IP

  cpu {
    cores = var.worker_cores
    type  = "host"
  }
  memory {
    dedicated = var.worker_memory_mb
    # Bật balloon device (min = max nên không bao giờ thu hồi RAM): driver balloon trong VM
    # báo RAM trống thật ra ngoài -> Proxmox hiển thị đúng thay vì tính cả page cache.
    floating = var.worker_memory_mb
  }

  scsi_hardware = "virtio-scsi-single"
  disk {
    datastore_id = "local"
    interface    = "scsi0"
    # Tạo đĩa từ cloud image (images.tf) thay vì clone template. Chỉ dùng lúc TẠO VM.
    import_from = proxmox_download_file.ubuntu_noble.id
    size        = var.worker_disk_gb
    file_format = "raw"
    discard     = "on"
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  # Cloud image Ubuntu chỉ có console serial (giống template).
  serial_device {}
  vga {
    type = "serial0"
  }
  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = "local"
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "10.10.10.1"
      }
    }
    dns {
      servers = ["10.10.10.1"]
    }
    user_account {
      username = "dwcks"
      keys     = var.ssh_public_keys
    }
    # = k8s-node.yaml + kubeadm join (sinh bởi gen-worker-snippet.sh, không nằm trong Git)
    vendor_data_file_id = "local:snippets/k8s-worker.yaml"
  }

  # Khi TẠO: đợi VM tự join (cloud-init ~2-3 phút) rồi gắn nhãn role.
  # (kubelet không được tự gắn nhãn node-role.* cho chính nó, nên phải làm từ ngoài)
  provisioner "local-exec" {
    command = <<-EOT
      for i in $(seq 1 60); do kubectl get node ${self.name} >/dev/null 2>&1 && break; sleep 10; done
      kubectl wait --for=condition=Ready node/${self.name} --timeout=300s
      kubectl label node ${self.name} node-role.kubernetes.io/worker= --overwrite
    EOT
  }

  # Khi GIẢM workers: trước khi xoá VM, đuổi pod sang node khác rồi xoá node khỏi cluster.
  # (destroy-time provisioner chỉ được dùng self.*)
  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = <<-EOT
      kubectl drain ${self.name} --ignore-daemonsets --delete-emptydir-data --timeout=180s
      kubectl delete node ${self.name} --ignore-not-found
    EOT
  }

  lifecycle {
    # Đổi snippet/image SAU khi tạo không được ép tạo lại VM đang chạy.
    # clone: worker-1/2 được tạo từ template 9000 cũ, state còn lưu khối clone.
    ignore_changes = [clone, disk[0].import_from, initialization[0].vendor_data_file_id]
  }
}
