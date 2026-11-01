# linux_user

**Nombre completo:** `pepesan.kasm.linux_user` (colección [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Rol genérico y reutilizable: crea un usuario Linux con una contraseña
aleatoria persistida en el nodo de control, y asegura que su propio grupo
más cualquier grupo adicional (ej. `docker`, `sudo`) existan antes —
funciona incluso si nada más ha creado esos grupos todavía.

No específico de este proyecto ni de Kasm en absoluto.
[`student`](../student/README.es.md) es un wrapper fino sobre este rol que
solo fija el username a `student` y sus grupos por defecto.

## Nota sobre idempotencia

`password_hash()` genera una sal aleatoria en cada llamada a menos que se
le dé una explícitamente — sin una sal fija, el hash calculado (y por
tanto la task del usuario) aparecería como "changed" en cada ejecución,
incluso cuando la contraseña en sí nunca cambió. Este rol persiste la sal
igual que la propia contraseña (`linux_user_password_salt`, leída con el
mismo patrón `lookup('password', ...)`), así que las reejecuciones son
realmente idempotentes.

## Variables

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `linux_user_name` | — (obligatoria) | Username y nombre del grupo principal |
| `linux_user_shell` | `/bin/bash` | Shell de login |
| `linux_user_extra_groups` | `[]` | Grupos suplementarios, creados antes si faltan |
| `linux_user_credentials_dir` | `{{ playbook_dir }}/.credentials` | Dónde viven los ficheros de password y sal |
| `linux_user_password_plain` | aleatoria, persistida | Sobreescribir con `-e` para fijar una contraseña concreta |
| `linux_user_password_salt` | aleatoria, persistida | Raramente se sobreescribe directamente |

## Ejemplo


Un usuario de CI en el grupo `docker`, con una contraseña aleatoria guardada en su máquina:

```yaml
- hosts: ubuntu
  roles:
    - role: pepesan.kasm.linux_user
      vars:
        linux_user_name: ci-runner
        linux_user_extra_groups: [docker]
```

Una cuenta de servicio sin acceso interactivo, con una contraseña que usted aporta:

```yaml
- hosts: ubuntu
  roles:
    - role: pepesan.kasm.linux_user
      vars:
        linux_user_name: backup
        linux_user_shell: /usr/sbin/nologin
        linux_user_password_plain: "{{ vault_backup_password }}"
```

Los grupos de `linux_user_extra_groups` se crean si no existen. Repetirlo no cambia nada y la contraseña no se reinicia: se
reutiliza la guardada en `.credentials/<host>-<usuario>.pass`.

```bash
id ci-runner
getent group docker
```
