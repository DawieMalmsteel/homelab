output "workers" {
  description = "Worker đang quản lý: tên => VMID, IP"
  value       = { for name, w in local.workers : name => "vm ${w.vm_id}, ${w.ip}" }
}
