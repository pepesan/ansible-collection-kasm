#!/usr/bin/env bash

kasm_examples_init() {
  local inventory_input="${1:?Inventory path is required}"
  local caller_dir="$PWD"
  local examples_dir
  local inventory_link_name
  local repo_root

  examples_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  repo_root="$(realpath -e -- "${examples_dir}/..")"
  export ANSIBLE_CONFIG="${examples_dir}/ansible.cfg"

  KASM_DATA_DIR="${KASM_DATA_DIR:-${HOME}/.local/share/pepesan-kasm/examples}"
  if [[ "${KASM_DATA_DIR}" != /* ]]; then
    KASM_DATA_DIR="${caller_dir}/${KASM_DATA_DIR}"
  fi
  KASM_DATA_DIR="$(realpath -m -- "${KASM_DATA_DIR}")"
  case "${KASM_DATA_DIR}" in
    "${repo_root}"|"${repo_root}"/*)
      printf 'KASM_DATA_DIR must be outside the collection checkout: %s\n' "${KASM_DATA_DIR}" >&2
      return 2
      ;;
  esac
  KASM_CREDENTIALS_DIR="${KASM_DATA_DIR}/.credentials"
  KASM_CSV_DIR="${KASM_DATA_DIR}/csv"
  install -d -m 700 -- "${KASM_DATA_DIR}" "${KASM_CREDENTIALS_DIR}" "${KASM_CSV_DIR}"
  export KASM_DATA_DIR KASM_CREDENTIALS_DIR KASM_CSV_DIR

  if [[ "${inventory_input}" != /* ]]; then
    inventory_input="${caller_dir}/${inventory_input}"
  fi
  if [[ ! -e "${inventory_input}" ]]; then
    printf 'Inventory does not exist: %s\n' "${inventory_input}" >&2
    return 2
  fi
  KASM_SOURCE_INVENTORY="$(realpath -e -- "${inventory_input}")"
  local inventory_basename
  local sanitized_inventory_basename
  inventory_basename="${KASM_SOURCE_INVENTORY##*/}"
  sanitized_inventory_basename="$(jq -rn --arg name "${inventory_basename}" '$name | gsub("[^A-Za-z0-9._-]+"; "-") | gsub("^-+|-+$"; "")')"
  KASM_CSV_NAME="access-data-${sanitized_inventory_basename:-inventory}.csv"
  export KASM_CSV_NAME

  if [[ -f "${KASM_SOURCE_INVENTORY}" ]] && \
    ansible-inventory -i "${KASM_SOURCE_INVENTORY}" --list 2>/dev/null |
      jq -e 'has("ubuntu") and (has("kasm") | not)' >/dev/null; then
    KASM_INVENTORY_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pepesan-kasm-inventory.XXXXXX")"
    chmod 700 -- "${KASM_INVENTORY_TMP}"
    case "${KASM_SOURCE_INVENTORY}" in
      *.yaml|*.yml) inventory_link_name="01-source.yml" ;;
      *) inventory_link_name="01-source.ini" ;;
    esac
    ln -s -- "${KASM_SOURCE_INVENTORY}" "${KASM_INVENTORY_TMP}/${inventory_link_name}"
    printf '[kasm:children]\nubuntu\n' > "${KASM_INVENTORY_TMP}/02-kasm-group.ini"
    chmod 600 -- "${KASM_INVENTORY_TMP}/02-kasm-group.ini"
    export KASM_INVENTORY_FOR_RUN="${KASM_INVENTORY_TMP}"
    trap 'rm -rf -- "${KASM_INVENTORY_TMP}"' EXIT
    printf 'Using a temporary [kasm:children] alias for the inventory\047s [ubuntu] group; the source file is unchanged.\n' >&2
  else
    export KASM_INVENTORY_FOR_RUN="${KASM_SOURCE_INVENTORY}"
  fi

  cd -- "${KASM_DATA_DIR}"
}
