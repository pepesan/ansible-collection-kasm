# Changelog

All notable changes to the `pepesan.kasm` collection are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [0.0.1] - unreleased

### Added
- First version of the collection: roles `docker`, `kasm`, `kasm_credentials`,
  `kasm_docker_image`, `kasm_group`, `kasm_session`, `kasm_uninstall`,
  `kasm_user`, `kasm_workspace`, `linux_user` and `student`.
- The access CSV keeps its rows sorted by Kasm URL host name (natural order).
- Every password can be passed as a parameter and is random (persisted) by default, including the passwords of users created with `kasm_user`. The built-in Kasm user's password is now `kasm_default_user_password` (it used to share the name `kasm_user_password` with the `kasm_user` role). The access CSV records the student password actually in use.
- The Kasm install script no longer prints the generated passwords, and its log (`kasm_deploy.log`) is readable by root only (mode 600). The passwords stay in the access CSV and `.credentials/` on the control node.
- Default workspace image `pepesan/core-ubuntu-resolute:1.20` (only when creating; deleting never defaults).
- Example playbooks and scripts under `playbooks/`.
- `requirements.yml` with the third-party roles by Jeff Geerling
  (`geerlingguy.docker`, `geerlingguy.swap`, `geerlingguy.certbot`), which are
  used but not shipped with the collection.
