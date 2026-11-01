#!/bin/bash
# Runs Molecule for one role of this collection using fully qualified role
# names (pepesan.kasm.<role>). Ansible only resolves them if the collection
# sits in a path shaped like <path>/ansible_collections/pepesan/kasm, so a
# temporary one is created that points at this checkout (nothing is copied or
# installed).
#
# Usage: scripts/molecule.sh <role> [molecule args]     (default: test)
#   scripts/molecule.sh student
#   scripts/molecule.sh linux_user converge
#
# SAFE roles on a workstation: linux_user, student, kasm_credentials.
# The scenarios of docker, kasm and kasm_uninstall load kernel modules and set
# sysctl values that, inside a privileged container, hit the HOST kernel: run
# them only in a disposable VM. The Kasm-dependent roles (kasm_docker_image,
# kasm_group, kasm_session, kasm_user, kasm_workspace) need a live Kasm and are
# verified end to end against a real server instead.
set -euo pipefail

ROLE="${1:?Usage: $0 <role> [molecule args]}"
shift || true
REPO="$(cd "$(dirname "$0")/.." && pwd)"

case "$ROLE" in
  docker|kasm|kasm_uninstall)
    echo "Refusing: the '$ROLE' scenario modifies the host kernel (modprobe/sysctl)." >&2
    echo "Run it in a disposable VM, or set MOLECULE_ALLOW_UNSAFE=1 to override." >&2
    [ "${MOLECULE_ALLOW_UNSAFE:-0}" = "1" ] || exit 2 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/ansible_collections/pepesan"
ln -s "$REPO" "$TMP/ansible_collections/pepesan/kasm"

# Setting ANSIBLE_COLLECTIONS_PATH replaces Ansible's default search paths, which would hide the collections
# installed there (community.docker, needed by Molecule's Docker driver). So the configured paths are kept.
DEFAULT_PATHS="$(ansible-config dump -f json 2>/dev/null | python3 -c "
import json, sys
print(':'.join(next(x['value'] for x in json.load(sys.stdin) if x['name'] == 'COLLECTIONS_PATHS')))" 2>/dev/null)"
DEFAULT_PATHS="${DEFAULT_PATHS:-$HOME/.ansible/collections:/usr/share/ansible/collections}"
export ANSIBLE_COLLECTIONS_PATH="$TMP:$DEFAULT_PATHS"
cd "$REPO/roles/$ROLE"
molecule "${@:-test}"
