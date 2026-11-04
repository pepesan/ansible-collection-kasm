# Compatibility and Test Coverage

This page summarizes the collection's documented platform targets and test coverage. It distinguishes automated checks from historical end-to-end reports; real-server tests are not part of CI.

## Supported server platforms

| Server OS | End-to-end status |
|---|---|
| Ubuntu 24.04 | Passed no-TLS E2E on 2026-11-03 |
| Ubuntu 26.04 | Passed no-TLS E2E on 2026-11-03 |
| Debian 12 | Passed no-TLS E2E on 2026-11-03 |
| Debian 13 | Passed no-TLS E2E on 2026-11-03 |
| AlmaLinux 9 | Passed no-TLS E2E on 2026-11-04 |
| Rocky Linux 9 | Passed no-TLS E2E on 2026-11-04; repeated in follow-up |
| AlmaLinux 10 | Passed no-TLS E2E on 2026-11-04 |
| Rocky Linux 10 | Passed no-TLS E2E on 2026-11-04 |

The original seven-VM cycle and 2026-11-04 follow-ups covered all eight supported releases. Each passed no-TLS install and idempotence, user/workspace/session operations, privileged DinD with a real nested `docker run`, and uninstall/reinstall. No production server was altered.


## Automated checks

CI and the release workflow run:

- `ansible-lint` and `yamllint`.
- Collection archive inspection and clean-install validation (`scripts/check-build.sh`).
- Syntax checks for documented playbooks (`scripts/check-examples.sh`).
- Molecule for `linux_user`, `student` and `kasm_credentials`.

The local release gates passed on 2026-11-04: lint, package checks, all 50 documented plays, and all three Molecule scenarios. The Galaxy importer reported three warnings; Molecule reported environment/deprecation warnings, with no scenario failures. This is local verification, not a report of a new CI run or real-server deployment.

The release workflow also checks that a pushed `vX.Y.Z` tag matches `galaxy.yml`. A manual workflow run is a dry run; Galaxy publication requires the `GALAXY_API_KEY` secret. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the local commands and release procedure.

## End-to-end testing

The 2026-11-03/04 local E2E cycle used disposable LXD VMs and covered no-TLS installation, idempotence, user/workspace lifecycle, privileged DinD, and uninstall/reinstall. A separate real-server E2E on Rocky Linux 10.2 with Kasm 1.19.0 passed Let's Encrypt installation, trusted HTTPS, idempotent reinstall, user access, and a nested Docker run.

The first post-session reboot left the existing Kasm session record but stopped its container. An initial recovery-unit attempt also started too early, before Kasm's API, manager, and agent were healthy; the container exited 137. The local, unreleased helper now waits for those components and verifies the existing container remains running.

A second reboot verified automatic recovery: systemd completed successfully, the same session/container returned to `running`, and its home marker, cached `alpine:3.20` image, and nested Docker daemon remained available. The post-reboot `kasm_session` rerun returned `changed=0`; HTTPS returned HTTP 200 with trusted TLS. The user confirmed the workspace opened before this reboot; visual resume after the second reboot remains unchecked. The Compose workload and restart-time measurement remain unverified.

## Real-server E2E: Rocky Linux 10 + TLS — session recovery verified

The server remains available with TLS. One existing session was retained; no replacement session was created. Real server addresses and credentials are excluded from this matrix.
