# Changelog

All notable changes to the `pepesan.kasm` collection are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [0.0.1] - unreleased

### Added
- First version of the collection: roles `docker`, `kasm`, `kasm_credentials`,
  `kasm_docker_image`, `kasm_group`, `kasm_session`, `kasm_uninstall`,
  `kasm_user`, `kasm_workspace`, `linux_user` and `student`.
- The access CSV keeps its rows sorted by Kasm URL host name (natural order).
- Default workspace image `pepesan/core-ubuntu-resolute:1.20` (only when creating; deleting never defaults).
- Example playbooks and scripts under `playbooks/`.
- `requirements.yml` with the third-party roles by Jeff Geerling
  (`geerlingguy.docker`, `geerlingguy.swap`, `geerlingguy.certbot`), which are
  used but not shipped with the collection.
