# Local validation record — 2026-10-03

Passed: `terraform init -backend=false`, `terraform fmt -check`, `terraform validate`, Ansible syntax check against sanitized bare-metal inventory, and `bash -n` for all scripts. Provider lock file is included. Documentation addresses and fake public-key placeholders are intentional.

Not executed: Terraform plan against a real endpoint, apply/destroy, SSH bootstrap, Kubernetes API operations, secret creation or publication. Runtime behavior needs an isolated owner-reviewed lab test. No estate configuration or credentials were copied.

The exact 1.35.9-1.1 packages for kubeadm/kubelet/kubectl were confirmed in the official v1.35 apt index. Both pinned Calico 3.33 bootstrap manifests returned HTTP 200. This verifies artifact availability, not cluster convergence.

## Manual private CI additions (2026-10-03)

Local checks passed: actionlint (custom homelab label declared), ShellCheck, every Bash script syntax, GitHub/GitLab YAML parsing, and helper fail-closed behavior without private/enabled deployment flags. Terraform fmt, backend-disabled init, validate and Ansible syntax checks passed. The first workflow lint flagged the intentional custom runner label; declaring that label corrected the diagnostic. The initial validation inventory filename was corrected to the existing bare-metal example before final checks. No Terraform plan/apply, SSH bootstrap, real CI deployment or Kubernetes API calls were performed. Runner prerequisites, secrets, TLS/host trust, persistent-state backup and actual first deployment remain unverified. Existing runtime diagnostic limitations above are unchanged.

Publication review correction: platform-prefixed default state IDs prevent cross-platform numeric collisions; an intentional migration retains its original prefixed ID and state. The deploy phase checks SSH_KNOWN_HOSTS before any Terraform execution; provision continues without SSH trust. Actionlint and ShellCheck pass after correction.
