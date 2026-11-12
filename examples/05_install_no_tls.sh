#!/usr/bin/env bash
# Local/DNS-less install; Kasm keeps its self-signed certificate.
# If inventory is omitted, the default from ansible.cfg (./inventory) is used.
#
# Usage: ./05_install_no_tls.sh [inventory]
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
if (($# > 1)); then
  printf 'Usage: %s [inventory]\n' "$0" >&2
  exit 2
fi
INVENTORY="${1:-}"

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.site_kasm \
  -e kasm_base_domain=example.com \
  -e kasm_letsencrypt_enabled=false \
  -e "student_credentials_dir=${KASM_CREDENTIALS_DIR}" \
  -e "kasm_credentials_dir=${KASM_CREDENTIALS_DIR}" \
  -e "kasm_credentials_csv_name=${KASM_CSV_NAME}" \
  -e "kasm_credentials_csv_dir=${KASM_CSV_DIR}"
kasm_examples_print_credentials_summary
