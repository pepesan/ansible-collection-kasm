#!/bin/bash

set -e

# ============================================
# CONFIG
# ============================================
ADMIN_PASSWORD="${KASM_ADMIN_PASSWORD:?KASM_ADMIN_PASSWORD is not set}"
USER_PASSWORD="${KASM_USER_PASSWORD:?KASM_USER_PASSWORD is not set}"
RELEASE_DIR="${KASM_RELEASE_DIR:-/kasm_release}"
# How to reach the Docker CLI: a command prefix, e.g. "docker" (default) or
# "docker exec kasm docker".
read -r -a DOCKER <<< "${KASM_DOCKER:-docker}"
INSTALL_MARKER="${KASM_INSTALL_MARKER:-/opt/kasm_install_complete}"
REQUIRED_SERVICES="${KASM_REQUIRED_SERVICES:-kasm_db kasm_api kasm_manager}"
INSTALL_ARGS="${KASM_INSTALL_ARGS:---install-profile noninteractive}"
read -r -a INSTALL_ARGS_ARRAY <<< "${INSTALL_ARGS}"
# Roles that do not seed the database (app, agent) do not take the passwords.
if [ "${KASM_PASSWORDS_IN_ARGS:-true}" = "true" ]; then
    INSTALL_ARGS_ARRAY+=(--admin-password "${ADMIN_PASSWORD}" --user-password "${USER_PASSWORD}")
fi
# ============================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Redirect output to a log file (all-in-one default: reachable from the host at
# /opt/kasm/data/opt/kasm_deploy.log)
LOG_FILE="${KASM_LOG_FILE:-/opt/kasm_deploy.log}"
# Only root may read the log. umask covers a new file; the explicit chmod covers
# a log left by an earlier run (tee keeps the mode of an existing file).
umask 077
: > "${LOG_FILE}"
chmod 600 "${LOG_FILE}"
exec 1> >(tee "${LOG_FILE}") 2>&1

# Our own marker, written once install.sh finishes successfully (see bottom of
# this script). Not relying on a Kasm-internal file here on purpose: the
# binary/path we used to check (bin/kasm_server) does not exist at all in
# Kasm 1.19.0 — it was a leftover assumption from an older Kasm release, and
# its absence silently made this check always false, triggering a full
# reinstall (new self-signed cert, new sidecar network, etc.) on every single
# run. Confirmed the hard way on Contabo E2E testing (2026-10-09).
MARKER_FILE="${INSTALL_MARKER}"
if [ -f "${MARKER_FILE}" ]; then
    echo -e "${GREEN}Kasm is already installed. Skipping installation.${NC}"
    exit 0
fi

if [ -f "${RELEASE_DIR}/install.sh" ]; then
    echo -e "${YELLOW}>> Checking install.sh for known bugs...${NC}"
    sed -i "s/'install-depends',/'install-depends'/" "${RELEASE_DIR}/install.sh" 2>/dev/null || true
    # Extra sed expressions (one per line) for installer quirks on a given OS.
    if [ -n "${KASM_INSTALL_PATCHES:-}" ]; then
        while IFS= read -r expr; do
            [ -n "${expr}" ] || continue
            sed -i "${expr}" "${RELEASE_DIR}/install.sh"
        done <<< "${KASM_INSTALL_PATCHES}"
    fi
    echo -e "${GREEN}OK install.sh prepared${NC}"
fi

if [ -f "${RELEASE_DIR}/profiles/noninteractive.yaml" ]; then
    echo -e "${YELLOW}>> Adding install-depends to the noninteractive profile...${NC}"
    grep -q "install-depends" "${RELEASE_DIR}/profiles/noninteractive.yaml" 2>/dev/null || \
        echo "install-depends: false" >> "${RELEASE_DIR}/profiles/noninteractive.yaml"
    echo -e "${GREEN}OK Profile updated${NC}"
fi

# The core services Kasm cannot work without. Their absence after install.sh
# means the install did NOT complete, whatever the exit code said: install.sh
# aborts early when one of its Docker plugins (kasmweb/logger, kasmweb/sidecar)
# is not yet answering on its socket at the moment Docker tries to enable it
# ("dial unix .../kasmlogger.sock: connect: connection refused"). That is a
# timing race, not a persistent fault: the plugin is up a few seconds later.
core_services_up() {
  local c
  for c in ${REQUIRED_SERVICES}; do
    "${DOCKER[@]}" ps --format '{{.Names}}' | grep -Fqx "$c" || return 1
  done
  # In Kasm 1.20+, verify ClickHouse if the container exists.
  if "${DOCKER[@]}" ps -a --format '{{.Names}}' | grep -Fqx "kasm_clickhouse"; then
    "${DOCKER[@]}" ps --format '{{.Names}}' | grep -Fqx "kasm_clickhouse" || return 1
  fi
  return 0
}

