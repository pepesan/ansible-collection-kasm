# kasm_session

**Fully qualified name:** `pepesan.kasm.kasm_session` (collection [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Starts (or destroys) a **running session** of an already registered Kasm
workspace for a given user, through Kasm's public API. It is the missing
counterpart of [`kasm_workspace`](../kasm_workspace/README.md) (registers the
workspace) and [`kasm_user`](../kasm_user/README.md) (creates the user): this
one makes a user *have a session*.

Uses `ansible.builtin.uri` with Kasm's public API and, optionally, the host's
Docker CLI to start **the same container** already registered by Kasm; it does
not access Postgres directly. Recovery is disabled by default. The role
authenticates with the persistent API key `kasm_workspace` creates on the host
(`/opt/kasm/.kasm_api_key.json`), so at least one workspace must have been
registered first.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `kasm_session_state` | `present` | `present`: ensure the user has an available session (launch it if missing, wait until `running` or `paused`). `absent`: destroy it |
| `kasm_session_user` | `user@kasm.local` | Kasm username owning the session. Must already exist |
| `kasm_session_workspace` | `""` (required) | An already registered workspace, by its image `name` (`pepesan/mi-ubuntu-resolute-kasm-python-dind:1.3`) or `friendly_name` (`Python Docker (Ubuntu 26.04)`) |
| `kasm_session_recover_stopped` | `false` | Perform an API-based recovery when this role runs. With boot recovery enabled, this check is already active; set it to `true` to recover immediately while `kasm_session_recover_on_boot` is disabled |
| `kasm_session_recover_on_boot` | `true` | Install and enable a per-session systemd unit that starts the same existing container after reboot; no replacement session is created |
| `kasm_session_timeout_seconds` | `600` | How long to wait for Kasm to report `running` or `paused` (a cold start of a large image can take minutes) |
| `kasm_session_launch_retries` / `kasm_session_launch_delay` | `18` / `10` | Attempts and seconds between retries when Kasm refuses a request temporarily (up to 3 minutes, allowing large workspace images to finish staging) |
| `kasm_session_poll_seconds` | `5` | Polling interval while waiting |
| `kasm_session_api_key_file` | `{{ kasm_dir }}/.kasm_api_key.json` | Persistent API key bootstrapped by `kasm_workspace` |

## Facts exported (state `present`)

| Fact | Content |
|---|---|
| `kasm_session_id` | The session's `kasm_id` |
| `kasm_session_container_id` | Its container id inside Kasm's DinD (`docker exec kasm docker exec <id> …`) |
| `kasm_session_status` | `operational_status` (`running` or `paused`) |

## Behaviour worth knowing

- **Idempotent**: if the user already has a session of that workspace, nothing
  is launched (`changed=false`); `absent` is a no-op when there is none.
- **ID formats differ between endpoints**: `get_users` returns UUIDs with
  dashes, `get_images`/`get_kasms` without. The role compares on the dashless
  lowercase form and sends the canonical dashed form. A first version compared
  them raw, never found the existing session and tried to launch a second one
  (`request_kasm` refused, so no harm, but it was caught only by testing).
- **A session started by automation has no client attached**, so Kasm will
  *pause* it after `keepalive_expiration` seconds (see
  [`kasm_group`](../kasm_group/README.md): 3600 s and action `pause` by
  default). Anything running inside (e.g. a docker compose lab) is frozen, not
  lost, and resumes when a user connects.
- The role installs one systemd recovery unit per existing session by default
  (`kasm_session_recover_on_boot=true`). At boot, it waits for host Docker,
  Kasm's nested Docker, and healthy Kasm API, manager, and agent components;
  then it starts the same container only when its state is `created` or
  `exited`. Running and paused containers are left alone and checked for
  stability for 15 seconds.
- The boot unit is removed when the session is set to `absent`, or when boot
  recovery is disabled. `kasm_uninstall` removes all such units and the helper.
- Recovery only restarts the existing container. It does not recreate a Kasm
  session or restore processes that were interrupted by the host shutdown.
- `kasm_session_recover_stopped=true` performs the same safe recovery when the
  role is run, even if `kasm_session_recover_on_boot=false`. Missing IDs,
  missing containers, and unsupported Docker states fail without replacing
  the session.
- The `request_kasm` response carries a session token: those tasks are
  `no_log`.
- One session reserves the workspace's cores and memory for as long as it
  exists; mind the host's capacity before launching several.

## Recover the same session after a host reboot

When the role runs with `kasm_session_state=present` (the default), it installs
and enables a per-session systemd unit. On the next boot, the unit waits for
the host and nested Docker daemons and healthy Kasm API, manager, and agent
components. It then starts the same existing container if it is `created` or
`exited` and checks that it remains running for 15 seconds.

For a session created before boot recovery was enabled, run the role once while
Kasm is available. The default `kasm_session_recover_on_boot=true` immediately
recovers a stopped existing container and installs the unit for future boots:

```bash
ansible-playbook -i inventory pepesan.kasm.kasm_session \
  -e kasm_session_workspace=pepesan/mi-ubuntu-resolute-kasm-ansible-dind:1.2 \
  -e kasm_session_recover_on_boot=true
```

The role waits for Kasm to report `running` or `paused`; then open the original
session in Kasm. Set `kasm_session_recover_on_boot=false` to remove/disable the
boot unit. This restarts the same container but cannot restore processes lost
when the host shut down.

## Names with spaces

Pass them as JSON, otherwise `-e key="a b"` is cut at the first space:

```bash
ansible-playbook -i <inventory> kasm-session.yml \
  -e '{"kasm_session_workspace": "Python Docker (Ubuntu 26.04)"}'
```

## Example


Start a session of a registered workspace for a user and wait until it is running. If the session already exists, nothing
is launched:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_session
      vars:
        kasm_session_user: user@kasm.local
        kasm_session_workspace: "pepesan/core-ubuntu-resolute:1.20"   # image name or friendly name
```

Wait longer for a big image, and use the facts the role exports afterwards:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_session
      vars:
        kasm_session_workspace: "Core Ubuntu Resolute"
        kasm_session_timeout_seconds: 1200
  tasks:
    - ansible.builtin.debug:
        msg: "Session {{ kasm_session_id }} is {{ kasm_session_status }}"
```

Destroy that session:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_session
      vars:
        kasm_session_state: absent
        kasm_session_workspace: "Core Ubuntu Resolute"
```

From the command line, with the playbook shipped in the collection:

```bash
ansible-playbook -i inventory-my-server pepesan.kasm.kasm_session \
  -e kasm_session_workspace=pepesan/core-ubuntu-resolute:1.20
```

See [`playbooks/kasm_session.yml`](../../playbooks/kasm_session.yml).
