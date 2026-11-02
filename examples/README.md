# Examples: install and manage Kasm

Run every command from this directory. The wrappers set `ansible.cfg` from
their own location, accept the inventory path explicitly, and keep generated
credentials outside the checkout.

## 1. Install Ansible dependencies

Prerequisites on the control node: `ansible-core` 2.15+, `ansible-galaxy`,
`jq`, and network access to Ansible Galaxy and Docker Hub. Install Ansible
using your OS/package manager or Python environment; do not run Galaxy
installation as root.

```bash
cd /path/to/ansible-collection-kasm/examples
./install_dependencies.sh
```

The script installs the collection from this checkout (not a potentially
older published copy), its collection dependencies, and the pinned third-party
roles from `../requirements.yml`. It builds the local collection into a
temporary directory, installs it into the current user's Ansible paths, then
removes the temporary archive.

`requirements.yml` pins `geerlingguy.docker` 8.0.0, `geerlingguy.swap` 2.2.0,
and `geerlingguy.certbot` 5.5.0. It also declares `community.docker`,
`community.general`, and `ansible.posix`. Ansible Galaxy installs collections
and roles with separate commands because a collection cannot depend on roles;
the script runs both. No `sudo` is needed.

## 2. Inventory and private files

The tracked `inventory.example` contains only the documentation address
`203.0.113.10`. Copy it before editing, or pass an existing inventory that
remains outside this repository:

```bash
mkdir -p "$HOME/.config/pepesan-kasm"
install -m 600 inventory.example "$HOME/.config/pepesan-kasm/inventory-my-server"
```

An inventory for this collection uses `[kasm]` and defines `node_name` for
each host. For a legacy file inventory with `[ubuntu]` and no `[kasm]`, the
wrappers create a temporary `[kasm:children]` overlay in `/tmp`. It is a
symlink to the source inventory, not a copy. The overlay is removed at exit;
the original file is never edited. New inventories should use `[kasm]`
directly.

By default, generated password files, the local API-key copy, and CSV output
go under `$HOME/.local/share/pepesan-kasm/examples/` (CSV in `csv/`). The CSV
filename is `access-data-<source-inventory-basename>.csv`; it stays tied to the
original inventory even when the wrapper uses a temporary group overlay.
Override that location with `KASM_DATA_DIR`, but keep it outside the checkout;
relative values resolve from the caller's current directory and paths inside
the repository are rejected. The wrapper changes into the private directory
before Ansible runs, so secrets are not written under `examples/`.

To inspect the safe sample inventory from this directory:

```bash
ansible-inventory --graph
```

## 3. Validate inventory, DNS, and TLS

The inventory preflight checks the collection group and `node_name`; it makes
no SSH connection. The DNS/TLS preflight is read-only: it checks public A/AAAA
records against `ansible_host` (or the inventory hostname), then verifies
HTTPS from the control node with certificate validation enabled.

```bash
INVENTORY="$HOME/.config/pepesan-kasm/inventory-my-server"
./00_preflight_inventory.sh "$INVENTORY"
./preflight_dns_tls.sh "$INVENTORY" kasm.example.com
```

The DNS check requires public records and a matching expected address. The
TLS check requires the service to be running and its certificate to be trusted
for the resulting `node_name.<base_domain>`. The preflight does not check
port 80; Let's Encrypt's HTTP-01 challenge requires it during installation.

## 4. Install Kasm with TLS

Use the custom-domain script for a public deployment. It runs the DNS
preflight before any installation role and then configures Docker, Kasm, and
Let's Encrypt:

```bash
LOG_DIR="${KASM_DATA_DIR:-$HOME/.local/share/pepesan-kasm/examples}/logs"
install -d -m 700 "$LOG_DIR"
install -m 600 /dev/null "$LOG_DIR/install.log"
./02_install_custom_domain.sh "$INVENTORY" kasm.example.com admin@example.com \
  2>&1 | tee "$LOG_DIR/install.log"
```

Use the base domain configured in your inventory and an email you control for
Let's Encrypt. The other installation scripts are examples only:
`01_install_default_domain.sh` uses `example.com`, and
`03_install_no_tls.sh` disables Let's Encrypt. Do not use those for a public
deployment.