# Enables any installed-but-disabled Docker plugin (the ones the race above
# leaves behind) so the next install.sh attempt does not depend on the race.
enable_disabled_plugins() {
  local p
  for p in $("${DOCKER[@]}" plugin ls --format '{{.Name}} {{.Enabled}}' | awk '$2=="false"{print $1}'); do
    echo -e "${YELLOW}>> Enabling plugin ${p}...${NC}"
    "${DOCKER[@]}" plugin enable "$p" || true
  done
}


# On a host where db and app share kasm.service, the db install has already
# activated this oneshot unit. Starting it again for app is a no-op: restart
# after app install so its new Compose file actually creates the app services.
# Also recover an app installed previously but missing our marker, without
# running install.sh yet again.
if [ -n "${KASM_RESTART_SYSTEMD_SERVICE:-}" ] && core_services_up; then
    touch "${MARKER_FILE}"
    exit 0
fi
# The installer output is already redacted before it is retained here. This
# lets deterministic failures stop without exposing credentials or retries.
INSTALL_OUTPUT_FILE=""
cleanup_install_output() {
  if [ -n "$INSTALL_OUTPUT_FILE" ]; then
    rm -f "$INSTALL_OUTPUT_FILE"
  fi
}
trap 'cleanup_install_output' EXIT

# Installing the app removes KASM_INSTALL_BASE, including files still mounted
# by the running database. Preserve those exact files outside that directory;
# otherwise the first reboot recreates them as directories and db cannot start.
DB_DIR="${KASM_PRESERVE_DB_DIR:-}"
if [ -n "$DB_DIR" ]; then
  DB_BACKUP=$(mktemp -d "${DB_DIR%/*}/.pepesan-db-preserve.XXXXXX")
  trap 'rm -rf "$DB_BACKUP"; cleanup_install_output' EXIT
  for file in certs/db_server.crt certs/db_server.key conf/database/pg_hba.conf conf/database/postgresql.conf; do
    if [ ! -f "$DB_DIR/$file" ]; then
      echo "ERROR: database file $DB_DIR/$file missing; refusing to install app." >&2
      exit 1
    fi
    mkdir -p "$DB_BACKUP/$(dirname "$file")"
    cp -p "$DB_DIR/$file" "$DB_BACKUP/$file"
  done
  test -d "$DB_DIR/log/postgres"
  DB_LOG_OWNER=$(stat -c '%u:%g' "$DB_DIR/log/postgres")
  DB_LOG_MODE=$(stat -c '%a' "$DB_DIR/log/postgres")
fi

restore_db_files() {
  [ -n "$DB_DIR" ] || return 0
  for file in certs/db_server.crt certs/db_server.key conf/database/pg_hba.conf conf/database/postgresql.conf; do
    mkdir -p "$DB_DIR/$(dirname "$file")"
    if [ -d "$DB_DIR/$file" ]; then
      rmdir "$DB_DIR/$file"
    fi
    cp -p "$DB_BACKUP/$file" "$DB_DIR/$file"
  done
  mkdir -p "$DB_DIR/log/postgres"
  chown "$DB_LOG_OWNER" "$DB_DIR/log/postgres"
  chmod "$DB_LOG_MODE" "$DB_DIR/log/postgres"
}
if [ -n "$DB_DIR" ]; then
  trap 'rm -rf "$DB_BACKUP"; cleanup_install_output' EXIT
fi

MAX_ATTEMPTS=3
ATTEMPT=1
while true; do
  if [ -n "$DB_DIR" ]; then
    trap 'restore_db_files && rm -rf "$DB_BACKUP"; cleanup_install_output' EXIT
  fi
  INSTALL_OUTPUT_FILE=$(mktemp "${TMPDIR:-/tmp}/kasm-install-output.XXXXXX")
  echo -e "${YELLOW}>> Installing Kasm (attempt ${ATTEMPT}/${MAX_ATTEMPTS})...${NC}"
