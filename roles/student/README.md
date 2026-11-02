# student

**Fully qualified name:** `pepesan.kasm.student` (collection [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Creates the `student` Linux user (the name is the `student_name` parameter) with `docker` and `sudo` group
membership. Thin wrapper around the generic [`linux_user`](../linux_user/README.md)
role — fixes the username and default groups, nothing else; see
`linux_user`'s README for the password/idempotency details.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `student_name` | `student` | Username/group created |
| `student_shell` | `/bin/bash` | Login shell |
| `student_extra_groups` | `[docker, sudo]` | Supplementary groups |
| `student_credentials_dir` | `<current directory>/.credentials` | Where the generated password file lives |
| `student_password_plain` | random, persisted | Override with `-e` to set a fixed password |

The password file path (`<credentials_dir>/<inventory_hostname>-student.pass`)
is the same pattern [`kasm_credentials`](../kasm_credentials/README.md) uses
to read the same value when writing the access CSV — keep
`student_credentials_dir` consistent across roles if you change it.

## Example


Minimal: creates the `student` user with a random password, in the `docker` and `sudo` groups.

```yaml
- hosts: kasm
  roles:
    - pepesan.kasm.student
```

A classroom with its own user name, a password you control (kept encrypted with Ansible Vault) and a different set of
groups:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.student
      vars:
        student_name: alumno
        student_password_plain: "{{ vault_student_password }}"   # from an Ansible Vault file
        student_extra_groups: [docker]                           # no sudo
```

Where to find the generated password (when not fixed): `.credentials/<host>-<student_name>.pass` on the machine
running Ansible, and the `student_user` and `student_password` columns of the access CSV when [`kasm_credentials`](../kasm_credentials/README.md)
runs in the same play. Check the user on the server:

```bash
id student
getent passwd student
```
