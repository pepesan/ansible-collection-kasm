#!/bin/bash
# Refuses secrets before they reach a commit, a push or the published tarball: real IP addresses,
# private keys, certificates, credentials, tokens, API keys, access data and real inventories.
#
#   scripts/check-secrets.sh --staged          what `git commit` would record (the pre-commit hook runs this)
#   scripts/check-secrets.sh --range <a>..<b>  what `git push` would publish, e.g. origin/develop..HEAD
#   scripts/check-secrets.sh --tracked         every file git tracks
#   scripts/check-secrets.sh --tree <dir>      every file under <dir> (check-build.sh runs it on the tarball)
#
# Literal strings that must never appear (real IPs, hostnames of test servers...) go one per line in
# .git/info/secrets-deny, which lives inside .git and is never committed. Extra files: SECRETS_DENY_FILES
# (colon-separated). Exit status 0 means nothing suspicious was found.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
bad() { echo "SECRET CHECK FAIL: $*" >&2; fail=1; }

# Documentation (RFC 5737), loopback, unspecified and well-known public resolvers.
ALLOWED_IP='^(127\.0\.0\.1|0\.0\.0\.0|203\.0\.113\.[0-9]+|192\.0\.2\.[0-9]+|198\.51\.100\.[0-9]+|10\.0\.0\.[0-9]+|1\.1\.1\.1|8\.8\.8\.8|9\.9\.9\.9)$'
IPV4='\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'
KEYS='-----BEGIN [A-Z ]*(PRIVATE KEY|CERTIFICATE)-----|\bAKIA[0-9A-Z]{16}\b|\bgh[pousr]_[A-Za-z0-9]{36,}|\bsk-ant-[A-Za-z0-9_-]{20,}|\bsk-[A-Za-z0-9]{32,}|\bxox[abpr]-[A-Za-z0-9-]{10,}'
# key = value with a literal value of 16+ characters mixing letters and digits (not a template or variable).
ASSIGN='(?i)(password|passwd|secret|token|api_?key)["'"'"']?\s*[:=]\s*["'"'"']?(?=[^"'"'"'\s]*\d)(?=[^"'"'"'\s]*[A-Za-z])[A-Za-z0-9/+_=.-]{16,}'
# Files that hold secrets or real data by their very name.
NAMES='(^|/)(\.credentials|\.credenciales)(/|$)|(^|/)(kasm-api-key-[^/]*|datos-acceso-[^/]*|access-data-[^/]*|cluster-access-[^/]*|user-access-[^/]*|inventory-[^/]*|known_hosts|galaxy_token|\.env|id_(rsa|ed25519|ecdsa)[^/]*)$|\.(pem|key|crt|p12|pfx|pass|kdbx)$|-salt\.txt$'

deny_files() {
  local f extra=()
  [ -f "$REPO/.git/info/secrets-deny" ] && echo "$REPO/.git/info/secrets-deny"
  [ -n "${SECRETS_DENY_FILES:-}" ] && IFS=: read -ra extra <<<"$SECRETS_DENY_FILES"
  for f in "${extra[@]}"; do [ -f "$f" ] && echo "$f"; done
  return 0
}

# Scans $2 (added content); $1 labels the findings. Called without a pipe so `bad` reaches this shell.
scan_text() {
  local label=$1 text=$2 ips d hits
  [ -n "$text" ] || return 0
  ips="$(grep -oE "$IPV4" <<<"$text" | grep -vE "$ALLOWED_IP" | sort -u)"
  [ -z "$ips" ] || bad "$label: IP addresses that are not documentation examples: $(echo $ips)"
  grep -qE -- "$KEYS" <<<"$text" && bad "$label: private key, certificate or provider token"
  grep -qP -- "$ASSIGN" <<<"$text" && bad "$label: literal credential: $(grep -oP -- "$ASSIGN" <<<"$text" | head -1 | cut -c1-40)…"
  while read -r d; do
    hits="$(grep -vE '^\s*(#|$)' "$d" | while IFS= read -r s; do grep -qF -- "$s" <<<"$text" && echo "$s"; done | sort -u)"
    [ -z "$hits" ] || bad "$label: strings from the deny list $d: $(echo $hits)"
  done < <(deny_files)
  return 0
}

check_names() {  # $1: file paths, one per line
  local hits
  hits="$(grep -vE '(^|/)inventory\.example$' <<<"$1" | grep -E "$NAMES")"
  [ -z "$hits" ] || bad "files that hold secrets or real data by name: $(echo $hits)"
}

added() { grep -E '^\+[^+]' | cut -c2-; }  # added lines of a unified diff

case "${1:-}" in
  --staged)
    cd "$REPO" || exit 2
    check_names "$(git diff --cached --name-only --diff-filter=ACMR)"
    scan_text "staged changes" "$(git diff --cached --diff-filter=ACMR -U0 --no-color | added)"
    ;;
  --range)
    [ -n "${2:-}" ] || { echo "usage: $0 --range <a>..<b>" >&2; exit 2; }
    cd "$REPO" || exit 2
    check_names "$(git diff --name-only --diff-filter=ACMR "$2")"
    scan_text "commits in $2" "$(git log -p --no-color --format= "$2" | added)"
    ;;
  --tracked)
    cd "$REPO" || exit 2
    check_names "$(git ls-files)"
    scan_text "tracked files" "$(git ls-files -z | xargs -0 grep -IhE '' 2>/dev/null)"
    ;;
  --tree)
    [ -d "${2:-}" ] || { echo "usage: $0 --tree <dir>" >&2; exit 2; }
    check_names "$(cd "$2" && find . -type f | sed 's|^\./||')"
    scan_text "files under $2" "$(grep -rIhE '' "$2" 2>/dev/null)"
    ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac

[ "$fail" -eq 0 ] && echo "secret check passed (${1#--})"
exit "$fail"
