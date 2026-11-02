#!/usr/bin/env bash
# Read-only public DNS and certificate check. Requires Kasm's domain to resolve
# to the expected address and HTTPS to return a trusted certificate.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

if (($# != 2)); then
  printf 'Usage: %s <inventory> <base_domain>\n' "$0" >&2
  exit 2
fi
INVENTORY="$1"
BASE_DOMAIN="$2"

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.preflight_kasm_dns_tls \
  -e "kasm_base_domain=${BASE_DOMAIN}"
