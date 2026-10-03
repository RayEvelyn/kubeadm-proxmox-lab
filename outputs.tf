output "ansible_inventory" {
  value = {
    all = {
      vars = { ansible_user = "ubuntu" }
      children = {
        control_plane = { hosts = { for name, n in var.nodes : name => { ansible_host = split("/", n.address)[0] } if n.control_plane } }
        workers       = { hosts = { for name, n in var.nodes : name => { ansible_host = split("/", n.address)[0] } if !n.control_plane } }
      }
    }
  }
}
