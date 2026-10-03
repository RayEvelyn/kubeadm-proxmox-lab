resource "proxmox_virtual_environment_vm" "node" {
  for_each  = var.nodes
  name      = each.key
  node_name = var.proxmox_node
  vm_id     = each.value.vm_id
  clone {
    vm_id        = var.template_vm_id
    full         = true
    datastore_id = var.datastore
  }
  agent { enabled = true }
  cpu {
    cores = each.value.cores
    type  = "host"
  }
  memory { dedicated = each.value.memory_mb }
  disk {
    datastore_id = var.datastore
    interface    = "scsi0"
    size         = each.value.disk_gb
  }
  network_device {
    bridge = var.bridge
    model  = "virtio"
  }
  initialization {
    datastore_id = var.datastore
    dns { servers = var.dns_servers }
    ip_config {
      ipv4 {
        address = each.value.address
        gateway = var.gateway
      }
    }
    user_account {
      username = "ubuntu"
      keys     = var.ssh_public_keys
    }
  }
  # Rebuilds/deletions must be an explicit source change after backups.
  lifecycle { prevent_destroy = true }
}
