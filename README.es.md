# pepesan.kasm

[English](README.md)

Colección de Ansible para instalar y gestionar [Kasm Workspaces](https://kasmweb.com/) en servidores Ubuntu: Docker, un
usuario Linux, Kasm con un certificado real de Let's Encrypt, política de grupo, workspaces, usuarios, sesiones y una
desinstalación limpia. Cada paso es idempotente: ejecutarlo otra vez no cambia nada.

> **Estado: preversión (0.0.1).** Probada de extremo a extremo en un servidor Ubuntu 26.04 limpio con Kasm 1.19.0. Aún no
> está publicada en Ansible Galaxy, así que los comandos `ansible-galaxy` de abajo funcionarán cuando lo esté.
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
- **Servidor:** Ubuntu (probado en 26.04), con los puertos 80 y 443 libres. Para un certificado real,
  `<node_name>.<kasm_base_domain>` debe resolver ya al servidor.
- **Colecciones:** `community.docker`, `community.general` y `ansible.posix` se instalan solas con esta.
- **Roles de terceros, que NO se incluyen** (una colección no puede depender de roles, así que hay que instalarlos aparte):

  | Rol | Autor | Lo usa |
  |---|---|---|
  | [`geerlingguy.docker`](https://github.com/geerlingguy/ansible-role-docker) | Jeff Geerling | `docker` |
  | [`geerlingguy.swap`](https://github.com/geerlingguy/ansible-role-swap) | Jeff Geerling | `kasm` |
  | [`geerlingguy.certbot`](https://github.com/geerlingguy/ansible-role-certbot) (>= 5.4.1) | Jeff Geerling | `kasm` |

  Todo el mérito de esas automatizaciones es de su autor. Esta colección solo las usa; no copia ni modifica su código. Si
  falta alguno, el rol falla con un mensaje que muestra el comando para instalarlo.

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

Un inventario con un host por servidor Kasm. `node_name` decide el nombre DNS: el servidor se alcanza en
`<node_name>.<kasm_base_domain>`.

```ini
# inventory-mi-servidor
[ubuntu]
203.0.113.10 node_name=kasmdemo

[ubuntu:vars]
ansible_user=root
ansible_become=false
```

```bash
# Instalar Kasm con certificado real (https://kasmdemo.kasm.example.com)
ansible-playbook -i inventory-mi-servidor pepesan.kasm.site_kasm \
  -e kasm_base_domain=kasm.example.com \
  -e letsencrypt_email=usted@example.com 2>&1 | tee install.log

# Registrar un workspace (sin indicar imagen, se usa la de por defecto)
ansible-playbook -i inventory-mi-servidor pepesan.kasm.kasm_workspace 2>&1 | tee workspace.log
```

Los cuatro playbooks de la colección se lanzan por su nombre: `pepesan.kasm.site_kasm`, `pepesan.kasm.kasm_workspace`,
`pepesan.kasm.kasm_session` y `pepesan.kasm.kasm_uninstall`. La primera instalación tarda varios minutos (lo lento es el
instalador de Kasm); enviar la salida a un log con `tee` permite seguirla con `tail -f`.

La guía completa, con todas las variables y la tabla de problemas habituales, está en [docs/usage.es.md](docs/usage.es.md).

## Contraseñas

Cualquier contraseña puede pasarse como parámetro; si no, se genera una aleatoria (20 caracteres) una sola vez y se reutiliza
en las ejecuciones siguientes. Se guardan en la máquina que ejecuta Ansible, nunca en un repositorio:

| Contraseña | Dónde consultarla | Fijarla con |
|---|---|---|
| Usuario Linux `student` | CSV de accesos y `.credentials/` | `-e student_password_plain=...` |
| Kasm `admin@kasm.local` | CSV de accesos y `.credentials/` | `-e kasm_admin_password=...` |
| Kasm integrado `user@kasm.local` | CSV de accesos y `.credentials/` | `-e kasm_default_user_password=...` |
| Usuarios de Kasm creados con `kasm_user` | solo `.credentials/` | `-e kasm_user_password=...` |

El CSV es `access-data-<nombre del fichero de inventario>.csv` en el directorio desde el que se ejecuta (modo 600). **No
suba nunca a un repositorio el CSV, `.credentials/` ni su inventario**: la IP del servidor también es un secreto. Detalles en
[`kasm_credentials`](roles/kasm_credentials/README.es.md).

## Pruebas

- `ansible-lint` (perfil production) y `yamllint` pasan sin fallos.
- Escenarios de Molecule, ejecutados con nombres completos mediante `scripts/molecule.sh <rol>`, para `linux_user`, `student`
  y `kasm_credentials`. El script rechaza a propósito los roles que tocan el kernel del anfitrión.
- Los roles que hablan con un Kasm vivo (`kasm_workspace`, `kasm_session`, `kasm_group`, `kasm_user`, `kasm_docker_image`) no
  se pueden ejecutar en un contenedor aislado, así que se verifican de extremo a extremo contra un servidor real.
- Extremo a extremo en un servidor Ubuntu 26.04 limpio: instalación completa, repetición (sin cambios), workspace, sesión.

Ver [CONTRIBUTING.es.md](CONTRIBUTING.es.md).

## Repositorios relacionados

- [`pepesan/workspaces-core-images`](https://github.com/pepesan/workspaces-core-images): imágenes core de Kasm (de aquí sale
  la imagen de workspace por defecto, `pepesan/core-ubuntu-resolute`).
- [`pepesan/kasm-workspaces-images`](https://github.com/pepesan/kasm-workspaces-images): imágenes de workspace de Kasm ya preparadas.

## Licencia

GPL-3.0-or-later. Ver [LICENSE](LICENSE). Los roles de terceros citados arriba conservan su propia licencia.
