# kasm_uninstall

**Nombre completo:** `pepesan.kasm.kasm_uninstall` (colección [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Desinstala Kasm Workspaces de forma limpia: detiene y elimina el contenedor
DinD `kasm` (junto con sus redes/volúmenes internos), borra los datos
persistidos y elimina la imagen Docker correspondiente de la caché del host.
Opcionalmente, elimina el certificado real de Let's Encrypt. Permite que el rol
[`kasm`](../kasm/README.es.md) vuelva a ejecutarse como una instalación nueva,
en vez de arreglar a mano por SSH un servidor a medio romper.

También deshabilita y elimina las unidades systemd de recuperación por sesión
instaladas por `kasm_session`.

No hay ningún rol de Galaxy que cubra esto, y el propio `install.sh` de Kasm
no tiene opción `--uninstall` — confirmado haciendo grep directamente sobre
un host real.

## Variables

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `kasm_dir` | `/opt/kasm` | Debe coincidir con la misma variable usada por el rol `kasm` |
| `kasm_uninstall_remove_data` | `true` | Borra `kasm_dir/data` (BD, certs propios de Kasm, marker de instalación, perfiles) |
| `kasm_uninstall_remove_all` | `true` | También elimina `kasm_dir` entero (`compose.yaml`, `init/`) — inofensivo, `kasm` los recrea |
| `kasm_image_tag` | `1.19.0-ls154` | Debe coincidir con la etiqueta usada por el rol `kasm` |
| `kasm_uninstall_remove_image` | `true` | Elimina la imagen Kasm de la caché Docker del host; usa `false` para conservarla |
| `kasm_uninstall_remove_letsencrypt_certs` | `false` | Elimina `/etc/letsencrypt/live/<kasm_domain>` en el host. Desactivado por defecto: fuerza pedir un certificado nuevo en la siguiente instalación, y Let's Encrypt limita esas peticiones por dominio |
| `kasm_domain` | `{{ node_name }}.{{ kasm_base_domain }}` | Solo se lee si `kasm_uninstall_remove_letsencrypt_certs` es true |

## Layouts

`kasm_uninstall_layout` elige qué se elimina:

| Layout | Qué elimina |
|---|---|
| `allinone` (por defecto) | Todo lo descrito arriba: el contenedor `kasm`, sus datos y la imagen en caché. Comportamiento sin cambios |
| `manager` | Manager oficial en el host: contenedores de Kasm (`kasm_*`: app, db, proxy…), sus redes Docker, volúmenes de datos (`kasm_db_<versión>`), imágenes de Kasm y `kasm_dir` (`/opt/kasm`, que incluye `current/certs`). Antes detiene los servicios con `kasm_dir/current/bin/stop` |
| `agent` | Agente oficial en el host: lo mismo, más los contenedores de sesión (creados desde imágenes con la etiqueta `com.kasmweb.image=true`) y esas imágenes |

`manager` y `agent` nunca desinstalan Docker (eso lo hace aparte un playbook
tipo `uninstall_kasm_and_docker.yml`) y nunca tocan `/etc/letsencrypt`: los
certificados se conservan salvo que `kasm_uninstall_remove_letsencrypt_certs`
sea true (entonces define también `kasm_domain` con el nombre del certificado).
Los layouts toleran un nodo donde Docker o Kasm ya no están.

**Antes se comprueban las sesiones activas** (`kasm_uninstall_check_sessions`,
por defecto `true`) y se avisa de ellas: el manager cuenta las filas
`running`, `starting` y `paused` de la tabla `kasms` (con
`kasm_uninstall_db_exec`, por defecto `docker exec kasm_db`); el agente cuenta
los contenedores en marcha cuyo nombre no empieza por `kasm_`. Con
`kasm_uninstall_abort_on_active_sessions: true` se detiene en vez de avisar.

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `kasm_uninstall_layout` | `allinone` | `allinone`, `manager` o `agent` |
| `kasm_uninstall_check_sessions` | `true` | manager/agent: busca sesiones activas y avisa |
| `kasm_uninstall_abort_on_active_sessions` | `false` | manager/agent: falla en vez de avisar si hay sesiones |
| `kasm_uninstall_db_exec` | `docker exec kasm_db` | manager: prefijo que llega a PostgreSQL para la comprobación de sesiones |

En `manager`/`agent`, `kasm_uninstall_remove_data` controla los volúmenes de
datos de Docker, `kasm_uninstall_remove_image` las imágenes de Kasm
(servicios y workspaces) y `kasm_uninstall_remove_all` el directorio
`kasm_dir`. `kasm_image_tag` solo se aplica a `allinone`.

## Idempotencia

Cada task es un `state: absent`, protegido por una comprobación previa de
existencia (`stat` sobre el compose file; listar antes de borrar en
`manager`/`agent`). Ejecutarlo dos veces seguidas no hace nada la segunda vez.

## Ejemplo


Eliminar Kasm y sus datos conservando el certificado de Let's Encrypt, para que reinstalar no gaste uno de los pocos
certificados que se emiten por nombre y semana:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_uninstall
```

**Esto borra los datos de Kasm del servidor.** Para forzar además un certificado nuevo en la próxima instalación:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_uninstall
      vars:
        kasm_uninstall_remove_letsencrypt_certs: true
        node_name: kasmdemo
        kasm_base_domain: example.com
```

Desde la línea de comandos, con el playbook que trae la colección (y luego reinstalar desde cero):

```bash
ansible-playbook -i inventory-mi-servidor pepesan.kasm.kasm_uninstall 2>&1 | tee uninstall.log
ansible-playbook -i inventory-mi-servidor pepesan.kasm.site_kasm \
  -e kasm_base_domain=kasm.example.com -e letsencrypt_email=usted@example.com 2>&1 | tee install.log
```
