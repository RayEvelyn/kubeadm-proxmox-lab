#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
[[ ${LAB_BOOTSTRAP_ACK:-} == yes ]] || { echo 'Set LAB_BOOTSTRAP_ACK=yes after reviewing inventory and playbook.' >&2; exit 1; }
[[ -f ${1:-ansible/inventory.local.json} ]] || { echo 'Inventory missing.' >&2; exit 1; }
ansible-playbook -i "${1:-ansible/inventory.local.json}" ansible/site.yml
