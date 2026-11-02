# kasm_user

**Nombre completo:** `pepesan.kasm.kasm_user` (colección [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Crea o borra un usuario de la aplicación Kasm (ej. `user@kasm.local`) vía
`kasm_user_state: present|absent` — **no** el usuario Linux `student` (ver
[`student`](../student/README.es.md)), sino una cuenta de Kasm dentro de la
propia aplicación.

A diferencia de [`kasm_workspace`](../kasm_workspace/README.es.md) y
[`kasm_group`](../kasm_group/README.es.md), la API pública
de Kasm cubre completamente la gestión de usuarios (`create_user`,
`get_users`, `delete_user`), así que este rol es `ansible.builtin.uri` puro
— sin acceso directo a Postgres, sin script bash envuelto. Es el primer rol
de Kasm de esta colección sin nada de SQL.

## Requiere una API key existente

Reutiliza la API key persistente de gestión por Ansible que genera
[`kasm_workspace`](../kasm_workspace/README.es.md) (`{{ kasm_dir }}/.kasm_api_key.json`)
en vez de crear una propia. Ejecuta `kasm_workspace` al menos una vez; su key
se probó para listar, crear y borrar usuarios en Kasm 1.19.0. Si creas una key
manualmente, concédele los permisos **Users Create**, **Users Delete** y
**Users View**.

## Idempotencia

Comprueba primero con `get_users`; `create_user` solo se ejecuta si no
existe ya un usuario con ese username, `delete_user` solo si existe.

## Variables

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `kasm_user_username` | — (obligatoria) | ej. `user@kasm.local` |
| `kasm_user_state` | `present` | `present` crea si falta; `absent` borra si existe |
| `kasm_user_password` | aleatoria (20 caracteres), persistida por host y usuario | Contraseña del usuario de Kasm que se crea. Pásela con `-e` para fijarla |
| `kasm_user_credentials_dir` | `<directorio actual>/.credentials` | Dónde queda la contraseña generada: `<dir>/<host>-kasm-user-<usuario>.pass` (modo 600) |
| `kasm_user_first_name` / `_last_name` / `_organization` / `_phone` | `""` | Campos de perfil opcionales |
| `kasm_user_locked` / `_disabled` | `false` | Flags de cuenta |
| `kasm_url` | `https://127.0.0.1:443` | URL base de Kasm |
| `kasm_user_api_key_file` | `{{ kasm_dir }}/.kasm_api_key.json` | De dónde leer la API key |

## Ejemplo


Crear un usuario de Kasm. La contraseña es aleatoria por defecto (20 caracteres) y queda guardada en
`.credentials/<host>-kasm-user-<usuario>.pass` en su máquina:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_user
      vars:
        kasm_user_username: "alicia@example.com"
        kasm_user_first_name: "Alicia"
        kasm_user_last_name: "Pérez"
```

Con una contraseña propia, guardada en un fichero de Ansible Vault:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_user
      vars:
        kasm_user_username: "alicia@example.com"
        kasm_user_password: "{{ vault_alicia_password }}"
```

Borrar un usuario:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_user
      vars:
        kasm_user_username: "alicia@example.com"
        kasm_user_state: absent
```

Necesita la clave de API persistente que crea el registro del primer workspace (ver
[`kasm_workspace`](../kasm_workspace/README.es.md)). Esta contraseña es una variable distinta de la del usuario integrado
`user@kasm.local` (`kasm_default_user_password`, ver [`kasm_credentials`](../kasm_credentials/README.es.md)).
