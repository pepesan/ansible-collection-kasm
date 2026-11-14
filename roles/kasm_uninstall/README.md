# kasm_uninstall

**Fully qualified name:** `pepesan.kasm.kasm_uninstall` (collection [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Removes a Kasm Workspaces install cleanly: stops and removes the `kasm` DinD
container (and its nested networks/volumes), wipes the persisted app data and
removes the matching cached Docker image. It optionally removes the host's real
Let's Encrypt certificate. Lets the [`kasm`](../kasm/README.md) role run again
as a genuine fresh install afterwards, instead of hand-fixing a half-broken
server over SSH.

It also disables and removes per-session systemd recovery units installed by
`kasm_session`.

Not covered by any Galaxy role, and Kasm's own `install.sh` has no
`--uninstall` flag — confirmed by grepping it directly on a live host.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `kasm_dir` | `/opt/kasm` | Must match the same variable used by the `kasm` role |
| `kasm_uninstall_remove_data` | `true` | Wipes `kasm_dir/data` (DB, Kasm's own certs, install marker, profiles) |
| `kasm_uninstall_remove_all` | `true` | Also removes `kasm_dir` itself (`compose.yaml`, `init/`) — harmless, `kasm` recreates both |
| `kasm_image_tag` | `1.19.0-ls154` | Must match the tag used by the `kasm` role |
| `kasm_uninstall_remove_image` | `true` | Removes the Kasm image from the host Docker cache; set `false` to keep it |
| `kasm_uninstall_remove_letsencrypt_certs` | `false` | Removes `/etc/letsencrypt/live/<kasm_domain>` on the host. Off by default: forces a brand new certificate request next install, and Let's Encrypt rate-limits that per domain |
| `kasm_domain` | `{{ node_name }}.{{ kasm_base_domain }}` | Only read when `kasm_uninstall_remove_letsencrypt_certs` is true |

## Layouts

`kasm_uninstall_layout` selects what is removed:

| Layout | What it removes |
|---|---|
| `allinone` (default) | Everything described above: the `kasm` container, its data, the cached image. Unchanged behaviour |
| `manager` | Official manager on the host: Kasm containers (`kasm_*`: app, db, proxy…), their Docker networks, data volumes (`kasm_db_<version>`), Kasm images and `kasm_dir` (`/opt/kasm`, which includes `current/certs`). Stops the services first with `kasm_dir/current/bin/stop` |
| `agent` | Official agent on the host: the same, plus the session containers (started from images labelled `com.kasmweb.image=true`) and those images |

`manager` and `agent` never uninstall Docker (the `uninstall_kasm_and_docker.yml`
style playbook does that separately) and never touch `/etc/letsencrypt`:
the certificates survive unless `kasm_uninstall_remove_letsencrypt_certs` is
true (then also set `kasm_domain` to the certificate name). The layouts are
tolerant of a node where Docker or Kasm is already gone.

**Active sessions are checked first** (`kasm_uninstall_check_sessions`, default
`true`) and reported with a warning: the manager counts `running`, `starting`
and `paused` rows of the `kasms` table (through `kasm_uninstall_db_exec`,
default `docker exec kasm_db`); the agent counts running containers whose name
does not start with `kasm_`. Set `kasm_uninstall_abort_on_active_sessions: true`
to stop instead of warning.

| Variable | Default | Purpose |
|---|---|---|
| `kasm_uninstall_layout` | `allinone` | `allinone`, `manager` or `agent` |
| `kasm_uninstall_check_sessions` | `true` | manager/agent: look for active sessions and warn |
| `kasm_uninstall_abort_on_active_sessions` | `false` | manager/agent: fail instead of warning when sessions exist |
| `kasm_uninstall_db_exec` | `docker exec kasm_db` | manager: prefix that reaches PostgreSQL for the session check |

In `manager`/`agent`, `kasm_uninstall_remove_data` controls the Docker data
volumes, `kasm_uninstall_remove_image` the Kasm images (services and
workspaces) and `kasm_uninstall_remove_all` the `kasm_dir` directory.
`kasm_image_tag` only applies to `allinone`.

## Idempotency

Every task is a `state: absent`, guarded by a prior existence check
(`stat` for the compose file; listing before removing in `manager`/`agent`).
Running it twice in a row is a no-op the second time.

## Example


Remove Kasm and its data, keeping the Let's Encrypt certificate so that reinstalling does not spend one of the few
certificates issued per name and week:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_uninstall
```

**This deletes the Kasm data of the server.** To also force a brand new certificate on the next install:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_uninstall
      vars:
        kasm_uninstall_remove_letsencrypt_certs: true
        node_name: kasmdemo
        kasm_base_domain: example.com
```

From the command line, with the playbook shipped in the collection (and then reinstall from scratch):

```bash
ansible-playbook -i inventory-my-server pepesan.kasm.kasm_uninstall 2>&1 | tee uninstall.log
ansible-playbook -i inventory-my-server pepesan.kasm.site_kasm \
  -e kasm_base_domain=kasm.example.com -e letsencrypt_email=you@example.com 2>&1 | tee install.log
```
