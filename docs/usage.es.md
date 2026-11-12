# Guía de uso

[English](usage.md) · [Volver al README](../README.es.md)

Todos los comandos de abajo usan los playbooks de la colección por nombre (`pepesan.kasm.<playbook>`). Su código está en
[`playbooks/`](../playbooks); [`examples/`](../examples) contiene el `ansible.cfg` seguro, el inventario de ejemplo, el
instalador de dependencias y scripts operativos. Consulte [`examples/README.md`](../examples/README.md) para prepararlos y probar imágenes.

> Envíe siempre la salida del playbook a un log con `tee`, para poder seguirla con `tail -f` desde otro terminal.

## 1. Antes de empezar

**Nodo de control** (su máquina): `ansible-core` 2.15+ y acceso SSH como `root`
a un servidor compatible (Ubuntu 24.04/26.04, Debian 12/13, AlmaLinux 9/10 o
Rocky Linux 9/10). Instale una sola vez la colección y los roles de terceros
(ver el [README](../README.es.md#instalación)).

**Inventario.** Un host por servidor Kasm. `node_name` decide el nombre DNS: el servidor se alcanza en
`<node_name>.<kasm_base_domain>`.

```ini
[kasm]
203.0.113.10 node_name=kasmdemo

[kasm:vars]
ansible_user=root
ansible_become=false
```

Con `kasm_base_domain=kasm.example.com` ese host pasa a ser `https://kasmdemo.kasm.example.com`. Guarde los inventarios
reales fuera de este repositorio, por ejemplo en `$HOME/.config/pepesan-kasm/inventory-mi-servidor`. Cree una copia
privada del inventario de ejemplo:

```bash
mkdir -p "$HOME/.config/pepesan-kasm"
install -m 600 examples/inventory.example "$HOME/.config/pepesan-kasm/inventory-mi-servidor"
```

**DNS.** Para un certificado real, `<node_name>.<kasm_base_domain>` debe resolver ya al servidor, idealmente sin un registro
AAAA que apunte a un sitio roto, y el puerto 80 debe estar libre para el desafío HTTP-01.

### Fuentes y referencias de variables

Para las fuentes de configuración utilizadas por estos playbooks, la
precedencia es: defaults del rol < variables del inventario < variables del
playbook < variables extra de la línea de comandos (`-e`). `-e` prevalece
sobre los valores del inventario y del playbook. Otras fuentes de Ansible
pueden tener su propia precedencia; consulte la
[referencia de precedencia de Ansible](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html#understanding-variable-precedence)
para ver el orden completo.

Defina los valores de cada servidor, como `node_name`, en su línea del
inventario, y los valores compartidos, como `kasm_base_domain` y
`letsencrypt_email`, en `[kasm:vars]`. Use `-e` para una modificación de una
sola ejecución. `KASM_DATA_DIR` es distinto: es una variable de entorno que
leen los scripts shell de `examples` para elegir dónde guardar los CSV y
ficheros de credenciales locales; Ansible no la trata como variable de la
colección.

No incluya contraseñas reales en un inventario normal ni en argumentos
literales como `-e password=valor`. Use Ansible Vault para secretos fijos;
las credenciales generadas se guardan en el nodo de control, como se explica
más abajo.

El README de cada rol documenta sus variables públicas, defaults, valores
obligatorios y efectos. El rol `kasm_workspace` agrupa las variables por
función.

| Rol | Referencia de variables |
|---|---|
| `docker` | [README del rol](../roles/docker/README.es.md) |
| `kasm` | [README del rol](../roles/kasm/README.es.md) |
| `kasm_credentials` | [README del rol](../roles/kasm_credentials/README.es.md) |
| `kasm_docker_image` | [README del rol](../roles/kasm_docker_image/README.es.md) |
| `kasm_group` | [README del rol](../roles/kasm_group/README.es.md) |
| `kasm_session` | [README del rol](../roles/kasm_session/README.es.md) |
| `kasm_uninstall` | [README del rol](../roles/kasm_uninstall/README.es.md) |
| `kasm_user` | [README del rol](../roles/kasm_user/README.es.md) |
| `kasm_workspace` | [README del rol](../roles/kasm_workspace/README.es.md) |
| `linux_user` | [README del rol](../roles/linux_user/README.es.md) |
| `student` | [README del rol](../roles/student/README.es.md) |

Los ficheros de variables cifrados se pueden pasar con `-e @vault.yml --ask-vault-pass`.

## 2. Instalar Kasm (`pepesan.kasm.site_kasm`)

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-mi-servidor" pepesan.kasm.site_kasm \
  -e kasm_base_domain=kasm.example.com \
  -e letsencrypt_email=usted@example.com 2>&1 | tee install.log
```

Qué hace, en orden:

1. `docker`: prefiere IPv4 en glibc, instala Docker Engine y Compose, carga los módulos del kernel y los valores de sysctl que
   necesita Kasm.
2. `student`: crea el usuario Linux `student`.
3. `kasm_credentials`: genera las contraseñas de Kasm (o usa las que usted pase).
4. `kasm`: swapfile, certificado de Let's Encrypt, Kasm en sí y el hook de renovación del certificado.
5. `kasm_group`: aplica la política de sesión (keepalive, portapapeles, descargas...) al grupo `All Users`.
6. `kasm_credentials` escribe el CSV de accesos con la dirección y las credenciales del servidor.

Variables de uso frecuente:

| Variable | Valor por defecto | Rol | Significado |
|---|---|---|---|
| `kasm_base_domain` | `example.com` | `kasm` | Dominio base; el host es `<node_name>.<kasm_base_domain>` |
| `letsencrypt_email` | `admin@<kasm_base_domain>` | `kasm` | Correo para certbot |
| `kasm_letsencrypt_enabled` | `true` | `kasm` | `false` conserva el certificado autofirmado de Kasm |
| `kasm_version` / `kasm_image_tag` | `1.19.0` / `1.19.0-ls154` | `kasm` | Versión de Kasm y etiqueta de la imagen de linuxserver |
| `kasm_swap_file_size_mb` | `4096` | `kasm` | Tamaño del fichero de swap |
| `student_name` | `student` | `student` | Nombre del usuario Linux |
| `kasm_group_keepalive_seconds` | `3600` | `kasm_group` | Segundos antes de que una sesión inactiva se pause o se borre |
| `kasm_group_keepalive_action` | `pause` | `kasm_group` | `pause` o `delete` |

Sin TLS (para una prueba local): añada `-e kasm_letsencrypt_enabled=false`.

## 3. Credenciales y ficheros generados

Todo se crea en **su máquina**, en el directorio desde el que se ejecuta, y está ignorado por git. No lo suba nunca a un
repositorio.

| Fichero | Qué contiene |
|---|---|
| `.credentials/[<proyecto>-]<host>-<student_name>.pass` | Contraseña del usuario Linux |
| `.credentials/[<proyecto>-]<host>-kasm-admin.pass` | Contraseña de `admin@kasm.local` |
| `.credentials/[<proyecto>-]<host>-kasm-user.pass` | Contraseña del `user@kasm.local` integrado |
| `.credentials/[<proyecto>-]<host>-kasm-user-<usuario>.pass` | Contraseña de un usuario creado con `kasm_user` |
| `access-data-<proyecto|inventario>.csv` | Una fila por nodo; columnas `kasm_url`, `ip`, `student_user`, `student_password` y credenciales admin/usuario normal de Kasm; filas ordenadas por la URL completa |
| `kasm-api-key-<inventory_hostname>.json` | Copia de la clave de API persistente (se crea con el primer workspace) |

Las contraseñas se generan **una sola vez** y se reutilizan en las ejecuciones siguientes. Para obtener otras nuevas, borre
`.credentials/` antes de la instalación. Cualquiera de ellas se puede fijar con un parámetro: `-e student_password_plain=...`,
`-e kasm_admin_password=...`, `-e kasm_default_user_password=...`, `-e kasm_user_password=...`.

La propia clave de API vive en el servidor, en `/opt/kasm/.kasm_api_key.json` (modo 600), y se crea la primera vez que se
registra un workspace.

## 4. Workspaces (`pepesan.kasm.kasm_workspace`)

Sin indicar imagen se usa la de por defecto: `pepesan/core-ubuntu-resolute:1.20` (un escritorio Ubuntu 26.04 pequeño),
registrada como "Core Ubuntu Resolute".

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-mi-servidor" pepesan.kasm.kasm_workspace 2>&1 | tee workspace.log
```

Con su propia imagen (el nombre lleva espacios, así que va en forma JSON: un `-e var=a b` normal se corta en el primer espacio):

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-mi-servidor" pepesan.kasm.kasm_workspace \
  -e kasm_docker_image_name=usuario/imagen:1.0 \
  -e kasm_workspace_image=usuario/imagen:1.0 \
  -e '{"kasm_workspace_name": "Mi workspace"}' \
  -e kasm_workspace_cores=2 -e kasm_workspace_memory_gb=4
```

Las imágenes que ejecutan Docker dentro de la sesión (DinD) necesitan `-e kasm_workspace_privileged=true`.

| Variable | Valor por defecto | Significado |
|---|---|---|
| `kasm_workspace_image` | la imagen por defecto (al crear) | Imagen Docker del workspace |
| `kasm_workspace_name` | `Core Ubuntu Resolute` con la imagen por defecto, obligatoria en otro caso | Nombre que muestra Kasm |
| `kasm_workspace_cores` / `kasm_workspace_memory_gb` | `4` / `8` | Recursos por sesión |
| `kasm_workspace_privileged` | `false` | Necesario para Docker dentro de la sesión |
| `kasm_workspace_state` | `present` | `present` o `absent` |

### Borrar workspaces

Borrar nunca usa una imagen por defecto: indique cuál, o borre todos.

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-mi-servidor" pepesan.kasm.kasm_workspace \
  -e kasm_workspace_state=absent -e kasm_workspace_image=usuario/imagen:1.0 \
  -e kasm_docker_image_name=usuario/imagen:1.0
# todos los workspaces:  -e kasm_workspace_state=absent -e kasm_workspace_clean_all=true
```

Por defecto también se borran los perfiles persistentes de ese workspace (`kasm_workspace_delete_persistent_data`).

## 5. Sesiones (`pepesan.kasm.kasm_session`)

Inicia (o, con `-e kasm_session_state=absent`, destruye) la sesión de un usuario en un workspace ya registrado, y espera a que
esté en marcha. Si la sesión ya existe, no se lanza nada.

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-mi-servidor" pepesan.kasm.kasm_session \
  -e kasm_session_workspace=pepesan/core-ubuntu-resolute:1.20 \
  -e kasm_session_user=user@kasm.local
```

`kasm_session_workspace` es el nombre de la imagen o el nombre amigable que muestra el panel. Iniciar la sesión por adelantado
evita el arranque en frío que el usuario esperaría en su primer acceso.

## 6. Usuarios (`pepesan.kasm.kasm_user`)

Crea o borra un usuario de Kasm mediante la API pública. La contraseña es aleatoria por defecto (guardada en
`.credentials/<host>-kasm-user-<usuario>.pass`) o la que pase con `-e kasm_user_password=...`. Vea el README del rol para el
resto de campos.

## 7. Política de sesión (`pepesan.kasm.kasm_group`)

`site_kasm` ya la aplica. Para cambiarla, fije las variables y vuelva a ejecutar el rol, por ejemplo
`kasm_group_keepalive_seconds`, `kasm_group_allow_clipboard_down`, `kasm_group_allow_downloads`, `kasm_group_allow_uploads` o
`kasm_group_allow_printing` (todos los permisos de portapapeles, descarga, subida e impresión están desactivados por defecto).
El rol solo cambia los ajustes cuyo valor difiere.

## 8. Desinstalar (`pepesan.kasm.kasm_uninstall`)

```bash
ansible-playbook -i "$HOME/.config/pepesan-kasm/inventory-mi-servidor" pepesan.kasm.kasm_uninstall 2>&1 | tee uninstall.log
```

**Esto borra los datos de Kasm del servidor.** Por defecto conserva el certificado de Let's Encrypt
(`kasm_uninstall_remove_letsencrypt_certs: false`), para que reinstalar no gaste uno de los pocos certificados que Let's Encrypt
emite por nombre y semana. Para reinstalar desde cero, desinstale y vuelva a ejecutar `site_kasm`. La desinstalación no toca su
`.credentials/`.

## 9. Comprobar el resultado (solo lectura)

Ejecute esto en el servidor; nada de ello cambia nada.

```bash
# Contenedores propios de Kasm
docker exec kasm docker ps --format '{{.Names}}  {{.Status}}'

# Imágenes descargadas en el Docker de Kasm
docker exec kasm docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}'

# Workspaces registrados
docker exec kasm docker exec kasm_db psql -U kasmapp -d kasm -c "SELECT name, friendly_name FROM images;"

# Sesiones vivas ahora mismo
docker exec kasm docker exec kasm_db psql -U kasmapp -d kasm \
  -c "SELECT u.username, k.operational_status FROM kasms k JOIN users u USING (user_id);"

# Log del instalador, en vivo (solo lo lee root; no contiene las contraseñas)
tail -f /opt/kasm/data/opt/kasm_deploy.log
```

## 10. Problemas habituales

| Síntoma | Causa y solución |
|---|---|
| El primer acceso se queda en "Creating a secure connection..." y el proxy devuelve 502 | El contenedor de la sesión aún está arrancando (arranque en frío de una imagen grande). Se resuelve solo en segundos o pocos minutos. Inicie la sesión por adelantado con `kasm_session`. |
| El escritorio abre con el fondo negro pero el menú funciona | El escritorio aún se está pintando en un arranque en frío. Aparece poco después. |
| Docker no funciona dentro de la sesión | El workspace se creó sin `kasm_workspace_privileged=true`. Bórrelo y créelo de nuevo con esa opción. |
| `-e kasm_workspace_name=Mi workspace` registra el nombre "Mi" | Un `-e` normal se corta en el primer espacio. Use `-e '{"kasm_workspace_name": "Mi workspace"}'`. |
| `geerlingguy.certbot` falla con un condicional `list` frente a `boolean` | Versión anterior a la `5.4.1`. Reinstale los roles de terceros desde `requirements.yml`. |
| Un rol falla diciendo que no encuentra un rol `geerlingguy.*` | Los roles de terceros no están instalados: `ansible-galaxy role install -r requirements.yml`. |
| `kasm_credentials` falla con un inventario en línea de comandos (`-i 10.0.0.1,`) | Corregido en esta colección: el nombre del CSV se deriva del inventario y se sanea. |
| La sesión se pausa pasada una hora | Política de grupo. Suba `kasm_group_keepalive_seconds`. |
| `ps -u student` en el anfitrión muestra procesos Python de Kasm | Los contenedores de servicio de Kasm corren con el UID 1001, el mismo número que el usuario `student`. No son procesos de `student`. No haga `pkill -u student`: mataría la API de Kasm. |
