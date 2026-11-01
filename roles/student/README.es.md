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
| `student_credentials_dir` | `{{ playbook_dir }}/.credentials` | Dónde vive el fichero de la contraseña generada |
| `student_password_plain` | aleatoria, persistida | Sobreescribir con `-e` para fijar una contraseña concreta |

La ruta del fichero de contraseña (`<credentials_dir>/<inventory_hostname>-student.pass`)
es el mismo patrón que usa [`kasm_credentials`](../kasm_credentials/README.es.md) para
leer ese mismo valor al escribir el CSV de accesos — mantén
`student_credentials_dir` consistente entre roles si lo cambias.

## Ejemplo

```yaml
- hosts: ubuntu
  roles:
    - pepesan.kasm.student
```
