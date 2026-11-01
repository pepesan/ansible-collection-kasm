#!/bin/bash
# Extracts every YAML play from the Markdown documentation (README files,
# docs/ and the README of every role) and runs `ansible-playbook
# --syntax-check` on it, using the collection built from this checkout. A wrong
# role name or a YAML mistake in an example is caught here.
#
# Usage: scripts/check-examples.sh      (needs network: it installs the collection
#                                         dependencies and the third-party roles)
# Exit status 0 means every example passed.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

(cd "$REPO" && ansible-galaxy collection build --force --output-path "$W") >/dev/null 2>&1 \
  || { echo "ansible-galaxy collection build failed"; exit 1; }
: > "$W/empty.cfg"
export ANSIBLE_HOME="$W/home" ANSIBLE_CONFIG="$W/empty.cfg" ANSIBLE_FORCE_COLOR=0 \
       ANSIBLE_COLLECTIONS_PATH="$W/colls" ANSIBLE_ROLES_PATH="$W/roles"
ansible-galaxy collection install "$W"/*.tar.gz -p "$W/colls" >/dev/null 2>&1 \
  || { echo "the tarball does not install"; exit 1; }
python3 -c "
import yaml
d = yaml.safe_load(open('$REPO/requirements.yml'))
yaml.safe_dump({'roles': d['roles']}, open('$W/roles.yml', 'w'))"
ansible-galaxy role install -r "$W/roles.yml" -p "$W/roles" >/dev/null 2>&1 \
  || { echo "the third-party roles do not install"; exit 1; }

mkdir "$W/plays"
python3 - "$REPO" "$W/plays" <<'PY'
import glob, os, re, sys
repo, out = sys.argv[1:3]
files = sorted(glob.glob(repo + '/*.md') + glob.glob(repo + '/docs/*.md') + glob.glob(repo + '/roles/*/README*.md'))
count = 0
for path in files:
    for index, match in enumerate(re.finditer(r'```yaml\n(.*?)```', open(path).read(), re.S)):
        body = match.group(1)
        if not body.lstrip().startswith('- hosts:'):
            continue  # a fragment (requirements, inventory...), not a play
        count += 1
        name = os.path.relpath(path, repo).replace('/', '__') + '__%d.yml' % index
        open(os.path.join(out, name), 'w').write(body)
print(count, 'plays found')
PY

ok=0; bad=0
for play in "$W"/plays/*.yml; do
  if ansible-playbook -i localhost, "$play" --syntax-check 2>&1 | grep -q '^playbook:'; then
    ok=$((ok + 1))
  else
    bad=$((bad + 1)); echo "FAIL: $(basename "$play")"
    ansible-playbook -i localhost, "$play" --syntax-check 2>&1 | grep -E 'ERROR|could not|error' | head -2 | cut -c1-200
  fi
done
echo "RESULT: $ok passed, $bad failed"
[ "$bad" -eq 0 ]
