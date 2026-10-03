# Learn Kubernetes with kubeadm on Proxmox or bare metal

Start with [GitOps, the bootstrap order, and why the repos are separate](docs/START-HERE.md).

Build a small private lab that teaches what a Kubernetes distribution normally hides: node preparation, CRI runtime, kubelet, control plane, worker registration and pod networking. Terraform clones the guests; Ansible installs Kubernetes. Start with one control plane and two workers. This teaches scheduling and multi-node networking while remaining easy to rebuild; one control plane is a single point of failure.

The **API server** accepts authenticated requests; **etcd** stores cluster state; **scheduler** chooses a node; **controllers** reconcile desired state; **kubelet** manages pods on each node; **containerd** runs their containers. A **CNI** gives pods networking. Kubernetes needs both the node network and separate non-overlapping pod/service address spaces.


## Capacity and reachability before deployment

The checked-in VM example allocates **three guests, each 4 vCPU, 8 GiB RAM and 40 GiB disk**: 12 allocated vCPU, 24 GiB RAM and 120 GiB guest disks before Proxmox, runner, template and workload overhead. These are example allocations, not a minimum hardware specification or throughput benchmark. If you cannot spare this, use the documented bare-metal path only on suitable dedicated hosts or first reduce the reviewed topology; do not blindly apply the three-guest example.

**No GPU is required** for this DNS, Kubernetes, Rancher, telemetry or tunnel lesson. AI inference is a separate optional workload: model size, precision, context and concurrency determine RAM/VRAM requirements; these examples do not reserve or promise that capacity. Account separately for the chosen runner, GitLab if self-hosted, host OS and existing services. Check `free -h`, `df -h`, and Proxmox `pvesm status`/`pvesh get /nodes/YOUR_NODE/status` on the actual intended machines. On an existing cluster compare allocatable and requested resources with `kubectl describe nodes` and storage/PVC inventory before adding LGTM.

| Initiator | Destination and port | Purpose / when needed |
| --- | --- | --- |
| Workstation | Selected GitHub or GitLab HTTPS 443 (or configured trusted local TLS port) | Clone, CLI API and pipeline control; not a substitute for runner network reach |
| Dedicated selected runner | Proxmox TLS API TCP 8006 | VM Terraform path only; trust its CA, keep management outside DMZ |
| Dedicated selected runner | Intended guest TCP 22 | Reviewed SSH/bootstrap paths; pin unique host keys |
| Runner / guests | Approved package and container registries TCP 443 | Downloads; add only repository-specific approved HTTP 80 sources if required |
| Workload runner | Intended Kubernetes TLS API TCP 6443, or configured KAS TLS route | Manifest/Helm paths only; scoped credentials and verified TLS |
| Trusted LAN DNS clients | Intended DNS server UDP and TCP 53 | DNS paths only; deliberate listener and narrow ACL/firewall, not demo high ports |
| DMZ tunnel host | Cloudflare UDP/TCP 7844 and approved HTTPS 443 | Cloudflare connector/install path only; no inbound router forward |

A hosted GitHub validation runner has **no assumed route to your private LAN**. Configure only the selected private execution runner with necessary routes, DNS and firewall permissions. Keep DMZ-to-LAN/admin denial intact; tunnel connectivity alone does not segment your network. Test the selected route from the actual runner with TLS-verifying `curl`, pinned-key SSH and the README runtime commands before deploying, rather than opening management broadly.


## Reviewed versions and networking

Pins checked against official sources on 2026-10-03: Kubernetes **1.35.9**, Debian packages **1.35.9-1.1**, official `pkgs.k8s.io` v1.35 repository, Calico **3.33.0** (tested with Kubernetes 1.35), Ubuntu **24.04**. Ubuntu's supported containerd package receives OS security updates; its generated configuration enables CRI and systemd cgroups. Kubernetes packages are held to avoid accidental upgrades.

Calico 3.33's v3 CRDs on Kubernetes 1.35 require `MutatingAdmissionPolicy`; the versioned kubeadm config explicitly enables it and installs the matching v1beta1 CRDs before the operator. VXLAN is configured, with BGP disabled. Allow node-to-node UDP 4789, private control-plane TCP 6443, control-plane-to-node TCP 10250 and normal SSH/DNS/NTP/HTTPS egress through your IaC firewall policy. Never expose etcd 2379/2380 or API 6443 publicly. Firewall rules are not automatically disabled by the playbook.

