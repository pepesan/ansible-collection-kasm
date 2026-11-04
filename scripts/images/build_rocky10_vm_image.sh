#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  printf 'Usage: %s [ISO_VERSION=10.2] [ARCH=x86_64]\n' "$0"
  printf 'Example: %s 10.2 x86_64\n' "$0"
  printf 'Override the cached ISO directory with ISO_DIR=/path/to/isos.\n'
  exit 0
fi
VERSION="${1:-${ROCKY_ISO_VERSION:-10.2}}"
ARCH="${2:-${ROCKY_ARCH:-x86_64}}"
exec "${SCRIPT_DIR}/build_iso_vm_image.sh" rocky "${VERSION}" "${ARCH}"
