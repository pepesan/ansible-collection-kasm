# pepesan.kasm.kasm_manager

Instala un **manager** de Kasm Workspaces directamente en el host con el instalador oficial (layout `/opt/kasm/current`): rol de base de datos (`install.sh --role db`) y de aplicación web (`--role app`) en el mismo host, **sin agente local**. Los agentes se instalan con [`kasm_agent`](../kasm_agent/README.es.md) en otros hosts y se registran con el token que genera este rol.

Frente a [`kasm`](../kasm/README.es.md) (todo-en-uno: Kasm dentro de un contenedor `linuxserver/kasm`), aquí `install.sh` se ejecuta en el host, así que ve el SO real y los contenedores son los oficiales (`docker exec kasm_db ...`, de ahí `kasm_db_exec: docker exec kasm_db` en los roles que consultan la base de datos).

## Qué hace

1. Genera las contraseñas de admin/user ([`kasm_credentials`](../kasm_credentials/README.es.md), salvo que un rol anterior ya lo hiciera) y comprueba el DNS público de `kasm_manager_hostname` (solo con Let's Encrypt).
2. Instala Docker ([`docker`](../docker/README.es.md)), swap y el certificado de Let's Encrypt (`geerlingguy.swap`, `geerlingguy.certbot`: roles de terceros, `ansible-galaxy role install -r requirements.yml`).
3. Descarga y descomprime el release `kasm_version` en `{{ kasm_dir }}/kasm_release`, guarda `install.sh --help` en `{{ kasm_dir }}/install-help.txt` (MGR-01) y **usa los flags que anuncia**: si falta alguno necesario, el rol falla señalando ese fichero.
4. Ejecuta `install.sh --role db` y `--role app` con el `fix_and_install_kasm.sh` del rol `kasm` (parametrizado con variables `KASM_*`): parches de `install.sh`, hasta 3 intentos para fallos transitorios de plugins Docker (carrera de `kasmlogger.sock`) y éxito decidido por los contenedores en marcha, no por el código de salida. Los conflictos de puerto no se reintentan si faltan los servicios requeridos; los servicios sanos siguen contando como éxito. Se muestra el error real de `install.sh` y no se escribe marcador en el fallo.
5. Comprueba que la base de datos contiene una configuración no vacía del token del manager, que `kasm_db`, `kasm_api`, `kasm_manager` y `kasm_proxy` están Up y que **no** hay `kasm_agent`, y escribe `/opt/kasm/.pepesan_install_complete_manager`. El registro del primer agente verifica que el token guardado autentica de verdad. Una segunda pasada omite la instalación.
6. TLS: copia el certificado a `/opt/kasm/current/certs`, reinicia `kasm_proxy` solo si cambió e instala el deploy-hook de renovación (reutiliza el `letsencrypt.yml` del rol `kasm`; el hook lee `/etc/letsencrypt/kasm-deploy-hook.env`).

La BD oficial publica el puerto 5432. Este rol bloquea su acceso entrante por la interfaz pública en `INPUT` y `DOCKER-USER` (IPv4 e IPv6), sin bloquear la red Docker interna ni reiniciar Docker. La regla se reaplica al arrancar Docker mediante `kasm-db-firewall.service`. Verifica desde fuera que 5432 no responde y desde la app que sigue conectada a la BD. Si cambias la interfaz pública, vuelve a ejecutar el rol.

## Token de registro

Se genera la primera vez y se guarda **en el nodo de control** en `{{ kasm_credentials_dir }}/<kasm_manager_hostname>-manager-token.pass` (modo 600, nunca se muestra), y se expone como fact `kasm_manager_token`. [`kasm_agent`](../kasm_agent/README.es.md) lee el mismo fichero. Con `-e kasm_manager_token=...` se usa uno propio (solo letras y dígitos): se guarda en ese fichero. El token se entrega al rol db con `--manager-token`; el valor del ajuste en BD no coincide necesariamente con el texto original, por lo que la autenticación se prueba registrando un agente (AGT-02).

## Variables

| Variable | Valor predeterminado | Descripción |
|---|---|---|
| `kasm_manager_hostname` | — (**obligatoria**) | FQDN del manager (certificado, URL, registro de agentes). |
| `kasm_version` | `1.19.0` | Release de Kasm; mantenla igual en los agentes. |
| `kasm_dir` | `/opt/kasm` | Directorio del release, la ayuda y los marcadores. |
| `kasm_manager_token` | generado / leído del fichero de credenciales | Token de registro de agentes. |
| `kasm_credentials_dir` | `$KASM_DATA_DIR/.credentials` o `{{ playbook_dir }}/data/.credentials` | Directorio de credenciales del nodo de control. |
| `kasm_letsencrypt_enabled` | `true` | TLS real sí/no (compartida con el rol `kasm`). |
| `letsencrypt_email` | `admin@{{ kasm_base_domain }}` | Email de la cuenta de certbot. |
| `kasm_manager_release_url` / `kasm_manager_release_checksum` | URL oficial en S3 de `kasm_version` / vacío | Archivo del release y `sha256:<hex>` opcional. |
| `kasm_manager_db_hostname` | IPv4 por defecto del host | Dirección de la BD vista desde los contenedores `kasm_api`/`kasm_manager`. |
| `kasm_manager_install_flags` | `--role`, `--accept-eula`/`-e`, `--db-hostname`/`-q`, `--db-password`/`-Q`, `--manager-token`/`-M` | Grafías aceptadas por opción, comprobadas con `install.sh --help`. |
| `kasm_manager_db_extra_args` / `kasm_manager_app_extra_args` | vacío | Argumentos extra de `install.sh` por rol. |
| `kasm_manager_installer_patches` | `[]` | Expresiones `sed` aplicadas a `install.sh` antes de ejecutarlo (p. ej. para saltar un check de SO en un Ubuntu nuevo). |
| `kasm_manager_db_services` / `kasm_manager_app_services` | `kasm_db` / `kasm_api kasm_manager kasm_proxy` | Contenedores que deben estar Up. |

El instalador recibe contraseñas y token como argumentos (igual que el procedimiento oficial); el wrapper redacta sus salidas conocidas y deja el log `/var/log/kasm-manager-{db,app}-install.log` accesible solo a root. No distribuyas esos logs; verifica que no aparecen secretos antes de compartirlos.

## Ejemplo

```yaml
- hosts: kasm_manager
  roles:
    - role: pepesan.kasm.kasm_manager
      vars:
        kasm_manager_hostname: manager.example.com
```

Verificación: `docker ps` en el host muestra `kasm_db`, `kasm_api`, `kasm_manager`, `kasm_proxy`; `https://manager.example.com` sirve el certificado de Let's Encrypt; la segunda pasada da `changed=0`.
