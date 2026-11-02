# pepesan.kasm

[English](README.md)

Colección de Ansible para instalar y gestionar [Kasm Workspaces](https://kasmweb.com/) en servidores Ubuntu y Debian: Docker, un
usuario Linux, Kasm con un certificado real de Let's Encrypt, política de grupo, workspaces, usuarios, sesiones y una
desinstalación limpia. Cada paso es idempotente: ejecutarlo otra vez no cambia nada.

> **Versión actual de Galaxy (0.0.2).** Probada de extremo a extremo en servidores limpios Ubuntu 24.04 y 26.04 y Debian 12 y 13 con Kasm 1.19.0.
> Es un proyecto independiente, sin relación con Kasm Technologies ni respaldado por ella.

## Qué incluye

| Rol | Qué hace |
|---|---|
| [`docker`](roles/docker/README.es.md) | Docker Engine y el ajuste del kernel que necesita Kasm |
| [`student`](roles/student/README.es.md) | El usuario Linux `student` (grupos `docker` y `sudo`) con contraseña aleatoria |
| [`linux_user`](roles/linux_user/README.es.md) | Usuario Linux genérico con contraseña aleatoria persistida (`student` es una envoltura fina) |
| [`kasm_credentials`](roles/kasm_credentials/README.es.md) | Contraseñas aleatorias de Kasm y el CSV de accesos (una fila por servidor) |
| [`kasm`](roles/kasm/README.es.md) | Instala Kasm Workspaces, con TLS de Let's Encrypt por defecto |
| [`kasm_group`](roles/kasm_group/README.es.md) | Política de sesión y endurecimiento de un grupo de Kasm (keepalive, portapapeles, descargas...) |
| [`kasm_docker_image`](roles/kasm_docker_image/README.es.md) | Descarga o elimina una imagen dentro del Docker de Kasm |
| [`kasm_workspace`](roles/kasm_workspace/README.es.md) | Registra o borra un workspace (imagen por defecto: un escritorio Ubuntu 26.04 pequeño) |
| [`kasm_user`](roles/kasm_user/README.es.md) | Crea o borra un usuario de Kasm mediante su API pública |
| [`kasm_session`](roles/kasm_session/README.es.md) | Inicia o destruye la sesión de un usuario en un workspace |
| [`kasm_uninstall`](roles/kasm_uninstall/README.es.md) | Elimina Kasm para poder reinstalar desde cero |

Los roles se usan por su nombre completo, por ejemplo `pepesan.kasm.kasm_workspace`.

## Requisitos

- **Nodo de control:** `ansible-core` 2.15 o superior y acceso SSH como `root` al servidor.
- **Servidor:** Ubuntu 24.04 o 26.04, o Debian 12 o 13 (todos probados), con los puertos 80 y 443 libres. Con TLS activado,
  `site_kasm` comprueba los registros DNS públicos A/AAAA y la IP esperada antes de ejecutar cualquier rol de instalación.
  Si falla un nodo, los demás continúan; el play final enumera los fallos DNS.
- **Colecciones:** `community.docker`, `community.general` y `ansible.posix` se instalan solas con esta.
- **Roles de terceros, que NO se incluyen** (una colección no puede depender de roles, así que hay que instalarlos aparte):

  | Rol | Autor | Licencia | Lo usa |
  |---|---|---|---|
  | [`geerlingguy.docker`](https://github.com/geerlingguy/ansible-role-docker) | Jeff Geerling | MIT | `docker` |
  | [`geerlingguy.swap`](https://github.com/geerlingguy/ansible-role-swap) | Jeff Geerling | MIT | `kasm` |
  | [`geerlingguy.certbot`](https://github.com/geerlingguy/ansible-role-certbot) (>= 5.4.1) | Jeff Geerling | MIT | `kasm` |

  Todo el mérito de esas automatizaciones es de su autor. Esta colección solo las usa; no copia ni modifica su código. Si
  falta alguno, el rol falla con un mensaje que muestra el comando para instalarlo.

## Validar un inventario sin desplegar

Ejecute el playbook de comprobación únicamente contra el fichero de inventario
que quiera validar:

```bash
ansible-playbook -i /ruta/al/inventario pepesan.kasm.preflight_kasm_inventory
```

Exige el grupo `kasm` que usa `site_kasm`, un `node_name` no vacío por host y
nombres de nodo únicos. Solo se ejecuta en el nodo de control: no abre SSH, no
ejecuta roles de instalación ni copia el inventario a este repositorio. Solo
valida la estructura; no comprueba DNS ni la conectividad con los hosts.

## Preflight DNS antes del despliegue

Con `kasm_letsencrypt_enabled: true` (valor predeterminado), `site_kasm`
ejecuta el preflight DNS como primera tarea previa, antes de cualquier rol de
instalación. Por defecto, `kasm_domain` es
`<node_name>.<kasm_base_domain>`.

El nodo de control de Ansible consulta por HTTPS el DNS público de Cloudflare
para obtener los registros A y AAAA. Necesita acceso HTTPS saliente a
`cloudflare-dns.com`. El validador combina las direcciones A/AAAA obtenidas:
debe existir al menos una y el conjunto resultante debe coincidir exactamente
con `kasm_dns_expected_ips`. El preflight falla si la respuesta está vacía,
hay una dirección pública adicional, falta una dirección esperada o se
producen errores de red/resolución.

Por defecto, `kasm_dns_expected_ips` usa `[ansible_host]` y, si no existe, usa
`[inventory_hostname]`. Sobrescríbala en el inventario externo, `host_vars` o
`group_vars/kasm.yml` si Ansible se conecta a una dirección privada pero el
DNS público apunta a otra:

```yaml
kasm_dns_expected_ips:
  - "203.0.113.10"
  - "2001:db8::10"
```

Si las direcciones públicas pertenecen a un proxy o balanceador, defina
`kasm_dns_expected_ips: []`. Se seguirá exigiendo que exista algún registro
A/AAAA público, pero no se compararán las direcciones.

En `site_kasm`, si un host falla se omiten sus roles de instalación, mientras
los demás continúan. Al final se enumeran los hosts y dominios fallidos y el
playbook termina con resultado no nulo. Si pasa, el host continúa con la
instalación completa: este preflight es una barrera de despliegue, no una
ejecución DNS aislada. El playbook `preflight_kasm_inventory` solo valida la
estructura del inventario; no consulta DNS. Desactivar TLS omite el preflight
DNS. La comprobación no verifica el puerto 80 ni la emisión del certificado;
el challenge HTTP-01 de Let's Encrypt sigue necesitando el puerto 80 libre.

## Instalación

```bash
# 1. La colección (y sus dependencias de colecciones)
ansible-galaxy collection install pepesan.kasm

# 2. Los roles de terceros, con las versiones con las que se probó esta colección
ansible-galaxy role install -r requirements.yml
```

`requirements.yml` está en la raíz de este repositorio (descárguelo, o copie estas líneas):

```yaml
roles:
  - {name: geerlingguy.docker, version: "8.0.0"}
  - {name: geerlingguy.swap, version: "2.2.0"}
  - {name: geerlingguy.certbot, version: "5.5.0"}   # hace falta la 5.4.1 o posterior
```

## Inicio rápido

Un inventario tiene un host por servidor Kasm. `node_name` decide el nombre DNS:
el servidor se alcanza en `<node_name>.<kasm_base_domain>`.

El directorio [`examples/`](examples/) contiene un `ansible.cfg` seguro, un
inventario de ejemplo, un instalador de dependencias y scripts ejecutables. Su
[README](examples/README.md) explica la preparación, inventarios externos,
DNS/TLS, workspaces, sesiones, usuarios y limpieza.

```bash
mkdir -p "$HOME/.config/pepesan-kasm"
install -m 600 examples/inventory.example "$HOME/.config/pepesan-kasm/inventory-mi-servidor"
```

```ini
# Contenido de ejemplo; mantenga el inventario real fuera del repositorio.
[kasm]
203.0.113.10 node_name=kasmdemo

[kasm:vars]
ansible_user=root
ansible_become=false
```

```bash
# Ejecute los playbooks con el inventario externo.
INVENTARIO="$HOME/.config/pepesan-kasm/inventory-mi-servidor"
ansible-playbook -i "$INVENTARIO" pepesan.kasm.site_kasm \
  -e kasm_base_domain=kasm.example.com \
  -e letsencrypt_email=usted@example.com 2>&1 | tee install.log

# Registrar un workspace (sin indicar imagen, se usa la de por defecto)
ansible-playbook -i "$INVENTARIO" pepesan.kasm.kasm_workspace 2>&1 | tee workspace.log
```

Los playbooks de la colección se lanzan por nombre:
`pepesan.kasm.site_kasm`, `pepesan.kasm.kasm_workspace`,
`pepesan.kasm.kasm_session`, `pepesan.kasm.kasm_user`,
`pepesan.kasm.kasm_uninstall`, `pepesan.kasm.preflight_kasm_inventory`
(solo estructura) y `pepesan.kasm.preflight_kasm_dns_tls` (solo DNS público y
HTTPS/TLS de confianza). La primera instalación tarda varios minutos; envíe
la salida a un log con `tee` y sígala con `tail -f`.

La guía completa, con todas las variables y la tabla de problemas habituales, está en [docs/usage.es.md](docs/usage.es.md).

## Contraseñas

Cualquier contraseña puede pasarse como parámetro; si no, se genera una aleatoria (20 caracteres) una sola vez y se reutiliza
en las ejecuciones siguientes. Se guardan en la máquina que ejecuta Ansible, nunca en un repositorio:

| Contraseña | Dónde consultarla | Fijarla con |
|---|---|---|
| Usuario Linux `student` | CSV (`student_user`, `student_password`) y `.credentials/` | `-e student_password_plain=...` |
| Kasm `admin@kasm.local` | CSV (`kasm_admin_user`, `kasm_admin_password`) y `.credentials/` | `-e kasm_admin_password=...` |
| Kasm integrado `user@kasm.local` | CSV (`kasm_normal_user`, `kasm_normal_user_password`) y `.credentials/` | `-e kasm_default_user_password=...` |
| Usuarios de Kasm creados con `kasm_user` | solo `.credentials/` | `-e kasm_user_password=...` |

El CSV es `access-data-<nombre del fichero de inventario>.csv` en el directorio de ejecución (modo 600), con `kasm_url` como
primer campo y las filas ordenadas por esa URL. **No suba nunca a un repositorio el CSV, `.credentials/` ni su inventario**:
[`kasm_credentials`](roles/kasm_credentials/README.es.md).

## Pruebas

- `ansible-lint` (perfil production) y `yamllint` pasan sin fallos.
- Escenarios de Molecule, ejecutados con nombres completos mediante `scripts/molecule.sh <rol>`, para `linux_user`, `student`
  y `kasm_credentials`. El script rechaza a propósito los roles que tocan el kernel del anfitrión.
- Los roles que hablan con un Kasm vivo (`kasm_workspace`, `kasm_session`, `kasm_group`, `kasm_user`, `kasm_docker_image`) no
  se pueden ejecutar en un contenedor aislado, así que se verifican de extremo a extremo contra un servidor real.
- Extremo a extremo en servidores limpios Ubuntu 24.04 y 26.04 y Debian 12 y 13: instalación completa, repetición (sin cambios), workspace, sesión, usuario, desinstalación y reinstalación.

Ver [CONTRIBUTING.es.md](CONTRIBUTING.es.md).

## Repositorios relacionados

- [`pepesan/workspaces-core-images`](https://github.com/pepesan/workspaces-core-images): imágenes core de Kasm (de aquí sale
  la imagen de workspace por defecto, `pepesan/core-ubuntu-resolute`).
- [`pepesan/kasm-workspaces-images`](https://github.com/pepesan/kasm-workspaces-images): imágenes de workspace de Kasm ya preparadas.

## Licencia

GPL-3.0-or-later. Ver [LICENSE](LICENSE). Los roles de terceros citados arriba son de Jeff Geerling y conservan su propia licencia (MIT). Esta
colección no copia ni redistribuye su código, solo los usa.
