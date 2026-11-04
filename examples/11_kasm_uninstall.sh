#!/usr/bin/env bash
# Remove an existing Kasm install, including persisted Kasm data.
# Let's Encrypt certificates are kept by default.
#
# Usage: ./11_kasm_uninstall.sh <inventory>

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
if (($# != 1)); then
  printf 'Usage: %s <inventory>\n' "$0" >&2
  exit 2
fi
INVENTORY="$1"

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.kasm_uninstall
