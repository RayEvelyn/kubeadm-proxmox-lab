#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
umask 077
mkdir -p ansible
terraform output -json ansible_inventory > ansible/inventory.local.json.tmp
python3 -m json.tool ansible/inventory.local.json.tmp >/dev/null
mv ansible/inventory.local.json.tmp ansible/inventory.local.json
printf '%s\n' 'Inventory written; verify SSH host fingerprints before running Ansible.'
