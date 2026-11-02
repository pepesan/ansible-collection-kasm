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

You need `ansible-core`, `ansible-lint`, `yamllint` and, for Molecule, `molecule` and Docker.

```bash
ansible-lint                      # production profile, configured in .ansible-lint
yamllint .
scripts/check-examples.sh         # every YAML play in the documentation passes --syntax-check
scripts/check-build.sh            # builds the tarball, inspects it and installs it in a clean environment
scripts/molecule.sh student       # Molecule for one role, using fully qualified names
```

### Self-hosted CI runner

The Molecule matrix uses GitHub-hosted runners for pull requests and events not initiated by `pepesan` on `main` or
`develop`. Owner-triggered pushes and manual runs on those branches use the runner label stored in the repository Actions
variable `LORIEN_RUNNER_LABEL`; if it is unset, the job falls back to `ubuntu-latest`. The self-hosted job creates a
per-job virtual environment with the host's Python 3.13. Enable the runner account's rootless `podman.socket` user unit
with lingering, and provide `$HOME/.local/bin/docker` as a symlink to Podman. The workflow points Docker SDK at
`/run/user/<uid>/podman/podman.sock`. Never route pull-request jobs to this runner.

Only three roles have a Molecule scenario, because they are the ones that can be tested in an isolated container:
`linux_user`, `student` and `kasm_credentials`. The rest are covered by `ansible-lint` (all of them) and by the end-to-end test
against a real server, not by Molecule: `docker`, `kasm` and `kasm_uninstall` load kernel modules and set sysctl values, which
inside a privileged container affects the **host's** kernel, and `kasm_workspace`, `kasm_session`, `kasm_group`, `kasm_user` and
`kasm_docker_image` need a live Kasm. The end-to-end test is not part of the CI: it is run by hand before a release.

### End-to-end on a real server

For a change that touches installation or the Kasm roles, test on a disposable Ubuntu server you own, from a clean state:

1. Build and install the collection from your checkout into a temporary directory, and the third-party roles from
   `requirements.yml`, so you test your code and not an old copy.
2. Keep the inventory **outside the repository** (a server IP is a secret) and send every run to a log:
   `ansible-playbook ... 2>&1 | tee e2e.log`.
3. Run `pepesan.kasm.site_kasm`, then **run it again and check that nothing changes**, then register a workspace, start a
   session, and delete both.

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
Versions published on Ansible Galaxy cannot be overwritten, so build and check the tarball (`scripts/check-build.sh`) first.

Run exactly one command to increment `galaxy.yml`:

```bash
python3 scripts/bump_version.py patch   # e.g. 0.0.1 -> 0.0.2
python3 scripts/bump_version.py minor   # e.g. 0.0.1 -> 0.1.0
python3 scripts/bump_version.py major   # e.g. 0.0.1 -> 1.0.0
```

The script edits only `galaxy.yml`. Update the `Unreleased` section in
`CHANGELOG.md` manually; it does not commit, tag, push, or publish.

Before tagging, run the local checks and dispatch the `Release` workflow
manually for its dry run. A pushed `vX.Y.Z` tag matching `galaxy.yml` triggers
the Galaxy publication and GitHub release; the workflow requires the
repository's `GALAXY_API_KEY` secret.
