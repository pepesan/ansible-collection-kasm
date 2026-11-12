#!/usr/bin/env bash
# Read-only public DNS and certificate check. Requires Kasm's domain to resolve
#
# Usage: ./04_preflight_dns_tls.sh [inventory] <base_domain>

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

if (($# == 1)); then
  INVENTORY=""
  BASE_DOMAIN="$1"
elif (($# == 2)); then
  INVENTORY="$1"
  BASE_DOMAIN="$2"
else
  printf 'Usage: %s [inventory] <base_domain>\n' "$0" >&2
  exit 2
fi

kasm_examples_init "${INVENTORY}"
ansible-playbook -i "${KASM_INVENTORY_FOR_RUN}" pepesan.kasm.preflight_kasm_dns_tls \
  -e "kasm_base_domain=${BASE_DOMAIN}"
