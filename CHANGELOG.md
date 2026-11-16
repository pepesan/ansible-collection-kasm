# Changelog

All notable changes to the `pepesan.kasm` collection are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.2] - 2026-11-16

### Changed
- `kasm_workspace` identifies a workspace by image **and** display name, so several workspaces can share one image (for example, different editions of a course).
  - Create: reuses the workspace only when both match; fails if the name is already used by another image; otherwise creates it.
  - Autostart: looks up the workspace by image and name.
  - Delete: removes one workspace selected by `kasm_workspace_name`. It fails when several workspaces share the image and no name is given. The Docker image in the DinD cache and the running sessions are removed only when no other workspace uses that image.
  - `kasm_workspace_clean_all` walks image/name pairs.
- The `absent` path of `playbooks/kasm_workspace.yml` no longer runs `kasm_docker_image`: its `rmi` ignored other workspaces that use the same image.

### Fixed
- The existence check of `kasm_workspace` reused any workspace with the same image, whatever its name, so a wrong name went unnoticed and was never corrected. Name and image are now both checked.

## [0.2.1] - 2026-11-15

### Fixed
- `fix_and_install_kasm.sh` no longer retries deterministic port conflicts when required services are missing; transient Docker plugin race retries remain.

## [0.2.0] - 2026-11-14

### Added
- `scripts/check-secrets.sh`: refuses real IP addresses, private keys, certificates, provider tokens, literal credentials, secret-bearing file names and locally deny-listed strings in staged changes, pushed commits, tracked files or a directory. `scripts/check-build.sh` now runs it on the built tarball.
- Cluster mode (official manager + agents layout): playbooks `site_kasm_cluster` (preflight, manager, agents in
  `kasm_cluster_agents_serial` batches, images on the agents, workspaces/groups/users, CSV files) and
  `preflight_kasm_cluster` (public DNS A record, operating system, free ports 80/443, SSH/Python; fails before any role runs).
- Roles `kasm_manager` and `kasm_agent`; `kasm_db_exec` (kasm_workspace, kasm_group), `kasm_docker_image_exec`
  (kasm_docker_image) and `kasm_uninstall_layout` (`manager`/`agent`) to work on the official layout; local copy of the
  Kasm API key by `kasm_workspace`.
- `kasm_credentials` writes `cluster-access-<project>.csv` (operator: nodes, SSH, admin password, agent token) and
  `user-access-<project>.csv` (learners) with `tasks_from: cluster_csv.yml` / `user_csv.yml`: upsert by `node` /
  `kasm_user`, sorted, atomic, mode 600, secrets only in the environment, regenerable from `.credentials/` without
  touching the nodes (`update_cluster_csv.py --from-credentials`).
- Cluster guide: [docs/cluster.md](docs/cluster.md) / [docs/cluster.es.md](docs/cluster.es.md).
- The co-located manager database is protected on the public interface (IPv4/IPv6) by idempotent firewall rules reapplied at Docker startup.

### Changed
- The access CSV of the all-in-one mode (`access-data-*.csv`) and `update_credentials_csv.py` are unchanged.
- Manager setup recovers from Kasm's already-active oneshot service when adding the app to the database host; validates the database token setting without assuming its stored representation equals the original token.
- Agent installation recognizes a healthy container with a completed heartbeat instead of requiring an absent success message; it recovers an existing installed agent without running the installer again and protects its installer log with mode `0600`.
- Named workspace grants for groups and optional user group membership are applied and verified idempotently in Kasm's `group_images` and `user_groups` relations.
- Cluster deployments disable Kasm's aggressive server image pruning after agent registration, before pulling custom workspace images.
- Co-located manager installation preserves database TLS files, PostgreSQL configuration and log-directory ownership when Kasm's app installer recreates the version directory.

## [0.1.3] - 2026-11-12

### Added
- Example scripts now resolve their inventory from `ansible.cfg` (`./inventory`) by default; passing the inventory is now optional across all wrappers.
- Credentials in `.credentials/` and access CSV files now use the `kasm_training_project` slug prefix when defined (`access-data-<project>.csv`).
- Installation scripts now print a summary of generated credential directories and CSV paths upon completion.

### Changed
- Removed the obsolete `nombre` column from the access CSV.
- Pinned GitHub Actions runners explicitly to `ubuntu-26.04`.

## [0.1.2] - 2026-11-09

### Changed
- Refactored the Release workflow into modular, parallel stages (fast validation, parallel Molecule matrix for all roles, build and documentation checks, and final publishing).

## [0.1.1] - 2026-11-09

### Added
- Added YAML inventory templates (`examples/inventory.example.yml` and `examples/inventory.two-machines.yml`) and documented their usage.

### Changed
- Clarified the Gitflow contribution workflow and branch protection documentation.
- Reordered and renumbered example deployment scripts so installation preflights and workflows precede post-install DNS/TLS verification (`02_install_custom_domain.sh`, `03_install_default_domain.sh`, `04_preflight_dns_tls.sh`).

## [0.1.0] - 2026-11-04

### Added
- `kasm_session` now installs a per-session systemd unit by default. It waits for healthy Kasm API, manager, and agent components, then recovers only the existing workspace container after a reboot.
- Added tested server support for Rocky Linux 9/10 and AlmaLinux 9/10.
- Added an example two-machine inventory and Rocky/AlmaLinux 10 VM image builders from official ISOs.

