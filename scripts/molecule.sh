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
# Only three roles have a Molecule scenario: linux_user, student and kasm_credentials. They are the ones that can be tested
# in an isolated container. The others either change the kernel of the machine (docker, kasm, kasm_uninstall: modprobe and
# sysctl inside a privileged container hit the HOST kernel) or need a live Kasm (kasm_docker_image, kasm_group, kasm_user,
# kasm_workspace, kasm_session), so they are verified end to end against a real server (see CONTRIBUTING.md).
set -euo pipefail

ROLE="${1:?Usage: $0 <role> [molecule args]}"
shift || true
REPO="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$REPO/roles/$ROLE/molecule" ]; then
  echo "The role '$ROLE' has no Molecule scenario. Roles that have one: $(cd "$REPO/roles" && ls -d */molecule 2>/dev/null | cut -d/ -f1 | tr '\n' ' ')" >&2
  exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# A real copy of the collection (not a symbolic link: Molecule installs the collection of the checkout on its own
# with --force and cannot replace a link). Molecule overwrites this copy, and if it did not, it would already be here.
ansible-galaxy collection install "$REPO" -p "$TMP" --force >/dev/null 2>&1 \
  || { echo "Could not install the collection from $REPO" >&2; exit 1; }

# Setting ANSIBLE_COLLECTIONS_PATH replaces Ansible's default search paths, which would hide the collections
# installed there (community.docker, needed by Molecule's Docker driver). So the configured paths are kept.
DEFAULT_PATHS="$(ansible-config dump -f json 2>/dev/null | python3 -c "
import json, sys
print(':'.join(next(x['value'] for x in json.load(sys.stdin) if x['name'] == 'COLLECTIONS_PATHS')))" 2>/dev/null)"
DEFAULT_PATHS="${DEFAULT_PATHS:-$HOME/.ansible/collections:/usr/share/ansible/collections}"
export ANSIBLE_COLLECTIONS_PATH="$TMP:$DEFAULT_PATHS"
cd "$REPO/roles/$ROLE"
molecule "${@:-test}"