Pods use `10.244.0.0/16`, Services `10.96.0.0/12`. Change the kubeadm and Calico config together **before the first bootstrap** if these overlap your network. The playbook disables swap and persists bridge/IPv4 forwarding settings. It backs up fstab/containerd config before changing them and is intended for dedicated clean nodes, not hosts running other container workloads.

## Why start here, and how GitOps grows from it

A homelab gives you a place to learn failure recovery, networking and automation without buying a cloud fleet. Proxmox makes several disposable machines available on one physical server; declarative code records how they were built. Kubernetes adds scheduling and reconciliation when several container workloads outgrow one machine. Rancher can then centralize management of those clusters. Add each layer because it solves a problem you have, and measure the RAM, storage and operational cost.

Bootstrap your **local GitLab first** on infrastructure outside the Kubernetes cluster it will later manage. Then keep these VM/bootstrap files in an infrastructure repository and application/Helm YAML in a separate manifest repository. GitLab reviews and protected CI jobs can validate both. Install a narrowly scoped cluster agent only after Kubernetes is healthy. A GitOps controller such as Flux can later reconcile reviewed manifests from Git; KAS supplies agent/CI connectivity and is not itself that reconciler. Keeping GitLab outside this lab avoids the recovery cycle of needing a broken cluster to access the code that repairs it.

## Terraform and Kubernetes manifests have different jobs

Terraform here owns **Proxmox VMs, CPU/RAM/disks, bridge attachment and cloud-init addresses**. It does not create VLANs, router ACLs, DNS or the existing Ubuntu template. Ansible owns the dedicated hosts' OS/bootstrap configuration. Kubernetes YAML and Helm values own **objects inside the cluster**: Deployments, Services, RBAC, ingress, network policy and observability.

Keep VM state and Kubernetes deployment repositories separate as your lab grows. A runner plans Terraform with a narrowly scoped Proxmox token; an application pipeline applies reviewed manifests with namespace-scoped Kubernetes permissions. Removing a Deployment should not remove its VM. Destroying a VM does not make Terraform a backup tool for its workloads. Keep state encrypted, access controlled and backed up; this example starts with ignored local state for learning.

### Optional GitLab Agent (KAS)

The GitLab Agent for Kubernetes runs inside a cluster and makes an **outbound** connection to GitLab's Kubernetes Agent Server (KAS). Authorized GitLab CI jobs can use the agent's tunnel and generated kubeconfig contexts instead of exposing port 6443 to the internet. This does not grant every pipeline cluster-admin, or mean KAS automatically applies application YAML. GitOps reconciliation is a separate controller/workflow.

After creating the agent registration via the GitLab API, install the official agent Helm chart with its registration token delivered through a secret manager/protected local values file. Never commit that token. Put nonsecret configuration in `.gitlab/agents/lab/config.yaml` in the agent-config repository, for example:

```yaml
ci_access:
  projects:
    - id: example-group/lab-manifests
```

