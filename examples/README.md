# Examples: install and manage Kasm

Run every command from this directory. The wrappers set `ansible.cfg` from
their own location, accept the inventory path explicitly, and keep generated
credentials outside the checkout.

## Script reference

| Script | Purpose and arguments |
|---|---|
| `00_install_dependencies.sh` | Install this checkout, its collection dependencies, and pinned third-party roles. No arguments. |
| `01_preflight_inventory.sh [inventory]` | Validate inventory structure only; no SSH connection. Defaults to `./inventory`. |
| `02_preflight_dns_tls.sh <inventory> <base_domain>` | Check public DNS and trusted HTTPS for an already-running Kasm endpoint. |
| `03_install_default_domain.sh <inventory>` | Install with placeholder `example.com`; demonstration only, not for a public deployment. |
| `04_install_custom_domain.sh <inventory> <base_domain> <email>` | Install for a real domain after the DNS preflight passes. |
| `05_install_no_tls.sh <inventory>` | Install without Let's Encrypt; intended for local or DNS-less testing. |
| `06_workspace_create.sh <inventory> [image] [name]` | Register a workspace; defaults to `pepesan/mi-ubuntu-resolute-kasm:1.0`. |
| `07_workspace_create_custom_image.sh <inventory> <image> <name>` | Register the specified image; references containing `dind` are made privileged. |
| `08_workspace_delete.sh <inventory> <image> [keep_profiles]` | Delete a workspace; persistent profiles are deleted unless `keep_profiles` is supplied. |
| `09_kasm_session.sh <inventory> <present\|absent> <username> <image> [recover_on_boot]` | Start or destroy a session; boot recovery is enabled by default and can be disabled with `false`. |
| `10_kasm_user.sh <inventory> <present\|absent> <username>` | Create or delete a Kasm user. |
| `11_kasm_uninstall.sh <inventory>` | **Destructive:** remove the Kasm installation and its data from the target host. |

## Recommended first deployment

The numbered sections below explain each step. For a new public deployment:

1. Install dependencies with `00_install_dependencies.sh`.
2. Copy `inventory.example` to `inventory` for one host, or use
   `inventory.two-machines` for two hosts. Replace all placeholders.
3. Run `01_preflight_inventory.sh`; the install playbook checks public DNS
   before making changes.
4. Install with `04_install_custom_domain.sh`, using the inventory's base
   domain and an email you monitor.
5. After installation, run `02_preflight_dns_tls.sh` to verify DNS and the
   trusted HTTPS endpoint.
6. Register a workspace with `06_workspace_create.sh` or
   `07_workspace_create_custom_image.sh`; create a test user with
   `10_kasm_user.sh`, then start a session with `09_kasm_session.sh`.
   Verify it in Kasm, stop the session with state `absent`, and remove the test
   user with `10_kasm_user.sh` using state `absent`.
7. Remove test resources only when they are no longer needed. `08_workspace_delete.sh`
   deletes persistent profiles by default; use `11_kasm_uninstall.sh` only on a
   disposable host.

## 1. Install Ansible dependencies

Prerequisites on the control node: Bash, `ansible-core` 2.15+, `jq`, `realpath`,
the OpenSSH client, and standard utilities (`install`, `mktemp`, `tee`). The
control node needs outbound access to Ansible Galaxy and HTTPS access to
`cloudflare-dns.com` for the DNS/TLS preflight. The target must be reachable
over SSH; use root or configure an account with privilege escalation in the
inventory. The Kasm server needs outbound access to the image registry when
pulling workspace images. Install Ansible using your OS package manager or
Python environment; do not run Galaxy installation as root.

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

Choose only one template. For two hosts, use this alternative copy command
instead of the `inventory.example` copy above:

```bash
umask 077
cp -n inventory.two-machines inventory
chmod 600 inventory
```

Replace both `ansible_host=X.X.X.X` values with their SSH target addresses.
If Ansible connects to private addresses, set each host's
`kasm_dns_expected_ips` to the corresponding public address. The tracked file
is a template; the local `inventory` copy remains ignored by Git.

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

