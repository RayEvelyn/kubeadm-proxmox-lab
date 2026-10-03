# Local validation record — 2026-10-03

Passed: `terraform init -backend=false`, `terraform fmt -check`, `terraform validate`, Ansible syntax check against sanitized bare-metal inventory, and `bash -n` for all scripts. Provider lock file is included. Documentation addresses and fake public-key placeholders are intentional.

Not executed: Terraform plan against a real endpoint, apply/destroy, SSH bootstrap, Kubernetes API operations, secret creation or publication. Runtime behavior needs an isolated owner-reviewed lab test. No estate configuration or credentials were copied.

The exact 1.35.9-1.1 packages for kubeadm/kubelet/kubectl were confirmed in the official v1.35 apt index. Both pinned Calico 3.33 bootstrap manifests returned HTTP 200. This verifies artifact availability, not cluster convergence.
