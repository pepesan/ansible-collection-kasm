# docker

**Nombre completo:** `pepesan.kasm.docker` (colección [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Wrapper fino alrededor de [`geerlingguy.docker`](https://galaxy.ansible.com/ui/standalone/roles/geerlingguy/docker/)
(incluido desde `tasks/main.yml`) que añade lo que ese rol no cubre pero que
Kasm necesita: los módulos de kernel `overlay` / `br_netfilter`, los valores
sysctl `net.ipv4.ip_forward` / `net.bridge.bridge-nf-call-iptables`, y una
preferencia de IPv4 sobre IPv6 en la resolución de nombres aplicada *antes* de
instalar nada.

## Orden de ejecución

1. **Preferir IPv4 sobre IPv6** (`/etc/gai.conf`).
2. `geerlingguy.docker`, mediante `include_role`.
3. Módulos de kernel, valores sysctl y `python3-docker`.

`geerlingguy.docker` se incluye a propósito desde las tareas y **no** como
dependencia de `meta`: las dependencias siempre se ejecutan antes que las
tareas propias del rol, y el paso 1 tiene que ir antes de los `apt` del
paso 2.

## Preferencia IPv4

Escribe `precedence ::ffff:0:0/96  100` en `/etc/gai.conf`, de modo que glibc
ordena IPv4 por encima de IPv6 cuando un nombre resuelve a ambas. Útil en VPS
que anuncian una ruta IPv6 que no funciona (`apt`, `curl` o `git` esperan
decenas de segundos a que IPv6 caduque antes de usar IPv4).

- **No** desactiva IPv6: un destino solo-IPv6 sigue funcionando.
- Solo afecta a programas que resuelven mediante glibc. Los binarios en Go,
  como `dockerd`, tienen su propio resolvedor e ignoran `gai.conf`, así que un
  `docker pull` lento no lo arregla esto.
- No llega a los contenedores (cada uno tiene su propio `/etc/gai.conf`).
- Idempotente: el `gai.conf` de fábrica trae la directiva comentada, así que
  la primera ejecución añade una línea y las siguientes no cambian nada.

## Por qué no reimplementar la instalación de Docker

`geerlingguy.docker` está activamente mantenido (v8.0.0, ene-2026) y ya
instala Docker Engine, el repo oficial, el plugin de Compose, gestiona el
servicio y añade usuarios al grupo `docker`. Reimplementar eso sería pura
duplicación.

## Variables

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `docker_kernel_modules` | `[overlay, br_netfilter]` | Módulos de kernel cargados vía `modprobe` |
| `docker_sysctl_values` | ip_forward + bridge-nf-call-iptables | Valores sysctl necesarios para la red de contenedores |
| `docker_prefer_ipv4` | `true` | Aplica la preferencia IPv4 descrita arriba. `false` mantiene el valor de la distribución |
| `docker_prefer_ipv4_gai_conf` | `/etc/gai.conf` | Fichero a editar |
| `docker_prefer_ipv4_precedence` | `100` | Precedencia de las direcciones IPv4 mapeadas (glibc: 35; IPv6 nativo: 40; por encima de 40 invierte la preferencia) |
| `docker_edition` | `ce` | Se pasa tal cual a `geerlingguy.docker` |
| `docker_users` | `["{{ ansible_user_id }}"]` | Usuarios añadidos al grupo `docker` |

Para la lista completa de variables de `geerlingguy.docker`, ver su
[README](https://github.com/geerlingguy/ansible-role-docker).

## Dependencias

- Rol de terceros de **Jeff Geerling ([geerlingguy](https://github.com/geerlingguy))**, usado pero **no incluido** en esta
  colección (todo el mérito es de su autor):
  [`geerlingguy.docker`](https://github.com/geerlingguy/ansible-role-docker).
  Instalación: `ansible-galaxy role install -r requirements.yml` (fichero en la raíz del repositorio de la colección).
  Si falta, el rol falla con un mensaje que muestra ese comando.
- `community.general` (modprobe), `ansible.posix` (sysctl)

## Ejemplo


Mínimo: Docker Engine y el plugin Compose, con los ajustes del kernel que necesita Kasm.

```yaml
- hosts: kasm
  roles:
    - pepesan.kasm.docker
```

Docker para un usuario de CI. El usuario debe existir antes de poder entrar en el grupo `docker`, así que se crea antes con
[`linux_user`](../linux_user/README.es.md). `docker_users` sustituye a la lista por defecto (el usuario con el que se
conecta Ansible) y `docker_prefer_ipv4: false` conserva la selección de direcciones de la distribución:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.linux_user
      vars:
        linux_user_name: ci-runner
    - role: pepesan.kasm.docker
      vars:
        docker_users: [ci-runner]
        docker_prefer_ipv4: false
```

Compruébelo en el servidor (solo lectura):

```bash
docker --version && docker compose version
systemctl is-active docker
lsmod | grep -E 'overlay|br_netfilter'      # módulos del kernel
sysctl net.ipv4.ip_forward                  # debe valer 1
id ci-runner                                # muestra el grupo docker
```