### Fixed
- The example dependency installer now refreshes pre-existing Galaxy roles to the versions pinned in `requirements.yml` instead of retaining stale versions.
- `linux_user` now sets the user's same-name group as primary, including on distributions that default accounts to a shared group such as Rocky Linux.
- Local Rocky/Alma ISO and VM image builders now live under `scripts/images`; generated workspaces remain ignored and are excluded from Galaxy packaging with the rest of `scripts`.
- The credentials CSV now places `student_user` immediately after `ip`, before `nombre` and `student_password`.
- The credentials CSV directory stays private (`0700`), avoiding a looser permission reset on each example install rerun.
- The Docker role enables EPEL on Rocky/AlmaLinux before installing `python3-docker`, which is not provided by their default repositories.
- `kasm_session` retries transient launch refusals for up to three minutes by default, so a just-registered large workspace can finish staging before the session request gives up.

### Changed
- Numbered the example scripts sequentially from `00_install_dependencies.sh`; expanded the self-contained deployment guide and inventory examples.
- Promoted Rocky Linux 10 and AlmaLinux 10 to supported server platforms after passing no-TLS end-to-end validation.
- Release CI now runs lint, package/example checks, and the supported Molecule scenarios before building the collection.

## [0.0.3] - 2026-11-02

### Added
- Per-host public DNS A/AAAA preflight before Kasm installation, with expected-IP validation and a final `site_kasm` summary of failed nodes.
- Added a check-only inventory preflight playbook. It validates the `kasm`
  group and unique, non-empty `node_name` values without connecting to
  servers or copying inventory data into the repository.
- Added standalone public DNS and trusted-HTTPS/TLS preflight with no host changes.
- Added the `kasm_user` collection playbook and a DinD session smoke check.
- Added an `examples/` dependency installer, temporary compatibility mapping for external `ubuntu` inventories, and lifecycle wrappers for workspaces, sessions, and Kasm users. Generated secrets stay outside the checkout.

### Changed

- Moved the safe Ansible configuration, sample inventory, and usage scripts to
  `examples/`; real inventories must stay outside the repository.
- Redact generated password, secret, and token fields from Kasm installer output before writing the remote log or returning
  Ansible task output.
- Preserve the source inventory basename for the access CSV; reject
  `KASM_DATA_DIR` paths inside the checkout.
- Resolve access CSV IPs from the inventory host despite `delegate_to: localhost`;
  assert the value in the credentials-role Molecule scenario.
- The `kasm_workspace` persistent API key was verified to support `kasm_user`
  list/create/delete; remove obsolete manual-grant instructions.
- Defer the nested Docker smoke check for paused sessions; rerun the playbook
  after connecting to that same session.
- Remove the Kasm container image from the host Docker cache during full
  uninstall; retain the Let's Encrypt certificate by default.

## [0.0.2] - 2026-11-02

### Changed
- The default Ansible inventory group is now `kasm` instead of `ubuntu`.
- The access CSV now starts with `kasm_url`, includes the inventory name and student username, and uses `kasm_normal_user` field names.
- It uses `ansible_host` for `ip`, sorts by the full Kasm URL, migrates legacy headers, and upserts/deduplicates nodes by IP or inventory name.
- Added behavioral tests for the CSV schema, legacy migration, identity matching, deduplication, URL ordering, and idempotency.

- Added opt-in reboot recovery for an existing workspace session: inspect its known container ID and start that same container when Kasm reports `paused`/stopped and Docker says `created`/`exited`; no replacement session is requested.

## [0.0.1] - 2026-11-02

### Added
- First version of the collection: roles `docker`, `kasm`, `kasm_credentials`,
  `kasm_docker_image`, `kasm_group`, `kasm_session`, `kasm_uninstall`,
  `kasm_user`, `kasm_workspace`, `linux_user` and `student`.
- The access CSV keeps its rows sorted by Kasm URL host name (natural order).
- Every password can be passed as a parameter and is random (persisted) by default, including the passwords of users created with `kasm_user`. The built-in Kasm user's password is now `kasm_default_user_password` (it used to share the name `kasm_user_password` with the `kasm_user` role). The access CSV records the student password actually in use.
- The Kasm install script no longer prints the generated passwords, and its log (`kasm_deploy.log`) is readable by root only (mode 600). The passwords stay in the access CSV and `.credentials/` on the control node.
- Passwords, the access CSV and the API key copy are written in the directory `ansible-playbook` is run from, not in the folder of
  the playbook. Run by name from the installed collection, a playbook's folder is inside the collection, where the credentials
  would be lost (and regenerated differently) on an upgrade. The CSV helper script is run from the role and is no longer copied.
- Supported servers: Ubuntu 24.04 and 26.04, Debian 12 and 13. The `kasm` role installs `curl` (the workspace script needs it on the host and minimal Debian images lack it) and only sets the AppArmor user-namespace sysctl on kernels that have it (Ubuntu).
- Default workspace image `pepesan/core-ubuntu-resolute:1.20` (only when creating; deleting never defaults).
- Example playbooks and scripts under `playbooks/`.
- `requirements.yml` with the third-party roles by Jeff Geerling
  (`geerlingguy.docker`, `geerlingguy.swap`, `geerlingguy.certbot`), which are
  used but not shipped with the collection.