Follow the Ansible output from another control-node terminal:

```bash
LOG_DIR="${KASM_DATA_DIR:-$HOME/.local/share/pepesan-kasm/examples}/logs"
tail -f "$LOG_DIR/install.log"
```

For Kasm's root-only detailed installer log, use SSH:

```bash
ssh root@<server> 'tail -f /opt/kasm/data/opt/kasm_deploy.log'
```

## 5. Register terminal, desktop, and DinD workspaces

`05_workspace_create_custom_image.sh` takes the inventory, image, and
workspace name. It sets `kasm_workspace_privileged=true` automatically when
the image reference contains `dind`, which is required for Docker-in-Docker.
The tested images are:

| Type | Image |
|---|---|
| Terminal | `kasmweb/terminal:1.19.0` |
| Full desktop | `pepesan/mi-ubuntu-resolute-kasm-desktop:1.0` |
| Docker-in-Docker | `pepesan/mi-ubuntu-resolute-kasm-ansible-dind:1.2` |

For each image, register the workspace, start and destroy a session, then
remove the workspace. Example for the terminal:

```bash
IMAGE=kasmweb/terminal:1.19.0
NAME=example-terminal
LOG_DIR="${KASM_DATA_DIR:-$HOME/.local/share/pepesan-kasm/examples}/logs"
install -d -m 700 "$LOG_DIR"
install -m 600 /dev/null "$LOG_DIR/workspace-deploy.log"
./05_workspace_create_custom_image.sh "$INVENTORY" "$IMAGE" "$NAME" \
  2>&1 | tee "$LOG_DIR/workspace-deploy.log"
./kasm_session.sh "$INVENTORY" present user@kasm.local "$IMAGE"
./kasm_session.sh "$INVENTORY" absent user@kasm.local "$IMAGE"
./06_workspace_delete.sh "$INVENTORY" "$IMAGE"
```
While the workspace image is pulled and registered, follow the Ansible output
from a second control-node terminal:

```bash
LOG_DIR="${KASM_DATA_DIR:-$HOME/.local/share/pepesan-kasm/examples}/logs"
tail -f "$LOG_DIR/workspace-deploy.log"
```

Repeat with `IMAGE=pepesan/mi-ubuntu-resolute-kasm-desktop:1.0` and
`NAME=example-desktop`, then with
`IMAGE=pepesan/mi-ubuntu-resolute-kasm-ansible-dind:1.2` and
`NAME=example-dind`. For a DinD image, session startup checks that the nested
Docker daemon responds to `docker info` when the session is running. If Kasm
reports it as paused, the playbook defers the check. Connect to that same
session and rerun the playbook to verify nested Docker.

`04_workspace_create.sh` accepts the inventory and optional image/name; its
default image is `pepesan/mi-ubuntu-resolute-kasm:1.0`. Workspace deletion
removes the registered image and, by default, that workspace's persistent
profiles. Use `keep_profiles` only when retaining those files is intended.

## 6. Create and delete a Kasm user

The user wrapper takes an inventory, `present` or `absent`, and a username.
The role generates and persists a password in the private data directory:

```bash
TEST_USER=kasm-example-test@example.com
./kasm_user.sh "$INVENTORY" present "$TEST_USER"
# Optional: start and destroy a session for this user after creating a workspace.
./kasm_user.sh "$INVENTORY" absent "$TEST_USER"
```

The key bootstrapped by the workspace role was verified for user listing,
creation, and deletion on Kasm 1.19.0. Manually supplied keys need the
corresponding Users View/Create/Delete permissions.

## 7. Uninstall and restore the test server

`07_kasm_uninstall.sh` is destructive: it removes Kasm's database, workspaces,
sessions, profiles, install files, and cached Docker image. It keeps the host's
Let's Encrypt certificate by default. Run it only against a disposable test
server, then reinstall with the real domain and email:

```bash
./07_kasm_uninstall.sh "$INVENTORY"
./02_install_custom_domain.sh "$INVENTORY" kasm.example.com admin@example.com \
./preflight_dns_tls.sh "$INVENTORY" kasm.example.com
```

See the [usage guide](../docs/usage.md) for playbook variables, credential
files, and further operational details.
