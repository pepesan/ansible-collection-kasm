# kasm_session

**Nombre completo:** `pepesan.kasm.kasm_session` (colección [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Arranca (o destruye) una **sesión en ejecución** de un workspace de Kasm ya
registrado para un usuario concreto, mediante la API pública de Kasm. Es la
pieza que faltaba junto a [`kasm_workspace`](../kasm_workspace/README.es.md)
(registra el workspace) y [`kasm_user`](../kasm_user/README.es.md) (crea el
usuario): este rol hace que un usuario *tenga una sesión*.

Usa `ansible.builtin.uri` con la API pública y, opcionalmente, el Docker CLI
del host para iniciar **el mismo contenedor** que Kasm ya registró, sin
acceso directo a Postgres. La opción de recuperación está desactivada por
defecto; se autentica con la API key persistente que crea `kasm_workspace`
en el host (`/opt/kasm/.kasm_api_key.json`), así que antes debe haberse
registrado al menos un workspace.

## Variables

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `kasm_session_state` | `present` | `present`: asegura que el usuario tiene una sesión disponible (la crea si falta y espera a `running` o `paused`). `absent`: la destruye |
| `kasm_session_user` | `user@kasm.local` | Usuario de Kasm dueño de la sesión. Debe existir ya |
| `kasm_session_workspace` | `""` (obligatoria) | Un workspace ya registrado, por el `name` de su imagen (`pepesan/mi-ubuntu-resolute-kasm-python-dind:1.3`) o por su `friendly_name` (`Python Docker (Ubuntu 26.04)`) |
| `kasm_session_recover_stopped` | `false` | Ejecuta recuperación mediante API al lanzar el rol. Con recuperación al arranque activada, esta comprobación ya se realiza; ponlo en `true` para recuperar inmediatamente cuando `kasm_session_recover_on_boot` esté desactivada |
| `kasm_session_recover_on_boot` | `true` | Instala y habilita una unidad systemd por sesión que inicia el mismo contenedor tras reiniciar; no crea una sesión sustitutiva |
| `kasm_session_timeout_seconds` | `600` | Cuánto esperar a que Kasm reporte `running` o `paused` (el arranque en frío de una imagen grande puede tardar minutos) |
| `kasm_session_launch_retries` / `kasm_session_launch_delay` | `18` / `10` | Intentos y segundos entre reintentos cuando Kasm rechaza temporalmente la petición (hasta 3 minutos para permitir que se prepare una imagen grande) |
| `kasm_session_poll_seconds` | `5` | Intervalo de sondeo mientras espera |
| `kasm_session_api_key_file` | `{{ kasm_dir }}/.kasm_api_key.json` | API key persistente creada por `kasm_workspace` |

## Hechos exportados (estado `present`)

| Hecho | Contenido |
|---|---|
| `kasm_session_id` | El `kasm_id` de la sesión |
| `kasm_session_container_id` | Su id de contenedor dentro del DinD de Kasm (`docker exec kasm docker exec <id> …`) |
| `kasm_session_status` | `operational_status` (`running` o `paused`) |

## Comportamiento a tener en cuenta

- **Idempotente**: si el usuario ya tiene una sesión de ese workspace no se
  lanza otra (`changed=false`); `absent` no hace nada si no hay sesión.
- **Los endpoints devuelven los UUID en formatos distintos**: `get_users` con
  guiones, `get_images`/`get_kasms` sin ellos. El rol compara en minúsculas y
  sin guiones y envía la forma canónica con guiones. Una primera versión los
  comparaba tal cual, no encontraba la sesión existente e intentaba lanzar una
  segunda (`request_kasm` la rechazó, así que sin daños, pero solo se detectó
  probándolo).
- **Una sesión arrancada por automatización no tiene cliente conectado**, así
  que Kasm la *pausará* tras `keepalive_expiration` segundos (ver
  [`kasm_group`](../kasm_group/README.es.md): 3600 s y acción `pause` por
  defecto). Lo que corra dentro (p. ej. un laboratorio docker compose) queda
  congelado, no perdido, y se reanuda cuando un usuario se conecta.
- Por defecto, el rol instala una unidad systemd por sesión
  (`kasm_session_recover_on_boot=true`). Al arrancar, espera a Docker del host,
  al Docker anidado de Kasm y a que estén sanos Kasm API, manager y agent;
  después inicia el mismo contenedor solo si su estado es `created` o `exited`.
  Deja intactos los estados `running` y `paused` y comprueba su estabilidad
  durante 15 segundos.
- La unidad se elimina al poner la sesión en `absent` o desactivar la
  recuperación al arranque. `kasm_uninstall` elimina todas las unidades y el
  helper.
- Solo se reinicia el contenedor existente. No se crea otra sesión Kasm ni se
  restauran procesos interrumpidos por el apagado del host.
- `kasm_session_recover_stopped=true` ejecuta la misma recuperación segura al
  lanzar el rol, aunque `kasm_session_recover_on_boot=false`. Si faltan IDs o
  contenedores, o Docker informa un estado no admitido, falla sin sustituir la
  sesión.
- La respuesta de `request_kasm` incluye un token de sesión; las tareas correspondientes usan `no_log`.
- Una sesión reserva los cores y la memoria del workspace mientras exista;
  conviene vigilar la capacidad del host antes de lanzar varias.

## Recuperar la misma sesión tras reiniciar el host

Al ejecutar el rol con `kasm_session_state=present` (predeterminado), se
instala y habilita una unidad systemd por sesión. En el siguiente arranque,
espera a Docker del host, al Docker anidado y a que estén sanos Kasm API,
manager y agent. Después inicia el mismo contenedor si su estado es `created`
o `exited` y comprueba que sigue activo durante 15 segundos.

Para una sesión creada antes de habilitar esta función, ejecuta el rol una vez
cuando Kasm vuelva a estar disponible. `kasm_session_recover_on_boot=true` es
el valor predeterminado: recupera inmediatamente el contenedor detenido e
instala la unidad para futuros reinicios:

```bash
ansible-playbook -i inventory pepesan.kasm.kasm_session \
  -e kasm_session_workspace=pepesan/mi-ubuntu-resolute-kasm-ansible-dind:1.2 \
  -e kasm_session_recover_on_boot=true
```

El rol espera a que Kasm informe `running` o `paused`; después, abre la sesión
original. Usa `kasm_session_recover_on_boot=false` para deshabilitar y quitar
la unidad. Se reinicia el mismo contenedor, pero no se restauran procesos
interrumpidos al apagar el host.

## Nombres con espacios

Pásalos como JSON; con `-e clave="a b"` el valor se corta en el primer
espacio:

```bash
ansible-playbook -i <inventario> kasm-session.yml \
  -e '{"kasm_session_workspace": "Python Docker (Ubuntu 26.04)"}'
```

## Ejemplo


Iniciar la sesión de un usuario en un workspace registrado y esperar a que esté en marcha. Si la sesión ya existe, no se lanza
nada:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_session
      vars:
        kasm_session_user: user@kasm.local
        kasm_session_workspace: "pepesan/core-ubuntu-resolute:1.20"   # nombre de la imagen o nombre amigable
```

Esperar más para una imagen grande y usar después los datos que exporta el rol:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_session
      vars:
        kasm_session_workspace: "Core Ubuntu Resolute"
        kasm_session_timeout_seconds: 1200
  tasks:
    - ansible.builtin.debug:
        msg: "La sesión {{ kasm_session_id }} está {{ kasm_session_status }}"
```

Destruir esa sesión:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_session
      vars:
        kasm_session_state: absent
        kasm_session_workspace: "Core Ubuntu Resolute"
```

Desde la línea de comandos, con el playbook que trae la colección:

```bash
ansible-playbook -i inventory-mi-servidor pepesan.kasm.kasm_session \
  -e kasm_session_workspace=pepesan/core-ubuntu-resolute:1.20
```

Ver [`playbooks/kasm_session.yml`](../../playbooks/kasm_session.yml).
