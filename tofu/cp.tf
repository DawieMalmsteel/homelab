# Control-plane k8s-cp1 (VM 201): tạo bằng tay (qm) ngày 2026-11-26, sau đó IMPORT vào tofu.
# Resource này mô tả ĐÚNG VM đang chạy; mục tiêu là plan "no changes" — không phải để tạo lại.
# cp1 chứa etcd = toàn bộ trạng thái cluster -> prevent_destroy chặn mọi plan muốn xoá/tạo lại nó.
import {
  to = proxmox_virtual_environment_vm.cp1
  id = "nixos/201" # <node>/<vmid>
}

resource "proxmox_virtual_environment_vm" "cp1" {
  name      = "k8s-cp1"
  node_name = var.node_name
  vm_id     = 201
  on_boot   = true

  agent { enabled = true }

  cpu {
    cores = 3
    type  = "host"
  }
  memory {
    dedicated = 4096
  }

  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]
  disk {
    datastore_id = "local"
    interface    = "scsi0"
    size         = 30
    file_format  = "raw"
    discard      = "on"
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:E0:0A:9E" # giữ MAC cũ
  }

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
        address = "10.10.10.11/24"
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
    vendor_data_file_id = "local:snippets/k8s-node.yaml" # do NixOS đặt (nixos/homelab.nix)
  }

  lifecycle {
    prevent_destroy = true
  }
}
