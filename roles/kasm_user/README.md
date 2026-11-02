# kasm_user

**Fully qualified name:** `pepesan.kasm.kasm_user` (collection [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Creates or deletes a Kasm application user (e.g. `user@kasm.local`) via
`kasm_user_state: present|absent` — **not** the Linux `student` user (see
[`student`](../student/README.md)), a Kasm account inside the application
itself.

Unlike [`kasm_workspace`](../kasm_workspace/README.md) and
[`kasm_group`](../kasm_group/README.md), Kasm's public API
fully covers user management (`create_user`, `get_users`, `delete_user`), so
this role is pure `ansible.builtin.uri` — no direct Postgres access, no
wrapped bash script. It's the first Kasm role in this collection with zero
SQL.

## Requires an existing API key

Reuses the persistent, ansible-managed API key bootstrapped by
[`kasm_workspace`](../kasm_workspace/README.md) (`{{ kasm_dir }}/.kasm_api_key.json`)
rather than minting its own. Run `kasm_workspace` at least once first; its key
successfully supported user listing, creation, and deletion against Kasm
1.19.0. If you create a key manually, grant it the **Users Create**, **Users
Delete**, and **Users View** permissions.

## Idempotency

Checks `get_users` first; `create_user` only runs if no user with that
username exists yet, `delete_user` only runs if one does.

## Variables

| Variable | Default | Purpose |
|---|---|---|
| `kasm_user_username` | — (required) | e.g. `user@kasm.local` |
| `kasm_user_state` | `present` | `present` creates if missing; `absent` deletes if present |
| `kasm_user_password` | random (20 chars), persisted per host and user | Password of the Kasm user being created. Pass it with `-e` to set a fixed one |
| `kasm_user_credentials_dir` | `<current directory>/.credentials` | Where the generated password lives: `<dir>/<host>-kasm-user-<username>.pass` (mode 600) |
| `kasm_user_first_name` / `_last_name` / `_organization` / `_phone` | `""` | Optional profile fields |
| `kasm_user_locked` / `_disabled` | `false` | Account flags |
| `kasm_url` | `https://127.0.0.1:443` | Kasm base URL |
| `kasm_user_api_key_file` | `{{ kasm_dir }}/.kasm_api_key.json` | Where to read the API key from |

## Example


Create a Kasm user. The password is random by default (20 characters) and saved in
`.credentials/<host>-kasm-user-<username>.pass` on your machine:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_user
      vars:
        kasm_user_username: "alice@example.com"
        kasm_user_first_name: "Alice"
        kasm_user_last_name: "Smith"
```

With a password of your own, kept in an Ansible Vault file:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_user
      vars:
        kasm_user_username: "alice@example.com"
        kasm_user_password: "{{ vault_alice_password }}"
```

Delete a user:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_user
      vars:
        kasm_user_username: "alice@example.com"
        kasm_user_state: absent
```

It needs the persistent API key that registering the first workspace creates (see
[`kasm_workspace`](../kasm_workspace/README.md)). This password is a different variable from the built-in
`user@kasm.local`'s (`kasm_default_user_password`, see [`kasm_credentials`](../kasm_credentials/README.md)).
