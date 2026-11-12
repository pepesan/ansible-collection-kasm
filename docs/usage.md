# Usage guide

[Español](usage.es.md) · [Back to the README](../README.md)

Every command below uses the collection playbooks by name (`pepesan.kasm.<playbook>`). Their source is in
[`playbooks/`](../playbooks); [`examples/`](../examples) contains the safe config, sample inventory, dependency installer,
and operational wrappers. See [`examples/README.md`](../examples/README.md) for setup and image lifecycle commands.

> Always send the playbook output to a log with `tee`, so you can follow it with `tail -f` from another terminal.

## 1. Before you start

**Control node** (your machine): `ansible-core` 2.15+ and SSH access as `root`
to a supported server (Ubuntu 24.04/26.04, Debian 12/13, AlmaLinux 9/10 or
Rocky Linux 9/10). Install the collection and third-party roles once (see the
[README](../README.md#installation)).

**Inventory.** One host per Kasm server. `node_name` decides the DNS name: the server is reached at
`<node_name>.<kasm_base_domain>`.

```ini
[kasm]
203.0.113.10 node_name=kasmdemo

[kasm:vars]
ansible_user=root
ansible_become=false
```

With `kasm_base_domain=kasm.example.com` that host becomes `https://kasmdemo.kasm.example.com`. Keep real inventories
outside this repository, for example in `$HOME/.config/pepesan-kasm/inventory-my-server`. Create a private copy of the
tracked placeholder:

```bash
mkdir -p "$HOME/.config/pepesan-kasm"
install -m 600 examples/inventory.example "$HOME/.config/pepesan-kasm/inventory-my-server"
```

**DNS.** For a real certificate, `<node_name>.<kasm_base_domain>` must already resolve to the server, ideally with no
AAAA record pointing somewhere broken, and port 80 must be free for the HTTP-01 challenge.

### Variable sources and role references

For the configuration sources used by these playbooks, precedence is: role
defaults < inventory variables < playbook variables < command-line extra
variables (`-e`). `-e` overrides values set in the inventory or playbook.
Other Ansible variable sources can have their own precedence; see the
[Ansible precedence reference](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence)
for the complete order.

Put per-server values such as `node_name` on each host in the inventory, and
shared values such as `kasm_base_domain` and `letsencrypt_email` in
`[kasm:vars]`. Use `-e` for a one-run override. `KASM_DATA_DIR` is different:
it is an environment variable read by the example shell scripts to choose
where local CSVs and credential files are stored; Ansible does not treat it
as a collection variable.

Never put real passwords in a normal inventory or literal `-e
password=value` arguments. Use Ansible Vault for fixed secrets; generated
credentials are stored on the control node as described below.

Each role README documents its public variables, defaults, required values,
and effects. The workspace role groups its variables by function.

| Role | Variable reference |
|---|---|
| `docker` | [Role README](../roles/docker/README.md) |
| `kasm` | [Role README](../roles/kasm/README.md) |
| `kasm_credentials` | [Role README](../roles/kasm_credentials/README.md) |
| `kasm_docker_image` | [Role README](../roles/kasm_docker_image/README.md) |
| `kasm_group` | [Role README](../roles/kasm_group/README.md) |
| `kasm_session` | [Role README](../roles/kasm_session/README.md) |
| `kasm_uninstall` | [Role README](../roles/kasm_uninstall/README.md) |
| `kasm_user` | [Role README](../roles/kasm_user/README.md) |
| `kasm_workspace` | [Role README](../roles/kasm_workspace/README.md) |
| `linux_user` | [Role README](../roles/linux_user/README.md) |
| `student` | [Role README](../roles/student/README.md) |

Encrypted variable files can be passed with `-e @vault.yml --ask-vault-pass`.

## 2. Install Kasm (`pepesan.kasm.site_kasm`)

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-my-server" pepesan.kasm.site_kasm \
  -e kasm_base_domain=kasm.example.com \
  -e letsencrypt_email=you@example.com 2>&1 | tee install.log
```

What it does, in order:

1. `docker`: prefers IPv4 in glibc, installs Docker Engine and Compose, loads the kernel modules and sysctl values Kasm needs.
2. `student`: creates the `student` Linux user.
3. `kasm_credentials`: generates the Kasm passwords (or uses the ones you pass).
4. `kasm`: swapfile, Let's Encrypt certificate, Kasm itself, certificate renewal hook.
5. `kasm_group`: applies the session policy (keepalive, clipboard, downloads...) to the `All Users` group.
6. `kasm_credentials` writes the access CSV with the address and credentials of the server.

Frequently used variables:

| Variable | Default | Role | Meaning |
|---|---|---|---|
| `kasm_base_domain` | `example.com` | `kasm` | Base domain; the host is `<node_name>.<kasm_base_domain>` |
| `letsencrypt_email` | `admin@<kasm_base_domain>` | `kasm` | E-mail for certbot |
| `kasm_letsencrypt_enabled` | `true` | `kasm` | `false` keeps Kasm's self-signed certificate |
| `kasm_version` / `kasm_image_tag` | `1.19.0` / `1.19.0-ls154` | `kasm` | Kasm release and the linuxserver image tag |
| `kasm_swap_file_size_mb` | `4096` | `kasm` | Swap file size |
| `student_name` | `student` | `student` | Name of the Linux user |
| `kasm_group_keepalive_seconds` | `3600` | `kasm_group` | Seconds before an idle session is paused or deleted |
| `kasm_group_keepalive_action` | `pause` | `kasm_group` | `pause` or `delete` |

Without TLS (for a local test): add `-e kasm_letsencrypt_enabled=false`.

## 3. Credentials and generated files

Everything is created on **your machine**, in the directory you run from, and is git-ignored. Never commit it.

| File | What it holds |
|---|---|
| `.credentials/[<project>-]<host>-<student_name>.pass` | Password of the Linux user |
| `.credentials/[<project>-]<host>-kasm-admin.pass` | Password of `admin@kasm.local` |
| `.credentials/[<project>-]<host>-kasm-user.pass` | Password of the built-in `user@kasm.local` |
| `.credentials/[<project>-]<host>-kasm-user-<username>.pass` | Password of a user created with `kasm_user` |
| `access-data-<project|inventory>.csv` | One row per node; first column `kasm_url`, sorted by the full Kasm URL: IP, student username/password and Kasm admin/normal-user credentials |
| `kasm-api-key-<inventory_hostname>.json` | Copy of the persistent API key (created with the first workspace) |

Passwords are generated **once** and reused on later runs. To get new ones, delete `.credentials/` before running the
install. Any of them can be fixed with a parameter instead: `-e student_password_plain=...`,
`-e kasm_admin_password=...`, `-e kasm_default_user_password=...`, `-e kasm_user_password=...`.

The API key itself lives on the server in `/opt/kasm/.kasm_api_key.json` (mode 600), created the first time a workspace is
registered.

## 4. Workspaces (`pepesan.kasm.kasm_workspace`)

With no image given, the default one is used: `pepesan/core-ubuntu-resolute:1.20` (a small Ubuntu 26.04 desktop),
registered as "Core Ubuntu Resolute".

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-my-server" pepesan.kasm.kasm_workspace 2>&1 | tee workspace.log
```

Your own image (the name has spaces, so it goes in JSON form: a plain `-e var=a b` truncates at the first space):

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-my-server" pepesan.kasm.kasm_workspace \
  -e kasm_docker_image_name=user/image:1.0 \
  -e kasm_workspace_image=user/image:1.0 \
  -e '{"kasm_workspace_name": "My workspace"}' \
  -e kasm_workspace_cores=2 -e kasm_workspace_memory_gb=4
```

Images that run Docker inside the session (DinD) need `-e kasm_workspace_privileged=true`.

| Variable | Default | Meaning |
|---|---|---|
| `kasm_workspace_image` | the default image (when creating) | Docker image of the workspace |
| `kasm_workspace_name` | `Core Ubuntu Resolute` with the default image, required otherwise | Name shown in Kasm |
| `kasm_workspace_cores` / `kasm_workspace_memory_gb` | `4` / `8` | Resources per session |
| `kasm_workspace_privileged` | `false` | Needed for Docker inside the session |
| `kasm_workspace_state` | `present` | `present` or `absent` |

### Delete workspaces

Deleting never uses a default image: say which one, or delete them all.

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-my-server" pepesan.kasm.kasm_workspace \
  -e kasm_workspace_state=absent -e kasm_workspace_image=user/image:1.0 \
  -e kasm_docker_image_name=user/image:1.0
# every workspace:  -e kasm_workspace_state=absent -e kasm_workspace_clean_all=true
```

By default the persistent profiles of that workspace are deleted too (`kasm_workspace_delete_persistent_data`).

## 5. Sessions (`pepesan.kasm.kasm_session`)

Starts (or, with `-e kasm_session_state=absent`, destroys) a user's session of an already registered workspace, and waits
until it is running. If the session already exists, nothing is launched.

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-my-server" pepesan.kasm.kasm_session \
  -e kasm_session_workspace=pepesan/core-ubuntu-resolute:1.20 \
  -e kasm_session_user=user@kasm.local
```

`kasm_session_workspace` is the image name or the friendly name shown in the dashboard. Starting a session in advance
avoids the cold start the user would otherwise wait for at the first login.

## 6. Users (`pepesan.kasm.kasm_user`)

Creates or deletes a Kasm user through the public API. The password is random by default (saved in
`.credentials/<host>-kasm-user-<username>.pass`) or the one you pass with `-e kasm_user_password=...`. See the role README
for the other fields.

## 7. Session policy (`pepesan.kasm.kasm_group`)

`site_kasm` already applies it. To change it, set the variables and run the role again, for example
`kasm_group_keepalive_seconds`, `kasm_group_allow_clipboard_down`, `kasm_group_allow_downloads`, `kasm_group_allow_uploads`
or `kasm_group_allow_printing` (all clipboard, download, upload and print permissions are off by default). The role only
changes settings whose value differs.

## 8. Uninstall (`pepesan.kasm.kasm_uninstall`)

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-my-server" pepesan.kasm.kasm_uninstall 2>&1 | tee uninstall.log
```

**This deletes the Kasm data of the server.** By default it keeps the Let's Encrypt certificate
(`kasm_uninstall_remove_letsencrypt_certs: false`), so a reinstall does not spend one of the few certificates Let's Encrypt
issues per name and week. To reinstall from scratch, uninstall and then run `site_kasm` again. The uninstall does not
touch your `.credentials/`.

## 9. Check the result (read-only)

Run these on the server; none of them changes anything.

```bash
# Kasm's own containers
docker exec kasm docker ps --format '{{.Names}}  {{.Status}}'

# Images pulled into Kasm's Docker
docker exec kasm docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}'

# Registered workspaces
docker exec kasm docker exec kasm_db psql -U kasmapp -d kasm -c "SELECT name, friendly_name FROM images;"

# Sessions currently alive
docker exec kasm docker exec kasm_db psql -U kasmapp -d kasm \
  -c "SELECT u.username, k.operational_status FROM kasms k JOIN users u USING (user_id);"

# Installer log, live (readable by root only; it does not contain the passwords)
tail -f /opt/kasm/data/opt/kasm_deploy.log
```

## 10. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| First login hangs on "Creating a secure connection..." and the proxy returns 502 | The session container is still booting (cold start of a large image). It resolves itself in seconds to a few minutes. Start the session in advance with `kasm_session`. |
| Desktop opens with a black background but the menu works | The desktop is still rendering on a cold start. It appears shortly after. |
| Docker does not work inside the session | The workspace was created without `kasm_workspace_privileged=true`. Delete it and create it again with the flag. |
| `-e kasm_workspace_name=My workspace` registers the name "My" | A plain `-e` truncates at the first space. Use `-e '{"kasm_workspace_name": "My workspace"}'`. |
| `geerlingguy.certbot` fails with a `list` vs `boolean` conditional | A version older than `5.4.1`. Reinstall the third-party roles from `requirements.yml`. |
| A role fails saying a `geerlingguy.*` role was not found | The third-party roles are not installed: `ansible-galaxy role install -r requirements.yml`. |
| `kasm_credentials` fails with an inline inventory (`-i 10.0.0.1,`) | Fixed in this collection: the CSV name is derived from the inventory and sanitized. |
| The session is paused after an hour | Group policy. Raise `kasm_group_keepalive_seconds`. |
| `ps -u student` on the host shows Kasm's Python processes | Kasm's service containers run as UID 1001, the same number as the `student` user. They are not `student`'s processes. Do not `pkill -u student`: you would kill Kasm's API. |
