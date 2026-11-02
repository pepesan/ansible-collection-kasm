# Changelog

All notable changes to the `pepesan.kasm` collection are documented here.
This project follows [Semantic Versioning](https://semver.org/).

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