- `[kasm]` is the group of managed servers. Add one line per host. The first
  value is the inventory name; when it is an alias rather than the SSH target,
  `ansible_host` supplies the connection address.
- `node_name` is the unique DNS name prefix for each machine. For example,
  `node_name=kasmdemo-01` with `kasm_base_domain=kasm.example.com` forms
  `kasmdemo-01.kasm.example.com`. Use a different `node_name` for every host.
- `ansible_host` is the SSH target and, by default, the address checked by the
  install-time DNS preflight. DNS A/AAAA records for each
  `node_name.<kasm_base_domain>` must resolve to its public address. If SSH
  uses a private address, set that host's `kasm_dns_expected_ips` to its
  public address. Behind a proxy/load balancer, `kasm_dns_expected_ips: []`
  requires public DNS records without comparing their addresses.
- `[kasm:vars]` holds variables shared by the hosts. `ansible_user=root`
  connects over SSH as root, so `ansible_become=false`. With a non-root SSH
  account, set `ansible_user` to that account and enable `ansible_become`.
- `kasm_base_domain` is the shared DNS suffix. The DNS/TLS preflight and the
  custom-domain installer must use the same base domain; each host's DNS record
  must resolve to its corresponding server.
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

To reuse the same location for subsequent commands in the current terminal,
export it first:

```bash
export KASM_DATA_DIR="$HOME/mi-directorio-kasm"
./01_preflight_inventory.sh ./inventory
# Keep this export for installation and workspace commands below.
```

Without an override, the scripts use `$HOME/pepesan-kasm-data`. Relative
override paths resolve from the caller's current directory. The wrapper changes
into the private directory before Ansible runs. In another terminal, set the
same value before following the logs; otherwise use the default path:

### Generated data, permissions, and retention

The wrappers create `KASM_DATA_DIR` and `.credentials/` with mode `700`, then
run Ansible from that private directory. Generated password files under
`.credentials/` use mode `600`. The CSV task sets `csv/` to mode `755`, but
these wrappers keep it below the mode-`700` `KASM_DATA_DIR`; the CSV file
itself is mode `600`.

| Content | Default location | Notes |
|---|---|---|
| Generated passwords | `$KASM_DATA_DIR/.credentials/` | Per-host `student`, built-in Kasm admin/user, and `kasm_user` passwords; mode `600`. |
| Access CSV | `$KASM_DATA_DIR/csv/access-data-<inventory-basename>.csv` | Contains student and built-in Kasm passwords; mode `600`. |
| Local API key copy | `$KASM_DATA_DIR/kasm-api-key-<inventory-hostname>.json` | Created when registering a workspace; mode `600`. |
| Ansible logs | `$KASM_DATA_DIR/logs/install.log` and `workspace-deploy.log` | These examples create the directory as `700` and log files as `600`. |
| Kasm installer log | Server, by default `/opt/kasm/data/opt/kasm_deploy.log` | Mode `600`, readable by root; the installer redacts password, secret, and token fields. |

The control-node files are not removed by `10_kasm_user.sh` or
`11_kasm_uninstall.sh`. Deleting an application user leaves its generated
password file and CSV entry in place. Treat the CSV and `.credentials/` as
secrets: do not commit, email, or attach them to issue reports. If policy
requires a backup, keep it encrypted and access-restricted. Before uninstalling
Kasm, back up any server-side data you need; the uninstall role removes it.

To inspect your local inventory from this directory:

```bash
ansible-inventory --graph
```

With `inventory.two-machines`, this should show both `kasm01` and `kasm02`
under the `kasm` group.

## 3. Validate inventory, DNS, and TLS

The inventory preflight checks the `[kasm]` group and requires a unique,
non-empty `node_name` for every host; it makes no SSH connection. For a
Let's Encrypt install, `site_kasm` checks public A/AAAA DNS from the control
node before running installation roles. By default it compares the resolved
addresses with each host's `kasm_dns_expected_ips` (derived from
`ansible_host`, or the inventory name if that is unset).

If a host fails DNS preflight, its installation roles do not run; other hosts
continue, and the final summary lists the failed host and domain. Common
failures:

- `public DNS returned no A or AAAA records`: create the required public DNS
  record for that host's `node_name.<kasm_base_domain>`.
