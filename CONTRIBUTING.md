# Contributing

[Español](CONTRIBUTING.es.md)

Thanks for helping with `pepesan.kasm`. This page explains how the repository is organised, how to check a change and
what must never end up in it.

## Layout

| Path | What it is |
|---|---|
| `roles/<role>/` | One role: `defaults/`, `tasks/`, `meta/`, `README.md` (English) and `README.es.md` (Spanish) |
| `playbooks/` | The playbooks shipped with the collection |
| `examples/` | Safe `ansible.cfg`, placeholder inventory, dependency installer, and usage wrappers |
| `docs/` | The usage guide, in English and Spanish |
| `scripts/` | `molecule.sh`, `check-build.sh` and `check-examples.sh` |
| `galaxy.yml`, `meta/runtime.yml` | Collection metadata |
| `requirements.yml` | The third-party roles (by Jeff Geerling) that the collection uses but does not ship |

## Conventions

- **English in the code.** Role, variable and task names and comments are in English. Every role has a `README.md` in
  English and a `README.es.md` in Spanish; keep both in step.
- **Variables.** Public variables are documented in the role's README and start with the role's prefix. The `kasm_*`
  variables shared by several roles (`kasm_dir`, `kasm_url`, `kasm_admin_password`...) are the only exception, on purpose.
- **Fully qualified names** (`pepesan.kasm.<role>`) in playbooks, `include_role` and documentation.
- **Idempotent.** Running a role twice must change nothing the second time.
- **Passwords.** Any password must be passable as a parameter and, if it is not, be random and persisted. Tasks that handle
  a secret use `no_log: true`, and nothing secret is printed.
- **Third-party roles** are included from the tasks (not as `meta` dependencies, which a collection cannot declare) and the
  failure when one is missing says how to install it.

## Checking a change

Use the same gates locally that CI and release require:

```bash
ansible-lint
yamllint .
scripts/check-build.sh
scripts/check-examples.sh
scripts/molecule.sh linux_user test
scripts/molecule.sh student test
scripts/molecule.sh kasm_credentials test
```

These commands are sequential; run them one at a time. `check-build.sh` verifies the collection archive, performs a clean install, resolves the playbooks by name and runs the Galaxy importer. `check-examples.sh` syntax-checks every documented YAML play. The release workflow runs these checks before building or publishing.

### Self-hosted CI runner

The Molecule matrix uses GitHub-hosted runners for pull requests and events not initiated by `pepesan` on `main` or
`develop`. Owner-triggered pushes and manual runs on those branches use the runner label stored in the repository Actions
variable `LORIEN_RUNNER_LABEL`; if it is unset, the job falls back to `ubuntu-latest`. The self-hosted job creates a
per-job virtual environment with the host's Python 3.13. Enable the runner account's rootless `podman.socket` user unit
with lingering, and provide `$HOME/.local/bin/docker` as a symlink to Podman. The workflow points Docker SDK at
`/run/user/<uid>/podman/podman.sock`. Never route pull-request jobs to this runner.

Only three roles have a Molecule scenario, because they are the ones that can be tested in an isolated container:
`linux_user`, `student` and `kasm_credentials`. The rest are covered by `ansible-lint` and by manual end-to-end tests, not by
Molecule: `docker`, `kasm` and `kasm_uninstall` load kernel modules and set sysctl values, which inside a privileged container
affects the **host's** kernel, and `kasm_workspace`, `kasm_session`, `kasm_group`, `kasm_user` and `kasm_docker_image` need a live
Kasm. Consult [`MATRIX.md`](MATRIX.md) for reported compatibility evidence and explicit unverified scenarios. Real-server E2E is
not part of CI.

### End-to-end on a real server

For installation or Kasm-role changes, use a disposable server running an OS from the supported matrix in `MATRIX.md`:

1. Build and install the collection from your checkout into a temporary directory, and install third-party roles from
   `requirements.yml`, so you test your code and not an old copy.
2. Keep the inventory **outside the repository** and send every run to a log:
   `ansible-playbook ... 2>&1 | tee e2e.log`.
3. Run `pepesan.kasm.site_kasm` twice and verify the second run makes no changes. Exercise workspace, session and user operations.
4. For reboot persistence, use exactly one existing workspace session: create a file in its home, reboot, recover that same
   session, and verify the file and session ID. Do not create a second session or replacement workspace.
5. Record redacted results and environment versions in the private run log. Never claim an OS or scenario passed without evidence.

## Never commit secrets

Not a token, an API key, a password or the IP of a real server, in the code, the documentation, an example or a workflow.
Use `203.0.113.x` and `example.com` in examples. The `.gitignore` already covers what the roles and the tests generate
(`.credentials/`, `access-data-*.csv`, `inventory-*`, `kasm-api-key-*.json`, logs, tarballs...), but do not rely on it alone:
before every commit and every push run `git status` and `git diff --cached` and read what you are about to publish.

`scripts/check-build.sh` also fails if the tarball contains development files or an IPv4 address that is not a documentation
example.

## Commits

Short imperative summary on the first line, then a body that says *why*. One logical change per commit.

## Releases

The version is in `galaxy.yml` and follows [Semantic Versioning](https://semver.org/). Add the change to `CHANGELOG.md`.
Published Galaxy versions cannot be overwritten.

Run exactly one command to increment `galaxy.yml`:

```bash
python3 scripts/bump_version.py patch
python3 scripts/bump_version.py minor
python3 scripts/bump_version.py major
```

The script edits only `galaxy.yml`. Update the `Unreleased` section in `CHANGELOG.md` manually; it does not commit, tag, push,
or publish.

Before tagging:

1. Run every command in **Checking a change**, sequentially, and inspect the built tarball for private data.
2. Dispatch the `Release` workflow manually. This dry run runs validation and builds the archive but does not publish.
3. Confirm `vX.Y.Z` matches `galaxy.yml`. Pushing that tag triggers Galaxy publication and the GitHub release; the workflow
   requires the repository secret `GALAXY_API_KEY`.
4. For changes requiring server behavior verification, complete and record the manual E2E separately; CI never deploys to a
   real server.
