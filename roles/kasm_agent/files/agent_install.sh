#!/usr/bin/env bash
set -u

installer=${KASM_AGENT_INSTALLER:?}
hostname=${KASM_AGENT_HOSTNAME:?}
manager=${KASM_MANAGER_HOSTNAME:?}
token=${KASM_MANAGER_TOKEN:?}
marker=${KASM_AGENT_MARKER:?}
help_file="$(dirname "$(dirname "$installer")")/install-help.txt"
log_file=/var/log/kasm-agent-install.log
umask 077
touch "$log_file"
chmod 600 "$log_file"

# The command's return code is not authoritative: Kasm may return non-zero
# after its Docker plugin socket startup race. Verify both service and check-in.
chmod 600 "$help_file" 2>/dev/null || true
if grep -Eq -- '(^|[[:space:],])-e([[:space:],]|$)|--accept-eula' "$help_file"; then
  eula_flag=-e
else
  echo "Could not identify the install.sh EULA acceptance flag; see $help_file" >&2
  exit 1
fi

# An installed agent can lack our marker after a previous false negative. Do
# not invoke install.sh again when its container is already running.
verify_agent() {
  local attempt
  for attempt in $(seq 1 24); do
    if docker logs --tail 200 kasm_agent 2>&1 |
       grep -Eiq 'invalid.*token|unauthorized|registration.*(fail|error)|failed.*(register|manager)|unable to register'; then
      echo "Kasm agent registration failed; verify the manager is reachable and kasm_manager_token is valid." >&2
      return 1
    fi
    if [ "$(docker inspect -f '{{.State.Health.Status}}' kasm_agent 2>/dev/null)" = healthy ] &&
       docker logs --tail 200 kasm_agent 2>&1 | grep -Eiq 'Finished heartbeat'; then
      touch "$marker"
      chmod 600 "$marker"
      return 0
    fi
    sleep 5
  done
  echo "Kasm agent did not become healthy with a completed heartbeat; inspect $log_file and docker logs kasm_agent." >&2
  return 1
}

if docker ps --format '{{.Names}}' | grep -qx kasm_agent; then
  verify_agent
  exit $?
fi

# Retry only when the installer has not started the agent container. A Docker
# plugin socket startup race can interrupt the first install attempt.
attempt=1
while [ "$attempt" -le 3 ]; do
  set +e
  bash "$installer" --role agent --public-hostname "$hostname" \
    --manager-hostname "$manager" --manager-token "$token" "$eula_flag" \
    >"$log_file" 2>&1
  installer_rc=$?
  set -e

  if docker ps --format '{{.Names}}' | grep -qx kasm_agent; then
    verify_agent
    exit $?
  fi

  if [ "$attempt" -lt 3 ]; then
    while IFS= read -r plugin; do
      [ -n "$plugin" ] || continue
      docker plugin enable "$plugin" >/dev/null 2>&1 || true
    done < <(docker plugin ls --format '{{.Name}} {{.Enabled}}' | awk '$2 == "false" {print $1}')
    sleep 10
  fi
  attempt=$((attempt + 1))
done

if ! getent hosts "$manager" >/dev/null 2>&1 || ! timeout 5 bash -c "</dev/tcp/$manager/443" 2>/dev/null; then
  echo "Kasm manager $manager is unreachable on TCP 443; agent was not marked installed." >&2
else
  echo "Agent install did not start a container (installer rc=$installer_rc); inspect $log_file." >&2
fi
exit 1
