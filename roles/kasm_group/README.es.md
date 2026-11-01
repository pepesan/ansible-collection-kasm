# kasm_group

**Nombre completo:** `pepesan.kasm.kasm_group` (colección [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Configura de forma idempotente los ajustes a nivel de grupo de Kasm —
keepalive de sesión y bastionado (portapapeles/descargas/subidas/impresión)
— para un grupo dado. Extraído de lo que antes era un único script
"configura todo tras instalar", para poder ejecutarse contra cualquier
grupo, repetirse con seguridad, y reportar el estado changed/unchanged real
por ajuste.

No cubierto por ningún rol de Galaxy, y tampoco existe una API pública que
funcione para esto: el endpoint público `update_setting` rechaza cualquier
payload probado, y estos son overrides por grupo guardados en
`group_settings`, no los ajustes globales (cifrados). Escribe directamente
a Postgres de Kasm.

## Idempotencia

El valor actual de cada ajuste se lee primero; el UPSERT de un ajuste
concreto solo se ejecuta cuando difiere del valor deseado. Una segunda
ejecución contra un grupo ya configurado no reporta cambios — comprobado en la
ejecución de extremo a extremo contra un servidor Kasm real.

## Ciclo de vida del grupo: crear, nunca borrar

`kasm_group_state: present` (el único valor soportado) crea el grupo si no
existe todavía, y luego aplica los ajustes. No hay `absent`: borrar un
grupo de Kasm **no está implementado** a propósito, porque:

- El esquema de la tabla `groups` de Kasm más allá de `name`/`group_id`/`priority`
  no se ha verificado contra una instancia real, así que un `DELETE` podría
  dejar filas huérfanas en `group_users`/`group_permissions`.
- Un error tipográfico en `kasm_group_name` (ej. apuntar por error a
  `"All Users"`) podría borrar un grupo integrado del que el propio Kasm
  depende, sin posibilidad de deshacerlo.

Si necesitas borrar un grupo, hazlo desde el panel de administración de Kasm.

## Variables

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `kasm_group_name` | `All Users` | Grupo objetivo; reejecuta el rol con otro valor para configurar otro grupo |
| `kasm_group_state` | `present` | Solo se soporta `present` (ver arriba) |
| `kasm_group_priority` | `100` | Solo se usa al crear un grupo nuevo |
| `kasm_group_keepalive_seconds` | `3600` | Timeout de keepalive de sesión |
| `kasm_group_keepalive_action` | `pause` | `pause` o `delete` cuando expira el keepalive |
| `kasm_group_allow_clipboard_down` / `_up` / `_seamless` | `false` | Bastionado de portapapeles |
| `kasm_group_allow_downloads` / `_uploads` / `_printing` | `false` | Bastionado de ficheros/impresión |

El modo de pruning de imágenes (`prune_images_mode`) es a nivel de
servidor, no de grupo, y se queda como tarea propia en
[`kasm`](../kasm/README.es.md) en vez de vivir aquí.

## Ejemplo


Mantener vivas durante una semana las sesiones del grupo `Instructors` y permitir imprimir:

```yaml
- hosts: ubuntu
  roles:
    - role: pepesan.kasm.kasm_group
      vars:
        kasm_group_name: "Instructors"
        kasm_group_keepalive_seconds: 604800
        kasm_group_allow_printing: true
```

Dos políticas en un mismo play, una restrictiva para los alumnos y otra abierta para el profesorado (cada ejecución solo cambia
los ajustes cuyo valor difiere, así que repetirlo no cambia nada):

```yaml
- hosts: ubuntu
  roles:
    - role: pepesan.kasm.kasm_group
      vars:
        kasm_group_name: "All Users"
        kasm_group_keepalive_seconds: 3600
        kasm_group_keepalive_action: delete       # libera los recursos de las sesiones inactivas
    - role: pepesan.kasm.kasm_group
      vars:
        kasm_group_name: "Instructors"
        kasm_group_allow_clipboard_down: true
        kasm_group_allow_clipboard_up: true
        kasm_group_allow_downloads: true
        kasm_group_allow_uploads: true
```

Compruebe lo aplicado (en el servidor, solo lectura):

```bash
docker exec kasm docker exec kasm_db psql -U kasmapp -d kasm \
  -c "SELECT g.name, gs.name, gs.value FROM group_settings gs JOIN groups g USING (group_id) ORDER BY 1,2;"
```
