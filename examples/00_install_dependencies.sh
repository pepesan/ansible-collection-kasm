#!/usr/bin/env bash
# Install this checkout's collection, collection dependencies, and pinned roles.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

if ! command -v ansible-galaxy >/dev/null 2>&1; then
  printf 'ansible-galaxy is not installed. Install ansible-core 2.15+ first.\n' >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required by the example wrappers. Install it with your OS package manager first.\n' >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pepesan-kasm-build.XXXXXX")"
trap 'rm -rf -- "${TMP_DIR}"' EXIT

printf 'Installing collection dependencies from requirements.yml...\n'
ansible-galaxy collection install -r "${REPO_ROOT}/requirements.yml"
printf 'Installing pinned third-party roles from requirements.yml...\n'
ansible-galaxy role install --force -r "${REPO_ROOT}/requirements.yml"

printf 'Building and installing the collection from this checkout...\n'
ansible-galaxy collection build "${REPO_ROOT}" --output-path "${TMP_DIR}"
ARCHIVES=("${TMP_DIR}"/pepesan-kasm-*.tar.gz)
if ((${#ARCHIVES[@]} != 1)); then
  printf 'Expected one pepesan.kasm collection archive; found %s.\n' "${#ARCHIVES[@]}" >&2
  exit 1
fi
ansible-galaxy collection install --force "${ARCHIVES[0]}"
printf 'Dependencies installed. Run the example scripts from examples/.\n'
