terraform {
  backend "local" {}
  required_version = ">= 1.6, < 2.0"
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "0.115.0" }
  }
}
# PROXMOX_VE_ENDPOINT and PROXMOX_VE_API_TOKEN stay outside Terraform state inputs.
provider "proxmox" { insecure = false }
