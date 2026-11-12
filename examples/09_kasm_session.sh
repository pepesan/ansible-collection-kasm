#!/usr/bin/env bash
# Start or destroy one user's session for an already registered workspace.
#
# Usage: ./09_kasm_session.sh [inventory] <present|absent> <username> <image_name> [recover_on_boot=true|false]
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

if [[ "${1:-}" == "present" || "${1:-}" == "absent" ]]; then
  INVENTORY=""
  STATE="$1"
  USERNAME="${2:-}"
  IMAGE="${3:-}"
  RECOVER_ON_BOOT="${4:-true}"
  if (($# < 3 || $# > 4)); then
    printf 'Usage: %s [inventory] <present|absent> <username> <image_name> [recover_on_boot=true|false]\n' "$0" >&2
    exit 2
  fi
elif (($# >= 4 && $# <= 5)); then
  INVENTORY="$1"
  STATE="$2"
  USERNAME="$3"
  IMAGE="$4"
  RECOVER_ON_BOOT="${5:-true}"
else
  printf 'Usage: %s [inventory] <present|absent> <username> <image_name> [recover_on_boot=true|false]\n' "$0" >&2
  exit 2
fi
if [[ "${STATE}" != present && "${STATE}" != absent ]]; then
  printf 'State must be present or absent.\n' >&2
  exit 2
fi
if [[ "${RECOVER_ON_BOOT}" != true && "${RECOVER_ON_BOOT}" != false ]]; then
  printf 'recover_on_boot must be true or false.\n' >&2
  exit 2
fi

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.kasm_session \
  -e "kasm_session_state=${STATE}" \
  -e "kasm_session_user=${USERNAME}" \
  -e "kasm_session_workspace=${IMAGE}" \
  -e "kasm_session_recover_on_boot=${RECOVER_ON_BOOT}"
