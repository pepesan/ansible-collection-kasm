# linux_user

**Fully qualified name:** `pepesan.kasm.linux_user` (collection [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Generic, reusable role: creates a Linux user with a random password
persisted on the control node, sets the user's same-name private group as
the primary group, and ensures any extra groups (e.g. `docker`, `sudo`)
exist first — even if nothing else created those groups yet.

Not specific to this project or to Kasm at all. [`student`](../student/README.md)
is a thin wrapper around this role that just fixes the username to `student`
and its default groups.

## Idempotency note

`password_hash()` generates a random salt on every call unless one is given
explicitly — without a fixed salt, the computed hash (and therefore the
user task) would show as "changed" on every single run, even when the
password itself never changed. This role persists the salt the same way as
the password itself (`linux_user_password_salt`, read via the same
`lookup('password', ...)` pattern), so re-runs are genuinely idempotent.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `linux_user_name` | — (required) | Username and primary group name |
| `linux_user_shell` | `/bin/bash` | Login shell |
| `linux_user_extra_groups` | `[]` | Supplementary groups, created first if missing |
| `linux_user_credentials_dir` | `<current directory>/.credentials` | Where the password and salt files live |
| `linux_user_password_plain` | random, persisted | Override with `-e` to set a fixed password |
| `linux_user_password_salt` | random, persisted | Rarely overridden directly |

## Example


A CI user in the `docker` group, with a random password saved on your machine:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.linux_user
      vars:
        linux_user_name: ci-runner
        linux_user_extra_groups: [docker]
```

A service account that cannot log in interactively, with a password you provide:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.linux_user
      vars:
        linux_user_name: backup
        linux_user_shell: /usr/sbin/nologin
        linux_user_password_plain: "{{ vault_backup_password }}"
```

The groups in `linux_user_extra_groups` are created if they do not exist. Running it again changes nothing, and the
password is not reset: the one saved in `.credentials/<host>-<user>.pass` is reused.

```bash
id ci-runner
getent group docker
```
