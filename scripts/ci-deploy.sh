#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
umask 077
[[ ${DEPLOY_ENABLED:-} == true && ${HOMELAB_PRIVATE_REPOSITORY:-} == true ]] || { echo 'Private enabled deployment repository required.' >&2; exit 1; }
action=${HOMELAB_ACTION:-plan}
[[ $action == plan || $action == provision || $action == deploy ]] || exit 1
if [[ $action == deploy ]]; then
 : "${SSH_KNOWN_HOSTS:?Provide independently verified host keys before bootstrap}"
fi
: "${TF_REPOSITORY_ID:?Set a stable platform-prefixed repository state ID}"
[[ $TF_REPOSITORY_ID =~ ^(github|gitlab)-[0-9]+$ ]] || exit 1
state_root=${TF_STATE_ROOT:-/var/lib/homelab-terraform}
[[ $state_root == /* && $state_root != / && ! -L $state_root ]] || exit 1
mkdir -p "$state_root"
state_root=$(realpath "$state_root")
case "$state_root/" in "$PWD/"*|/tmp/*|/var/tmp/*|"${RUNNER_TEMP:-/nonexistent}/"*) echo 'State must persist outside checkout/temp.' >&2; exit 1;; esac
state_dir="$state_root/$TF_REPOSITORY_ID"
[[ ! -L $state_dir ]] || exit 1
mkdir -p "$state_dir"; chmod 700 "$state_dir"
for target in terraform.tfstate terraform.tfstate.backup deploy.lock; do
 [[ ! -L "$state_dir/$target" ]] || { echo 'Refusing state symlink.' >&2; exit 1; }
done
exec 9>"$state_dir/deploy.lock"; flock -n 9 || { echo 'Another deployment holds the state lock.' >&2; exit 1; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export TF_IN_AUTOMATION=true
: "${HOMELAB_TFVARS_JSON:?Provide nonsecret Terraform inputs}"
: "${SSH_PRIVATE_KEY:?Provide the matching private SSH identity}"
printf '%s\n' "$SSH_PRIVATE_KEY" > "$work/id"
ssh-keygen -y -P '' -f "$work/id" > "$work/public"
export CI_INPUT_FILE="$work/terraform.tfvars.json" CI_PUBLIC_FILE="$work/public"
python3 - <<'PYINPUT'
import json,os
from pathlib import Path
v=json.loads(os.environ['HOMELAB_TFVARS_JSON'])
p=Path(os.environ['CI_PUBLIC_FILE']).read_text().split()[:2]
if not isinstance(v,dict) or not any(k.split()[:2]==p for k in v.get('ssh_public_keys',[])):
 raise SystemExit('SSH identity does not match Terraform public keys.')
Path(os.environ['CI_INPUT_FILE']).write_text(json.dumps(v))
PYINPUT
unset HOMELAB_TFVARS_JSON SSH_PRIVATE_KEY
if [[ -n ${PROXMOX_CA_PEM:-} ]]; then
 cat /etc/ssl/certs/ca-certificates.crt > "$work/ca.pem"
 printf '\n%s\n' "$PROXMOX_CA_PEM" >> "$work/ca.pem"
 export SSL_CERT_FILE="$work/ca.pem"
fi
: "${PROXMOX_VE_ENDPOINT:?Set the trusted Proxmox API endpoint}"
: "${PROXMOX_VE_API_TOKEN:?Provide the scoped API token}"
terraform init -input=false -reconfigure -backend-config="path=$state_dir/terraform.tfstate" -backend-config="backup=$state_dir/terraform.tfstate.backup"
terraform validate
terraform plan -input=false -var-file="$CI_INPUT_FILE" -out="$work/plan.tfplan"
[[ $action != plan ]] || exit 0
if [[ -f $state_dir/terraform.tfstate ]]; then cp -p "$state_dir/terraform.tfstate" "$state_dir/terraform.tfstate.$(date -u +%Y%m%dT%H%M%S).backup"; fi
terraform apply -input=false "$work/plan.tfplan"
./scripts/inventory.sh
[[ $action != provision ]] || { echo 'Provisioned. Verify host fingerprints before the deploy phase.'; exit 0; }
printf '%s\n' "$SSH_KNOWN_HOSTS" > "$work/known_hosts"
cat > "$work/config" <<EOF
Host *
  IdentityFile $work/id
  UserKnownHostsFile $work/known_hosts
  StrictHostKeyChecking yes
  IdentitiesOnly yes
  BatchMode yes
EOF
export HOMELAB_SSH_CONFIG="$work/config" ANSIBLE_SSH_ARGS="-F $work/config"
export LAB_BOOTSTRAP_ACK=yes
./scripts/bootstrap.sh