# Kasm's installer prints generated credentials and tokens to stdout even in
# non-interactive mode. Redact credential-like fields before they reach the
# root-only install log or the Ansible task output.
  set +e
  bash "${RELEASE_DIR}/install.sh" "${INSTALL_ARGS_ARRAY[@]}" 2>&1 |
    sed -u -E \
      -e 's/^([[:space:]]*[[:alnum:] _-]*(password|token|secret)[[:space:]]*[:=][[:space:]]*).*/\1[REDACTED]/I' \
      -e 's/^(Setting Default Manager Token as ).*/\1[REDACTED]/I' |
    tee "$INSTALL_OUTPUT_FILE"
  INSTALL_EXIT=${PIPESTATUS[0]}
  set -e
  restore_db_files
  if [ -n "$DB_DIR" ]; then
    trap 'rm -rf "$DB_BACKUP"; cleanup_install_output' EXIT
  fi
  if [ "$INSTALL_EXIT" -ne 0 ] &&
     grep -Eq 'Port \([0-9]+\) is in use\. Installation cannot continue\.' "$INSTALL_OUTPUT_FILE" &&
     ! core_services_up; then
    echo -e "${RED}ERROR: Kasm installer reported a port conflict; not retrying this deterministic error.${NC}"
    exit "$INSTALL_EXIT"
  fi
  rm -f "$INSTALL_OUTPUT_FILE"
  INSTALL_OUTPUT_FILE=""
  if [ "$INSTALL_EXIT" -eq 0 ] && [ -n "${KASM_RESTART_SYSTEMD_SERVICE:-}" ] &&
     systemctl is-active --quiet "${KASM_RESTART_SYSTEMD_SERVICE}"; then
    systemctl restart "${KASM_RESTART_SYSTEMD_SERVICE}"
  fi

  if [ $INSTALL_EXIT -ne 0 ]; then
    echo -e "${YELLOW}>> Installer exited with an error ($INSTALL_EXIT). Checking pending containers...${NC}"
    CREATED=$("${DOCKER[@]}" ps -a --filter "status=created" --format "{{.Names}}")
    if [ -n "$CREATED" ]; then
      echo -e "${YELLOW}>> Starting containers in Created state: $CREATED${NC}"
      "${DOCKER[@]}" start $CREATED
      echo -e "${GREEN}OK Containers started${NC}"
    fi

    echo -e "${YELLOW}>> Waiting for services to become healthy (max 120s)...${NC}"
    TIMEOUT=120
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
      UNHEALTHY=$("${DOCKER[@]}" ps --filter "health=unhealthy" --format "{{.Names}}")
      STARTING=$("${DOCKER[@]}" ps --filter "health=starting" --format "{{.Names}}")
      if [ -z "$UNHEALTHY" ] && [ -z "$STARTING" ]; then
        break
      fi
      sleep 5
      ELAPSED=$((ELAPSED + 5))
    done

    if [ $ELAPSED -ge $TIMEOUT ]; then
      echo -e "${YELLOW}WARNING: Timed out waiting. Services still unhealthy: ${UNHEALTHY}${NC}"
    fi
  fi

  # Success is decided by the services being there, not by the exit code.
  if core_services_up; then
    echo -e "${GREEN}OK Core services are up (${REQUIRED_SERVICES})${NC}"
    break
  fi

  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo -e "${RED}ERROR: Kasm is not installed after ${MAX_ATTEMPTS} attempts (core services missing). Not writing the install marker.${NC}"
    exit 1
  fi

  echo -e "${YELLOW}>> Core services missing after attempt ${ATTEMPT}; enabling disabled plugins and retrying...${NC}"
  enable_disabled_plugins
  ATTEMPT=$((ATTEMPT + 1))
  sleep 5
done

touch "${MARKER_FILE}"

echo ""
echo -e "${GREEN}==============================${NC}"
echo -e "${GREEN}  OK Kasm installed            ${NC}"
echo -e "${GREEN}==============================${NC}"
echo ""
echo -e "  URL:            ${GREEN}https://localhost:443${NC}"
echo -e "  Admin user:     ${GREEN}admin@kasm.local${NC}"
echo -e "  User user:      ${GREEN}user@kasm.local${NC}"
# The passwords are deliberately NOT printed: this output ends up in a log file.
# They are kept on the machine running Ansible (access CSV and .credentials/).
echo -e "  Passwords:      not shown here (see the access CSV / .credentials/ on the Ansible control node)"
