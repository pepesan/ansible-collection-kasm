#!/usr/bin/env bash
# Delete one workspace. Persistent profile data is deleted by default; pass
# keep_profiles to preserve it.
#
# Usage: ./08_workspace_delete.sh [inventory] <image> [keep_profiles]
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
if (($# == 1)); then
  INVENTORY=""
  IMAGE="$1"
  KEEP_PROFILES=""
elif (($# == 2)); then
  if [[ "$2" == "keep_profiles" ]]; then
    INVENTORY=""
    IMAGE="$1"
    KEEP_PROFILES="$2"
  else
    INVENTORY="$1"
    IMAGE="$2"
    KEEP_PROFILES=""
  fi
elif (($# == 3)); then
  INVENTORY="$1"
  IMAGE="$2"
  KEEP_PROFILES="$3"
else
  printf 'Usage: %s [inventory] <image> [keep_profiles]\n' "$0" >&2
  exit 2
fi
if [[ -n "${KEEP_PROFILES}" && "${KEEP_PROFILES}" != keep_profiles ]]; then
  printf 'The optional argument must be keep_profiles.\n' >&2
  exit 2
fi
DELETE_PERSISTENT_DATA=true
[[ "${KEEP_PROFILES}" == keep_profiles ]] && DELETE_PERSISTENT_DATA=false

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.kasm_workspace \
  -e kasm_workspace_state=absent \
  -e "kasm_docker_image_name=${IMAGE}" \
  -e "kasm_workspace_image=${IMAGE}" \
  -e "kasm_workspace_delete_persistent_data=${DELETE_PERSISTENT_DATA}"
