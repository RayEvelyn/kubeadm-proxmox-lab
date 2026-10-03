variable "proxmox_node" { type = string }
variable "template_vm_id" { type = number }
variable "datastore" { type = string }
variable "bridge" { type = string }
variable "gateway" { type = string }
variable "dns_servers" { type = list(string) }
variable "ssh_public_keys" {
  type = list(string)
  validation {
    condition     = length(var.ssh_public_keys) > 0 && alltrue([for k in var.ssh_public_keys : can(regex("^ssh-(ed25519|rsa) ", k))])
    error_message = "Provide SSH public keys; never private-key material."
  }
}
variable "nodes" {
  type = map(object({ vm_id = number, address = string, control_plane = bool, cores = number, memory_mb = number, disk_gb = number }))
  validation {
    condition     = length([for n in var.nodes : n if n.control_plane]) == 1
    error_message = "This beginner lab supports exactly one control plane; HA needs a separate design."
  }
}
