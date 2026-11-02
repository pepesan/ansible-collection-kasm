#!/usr/bin/env bash
# Start or destroy one user's session for an already registered workspace.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

if (($# != 4)); then
  printf 'Usage: %s <inventory> <present|absent> <username> <image_name>\n' "$0" >&2
  exit 2
fi
INVENTORY="$1"
STATE="$2"
USERNAME="$3"
IMAGE="$4"
if [[ "${STATE}" != present && "${STATE}" != absent ]]; then
  printf 'State must be present or absent.\n' >&2
  exit 2
fi

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.kasm_session \
  -e "kasm_session_state=${STATE}" \
  -e "kasm_session_user=${USERNAME}" \
  -e "kasm_session_workspace=${IMAGE}"
