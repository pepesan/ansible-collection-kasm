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
./00_install_dependencies.sh
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

The tracked `inventory.example` is a template with the placeholder address
`X.X.X.X` and base domain `kasm.example.com`. Copy it beside the scripts and
edit the address, machine name, and domain for your server:

```bash
umask 077
cp -n inventory.example inventory
chmod 600 inventory
```

The local `inventory` file is ignored by Git and is not included in the
collection. Keep it mode `600`; do not commit it.

```ini
# Replace X.X.X.X with your server's SSH address.
[kasm]
X.X.X.X node_name=kasmdemo

[kasm:vars]
ansible_user=root
ansible_become=false
# Shared DNS suffix; node_name=kasmdemo becomes kasmdemo.kasm.example.com.
kasm_base_domain=kasm.example.com
kasm_training_project=client-01
letsencrypt_email=admin@example.com
```

Its structure:

- `[kasm]` is the group of managed servers. Add one line per machine; the
  first value is the SSH target (IP address or hostname). Replace the sample
  address with the real target.
- `node_name` is that machine's unique DNS name prefix. For example,
  `node_name=kasmdemo` and `kasm_base_domain=kasm.example.com` form
  `kasmdemo.kasm.example.com`. Give each machine a different `node_name`.
- `[kasm:vars]` holds variables shared by those machines. `ansible_user=root`
  connects over SSH as root, so `ansible_become=false`. With a non-root SSH
  account, set `ansible_user` to that account and enable `ansible_become`.
- `kasm_base_domain` is the shared DNS suffix. The DNS/TLS preflight and the
  custom-domain installer must use the same base domain; its A/AAAA record
  must resolve to the corresponding server.
- `kasm_training_project` is an optional course/project label used in the
  credentials role's dated CSV filename when no exact CSV name is supplied.
  The example scripts supply an exact inventory-based CSV name, so this
  variable does not change their CSV filename.
- `letsencrypt_email` is the contact address for certificate-expiry notices.
  Replace the placeholder with an address you monitor before installation.

By default, generated passwords, the local API-key copy, and CSV output go
under `$HOME/pepesan-kasm-data/` (CSV in `csv/`). This is a visible directory
directly under your home folder. The wrapper creates it automatically on first
run with mode `700`; no manual `mkdir` or data-directory setup is needed. The
CSV filename is
`access-data-<source-inventory-basename>.csv`, based on the original inventory
even when a temporary compatibility overlay is used.

Keep `KASM_DATA_DIR` outside the checkout: it contains credentials and runtime
data, so pointing it at `examples/` is not safe. Set it for one command:

```bash
KASM_DATA_DIR="$HOME/mi-directorio-kasm" ./01_preflight_inventory.sh ./inventory
```

To reuse the same location for several commands in the current terminal, export
it first:

```bash
export KASM_DATA_DIR="$HOME/mi-directorio-kasm"
./01_preflight_inventory.sh ./inventory
./02_preflight_dns_tls.sh ./inventory kasm.example.com
```

Without an override, the scripts use `$HOME/pepesan-kasm-data`. Relative
override paths resolve from the caller's current directory. The wrapper changes
into the private directory before Ansible runs. In another terminal, set the
same value before following the logs; otherwise use the default path:

To inspect your local inventory from this directory:

```bash
ansible-inventory --graph
```

## 3. Validate inventory, DNS, and TLS

The inventory preflight checks the collection group and `node_name`; it makes
no SSH connection. The DNS/TLS preflight is read-only: it checks public A/AAAA
records against `ansible_host` (or the inventory hostname), then verifies
HTTPS from the control node with certificate validation enabled.

```bash
INVENTORY=./inventory
./01_preflight_inventory.sh "$INVENTORY"
./02_preflight_dns_tls.sh "$INVENTORY" kasm.example.com
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
LOG_DIR="${KASM_DATA_DIR:-$HOME/pepesan-kasm-data}/logs"
install -d -m 700 "$LOG_DIR"
install -m 600 /dev/null "$LOG_DIR/install.log"
./04_install_custom_domain.sh "$INVENTORY" kasm.example.com admin@example.com \
  2>&1 | tee "$LOG_DIR/install.log"
```

