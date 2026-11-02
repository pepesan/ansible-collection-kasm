#!/usr/bin/env bash
# Create or delete one Kasm application user. Generated password stays outside
# the checkout in KASM_DATA_DIR/.credentials/.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

if (($# != 3)); then
  printf 'Usage: %s <inventory> <present|absent> <username>\n' "$0" >&2
  exit 2
fi
INVENTORY="$1"
STATE="$2"
USERNAME="$3"
if [[ "${STATE}" != present && "${STATE}" != absent ]]; then
  printf 'State must be present or absent.\n' >&2
  exit 2
fi

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.kasm_user \
  -e "kasm_user_state=${STATE}" \
  -e "kasm_user_username=${USERNAME}" \
  -e "kasm_user_credentials_dir=${KASM_CREDENTIALS_DIR}"
