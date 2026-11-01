# kasm

**Nombre completo:** `pepesan.kasm.kasm` (colección [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Instala Kasm Workspaces sin registrar ningún workspace todavía (eso lo hace
[`kasm_workspace`](../kasm_workspace/README.es.md)): ajuste sysctl,
`/opt/kasm`, docker compose, el script de fix-e-instalación, modo de pruning
de imágenes a nivel de servidor, bloqueo de impresión en nginx y, por
defecto, un certificado real de Let's Encrypt. Los timeouts de sesión y el
bastionado por grupo los configura por separado
[`kasm_group`](../kasm_group/README.es.md), ejecutado
después de este rol.

No cubierto por ningún rol de Galaxy mantenido (se valoró
`monolithprojects.kasm_server` y se descartó — último commit en 2021, y aun
así solo cubría una instalación básica). Este rol se escribe desde cero, pero
delega las dos piezas genéricas que necesita en roles de Galaxy mantenidos
en vez de reimplementarlas:

- **Swap**: [`geerlingguy.swap`](https://github.com/geerlingguy/ansible-role-swap)
  (incluido desde `tasks/main.yml`) — el instalador de Kasm necesita swap
  presente o falla.
- **Let's Encrypt**: [`geerlingguy.certbot`](https://github.com/geerlingguy/ansible-role-certbot)
  (incluido desde `tasks/main.yml`) gestiona instalar certbot, emitir el cert inicial y el cron
  de renovación. `tasks/letsencrypt.yml` solo añade lo específico de Kasm:
  localizar su directorio real de certs dentro del contenedor, copiar ahí el
  cert emitido por certbot, reiniciar `kasm_proxy`, instalar el deploy-hook
  de renovación y verificar que HTTPS responde.

## TLS activado por defecto

`kasm_letsencrypt_enabled: true`. Requiere que `kasm_domain`
(`{{ node_name }}.{{ kasm_base_domain }}`) ya resuelva a este host y que el
puerto 80 esté libre para el challenge HTTP-01. Para entornos
locales/sin DNS, desactivar explícitamente:

```
-e kasm_letsencrypt_enabled=false
```

Kasm queda accesible con su certificado autofirmado.

## Cómo se verifica la instalación (y se reintenta)

`files/fix_and_install_kasm.sh` ejecuta el `install.sh` de Kasm dentro del
contenedor. Hay dos cosas fáciles de hacer mal y muy caras de depurar:

- **`install.sh` puede abortar pronto** con `dial unix .../kasmlogger.sock` o
  `.../kasmnetwork.sock: connect: connection refused`. Son los plugins de
  Docker propios de Kasm (`kasmweb/logger`, `kasmweb/sidecar`) que no
  responden en su socket en el instante en que Docker intenta habilitarlos:
  una carrera de tiempo, no un fallo persistente. El plugin está arriba unos
  segundos después, así que habilitarlo a mano justo a continuación funciona.
  Afecta más a unos hosts que a otros y es más probable cuantas más
  instalaciones corran a la vez (ver `playbooks/`: usar un `-f` bajo).
- **El éxito lo decide el estado de los servicios, no el código de salida.**
  El script tolera un `install.sh` con código distinto de cero (un timeout
  inocuo del healthcheck de `kasm_manager` es un caso conocido), así que
  comprueba que `kasm_db`, `kasm_api` y `kasm_manager` estén realmente en
  marcha. Si no lo están, habilita los plugins desactivados y vuelve a
  ejecutar `install.sh`, hasta 3 intentos, y solo entonces sale con error
  **sin** escribir el marcador de instalación
  (`/opt/kasm/data/opt/kasm_install_complete` en el host).

Una versión anterior escribía el marcador siempre, y su bucle de "esperar a
que estén sanos" daba por bueno el caso de **no haber ningún contenedor**
(nada está `unhealthy` ni `starting`). El play "pasaba" y fallaba varias
tareas después, en `Read current image-pruning mode`, con
`No such container: kasm_db`, y cada reejecución imprimía
`already installed. Skipping` sin reparar nada. Si te encuentras ese estado en
un host, borra el marcador y vuelve a ejecutar.

## Variables

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `kasm_dir` | `/opt/kasm` | Directorio de instalación |
| `kasm_version` / `kasm_image_tag` | `1.19.0` / `1.19.0-ls154` | Versión de Kasm / tag de la imagen del contenedor (último publicado por linuxserver; el servidor 1.20 aún no existe, las imágenes de workspace "1.20" funcionan sobre él) |
| `node_name` | — (**obligatoria**, normalmente por host en el inventario) | Nombre de este servidor: se alcanza en `<node_name>.<kasm_base_domain>` |
| `kasm_base_domain` | `example.com` (placeholder, sin valor por defecto sensato fuera de este proyecto) | Dominio base; fijarlo explícitamente por despliegue |
| `kasm_domain` | `{{ node_name }}.{{ kasm_base_domain }}` | Dominio completo por nodo |
| `kasm_letsencrypt_enabled` | `true` | Activar/desactivar TLS real |
| `letsencrypt_email` | `admin@{{ kasm_base_domain }}` | Email de la cuenta de certbot (Let's Encrypt envía ahí los avisos de caducidad): fije uno real |
| `kasm_admin_password` / `kasm_default_user_password` | — | Las aporta [`kasm_credentials`](../kasm_credentials/README.es.md); ejecuta ese rol antes o fíjalas tú mismo |

## Log de instalación

El script de instalación escribe su progreso en `<kasm_dir>/data/opt/kasm_deploy.log` en el servidor (el rol sugiere seguirlo
con `tail -f`). El log solo es legible por root (modo 600) y **no** contiene las contraseñas: estas quedan en el CSV de accesos
y en `.credentials/` de la máquina que ejecuta Ansible (ver [`kasm_credentials`](../kasm_credentials/README.es.md)).

## Dependencias

- Roles de terceros de **Jeff Geerling ([geerlingguy](https://github.com/geerlingguy))**, usados pero **no incluidos** en esta
  colección (una colección no puede depender de roles, así que hay que instalarlos aparte; todo el mérito de esos roles es de su autor):
  [`geerlingguy.swap`](https://github.com/geerlingguy/ansible-role-swap),
  [`geerlingguy.certbot`](https://github.com/geerlingguy/ansible-role-certbot) (>= 5.4.1).
  Instalación: `ansible-galaxy role install -r requirements.yml` (fichero en la raíz del repositorio de la colección).
  Si faltan, el rol falla con un mensaje que muestra ese comando.
- `community.docker` (compose, container exec)
- Requiere que `kasm_admin_password`/`kasm_default_user_password` ya estén definidas
  — normalmente ejecutando antes [`kasm_credentials`](../kasm_credentials/README.es.md).

## Ejemplo


La instalación completa, en el orden habitual (es lo que hace el playbook `pepesan.kasm.site_kasm`):

```yaml
- hosts: ubuntu
  roles:
    - pepesan.kasm.docker
    - pepesan.kasm.student
    - pepesan.kasm.kasm_credentials
    - role: pepesan.kasm.kasm
      vars:
        node_name: kasmdemo                   # o defínalo por host en el inventario
        kasm_base_domain: kasm.example.com    # el servidor se alcanza en kasmdemo.kasm.example.com
        letsencrypt_email: usted@example.com  # Let's Encrypt envía aquí los avisos de caducidad
    - pepesan.kasm.kasm_group
```

Una instalación de prueba sin certificado (Kasm conserva el suyo autofirmado) y con menos swap:

```yaml
- hosts: ubuntu
  roles:
    - pepesan.kasm.docker
    - pepesan.kasm.kasm_credentials
    - role: pepesan.kasm.kasm
      vars:
        node_name: kasmtest
        kasm_base_domain: example.com         # sin certificado, no hace falta correo
        kasm_letsencrypt_enabled: false
        kasm_swap_file_size_mb: 2048
```

Compruébelo (solo lectura):

```bash
curl -sI https://kasmdemo.kasm.example.com | head -1             # HTTP 200
docker exec kasm docker ps --format '{{.Names}}  {{.Status}}'      # en el servidor
tail -f /opt/kasm/data/opt/kasm_deploy.log                       # log del instalador (solo root, sin contraseñas)
```
