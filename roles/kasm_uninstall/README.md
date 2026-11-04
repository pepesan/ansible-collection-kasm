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

## Idempotency

Every task is a `state: absent`, guarded by a prior existence check
(`stat` for the compose file). Running it twice in a row is a no-op the
second time.

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
