#!/bin/bash
# Deploy-hook run by certbot after each successful renewal: copies the renewed
# certificate to where Kasm reads it and restarts kasm_proxy.
#
# Defaults are the all-in-one layout (Kasm inside the "kasm" container, certs
# under <kasm_dir>/data/opt/kasm/<version>/certs). Roles that install Kasm
# straight on the host write /etc/letsencrypt/kasm-deploy-hook.env with
# KASM_CERT_DIR (e.g. /opt/kasm/current/certs) and KASM_DOCKER (e.g. docker).

set -e

HOOK_ENV="${KASM_HOOK_ENV:-/etc/letsencrypt/kasm-deploy-hook.env}"
if [ -f "${HOOK_ENV}" ]; then
    # shellcheck disable=SC1090
    . "${HOOK_ENV}"
fi

KASM_DIR="${KASM_DIR:-/opt/kasm}"
if [ -z "${KASM_CERT_DIR:-}" ]; then
    KASM_CERT_DIR=$(find "${KASM_DIR}/data/opt/kasm" -name "kasm_nginx.crt" 2>/dev/null | head -1 | xargs dirname)
fi
KASM_DOCKER="${KASM_DOCKER:-docker exec kasm docker}"

cp "${RENEWED_LINEAGE}/fullchain.pem" "${KASM_CERT_DIR}/kasm_nginx.crt"
cp "${RENEWED_LINEAGE}/privkey.pem"   "${KASM_CERT_DIR}/kasm_nginx.key"
chmod 644 "${KASM_CERT_DIR}/kasm_nginx.crt"
chmod 600 "${KASM_CERT_DIR}/kasm_nginx.key"

# shellcheck disable=SC2086
${KASM_DOCKER} restart kasm_proxy

echo "Certificate renewed and kasm_proxy restarted for ${RENEWED_DOMAINS}"
