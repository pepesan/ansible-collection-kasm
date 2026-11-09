# Changelog

All notable changes to the `pepesan.kasm` collection are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