- `public DNS addresses do not match kasm_dns_expected_ips`: correct the DNS
  record or expected public address. For NAT, use the public address rather
  than the private SSH address; for a proxy/load balancer, use an empty
  `kasm_dns_expected_ips` list to require records without comparing addresses.
- `could not query Cloudflare public DNS over HTTPS from the Ansible control node`:
  allow outbound HTTPS from the control node to `cloudflare-dns.com`.

```bash
INVENTORY=./inventory
./01_preflight_inventory.sh "$INVENTORY"
```

Run `02_preflight_dns_tls.sh` only when Kasm is already running: its HTTPS
check cannot pass before a first installation. The `04_install_custom_domain.sh`
script performs the DNS preflight itself before installation roles run.
The standalone DNS/TLS check also requires matching public A/AAAA records,
a trusted certificate for `node_name.<base_domain>`, and a running Kasm
service. It does not check port 80; Let's Encrypt's HTTP-01 challenge requires
port 80 to be reachable during installation.

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
Let's Encrypt. After installation completes, verify DNS and trusted HTTPS:

```bash
./02_preflight_dns_tls.sh "$INVENTORY" kasm.example.com
```

The other installation scripts are examples only:
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

By default, `09_kasm_session.sh` installs a per-session systemd unit. After a
host reboot, it waits for host and nested Docker plus healthy Kasm API, manager,
and agent. It starts the same session container only if it is `created` or
`exited`, checks stability for 15 seconds, and never replaces the session.
`absent` removes the unit. Disable boot recovery for a present session with:

```bash
./09_kasm_session.sh "$INVENTORY" present user@kasm.local "$IMAGE" false
```

This restarts the same container, but cannot restore processes interrupted by
the host shutdown.

For the desktop image, use `IMAGE=pepesan/mi-ubuntu-resolute-kasm-desktop:1.0`
and `NAME=example-desktop`. For a DinD image, session startup also checks
that the nested Docker daemon responds to `docker info`. If Kasm reports the
session as paused, the playbook defers that check; connect to that same
session and rerun the playbook to verify Docker.

`06_workspace_create.sh` accepts the inventory and optional image/name; its
default image is `pepesan/mi-ubuntu-resolute-kasm:1.0`. `08_workspace_delete.sh`
closes active sessions using the workspace, unregisters it, and deletes its
persistent profile directories by default. It also tries to remove the
associated image and prune unused layers; a shared image tag can prevent image
removal. Profile deletion is irreversible; pass `keep_profiles` only when
retaining those directories is intentional.

## 6. Create and delete a Kasm user

The user wrapper takes an inventory, `present` or `absent`, and a username.
The role generates and persists a password in the private data directory:

```bash
TEST_USER=kasm-example-test@example.com
./10_kasm_user.sh "$INVENTORY" present "$TEST_USER"
# Optional: start and destroy a session for this user after creating a workspace.
./10_kasm_user.sh "$INVENTORY" absent "$TEST_USER"
```

Deleting the Kasm account leaves its local password file and CSV entry. The
user role does not clean up persistent profiles; workspace deletion affects
every user of that workspace, so do not use it just to remove one user's data.

The key bootstrapped by the workspace role was verified for user listing,
creation, and deletion on Kasm 1.19.0. Manually supplied keys need the
corresponding Users View/Create/Delete permissions.

## 7. Uninstall and restore the test server

`11_kasm_uninstall.sh` is destructive: it removes Kasm's database, workspaces,
sessions, profiles, install files, and cached Docker image from the server.
It keeps the host's Let's Encrypt certificate by default. It does not remove
the control-node `KASM_DATA_DIR` or the credentials stored there. Run it only
against a disposable test server, then reinstall with the real domain and
email:

```bash
./11_kasm_uninstall.sh "$INVENTORY"
./04_install_custom_domain.sh "$INVENTORY" kasm.example.com admin@example.com
./02_preflight_dns_tls.sh "$INVENTORY" kasm.example.com
```

See the [usage guide](../docs/usage.md) for variable precedence, per-role
variable references, credential files, and further operational details.
