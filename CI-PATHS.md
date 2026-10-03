# Two selectable CI paths

Choose **one** path for this lab. Both invoke `./scripts/ci-deploy.sh` with the same reviewed inputs, but registration, variables and job controls belong to their own provider. No deployment has been run against your infrastructure. Public GitHub validation has no lab secrets or self-hosted runner access.

## A. GitHub Actions and your own runner

Use the private repository creation and `gh variable`/`gh secret` commands in README.md. Every YOUR_ACCOUNT/project placeholder in this document must be the exact private repository you created (including any -deployment suffix); do not target the public upstream. Install the official Actions runner distribution on a dedicated Linux machine; verify its release checksum. On that machine, use the [official runner registration procedure](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners) with a short-lived registration token obtained by CLI:

```bash
# From an authenticated gh CLI; no token is printed to the terminal.
set +x
umask 077
gh api --method POST repos/YOUR_ACCOUNT/kubeadm-proxmox-lab/actions/runners/registration-token --jq .token > /secure/local/github-runner-token
# In the unpacked runner directory, config.sh prompts for the token:
./config.sh --url https://github.com/YOUR_ACCOUNT/kubeadm-proxmox-lab --labels homelab
# Paste the private token only into its interactive token prompt; do not log it.
# Install/run the service as your dedicated runner user per official instructions.
```

The runner must advertise `self-hosted,linux,homelab`. Keep it assigned only to the private reviewed deployment repository. This is an intentionally persistent runner/state model, not ephemeral hosted execution. Install the prerequisites listed below on **this runner**, not merely on a workstation or GitHub server. Configure `homelab` environment policies supported by your plan; its name alone does not imply approval. Start and inspect the exact run:

```bash
gh workflow run deploy.yml --repo YOUR_ACCOUNT/kubeadm-proxmox-lab -f action=plan
gh run list --repo YOUR_ACCOUNT/kubeadm-proxmox-lab --workflow deploy.yml
gh run view RUN_ID --repo YOUR_ACCOUNT/kubeadm-proxmox-lab
# After review use the next supported action: plan/provision/deploy.
```

No local GitLab, GitLab runner, glab login or KAS connection is required by this path.

## B. Private GitLab CI and your own GitLab runner

An existing trusted GitLab instance is sufficient. If you choose to host local GitLab, bootstrap it separately before creating these deployment projects; do not put the only copy of your recovery code inside the cluster you are about to build. Authenticate glab to that instance using its approved local credential facility. Preserve upstream origin:

```bash
export GITLAB_HOST=gitlab.example.test
glab repo create YOUR_GROUP/kubeadm-proxmox-lab --private --defaultBranch main --remoteName gitlab-deployment
git push gitlab-deployment main
export GL_PROJECT=YOUR_GROUP/kubeadm-proxmox-lab
# Read numeric project ID/default_branch/visibility; use its actual branch below.
glab api "projects/$(printf '%s' "$GL_PROJECT" | sed 's|/|%2F|g')"
export GL_PROJECT_ID=YOUR_NUMERIC_PROJECT_ID
# Protect the actual default branch. A 409 means it already exists: inspect it,
# preserve existing restrictions, and update deliberately rather than replacing.
glab api --method POST "projects/$GL_PROJECT_ID/protected_branches" \
  --field name=main --field push_access_level=40 --field merge_access_level=40
```

