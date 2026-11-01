#!/bin/bash
# Builds the collection, inspects the tarball and installs it in a clean
# virtual environment, so what would be published is what gets checked.
#
#   1. the tarball must not contain development files, generated data or
#      anything that looks like a real server address;
#   2. the tarball installs, with its collection dependencies;
#   3. the playbooks of the collection resolve by name and every role loads.
#
# Usage: scripts/check-build.sh          (needs network: it downloads ansible-core,
#                                          the collection dependencies and the roles)
# Exit status 0 means everything passed.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
bad() { echo "FAIL: $*"; fail=1; }

VERSION="$(python3 -c "import yaml,sys;print(yaml.safe_load(open('$REPO/galaxy.yml'))['version'])")"
NAMESPACE="$(python3 -c "import yaml,sys;print(yaml.safe_load(open('$REPO/galaxy.yml'))['namespace'])")"
NAME="$(python3 -c "import yaml,sys;print(yaml.safe_load(open('$REPO/galaxy.yml'))['name'])")"
TARBALL="$W/$NAMESPACE-$NAME-$VERSION.tar.gz"

echo "== build"
(cd "$REPO" && ansible-galaxy collection build --force --output-path "$W") >/dev/null 2>&1 || bad "ansible-galaxy collection build failed"
[ -f "$TARBALL" ] || { echo "no tarball, stopping"; exit 1; }
tar tzf "$TARBALL" > "$W/files.txt"
echo "   $(grep -vc '/$' "$W/files.txt") files, $(stat -c %s "$TARBALL") bytes"

echo "== tarball content"
if grep -iE '(^|/)(PLAN\.md|CLAUDE\.md|AGENTS\.md|\.ansible|\.cache|molecule|__pycache__|\.git|\.credentials|\.credenciales)(/|$)|\.(csv|log|pid|pyc|pass)$|api-key|inventory-|known_hosts|\.tar\.gz|geerlingguy' "$W/files.txt" | grep -v '^inventory.example$' ; then
  bad "development files or generated data inside the tarball (listed above)"
fi
mkdir "$W/x" && tar xzf "$TARBALL" -C "$W/x"
# Any IPv4 that is not loopback or a documentation/example address would be a real one.
allowed='^(127\.0\.0\.1|0\.0\.0\.0|203\.0\.113\.[0-9]+|192\.0\.2\.[0-9]+|198\.51\.100\.[0-9]+|10\.0\.0\.[0-9]+|1\.1\.1\.1|8\.8\.8\.8|9\.9\.9\.9)$'
candidates="$(grep -rIhoE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "$W/x" 2>/dev/null | grep -vE "$allowed" | sort -u)"
if [ -n "$candidates" ]; then
  echo "   addresses that are not documentation examples:"; echo "$candidates" | sed 's/^/     /'
  bad "unexpected IPv4 addresses in the tarball (a real server address must never be published)"
fi

echo "== clean virtual environment"
python3 -m venv "$W/venv" && "$W/venv/bin/pip" install -q ansible-core >/dev/null 2>&1 || bad "could not create the virtual environment"
V="$W/venv/bin"
: > "$W/empty.cfg"
export ANSIBLE_HOME="$W/home" ANSIBLE_CONFIG="$W/empty.cfg" ANSIBLE_FORCE_COLOR=0 \
       ANSIBLE_COLLECTIONS_PATH="$W/colls" ANSIBLE_ROLES_PATH="$W/roles"
"$V/ansible-galaxy" collection install "$TARBALL" -p "$W/colls" >/dev/null 2>&1 || bad "the tarball does not install"
python3 -c "
import yaml
d = yaml.safe_load(open('$REPO/requirements.yml'))
yaml.safe_dump({'roles': d['roles']}, open('$W/roles.yml', 'w'))"
"$V/ansible-galaxy" role install -r "$W/roles.yml" -p "$W/roles" >/dev/null 2>&1 || bad "the third-party roles do not install"

echo "== playbooks by name and roles"
for p in site_kasm kasm_workspace kasm_session kasm_uninstall; do
  if "$V/ansible-playbook" -i localhost, "$NAMESPACE.$NAME.$p" --syntax-check 2>&1 | grep -q '^playbook:'; then
    echo "   $NAMESPACE.$NAME.$p ok"
  else
    bad "$NAMESPACE.$NAME.$p does not resolve or has a syntax error"
  fi
done
roles_loaded="$("$V/ansible-playbook" -i localhost, "$NAMESPACE.$NAME.site_kasm" --list-tasks 2>&1 | grep -oE "$NAMESPACE\.$NAME\.[a-z_]+ :" | sort -u | wc -l)"
echo "   roles that load in site_kasm: $roles_loaded"
[ "$roles_loaded" -ge 4 ] || bad "fewer roles than expected load in site_kasm"

echo
if [ "$fail" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit "$fail"
