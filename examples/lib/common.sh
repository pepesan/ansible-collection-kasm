#!/usr/bin/env bash

kasm_examples_init() {
  local inventory_input="${1:-}"
  local caller_dir="$PWD"
  local examples_dir
  local inventory_link_name
  local repo_root

  examples_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  repo_root="$(realpath -e -- "${examples_dir}/..")"
  export ANSIBLE_CONFIG="${ANSIBLE_CONFIG:-${examples_dir}/ansible.cfg}"

  KASM_DATA_DIR="${KASM_DATA_DIR:-${HOME}/pepesan-kasm-data}"
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

  if [[ -z "${inventory_input}" ]]; then
    if [[ -n "${KASM_INVENTORY:-}" ]]; then
      inventory_input="${KASM_INVENTORY}"
    elif [[ -f "${ANSIBLE_CONFIG}" ]]; then
      local cfg_inv
      cfg_inv="$(sed -n -E 's/^[[:space:]]*inventory[[:space:]]*=[[:space:]]*(.*)/\1/p' "${ANSIBLE_CONFIG}" | head -n 1 | tr -d '\r' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
      if [[ -n "${cfg_inv}" ]]; then
        local cfg_dir
        cfg_dir="$(cd -- "$(dirname -- "${ANSIBLE_CONFIG}")" && pwd)"
        if [[ "${cfg_inv}" != /* ]]; then
          inventory_input="${cfg_dir}/${cfg_inv}"
        else
          inventory_input="${cfg_inv}"
        fi
      else
        inventory_input="${examples_dir}/inventory"
      fi
    else
      inventory_input="${examples_dir}/inventory"
    fi
  fi

  if [[ "${inventory_input}" != /* ]]; then
    inventory_input="${caller_dir}/${inventory_input}"
  fi
  inventory_input="$(realpath -m -- "${inventory_input}")"
  if [[ ! -e "${inventory_input}" ]]; then
    printf 'Inventory does not exist: %s\n' "${inventory_input}" >&2
    printf 'Configure an inventory or copy %s/inventory.example to %s/inventory\n' "${examples_dir}" "${examples_dir}" >&2
    return 2
  fi
  KASM_SOURCE_INVENTORY="$(realpath -e -- "${inventory_input}")"

  local training_project=""
  if [[ -f "${KASM_SOURCE_INVENTORY}" ]]; then
    training_project="$(ansible-inventory -i "${KASM_SOURCE_INVENTORY}" --list 2>/dev/null | jq -r '[._meta.hostvars[].kasm_training_project // empty, .all.vars.kasm_training_project // empty, .kasm.vars.kasm_training_project // empty][0] // empty' || true)"
  fi
  local sanitized_training_project=""
  if [[ -n "${training_project}" && "${training_project}" != "null" ]]; then
    sanitized_training_project="$(jq -rn --arg name "${training_project}" '$name | gsub("[^A-Za-z0-9._-]+"; "-") | gsub("^-+|-+$"; "")' | tr '[:upper:]' '[:lower:]')"
  fi

  local inventory_basename
  local sanitized_inventory_basename
  inventory_basename="${KASM_SOURCE_INVENTORY##*/}"
  sanitized_inventory_basename="$(jq -rn --arg name "${inventory_basename}" '$name | gsub("[^A-Za-z0-9._-]+"; "-") | gsub("^-+|-+$"; "")')"

  if [[ -n "${sanitized_training_project}" ]]; then
    KASM_CSV_NAME="access-data-${sanitized_training_project}.csv"
  else
    KASM_CSV_NAME="access-data-${sanitized_inventory_basename:-inventory}.csv"
  fi
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
    printf 'Using a temporary [kasm:children] compatibility group; the source inventory is unchanged.\n' >&2
  else
    export KASM_INVENTORY_FOR_RUN="${KASM_SOURCE_INVENTORY}"
  fi

  cd -- "${KASM_DATA_DIR}"
}

kasm_examples_print_credentials_summary() {
  local csv_path="${KASM_CSV_DIR}/${KASM_CSV_NAME}"
  printf '\n====================================================================\n'
  printf 'Credenciales y datos de acceso / Access credentials:\n'
  printf '  - Carpeta de credenciales por host: %s\n' "${KASM_CREDENTIALS_DIR}"
  printf '  - Fichero CSV de accesos:           %s\n' "${csv_path}"
  printf '====================================================================\n\n'
}