Create a **project-scoped**, protected runner using the modern [runner creation API](https://docs.gitlab.com/api/users/#create-a-runner). This requires an identity allowed to manage runners. Do not use deprecated registration tokens. The API response includes a secret authentication token: write it only to a protected file, never stdout:

```bash
set +x
umask 077
glab api --method POST user/runners --field runner_type=project_type \
  --field project_id="$GL_PROJECT_ID" --field description=dedicated-homelab \
  --field tag_list=homelab --field run_untagged=false --field locked=true \
  --field access_level=ref_protected > /secure/local/gitlab-runner-registration.json
```

Install the official GitLab Runner package on a dedicated persistent Linux host. Register using the authentication token in the protected JSON and `gitlab-runner register`'s interactive token prompt; choose **shell** executor and the trusted GitLab URL. The prompt keeps the token out of command arguments. Modern authentication-token registration takes protection/tags from the API-created runner, not legacy registration flags. Install/start its service under the dedicated account using the [official registration documentation](https://docs.gitlab.com/runner/register/). Restrict runner use to this private project. Register a separate unprivileged runner tagged `validation` for validation; it must not have lab secrets, persistent state or LAN administration access. Verify both runner records and service health:

```bash
glab api "projects/$GL_PROJECT_ID/runners"
gitlab-runner list
gitlab-runner verify
```

Deployment runner prerequisites: Terraform 1.16.4 for VM/DNS paths, Python3 (PyYAML where required), GNU flock, OpenSSH, Ansible core 2.21.4 for VM bootstrap, and kubectl/Helm 3.20.x for Kubernetes paths. Install only the tools relevant to this repo. Validation runners need their own validation prerequisites. The shell executor does not install tools automatically or use job `image` settings. Use an isolated unprivileged Docker executor for validation if desired. Never give untrusted projects access to the protected shell deployment runner.

## GitLab inputs: identical helper contract, native variable storage

Required/relevant inputs here: `DEPLOY_ENABLED`, `HOMELAB_ACTION`, `TF_STATE_ROOT`, `HOMELAB_TFVARS_JSON`, `SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`, `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_API_TOKEN`, `PROXMOX_CA_PEM`. Use the exact JSON schema and host-key checks described in README.md. No credentials in tfvars JSON. These helpers expect **env_var contents**, not file-variable paths. For multiline keys/kubeconfigs, keep the variable protected and raw; GitLab masking rejects multiline values. Never echo them or enable shell tracing. For eligible single-line tokens add `--masked` (and `--hidden` where supported).

```bash
glab variable set DEPLOY_ENABLED false --repo "$GL_PROJECT" --protected --raw
glab variable set HOMELAB_ACTION plan --repo "$GL_PROJECT" --protected --raw
# Nonsecret example; omit Terraform inputs for manifest-only LGTM.
glab variable set TF_STATE_ROOT /var/lib/homelab-terraform --repo "$GL_PROJECT" --protected --raw
glab variable set HOMELAB_TFVARS_JSON --repo "$GL_PROJECT" --protected --raw < /secure/local/inputs.json
# Multiline values intentionally not marked masked:
glab variable set SSH_PRIVATE_KEY --repo "$GL_PROJECT" --protected --raw < /secure/local/id_ed25519
glab variable set SSH_KNOWN_HOSTS --repo "$GL_PROJECT" --protected --raw < /secure/local/known_hosts
# For the VM path; Cloudflare instead needs CLOUDFLARE_API_TOKEN:
glab variable set PROXMOX_VE_API_TOKEN --repo "$GL_PROJECT" --protected --masked --raw < /secure/local/proxmox-token
# Set each additional relevant input from the list above using stdin or nonsecret values.
glab variable set DEPLOY_ENABLED true --repo "$GL_PROJECT" --protected --raw
```

The block demonstrates syntax: skip variables irrelevant to this repository. For LGTM use protected `HOMELAB_KUBECONFIG` and `GRAFANA_ADMIN_PASSWORD` instead of SSH/Proxmox/Terraform inputs. Supply `EXPECTED_CONTEXT` and `STORAGE_CLASS`. For Cloudflare supply its existing DMZ host and scoped DNS token; credentials for its existing tunnel stay on that host, outside CI and Terraform state. For DNS provide the intended LAN `DNS_BIND_IP` and narrow trusted `DNS_ALLOWED_CIDRS`; loopback demo ports do not serve real clients. Do not disable firewall isolation to make a job pass.

Start a pipeline for the actual protected default branch, wait for validation success, inspect the job list and play the **manual** deployment job. Pipeline variables can select the supported action; server policies may restrict who can set them. If so, update the protected HOMELAB_ACTION project variable before creating the pipeline. Do not pass secrets as pipeline command arguments:

```bash
glab ci run --repo "$GL_PROJECT" --branch main --variables HOMELAB_ACTION:plan
glab api "projects/$GL_PROJECT_ID/pipelines/PIPELINE_ID/jobs"
# Choose the deploy job ID belonging to that exact pipeline; never a stale job.
glab api --method POST "projects/$GL_PROJECT_ID/jobs/JOB_ID/play"
glab api "projects/$GL_PROJECT_ID/jobs/JOB_ID"
# Local job traces may contain sensitive output: inspect privately, never publish raw.
```

Supported actions: **plan/provision/deploy**. Plan performs no apply; review it first. Provision (where available) applies the saved plan and stops before SSH. Verify the new guests' unique host keys through a trusted Proxmox console/guest-agent channel and pin known_hosts before deploy. Deploy creates/applies its own fresh saved plan, then performs the reviewed bootstrap. Cloudflare provisions DNS only and rejects a VM provision action; LGTM renders/applies manifests only. A successful process alone is not evidence of working DNS or end-to-end telemetry: run the README runtime checks.

## One state/release owner and optional KAS

A GitHub Actions runner and a GitLab runner are different execution agents. Their source-control servers need not run on the same machine as either runner. The chosen runner must reach the intended Proxmox API, SSH guest endpoints or Kubernetes API and necessary package registries. Cloudflare connector egress belongs to the DMZ host, not the CI runner. Keep Proxmox management outside the DMZ.

For Terraform, use one persistent runner and private `/var/lib/homelab-terraform` root. Default IDs are `github-<repository_id>` or `gitlab-<project_id>`; never guess or reuse another project's ID. Keep state/plan secrets outside checkout/cache/artifacts and maintain protected off-host backups. Resource groups/concurrency coordinate only their own provider; flock coordinates processes only on the same state host. **Never enable both paths to manage the same resources.** When deliberately adopting an existing lab, disable the old writer, back up/restore its exact state to the new fixed runner, explicitly retain its original prefixed state ID using `TF_REPOSITORY_ID`, and verify a reviewed no-change plan before enabling the new owner. Do not copy empty state or initialize a second independent state. LGTM has no Terraform backend: choose one owner for its Helm release and disable the other writer before transferring it.

GitLab KAS is optional only for the **GitLab Kubernetes access** route. Its cluster agent registration token is not the runner token and not a CI API token. KAS transports authorized access; it neither registers runners nor reconciles desired state. The current helper's documented kubeconfig contract works independently of KAS. To use KAS, separately configure agent `ci_access`, namespace-scoped Kubernetes RBAC and the authorized agent context before adapting the deployment access path. Never assume this example silently installs/configures an agent. GitHub uses its reviewed scoped kubeconfig/SSH route and has no GitLab dependency.

References: [glab variables](https://docs.gitlab.com/cli/variable/set/), [GitLab protected manual jobs](https://docs.gitlab.com/ci/jobs/job_control/), [GitLab CI variables](https://docs.gitlab.com/ci/variables/), [GitLab agent access](https://docs.gitlab.com/user/clusters/agent/ci_cd_workflow/), [Terraform local backend](https://developer.hashicorp.com/terraform/language/backend/local).