This Community Edition-compatible example uses the agent service account's permissions. Configure that service account with only the intended namespace/verbs and test `kubectl auth can-i`; do not accept a chart's cluster-admin default. CI-job impersonation with `access_as: ci_job` is an optional Premium/Ultimate feature, so it is not assumed by this CE lab. Authorizing a GitLab project is one trust gate; Kubernetes RBAC is another. Keep outbound HTTPS/WebSocket access to the correct KAS endpoint and validate its TLS certificate. Self-managed KAS configuration belongs to the GitLab administration repository, not the VM token or application manifests. See [GitLab agent CI workflow](https://docs.gitlab.com/user/clusters/agent/ci_cd_workflow/) and [agent installation](https://docs.gitlab.com/user/clusters/agent/install/).

## Proxmox prerequisites, in plain language

A **node** is a physical Proxmox host. A **template** is a reusable powered-off guest image. A **full clone** gets independent disks; a linked clone depends on its parent. A **datastore** stores virtual disks, and a **bridge** connects VM NICs to your lab network. **Cloud-init** sets first-boot user, public SSH keys, address, gateway and DNS; it does not install Kubernetes. The **QEMU guest agent** reports guest status to Proxmox.

Use an existing, tested Ubuntu Server 24.04 amd64 cloud-init template with `scsi0`, cloud-init drive, Python 3, passwordless sudo for `ubuntu`, SSH public-key authentication and an enabled QEMU guest agent. It must have clean machine identity/cloud-init state before templating. Verify its disk is no larger than the requested clone disk. Use `qm config TEMPLATE_ID` and `pvesm status` on Proxmox to inspect it. Template creation is intentionally outside this repository, so an unknown image is never imported or existing VM converted automatically.

Provide free VM IDs and unused addresses on a **dedicated private VLAN**, real bridge/datastore/node names and working DNS. `192.0.2.0/24` and `.example.test` are documentation placeholders, not an operational network. Avoid overlap between node, pod, service and VPN ranges. Confirm inter-node reachability and clock synchronization. For initial labs reserve 4 vCPUs, 8 GiB RAM and 40 GiB disk per VM; three VMs therefore need 24 GiB guest RAM plus host overhead.

Use a dedicated Proxmox API token. Scope its role/ACLs to the source template, a lab pool/VM paths and chosen storage; do not use a root token. Clone/configuration tasks require VM audit/clone/allocate/configuration/power privileges and storage audit/allocation. Token privilege separation requires both user and token ACLs. Compare permissions against the [provider authentication documentation](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) before applying; never solve a 403 by blindly granting Administrator. API access uses verified HTTPS. Trust your Proxmox CA in the controller trust store; do not set `insecure=true`.

## Provisioning and bare metal

Install Terraform 1.6+, Ansible Core, Python 3 and SSH on your workstation. These examples use the pinned `bpg/proxmox` provider 0.115.0. No private SSH key is copied to Proxmox or Terraform.

```sh
cp terraform.tfvars.example terraform.tfvars
# Edit the copy: actual template/node/storage/bridge, unused IDs/IPs and public keys.
# Set API identity privately, avoiding command-line/history credential literals:
export PROXMOX_VE_ENDPOINT=https://pve.example.test:8006/
read -r -s -p 'Proxmox API token: ' PROXMOX_VE_API_TOKEN; printf '\n'
export PROXMOX_VE_API_TOKEN
terraform init
terraform fmt -check
terraform validate
terraform plan -out=lab.tfplan
# Read the plan: only new intended VMs should appear. Run this only after your review.
terraform apply lab.tfplan
./scripts/inventory.sh
ansible-inventory --list
```

Accept SSH host keys only after verifying fingerprints from a trusted console/channel. This repository keeps SSH host-key checking enabled. Use `ssh-agent` or your local key file, never an inventory password. Check `ansible all -m ping` before bootstrapping. Terraform performs no remote-exec and does not run the bootstrap script automatically.

For bare metal, skip Terraform entirely. Supply fresh dedicated Ubuntu 24.04 machines with distinct hostnames/IPs, Python, SSH keys and passwordless sudo. Copy `ansible/inventory.baremetal.example.yml` to ignored `ansible/inventory.local.yml`, replace the documentation addresses, verify SSH fingerprints, then pass that inventory to the same bootstrap script. Nothing partitions disks or installs an OS.

## Cleanup, upgrades and evidence

There is no automatic destroy/reset action. Export workload data and take verified backups first. To remove this lab, review a deliberate source change removing `prevent_destroy`, then inspect `terraform plan -destroy` before any `terraform apply`. This destroys the managed VMs and their disks; it does not delete the original template. Bare-metal hosts are never wiped by this project. Kubernetes `drain`/uninstall/reset operations need separate review.

The bootstraps refuse implicit Kubernetes version changes. Recheck upstream support, take snapshots/backups, plan a documented Kubernetes/K3s upgrade and update version pins deliberately. Never call an untested snapshot your disaster-recovery plan: practice a restore in a separate isolated network to avoid duplicate node identities/IPs.

This is a **local review draft**. Static validation is not a live cluster test, security certification, HA claim or production deployment. No infrastructure was applied and no repository was published while preparing it.

## Bootstrap and check the cluster

```sh
ansible all -m ping
LAB_BOOTSTRAP_ACK=yes ./scripts/bootstrap.sh
# Bare metal alternative:
LAB_BOOTSTRAP_ACK=yes ./scripts/bootstrap.sh ansible/inventory.local.yml
```

Repeated runs skip `kubeadm init` when admin.conf exists and skip joins when kubelet.conf exists; they do not reset nodes. Join tokens expire after two hours and are suppressed in Ansible output. Treat `/etc/kubernetes/admin.conf` as a cluster-admin credential. Retrieve it only into an ignored private file on your controller:

```sh
mkdir -p .kube; chmod 700 .kube
ssh ubuntu@YOUR_CONTROL_PLANE 'sudo cat /etc/kubernetes/admin.conf' > .kube/lab.yaml
chmod 600 .kube/lab.yaml
export KUBECONFIG="$PWD/.kube/lab.yaml"
kubectl get nodes -o wide
kubectl -n kube-system get pods
kubectl get tigerastatus
kubectl get --raw='/readyz?verbose'
# Explicit disposable DNS check; remove its pod when complete.
kubectl run dns-check --image=busybox:1.37.0 --restart=Never --command -- nslookup kubernetes.default.svc.cluster.local
kubectl logs dns-check
kubectl delete pod dns-check
```

All expected nodes must be Ready, CoreDNS healthy and Calico Available. No default ingress or persistent-volume provisioner is included; a Service of type LoadBalancer stays pending without a load-balancer implementation. `kubectl describe pod`, events, `journalctl -u kubelet`, `journalctl -u containerd` and `crictl --runtime-endpoint unix:///run/containerd/containerd.sock info` help separate runtime, DNS and CNI failures. Install crictl separately if needed. Do not paste tokens/kubeconfigs into an issue.

For stateful labs, define storage and backups before deploying databases. Back up etcd with a compatible `etcdctl snapshot save` using the control-plane CA/client certificates; protect `/etc/kubernetes/pki`, encryption configuration if enabled, and application/PV backups. [Official etcd backup guidance](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/) covers certificate flags and restore procedure. A Proxmox VM backup alone does not guarantee coordinated application consistency across three machines.

## Official sources

- [Kubeadm package installation](https://v1-35.docs.kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Kubernetes 1.35 patch pointer](https://dl.k8s.io/release/stable-1.35.txt)
- [Calico supported Kubernetes versions](https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements)
- [Calico 3.33 on-premises installation and feature gate](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)
- [Kubernetes runtime/cgroup configuration](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)

## Choose one CI provider before configuring deployment

GitHub and GitLab are **alternative complete paths**. [CI-PATHS.md](CI-PATHS.md) provides the runner setup, GitLab CLI inputs and job controls alongside the GitHub commands below. Choose one owner for each lab. A source-control server stores code and schedules jobs; the selected **runner machine** executes Terraform, SSH, Ansible or Helm and needs the documented network access. Cloning this repository does not install a runner or create a route to Proxmox.

| Choice | Source and job scheduler | Execution machine | Kubernetes access |
| --- | --- | --- | --- |
| GitHub | Your private GitHub repository and Actions | Your dedicated self-hosted Linux runner | Scoped kubeconfig where needed; GitLab/KAS not required |
| GitLab | Your private GitLab project and GitLab CI | Your dedicated protected GitLab Linux runner | Scoped kubeconfig; GitLab agent/KAS is an optional separately configured route |

The public upstream runs unprivileged hosted validation only. A local GitLab is useful if you want to host your own source and scheduler, but is **not** a prerequisite for the GitHub path. KAS does not provision VMs and is not a general-purpose Terraform runner.

## Why the CI jobs have separate phases

Terraform owns VM allocation and cloud-init inputs; Ansible owns host bootstrap. Kubernetes manifests and Helm own workloads inside the resulting cluster. GitLab KAS connects an agent to GitLab for authorized Kubernetes access without exposing port 6443 publicly; it does not provision VMs or bypass Kubernetes RBAC. Community Edition uses the agent service account scope; CI job impersonation requires the applicable Premium/Ultimate tier.

The public repository validates code on an unprivileged hosted GitHub runner. Its deployment job is ineligible in the public upstream: self-hosted runners belong in your own private deployment repository, never a public fork that accepts outside code. `workflow_dispatch`, a private repository, the default branch, and `DEPLOY_ENABLED=true` must all match before deployment runs. The `homelab` environment can enforce reader-owned approval and secret policies; creating its name alone does not configure approvals. GitLab uses a private project, protected default branch, manual job, protected `homelab` runner and `resource_group`. Configure a separate unprivileged `validation` runner for GitLab validation. Do not share the deployment runner with untrusted projects.

Create a private copy using the CLI, after reviewing the source:

```sh
git clone https://github.com/RayEvelyn/kubeadm-proxmox-lab.git
cd kubeadm-proxmox-lab
gh repo create YOUR-OWNER/kubeadm-proxmox-lab-deployment --private --source . --remote deployment --push
# Target this private repository for subsequent gh secret/variable commands.
gh variable set DEPLOY_ENABLED --body false --repo YOUR-OWNER/REPO
```

For GitLab, create a private project with `glab repo create --private`, push the reviewed checkout there, protect its default branch, and register a protected deployment runner. Store secrets as protected CI variables; use masking for eligible single-line values. Multiline keys and kubeconfigs cannot satisfy masking restrictions: keep them protected, never print them, and follow CI-PATHS.md. Public settings belong in regular variables. Importing source does not transfer GitHub secrets, runners or state. Set `HOMELAB_ACTION` when starting the GitLab manual job; it defaults to `plan`.

### Persistent Terraform state and trusted SSH

Provision one fixed Linux runner with Terraform 1.16.4, Python 3/PyYAML, Ansible core 2.21.4, OpenSSH, `flock`, and this repository's documented Kubernetes/Helm clients. It needs private network routes to the trusted Proxmox API, VM SSH endpoints, and (for Rancher) management API. Give its dedicated account a private state directory, for example:

```sh
sudo install -d -m 700 -o "$USER" -g "$(id -gn)" /var/lib/homelab-terraform
```

`TF_STATE_ROOT` defaults to that persistent directory; each `TF_REPOSITORY_ID` receives its own state and lock. Defaults are `github-<repository_id>` and `gitlab-<project_id>` to prevent unrelated platform IDs from colliding; overrides must match `^(github|gitlab)-[0-9]+$`. State never goes in checkout, temporary files, CI caches or artifacts. Back up the entire private state directory securely outside CI and test recovery; state contains sensitive infrastructure data. Before moving runner or platform, restore that same state and explicitly keep the same original platform-prefixed `TF_REPOSITORY_ID` (for example `github-123456`). Do not let GitHub and GitLab initialize independent states for the same VMs. The file lock coordinates both platforms only when they use the same fixed runner and directory. Restrict access to that runner and its backups.

Configure repository/environment variables: `HOMELAB_TFVARS_JSON` containing the reviewed example tfvars as JSON, `PROXMOX_VE_ENDPOINT`, optional `PROXMOX_CA_PEM` (public CA certificate), and optional `TF_STATE_ROOT`/`TF_REPOSITORY_ID`. Secrets: scoped `PROXMOX_VE_API_TOKEN`, dedicated unencrypted automation `SSH_PRIVATE_KEY`, and, for deploy only, verified `SSH_KNOWN_HOSTS` (required before any Terraform plan/apply in that phase). The helper derives the public key and refuses tfvars without the matching key. Temporary key/config/CA files use private permissions and are removed on exit; no global SSH configuration or system trust store is replaced. Never put credentials in tfvars JSON. Supply secrets with `gh secret set NAME --repo YOUR-OWNER/REPO < protected-file`; use `gh variable set NAME --repo ... --body ...` for nonsecret settings.

Run `plan` first. `provision` saves and applies a fresh plan, writes inventory, and stops before any SSH connection. For newly created hosts, obtain SSH host public keys through a trusted Proxmox console/API guest-agent channel, e.g. `qm guest exec VMID -- cat /etc/ssh/ssh_host_ed25519_key.pub` on the trusted Proxmox host. Compare those keys with a candidate `ssh-keyscan` output; keyscan alone is not authentication. Store the verified host/IP lines as `SSH_KNOWN_HOSTS`, then run `deploy`. Deployment applies its own saved plan, uses strict pinned SSH host checking, and bootstraps only the reviewed dedicated VMs. Existing `prevent_destroy` guards remain in force. Plans and temporary files are removed; persistent state is retained.

```sh
gh variable set DEPLOY_ENABLED --body true --repo YOUR-OWNER/REPO
gh workflow run deploy.yml --repo YOUR-OWNER/REPO -f action=plan
# Review the run, then explicitly dispatch provision or deploy.
```


CI configuration has been checked locally as recorded in VALIDATION.md where present. No example workflow has been run against your infrastructure. The private runner prerequisites, network trust, secret values and first real deployment remain reader responsibilities. Official references: [GitHub runner guidance](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job), [GitLab protected/manual jobs](https://docs.gitlab.com/ci/jobs/job_control/), [Terraform local backend](https://developer.hashicorp.com/terraform/language/backend/local).
