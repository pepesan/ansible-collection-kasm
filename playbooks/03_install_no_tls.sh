#!/bin/bash
# Local/DNS-less install: disables real Let's Encrypt TLS, Kasm stays
# reachable over its self-signed certificate. Useful for
# inventory-prueba-kasm-local/-lxc style environments.
#
# Usage: ./03_install_no_tls.sh [inventory]   (default: ./inventory.example)

set -e

INVENTORY="${1:-inventory.example}"

ansible-playbook -i "${INVENTORY}" pepesan.kasm.site_kasm \
  -e kasm_base_domain=example.com \
  -e kasm_letsencrypt_enabled=false
