# student

**Nombre completo:** `pepesan.kasm.student` (colección [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Crea el usuario Linux `student` con pertenencia a los grupos `docker` y
`sudo`. Wrapper fino sobre el rol genérico [`linux_user`](../linux_user/README.es.md)
— solo fija el username y los grupos por defecto, nada más; ver el README
de `linux_user` para el detalle de contraseña/idempotencia.

## Variables

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `student_name` | `student` | Usuario/grupo creado |
| `student_shell` | `/bin/bash` | Shell de login |
| `student_extra_groups` | `[docker, sudo]` | Grupos suplementarios |
| `student_credentials_dir` | `<directorio actual>/.credentials` | Dónde vive el fichero de la contraseña generada |
| `student_password_plain` | aleatoria, persistida | Sobreescribir con `-e` para fijar una contraseña concreta |

La ruta del fichero de contraseña (`<credentials_dir>/<inventory_hostname>-student.pass`)
es el mismo patrón que usa [`kasm_credentials`](../kasm_credentials/README.es.md) para
leer ese mismo valor al escribir el CSV de accesos — mantén
`student_credentials_dir` consistente entre roles si lo cambias.

## Ejemplo


Mínimo: crea el usuario `student` con una contraseña aleatoria, en los grupos `docker` y `sudo`.

```yaml
- hosts: kasm
  roles:
    - pepesan.kasm.student
```

Un aula con su propio nombre de usuario, una contraseña que usted controla (guardada cifrada con Ansible Vault) y otros grupos:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.student
      vars:
        student_name: alumno
        student_password_plain: "{{ vault_student_password }}"   # de un fichero de Ansible Vault
        student_extra_groups: [docker]                           # sin sudo
```

Dónde está la contraseña generada (cuando no se fija): `.credentials/<host>-<student_name>.pass` en la máquina que ejecuta
Ansible, y las columnas `student_user` y `student_password` del CSV cuando [`kasm_credentials`](../kasm_credentials/README.es.md)
se ejecuta en el mismo play. Compruebe el usuario en el servidor:

```bash
id student
getent passwd student
```
