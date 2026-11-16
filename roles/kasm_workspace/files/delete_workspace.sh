#!/bin/bash
# Deletes one or ALL Kasm workspaces, using direct Postgres access (there is
# no documented or confirmed public /api/public/delete_image endpoint in
# Kasm 1.19.0's codebase — the only "delete_image" found is internal to the
# session-authenticated admin API, not the api_key one). Same pattern already
# used to check for existence in create_workspace.sh.
#
# Usage:
#   KASM_IMAGE=user/image:tag  bash delete_workspace.sh   # deletes only that image
#   KASM_CLEAN_ALL=true        bash delete_workspace.sh   # deletes ALL registered workspaces
#
# Before deleting the workspace record, closes (docker rm -f) any session
# currently open using that image — otherwise "docker rmi" fails because the
# image is in use, leaving an orphaned container with no workspace to belong to.
#
# By default DOES delete the persistent profile directories of users who used
# each workspace (IRREVERSIBLE, loses those users' desktop/documents for that
# image). This is the default on purpose: that profile is indexed by
# image_id, not by workspace, so leaving it alive can carry content from a
# previous image version into a new workspace that reuses the same image_id.
# To keep them:
#   KASM_DELETE_PERSISTENT_DATA=false
#
# Also always deletes each workspace's Docker image inside Kasm's DinD and
# prunes orphaned layers at the end, to free the disk space Kasm no longer
# needs after retiring the workspace(s).

set -e

CLEAN_ALL="${KASM_CLEAN_ALL:-false}"
DELETE_PERSISTENT_DATA="${KASM_DELETE_PERSISTENT_DATA:-true}"
# true (default, all-in-one): this node also runs Kasm's DinD, so session
# containers, profile directories and the image are cleaned up here. false
# (official manager): those live on the agents; only the catalog is touched.
DIND_CLEANUP="${KASM_DIND_CLEANUP:-true}"

PSQL() {
  # Unquoted on purpose: KASM_DB_EXEC is a multi-word command prefix.
  # shellcheck disable=SC2086
  ${KASM_DB_EXEC:-docker exec kasm docker exec kasm_db} psql -U kasmapp -d kasm "$@"
}

