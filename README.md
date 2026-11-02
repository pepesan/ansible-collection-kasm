# pepesan.kasm

[Español](https://github.com/pepesan/ansible-collection-kasm/blob/main/README.es.md)

Ansible collection to install and manage [Kasm Workspaces](https://kasmweb.com/) on Ubuntu and Debian servers: Docker, a
Linux user, Kasm itself with a real Let's Encrypt certificate, group policy, workspaces, users, sessions and a
clean uninstall. Every step is idempotent: running it again changes nothing.

> **Current release (0.0.3).** Tested end to end on clean Ubuntu 24.04 and 26.04 and Debian 12 and 13 servers with Kasm 1.19.0.
> This is an independent project, not affiliated with or endorsed by Kasm Technologies.

## What is inside

| Role | What it does |
|---|---|
| [`docker`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/docker/README.md) | Docker Engine and the kernel tuning Kasm needs |
| [`student`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/student/README.md) | The `student` Linux user (`docker` and `sudo` groups) with a random password |
| [`linux_user`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/linux_user/README.md) | Generic Linux user with a persisted random password (`student` is a thin wrapper) |
| [`kasm_credentials`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/kasm_credentials/README.md) | Random Kasm passwords and the access CSV (one row per server) |
| [`kasm`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/kasm/README.md) | Installs Kasm Workspaces, with TLS from Let's Encrypt by default |
| [`kasm_group`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/kasm_group/README.md) | Session policy and hardening of a Kasm group (keepalive, clipboard, downloads...) |
| [`kasm_docker_image`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/kasm_docker_image/README.md) | Pulls or removes an image inside Kasm's Docker |
| [`kasm_workspace`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/kasm_workspace/README.md) | Registers or deletes a workspace (default image: a small Ubuntu 26.04 desktop) |
| [`kasm_user`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/kasm_user/README.md) | Creates or deletes a Kasm user through the public API |
| [`kasm_session`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/kasm_session/README.md) | Starts or destroys a user's session of a workspace |
| [`kasm_uninstall`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/kasm_uninstall/README.md) | Removes Kasm for a clean reinstall |

The roles are used by their fully qualified name, for example `pepesan.kasm.kasm_workspace`.

## Requirements

- **Control node:** `ansible-core` 2.15 or newer and SSH access as `root` to the server.
- **Server:** Ubuntu 24.04 or 26.04, or Debian 12 or 13 (all tested), with ports 80 and 443 free. With TLS enabled, `site_kasm`
  checks public DNS A/AAAA records against the expected server address before any installation role runs. A failing host is
  skipped while other hosts continue; the final play lists DNS failures.
- **Collections:** `community.docker`, `community.general` and `ansible.posix` are installed automatically with this one.
- **Third-party roles, which are NOT included** (a collection cannot depend on roles, so install them yourself):

  | Role | Author | License | Used by |
  |---|---|---|---|
  | [`geerlingguy.docker`](https://github.com/geerlingguy/ansible-role-docker) | Jeff Geerling | MIT | `docker` |
  | [`geerlingguy.swap`](https://github.com/geerlingguy/ansible-role-swap) | Jeff Geerling | MIT | `kasm` |
  | [`geerlingguy.certbot`](https://github.com/geerlingguy/ansible-role-certbot) (>= 5.4.1) | Jeff Geerling | MIT | `kasm` |

  All the credit for those automations belongs to their author. This collection only uses them; it does not copy or
  modify their code. If one is missing, the role fails with a message that shows the command to install it.

## Validate an inventory without deploying

Run the check-only playbook against the specific inventory file you want to
validate:

```bash
ansible-playbook -i /path/to/inventory pepesan.kasm.preflight_kasm_inventory
```

It requires the `kasm` group used by `site_kasm`, a non-empty `node_name` on
each host, and unique node names. It runs on the control node only: no SSH
connection, installation role, or inventory copy into this repository. This
is a structural check only; it does not test DNS or host reachability.

## DNS preflight before deployment

With `kasm_letsencrypt_enabled: true` (the default), `site_kasm` runs the DNS
preflight as its first pre-task, before any installation role. By default,
`kasm_domain` is `<node_name>.<kasm_base_domain>`.

The Ansible control node queries Cloudflare's public DNS-over-HTTPS resolver
for both A and AAAA records. It needs outbound HTTPS access to
`cloudflare-dns.com`. The validator combines the returned A/AAAA addresses:
at least one must exist, and the resulting set must match
`kasm_dns_expected_ips` exactly. An empty answer, an extra published address,
a missing expected address, or resolver/network errors fail the preflight.

`kasm_dns_expected_ips` defaults to `[ansible_host]`, falling back to
`[inventory_hostname]`. Override it in the external inventory, `host_vars`, or
`group_vars/kasm.yml` when Ansible connects to a private address but the public
DNS points elsewhere:

```yaml
kasm_dns_expected_ips:
  - "203.0.113.10"
  - "2001:db8::10"
```

For a proxy or load balancer whose public addresses are not managed by this
host, set `kasm_dns_expected_ips: []`. This still requires at least one public
A/AAAA record, but disables address comparison.

In `site_kasm`, a failed host skips its installation roles while other hosts
continue. A final summary lists failed hosts and domains, then returns a
non-zero playbook result. A passing host proceeds with the full installation:
this is a deployment guard, not a DNS-only run. The separate
`preflight_kasm_inventory` playbook checks inventory structure only; it does
not query DNS. Disabling TLS skips the DNS preflight. The check does not verify
port 80 or certificate issuance; Let's Encrypt's HTTP-01 challenge still
requires port 80 to be available.

## Installation

```bash
# 1. The collection (and its collection dependencies)
ansible-galaxy collection install pepesan.kasm

# 2. The third-party roles, with the versions this collection was tested with
ansible-galaxy role install -r requirements.yml
```

`requirements.yml` is at the root of this repository (download it, or copy these lines):

```yaml
roles:
  - {name: geerlingguy.docker, version: "8.0.0"}
  - {name: geerlingguy.swap, version: "2.2.0"}
  - {name: geerlingguy.certbot, version: "5.5.0"}   # 5.4.1 or newer is required
```

## Quick start

An inventory has one host per Kasm server. `node_name` decides the DNS name:
the server is reached at `<node_name>.<kasm_base_domain>`.

The [`examples/`](examples/) directory contains a safe `ansible.cfg`, placeholder
inventory, dependency installer, and runnable wrappers. Its
[README](examples/README.md) explains setup, external inventories, DNS/TLS,
workspaces, sessions, users, and cleanup.

```bash
mkdir -p "$HOME/.config/pepesan-kasm"
install -m 600 examples/inventory.example "$HOME/.config/pepesan-kasm/inventory-my-server"
```

```ini
# Example content; keep the real inventory outside the repository.
[kasm]
203.0.113.10 node_name=kasmdemo

[kasm:vars]
ansible_user=root
ansible_become=false
```

```bash
# Run the playbooks with the external inventory.
INVENTORY="$HOME/.config/pepesan-kasm/inventory-my-server"
ansible-playbook -i "$INVENTORY" pepesan.kasm.site_kasm \
  -e kasm_base_domain=kasm.example.com \
  -e letsencrypt_email=you@example.com 2>&1 | tee install.log

# Register a workspace (with no image given, the default one is used)
ansible-playbook -i "$INVENTORY" pepesan.kasm.kasm_workspace 2>&1 | tee workspace.log
```

The collection playbooks can be run by name:
`pepesan.kasm.site_kasm`, `pepesan.kasm.kasm_workspace`,
`pepesan.kasm.kasm_session`, `pepesan.kasm.kasm_user`,
`pepesan.kasm.kasm_uninstall`, `pepesan.kasm.preflight_kasm_inventory`
(structure only), and `pepesan.kasm.preflight_kasm_dns_tls` (public DNS and
trusted HTTPS/TLS only). The first installation takes several minutes; send
output to a log with `tee` and follow it with `tail -f`.

The full guide, with every variable and the troubleshooting table, is in [docs/usage.md](https://github.com/pepesan/ansible-collection-kasm/blob/main/docs/usage.md).

## Passwords

Every password can be passed as a parameter; if you do not, a random one (20 characters) is generated once and reused on
later runs. They are kept on the machine that runs Ansible, never on a repository:

| Password | Where to find it | Fix one with |
|---|---|---|
| Linux user `student` | access CSV (`student_user`, `student_password`) and `.credentials/` | `-e student_password_plain=...` |
| Kasm `admin@kasm.local` | access CSV (`kasm_admin_user`, `kasm_admin_password`) and `.credentials/` | `-e kasm_admin_password=...` |
| Kasm built-in `user@kasm.local` | access CSV (`kasm_normal_user`, `kasm_normal_user_password`) and `.credentials/` | `-e kasm_default_user_password=...` |
| Kasm users created with `kasm_user` | `.credentials/` only | `-e kasm_user_password=...` |

The CSV is `access-data-<inventory file name>.csv` in the directory you run from (mode 600), with `kasm_url` first and rows
sorted by that URL. **Never commit the CSV, `.credentials/` or your inventory**: the server IP is a secret too. Details in
[`kasm_credentials`](https://github.com/pepesan/ansible-collection-kasm/blob/main/roles/kasm_credentials/README.md).

## Testing

- `ansible-lint` (production profile) and `yamllint` pass with no failures.
- Molecule scenarios, run with fully qualified names through `scripts/molecule.sh <role>`, for `linux_user`, `student`
  and `kasm_credentials`. Roles that touch the host kernel are refused by the script on purpose.
- The roles that talk to a live Kasm (`kasm_workspace`, `kasm_session`, `kasm_group`, `kasm_user`, `kasm_docker_image`) cannot
  run in an isolated container, so they are verified end to end against a real server instead.
- End-to-end on clean Ubuntu 24.04 and 26.04 and Debian 12 and 13 servers: full install, repeat (no changes), workspace, session, user, uninstall and reinstall.

See [CONTRIBUTING.md](https://github.com/pepesan/ansible-collection-kasm/blob/main/CONTRIBUTING.md).

## Related repositories

- [`pepesan/workspaces-core-images`](https://github.com/pepesan/workspaces-core-images): Kasm core images (the default
  workspace image, `pepesan/core-ubuntu-resolute`, comes from here).
- [`pepesan/kasm-workspaces-images`](https://github.com/pepesan/kasm-workspaces-images): ready-made Kasm workspace images.

## License

GPL-3.0-or-later. See [LICENSE](https://github.com/pepesan/ansible-collection-kasm/blob/main/LICENSE). The third-party roles listed above are by Jeff Geerling and keep their own license (MIT). This
collection does not copy or redistribute their code, it only uses them.
