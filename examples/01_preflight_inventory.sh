#!/usr/bin/env bash
# Validate inventory structure only; this playbook does not connect to hosts.
#
# Usage: ./01_preflight_inventory.sh [inventory]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
INVENTORY="${1:-${KASM_INVENTORY:-${SCRIPT_DIR}/inventory}}"

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.preflight_kasm_inventory