# Several workspaces may share one image (different editions). A workspace is
# identified by image AND display name; the name is optional only when the
# image has a single workspace.
delete_one() {
  local IMAGE_NAME="$1"
  local WORKSPACE_NAME="${2:-}"
  [[ "$IMAGE_NAME" != *:* ]] && IMAGE_NAME="${IMAGE_NAME}:latest"

  echo ""
  echo "======================================================================"
  echo ">> Workspace: ${IMAGE_NAME}${WORKSPACE_NAME:+ (${WORKSPACE_NAME})}"
  echo "======================================================================"

  local IMAGE_ID
  if [ -n "$WORKSPACE_NAME" ]; then
    IMAGE_ID=$(PSQL -t -c "SELECT image_id FROM images WHERE name = '${IMAGE_NAME}' AND friendly_name = '${WORKSPACE_NAME}';" | tr -d ' \n')
  else
    local COUNT
    COUNT=$(PSQL -t -c "SELECT count(*) FROM images WHERE name = '${IMAGE_NAME}';" | tr -d ' \n')
    if [ "${COUNT:-0}" -gt 1 ]; then
      echo "ERR ${COUNT} workspaces use image ${IMAGE_NAME}. Set KASM_WORKSPACE_NAME to choose one." >&2
      exit 1
    fi
    IMAGE_ID=$(PSQL -t -c "SELECT image_id FROM images WHERE name = '${IMAGE_NAME}';" | tr -d ' \n')
  fi

  if [ -z "$IMAGE_ID" ]; then
    echo "OK No workspace${WORKSPACE_NAME:+ named '${WORKSPACE_NAME}'} with image ${IMAGE_NAME} exists. Nothing to delete."
    return 0
  fi

  # Other workspaces on the same image keep the Docker image and their sessions.
  local OTHERS_SAME_IMAGE
  OTHERS_SAME_IMAGE=$(PSQL -t -c "SELECT count(*) FROM images WHERE name = '${IMAGE_NAME}' AND image_id <> '${IMAGE_ID}';" | tr -d ' \n')

  local PERSISTENT_PROFILE_PATH
  PERSISTENT_PROFILE_PATH=$(PSQL -t -c \
    "SELECT persistent_profile_path FROM images WHERE image_id = '${IMAGE_ID}';" | sed 's/^ *//;s/ *$//')

  echo "OK Workspace found: image_id=${IMAGE_ID}"

  # Close open sessions of this workspace first: if the Docker image is
  # deleted while a session container is still running, "docker rmi" fails
  # because it's in use, and the container is left orphaned (no row in
  # "images" to point to). Deleted by "ancestor" (every container started
  # from this image), not by user_id, to avoid depending on any API key or
  # on which user opened it.
  echo ""
  echo ">> Checking for active sessions of this workspace..."
  local SESSION_CONTAINERS=""
  if [ "$DIND_CLEANUP" = "true" ] && [ "$OTHERS_SAME_IMAGE" != "0" ]; then
    echo "   (another workspace uses image ${IMAGE_NAME}: its sessions are left running)"
  elif [ "$DIND_CLEANUP" = "true" ]; then
    SESSION_CONTAINERS=$(docker exec kasm docker ps -q --filter "ancestor=${IMAGE_NAME}")
  else
    echo "   (KASM_DIND_CLEANUP=false: session containers live on the agents, not checked here)"
  fi
  if [ -n "$SESSION_CONTAINERS" ]; then
    echo ">> Closing active session(s): $(echo "$SESSION_CONTAINERS" | tr '\n' ' ')"
    docker exec kasm docker rm -f $SESSION_CONTAINERS
    echo "OK Session(s) closed."
  elif [ "$DIND_CLEANUP" = "true" ] && [ "$OTHERS_SAME_IMAGE" = "0" ]; then
    echo "OK No active sessions of this workspace."
  fi
  # Also clean up any "kasms" row still pointing at those already-removed
  # containers (same orphaned-row pattern as a RestartPolicy unless-stopped
  # surviving a restart with operational_status=running but no real
  # container behind it).
  PSQL -c "DELETE FROM kasms WHERE image_id = '${IMAGE_ID}';" >/dev/null

  # Persistent profile directories are looked up on disk (glob inside the
  # DinD), not in the "kasms" table: that table only has ACTIVE/recent
  # session rows, and loses the row as soon as the session is destroyed — so
  # an already-closed session (the normal case when cleaning up a workspace)
  # would be invisible even though its profile is still on disk.
  local PERSISTED_DIRS=""
  if [ -n "$PERSISTENT_PROFILE_PATH" ] && [ "$DIND_CLEANUP" != "true" ]; then
    echo "   persistent_profile_path: ${PERSISTENT_PROFILE_PATH} (stored on the agents, not checked here)"
  elif [ -n "$PERSISTENT_PROFILE_PATH" ]; then
    echo "   persistent_profile_path: ${PERSISTENT_PROFILE_PATH}"
    # Note: the real directory on disk uses the image_id WITH dashes
    # (Postgres' canonical uuid format, which is exactly what $IMAGE_ID
    # already carries) — do not strip them.
    local GLOB_PATH="${PERSISTENT_PROFILE_PATH/\{user_id\}/*}"
    GLOB_PATH="${GLOB_PATH/\{username\}/*}"
    GLOB_PATH="${GLOB_PATH/\{image_id\}/$IMAGE_ID}"
    echo ""
    echo ">> Persistent profile directories found on disk (${GLOB_PATH}):"
    PERSISTED_DIRS=$(docker exec kasm sh -c "ls -d ${GLOB_PATH} 2>/dev/null" || true)
    if [ -z "$PERSISTED_DIRS" ]; then
      echo "   (none yet)"
    else
      while read -r dir; do
        [ -z "$dir" ] && continue
        echo "   - ${dir}"
      done <<< "$PERSISTED_DIRS"
    fi
  else
    echo "   (this workspace did not have persistence enabled)"
  fi

  echo ""
  echo ">> Deleting the workspace record from the database..."
  PSQL -c "DELETE FROM images WHERE image_id = '${IMAGE_ID}';"
  echo "OK Workspace '${IMAGE_NAME}'${WORKSPACE_NAME:+ (${WORKSPACE_NAME})} removed from Kasm's catalog."

  if [ "$DELETE_PERSISTENT_DATA" = "true" ] && [ -n "$PERSISTED_DIRS" ]; then
    echo ""
    echo ">> KASM_DELETE_PERSISTENT_DATA=true: deleting persistent profile directories..."
    while read -r dir; do
      [ -z "$dir" ] && continue
      echo "   Deleting ${dir}..."
      docker exec kasm rm -rf "${dir}"
    done <<< "$PERSISTED_DIRS"
    echo "OK Persistent profile directories deleted."
  elif [ "$DELETE_PERSISTENT_DATA" != "true" ] && [ -n "$PERSISTED_DIRS" ]; then
    echo ""
    echo "WARNING The persistent profile directories listed above were NOT deleted."
    echo "        To delete them too: -e kasm_delete_persistent_data=true"
  fi

  if [ "$DIND_CLEANUP" = "true" ] && [ "$OTHERS_SAME_IMAGE" != "0" ]; then
    echo ""
    echo "OK Docker image '${IMAGE_NAME}' kept: ${OTHERS_SAME_IMAGE} other workspace(s) use it."
  elif [ "$DIND_CLEANUP" = "true" ]; then
    echo ""
    echo ">> Deleting Docker image '${IMAGE_NAME}' from Kasm's DinD to free up space..."
    if docker exec kasm docker rmi "${IMAGE_NAME}" 2>&1; then
      echo "OK Image '${IMAGE_NAME}' deleted."
    else
      echo "WARNING Could not delete image '${IMAGE_NAME}' (it may be in use by an active session"
      echo "        or shared with another tag). The workspace is already removed from the catalog either way."
    fi
  fi
}

if [ "$CLEAN_ALL" = "true" ]; then
  echo ">> KASM_CLEAN_ALL=true: ALL registered Kasm workspaces will be deleted."
  # One "image|workspace name" line per record: an image may appear several times.
  ALL_IMAGES=$(PSQL -t -A -F'|' -c "SELECT name, friendly_name FROM images;" | sed 's/^ *//;s/ *$//' | grep -v '^$' || true)
  if [ -z "$ALL_IMAGES" ]; then
    echo "OK No workspace is registered. Nothing to delete."
  else
    echo "Workspaces found:"
    echo "$ALL_IMAGES" | sed 's/^/   - /'
    while IFS='|' read -r img wsname; do
      [ -z "$img" ] && continue
      delete_one "$img" "$wsname"
    done <<< "$ALL_IMAGES"
  fi
else
  IMAGE_NAME="${KASM_IMAGE:?ERR: KASM_IMAGE is required (e.g. user/image:1.0), or use KASM_CLEAN_ALL=true}"
  delete_one "$IMAGE_NAME" "${KASM_WORKSPACE_NAME:-}"
fi

echo ""
echo "======================================================================"
echo ">> Cleaning up dangling layers/images no longer used by any workspace/container..."
if [ "$DIND_CLEANUP" = "true" ]; then
  docker exec kasm docker image prune -f || true
  echo "OK Disk space cleanup complete."
fi
