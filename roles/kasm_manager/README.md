# pepesan.kasm.kasm_manager

Installs a Kasm Workspaces **manager** straight on the host with the official installer (layout `/opt/kasm/current`): database role (`install.sh --role db`) and web app role (`--role app`) on the same host, **no local agent**. Agents are installed by [`kasm_agent`](../kasm_agent/README.md) on other hosts and register with the token this role generates.

Compared with [`kasm`](../kasm/README.md) (all-in-one: Kasm inside a `linuxserver/kasm` container), here `install.sh` runs on the host, so it sees the host OS and the containers are the official ones (`docker exec kasm_db ...`, hence `kasm_db_exec: docker exec kasm_db` in the roles that query the database).

## What it does

1. Generates the admin/user passwords ([`kasm_credentials`](../kasm_credentials/README.md), unless an earlier role already did) and checks public DNS for `kasm_manager_hostname` (Let's Encrypt only).
2. Installs Docker ([`docker`](../docker/README.md)), swap and the Let's Encrypt certificate (`geerlingguy.swap`, `geerlingguy.certbot`: third-party roles, `ansible-galaxy role install -r requirements.yml`).
3. Downloads and extracts the release `kasm_version` to `{{ kasm_dir }}/kasm_release`, saves `install.sh --help` to `{{ kasm_dir }}/install-help.txt` (MGR-01) and **uses the flags it advertises**: the role fails, pointing at that file, if some needed flag is missing.
4. Runs `install.sh --role db` and `--role app` through the kasm role's `fix_and_install_kasm.sh` (parametrized by `KASM_*` variables): `install.sh` patches, up to 3 attempts enabling disabled Docker plugins (the `kasmlogger.sock` race) and success decided by running containers, not by the exit code. The real `install.sh` error is shown and no marker is written on failure.
5. Checks that the database contains a nonempty manager-token setting, that `kasm_db`, `kasm_api`, `kasm_manager` and `kasm_proxy` are Up and that **no** `kasm_agent` runs, then writes `/opt/kasm/.pepesan_install_complete_manager`. Registration of the first agent verifies that the saved token actually authenticates. A second run skips installation.
6. TLS: copies the certificate to `/opt/kasm/current/certs`, restarts `kasm_proxy` only when it changed and installs the renewal deploy-hook (reuses the `kasm` role's `letsencrypt.yml`; the hook reads `/etc/letsencrypt/kasm-deploy-hook.env`).

The official db role publishes port 5432. This role blocks inbound access on the public interface in `INPUT` and `DOCKER-USER` (IPv4 and IPv6) without blocking Docker's internal network or restarting Docker. `kasm-db-firewall.service` reapplies the rules when Docker starts. Verify 5432 is closed externally and the app still reaches its database. Rerun the role if the public interface changes.

## Registration token

Generated on the first run and persisted **on the control node** in `{{ kasm_credentials_dir }}/<kasm_manager_hostname>-manager-token.pass` (mode 600, never printed), and exposed as the fact `kasm_manager_token`. [`kasm_agent`](../kasm_agent/README.md) reads the same file. Pass `-e kasm_manager_token=...` to use your own (letters and digits only): it is saved to that file. The token is passed to the db role via `--manager-token`; the database setting does not necessarily equal the original text, so authentication is tested by registering an agent (AGT-02).

## Variables

| Variable | Default | Description |
|---|---|---|
| `kasm_manager_hostname` | — (**required**) | FQDN of the manager (certificate, URL, agent registration). |
| `kasm_version` | `1.19.0` | Kasm release; keep it equal on the agents. |
| `kasm_dir` | `/opt/kasm` | Directory of the release, help and markers. |
| `kasm_manager_token` | generated / read from the credential file | Agent registration token. |
| `kasm_credentials_dir` | `$KASM_DATA_DIR/.credentials` or `{{ playbook_dir }}/data/.credentials` | Control-node credential directory. |
| `kasm_letsencrypt_enabled` | `true` | Real TLS on/off (shared with the `kasm` role). |
| `letsencrypt_email` | `admin@{{ kasm_base_domain }}` | Certbot account email. |
| `kasm_manager_release_url` / `kasm_manager_release_checksum` | official S3 URL of `kasm_version` / empty | Release archive and optional `sha256:<hex>`. |
| `kasm_manager_db_hostname` | default IPv4 of the host | Database address as seen from the `kasm_api`/`kasm_manager` containers. |
| `kasm_manager_install_flags` | `--role`, `--accept-eula`/`-e`, `--db-hostname`/`-q`, `--db-password`/`-Q`, `--manager-token`/`-M` | Accepted spellings per option, checked against `install.sh --help`. |
| `kasm_manager_db_extra_args` / `kasm_manager_app_extra_args` | empty | Extra `install.sh` arguments per role. |
| `kasm_manager_installer_patches` | `[]` | `sed` expressions applied to `install.sh` before running it (e.g. to bypass an OS check on a newer Ubuntu). |
| `kasm_manager_db_services` / `kasm_manager_app_services` | `kasm_db` / `kasm_api kasm_manager kasm_proxy` | Containers that must be Up. |

The installer receives passwords and the token as arguments (as in the official procedure); the wrapper redacts known output and keeps `/var/log/kasm-manager-{db,app}-install.log` readable only by root. Do not distribute those logs; check them for secrets before sharing.

## Example

```yaml
- hosts: kasm_manager
  roles:
    - role: pepesan.kasm.kasm_manager
      vars:
        kasm_manager_hostname: manager.example.com
```

Verify: `docker ps` on the host shows `kasm_db`, `kasm_api`, `kasm_manager`, `kasm_proxy`; `https://manager.example.com` serves the Let's Encrypt certificate; the second run reports `changed=0`.
