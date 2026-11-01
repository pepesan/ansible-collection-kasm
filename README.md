# pepesan.kasm

[Español](README.es.md)

Ansible collection to install and manage [Kasm Workspaces](https://kasmweb.com/) on Ubuntu servers: Docker, a
Linux user, Kasm itself with a real Let's Encrypt certificate, group policy, workspaces, users, sessions and a
clean uninstall. Every step is idempotent: running it again changes nothing.

> **Status: pre-release (0.0.1).** Tested end to end on a clean Ubuntu 26.04 server with Kasm 1.19.0. Not published
> on Ansible Galaxy yet, so the `ansible-galaxy` commands below work once it is.
> This is an independent project, not affiliated with or endorsed by Kasm Technologies.

## What is inside

| Role | What it does |
|---|---|
| [`docker`](roles/docker/README.md) | Docker Engine and the kernel tuning Kasm needs |
| [`student`](roles/student/README.md) | The `student` Linux user (`docker` and `sudo` groups) with a random password |
| [`linux_user`](roles/linux_user/README.md) | Generic Linux user with a persisted random password (`student` is a thin wrapper) |
| [`kasm_credentials`](roles/kasm_credentials/README.md) | Random Kasm passwords and the access CSV (one row per server) |
| [`kasm`](roles/kasm/README.md) | Installs Kasm Workspaces, with TLS from Let's Encrypt by default |
| [`kasm_group`](roles/kasm_group/README.md) | Session policy and hardening of a Kasm group (keepalive, clipboard, downloads...) |
| [`kasm_docker_image`](roles/kasm_docker_image/README.md) | Pulls or removes an image inside Kasm's Docker |
| [`kasm_workspace`](roles/kasm_workspace/README.md) | Registers or deletes a workspace (default image: a small Ubuntu 26.04 desktop) |
| [`kasm_user`](roles/kasm_user/README.md) | Creates or deletes a Kasm user through the public API |
| [`kasm_session`](roles/kasm_session/README.md) | Starts or destroys a user's session of a workspace |
| [`kasm_uninstall`](roles/kasm_uninstall/README.md) | Removes Kasm for a clean reinstall |

The roles are used by their fully qualified name, for example `pepesan.kasm.kasm_workspace`.

## Requirements

- **Control node:** `ansible-core` 2.15 or newer and SSH access as `root` to the server.
- **Server:** Ubuntu (tested on 26.04), with ports 80 and 443 free. For a real certificate,
  `<node_name>.<kasm_base_domain>` must already resolve to the server.
- **Collections:** `community.docker`, `community.general` and `ansible.posix` are installed automatically with this one.
- **Third-party roles, which are NOT included** (a collection cannot depend on roles, so install them yourself):

  | Role | Author | Used by |
  |---|---|---|
  | [`geerlingguy.docker`](https://github.com/geerlingguy/ansible-role-docker) | Jeff Geerling | `docker` |
  | [`geerlingguy.swap`](https://github.com/geerlingguy/ansible-role-swap) | Jeff Geerling | `kasm` |
  | [`geerlingguy.certbot`](https://github.com/geerlingguy/ansible-role-certbot) (>= 5.4.1) | Jeff Geerling | `kasm` |

  All the credit for those automations belongs to their author. This collection only uses them; it does not copy or
  modify their code. If one is missing, the role fails with a message that shows the command to install it.

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

An inventory with one host per Kasm server. `node_name` decides the DNS name: the server is reached at
`<node_name>.<kasm_base_domain>`.

```ini
# inventory-my-server
[ubuntu]
203.0.113.10 node_name=kasmdemo

[ubuntu:vars]
ansible_user=root
ansible_become=false
```

```bash
# Install Kasm with a real certificate (https://kasmdemo.kasm.example.com)
ansible-playbook -i inventory-my-server pepesan.kasm.site_kasm \
  -e kasm_base_domain=kasm.example.com \
  -e letsencrypt_email=you@example.com 2>&1 | tee install.log

# Register a workspace (with no image given, the default one is used)
ansible-playbook -i inventory-my-server pepesan.kasm.kasm_workspace 2>&1 | tee workspace.log
```

The four playbooks of the collection can be run by name: `pepesan.kasm.site_kasm`, `pepesan.kasm.kasm_workspace`,
`pepesan.kasm.kasm_session` and `pepesan.kasm.kasm_uninstall`. The first install takes several minutes (the slow part is
Kasm's own installer); sending the output to a log with `tee` lets you follow it with `tail -f`.

The full guide, with every variable and the troubleshooting table, is in [docs/usage.md](docs/usage.md).

## Passwords

Every password can be passed as a parameter; if you do not, a random one (20 characters) is generated once and reused on
later runs. They are kept on the machine that runs Ansible, never on a repository:

| Password | Where to find it | Fix one with |
|---|---|---|
| Linux user `student` | access CSV and `.credentials/` | `-e student_password_plain=...` |
| Kasm `admin@kasm.local` | access CSV and `.credentials/` | `-e kasm_admin_password=...` |
| Kasm built-in `user@kasm.local` | access CSV and `.credentials/` | `-e kasm_default_user_password=...` |
| Kasm users created with `kasm_user` | `.credentials/` only | `-e kasm_user_password=...` |

The CSV is `access-data-<inventory file name>.csv` in the directory you run from (mode 600). **Never commit the CSV,
`.credentials/` or your inventory**: the server IP is a secret too. Details in
[`kasm_credentials`](roles/kasm_credentials/README.md).

## Testing

- `ansible-lint` (production profile) and `yamllint` pass with no failures.
- Molecule scenarios, run with fully qualified names through `scripts/molecule.sh <role>`, for `linux_user`, `student`
  and `kasm_credentials`. Roles that touch the host kernel are refused by the script on purpose.
- The roles that talk to a live Kasm (`kasm_workspace`, `kasm_session`, `kasm_group`, `kasm_user`, `kasm_docker_image`) cannot
  run in an isolated container, so they are verified end to end against a real server instead.
- End-to-end on a clean Ubuntu 26.04 server: full install, repeat (no changes), workspace, session.

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Related repositories

- [`pepesan/workspaces-core-images`](https://github.com/pepesan/workspaces-core-images): Kasm core images (the default
  workspace image, `pepesan/core-ubuntu-resolute`, comes from here).
- [`pepesan/kasm-workspaces-images`](https://github.com/pepesan/kasm-workspaces-images): ready-made Kasm workspace images.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE). The third-party roles listed above keep their own license.
