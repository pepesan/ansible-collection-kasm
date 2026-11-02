#!/usr/bin/env bash
# Full install with your domain and Let's Encrypt e-mail. Requires public DNS
# to point at each host and port 80 to be free for the HTTP-01 challenge.
#
# Usage: ./02_install_custom_domain.sh <inventory> <base_domain> <email>

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
if (($# != 3)); then
  printf 'Usage: %s <inventory> <base_domain> <email>\n' "$0" >&2
  exit 2
fi
INVENTORY="$1"
BASE_DOMAIN="$2"
EMAIL="$3"

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.site_kasm \
  -e "kasm_base_domain=${BASE_DOMAIN}" \
  -e "letsencrypt_email=${EMAIL}" \
  -e "student_credentials_dir=${KASM_CREDENTIALS_DIR}" \
  -e "kasm_credentials_dir=${KASM_CREDENTIALS_DIR}" \
  -e "kasm_credentials_csv_name=${KASM_CSV_NAME}" \
  -e "kasm_credentials_csv_dir=${KASM_CSV_DIR}"