Use the base domain configured in your inventory and an email you control for
Let's Encrypt. The other installation scripts are examples only:
`03_install_default_domain.sh` uses `example.com`, and
`05_install_no_tls.sh` disables Let's Encrypt. Do not use those for a public
deployment.

Follow the Ansible output from another control-node terminal:

```bash
LOG_DIR="${KASM_DATA_DIR:-$HOME/pepesan-kasm-data}/logs"
tail -f "$LOG_DIR/install.log"
```

For Kasm's root-only detailed installer log, use SSH:

```bash
ssh root@<server> 'tail -f /opt/kasm/data/opt/kasm_deploy.log'
```

## 5. Register terminal, desktop, and DinD workspaces

`07_workspace_create_custom_image.sh` takes the inventory, image, and
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
LOG_DIR="${KASM_DATA_DIR:-$HOME/pepesan-kasm-data}/logs"
install -d -m 700 "$LOG_DIR"
install -m 600 /dev/null "$LOG_DIR/workspace-deploy.log"
./07_workspace_create_custom_image.sh "$INVENTORY" "$IMAGE" "$NAME" \
  2>&1 | tee "$LOG_DIR/workspace-deploy.log"
./09_kasm_session.sh "$INVENTORY" present user@kasm.local "$IMAGE"
./09_kasm_session.sh "$INVENTORY" absent user@kasm.local "$IMAGE"
./08_workspace_delete.sh "$INVENTORY" "$IMAGE"
```
While the workspace image is pulled and registered, follow the Ansible output
from a second control-node terminal:

```bash
LOG_DIR="${KASM_DATA_DIR:-$HOME/pepesan-kasm-data}/logs"
tail -f "$LOG_DIR/workspace-deploy.log"
```

For a Docker-in-Docker workspace, pass the image reference and workspace name
as the second and third arguments. The wrapper detects `dind` in the image
reference and sets `kasm_workspace_privileged=true` automatically:

```bash
IMAGE=pepesan/mi-ubuntu-resolute-kasm-ansible-dind:1.2
NAME=example-dind
./07_workspace_create_custom_image.sh "$INVENTORY" "$IMAGE" "$NAME"
./09_kasm_session.sh "$INVENTORY" present user@kasm.local "$IMAGE"
./09_kasm_session.sh "$INVENTORY" absent user@kasm.local "$IMAGE"
./08_workspace_delete.sh "$INVENTORY" "$IMAGE"
```

For the desktop image, use `IMAGE=pepesan/mi-ubuntu-resolute-kasm-desktop:1.0`
and `NAME=example-desktop`. For a DinD image, session startup also checks
that the nested Docker daemon responds to `docker info`. If Kasm reports the
session as paused, the playbook defers that check; connect to that same
session and rerun the playbook to verify Docker.

`06_workspace_create.sh` accepts the inventory and optional image/name; its
default image is `pepesan/mi-ubuntu-resolute-kasm:1.0`. Workspace deletion
removes the registered image and, by default, that workspace's persistent
profiles. Use `keep_profiles` only when retaining those files is intended.

## 6. Create and delete a Kasm user

The user wrapper takes an inventory, `present` or `absent`, and a username.
The role generates and persists a password in the private data directory:

```bash
TEST_USER=kasm-example-test@example.com
./10_kasm_user.sh "$INVENTORY" present "$TEST_USER"
# Optional: start and destroy a session for this user after creating a workspace.
./10_kasm_user.sh "$INVENTORY" absent "$TEST_USER"
```

The key bootstrapped by the workspace role was verified for user listing,
creation, and deletion on Kasm 1.19.0. Manually supplied keys need the
corresponding Users View/Create/Delete permissions.

## 7. Uninstall and restore the test server

`11_kasm_uninstall.sh` is destructive: it removes Kasm's database, workspaces,
sessions, profiles, install files, and cached Docker image. It keeps the host's
Let's Encrypt certificate by default. Run it only against a disposable test
server, then reinstall with the real domain and email:

```bash
./11_kasm_uninstall.sh "$INVENTORY"
./04_install_custom_domain.sh "$INVENTORY" kasm.example.com admin@example.com \
./02_preflight_dns_tls.sh "$INVENTORY" kasm.example.com
```

See the [usage guide](../docs/usage.md) for playbook variables, credential
files, and further operational details.
