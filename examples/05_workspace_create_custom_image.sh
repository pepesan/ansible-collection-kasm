#!/usr/bin/env bash
# Register an image as a Kasm workspace. Images containing "dind" are
# automatically configured as privileged for their inner Docker daemon.
#
# Usage: ./05_workspace_create_custom_image.sh <inventory> <image> <name>

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
if (($# != 3)); then
  printf 'Usage: %s <inventory> <image> <workspace_name>\n' "$0" >&2
  exit 2
fi
INVENTORY="$1"
IMAGE="$2"
NAME="$3"
PRIVILEGED=false
[[ "${IMAGE,,}" == *dind* ]] && PRIVILEGED=true
NAME_JSON="$(jq -cn --arg name "${NAME}" '{kasm_workspace_name: $name}')"

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.kasm_workspace \
  -e kasm_workspace_state=present \
  -e "kasm_docker_image_name=${IMAGE}" \
  -e "kasm_workspace_image=${IMAGE}" \
  -e "${NAME_JSON}" \
  -e "kasm_workspace_privileged=${PRIVILEGED}" \
  -e kasm_workspace_cores=2 \
  -e kasm_workspace_memory_gb=4
