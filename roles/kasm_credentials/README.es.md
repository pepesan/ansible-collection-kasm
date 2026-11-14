# kasm_credentials

**Nombre completo:** `pepesan.kasm.kasm_credentials` (colección [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Genera contraseñas aleatorias de admin/user de Kasm por host (persistidas en
el nodo de control para reutilizarlas) y registra las credenciales en el CSV
del inventario (`access-data-<inventario>.csv`), una fila por nodo. Lo usa
[`kasm`](../kasm/README.es.md) y lee el mismo fichero de contraseña `student`
que genera [`student`](../student/README.es.md).

Las columnas, en este orden, son `kasm_url`, `ip`, `student_user`,
`student_password`, `kasm_admin_user`, `kasm_admin_password`,
`kasm_normal_user`, `kasm_normal_user_password`. Las filas se ordenan en orden
ascendente por la URL completa de Kasm. `ip` procede de `ansible_host`.
El directorio del CSV se crea con permisos `0700` y cada fichero CSV tiene
permisos `0600`; otros usuarios locales no pueden leer las credenciales.

No cubierto por ningún rol o collection de Galaxy — es contabilidad
específica de Kasm sin equivalente upstream.

## Dónde consultar cada contraseña

Todo está en la máquina que ejecuta Ansible (nunca en el repositorio):

| Contraseña | Dónde | Fijar una concreta con |
|---|---|---|
| Usuario Linux `student` | CSV (`student_user`, `student_password`) y `.credentials/[<proyecto>-]<host>-<student_name>.pass` | `-e student_password_plain=...` |
| Kasm `admin@kasm.local` | CSV (`kasm_admin_user`, `kasm_admin_password`) y `.credentials/[<proyecto>-]<host>-kasm-admin.pass` | `-e kasm_admin_password=...` |
| Kasm integrado `user@kasm.local` | CSV (`kasm_normal_user`, `kasm_normal_user_password`) y `.credentials/[<proyecto>-]<host>-kasm-user.pass` | `-e kasm_default_user_password=...` |
| Usuarios de Kasm creados con [`kasm_user`](../kasm_user/README.es.md) | solo `.credentials/[<proyecto>-]<host>-kasm-user-<usuario>.pass` (el CSV tiene una fila por host) | `-e kasm_user_password=...` |

Cualquiera se puede pasar como parámetro; si no, se genera una aleatoria una sola vez y se reutiliza en ejecuciones
posteriores. El CSV recoge el valor realmente en uso, también cuando es fijo.

## Variables

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `kasm_credentials_dir` | `<directorio actual>/.credentials` | Dónde viven los ficheros de contraseña generados (mantener sincronizado con `student_credentials_dir`) |
| `kasm_admin_password` / `kasm_default_user_password` | aleatoria, persistida | Sobreescribir con `-e` para fijar contraseñas concretas |
| `kasm_credentials_admin_user` / `_user_user` | `admin@kasm.local` / `user@kasm.local` | Usuarios registrados en el CSV |
| `kasm_credentials_student_name` | `{{ student_name | default("student") }}` | Nombre del usuario Linux creado por [`student`](../student/README.es.md); sigue a `student_name` automáticamente para leer el fichero de contraseña correcto |
| `kasm_credentials_csv_prefix` | `access-data` | Prefijo del nombre del CSV (letras, dígitos, `.`, `_`, `-`). El `.gitignore` del repositorio solo cubre `access-data-*` (y el antiguo `datos-acceso-*`): añada su patrón si lo cambia |
| `kasm_credentials_csv_name` | `access-data-<proyecto|inventario>.csv` | Nombre exacto del CSV, derivado de `kasm_training_project` (o del inventario). Poner `""` para usar la fecha del día de ejecución. Debe ser un nombre `*.csv` simple |
| `kasm_training_project` | `""` | Prefijo de curso/proyecto para contraseñas generadas y CSV (`access-data-<proyecto>.csv`) |
| `kasm_credentials_csv_dir` | `<directorio actual>` | Dónde se escribe el CSV (el directorio desde el que se ejecuta `ansible-playbook`, no la carpeta del playbook) |

Requiere que quien llame al rol fije `kasm_domain` (normalmente lo aporta
`kasm`).

Las filas se ordenan en orden ascendente por la URL completa de Kasm,
desempatando por IP y nombre del inventario.

## Idempotencia

`files/update_credentials_csv.py` identifica el nodo por IP o nombre del
inventario, migra las columnas antiguas, elimina filas duplicadas y ordena
por URL de Kasm. Solo reescribe el CSV si cambian el esquema o las filas
canónicas; imprime `CHANGED ...` si lo hace y `OK ... already up to date` si
no hay cambios. La tarea de Ansible usa esa marca en `changed_when`.

## Concurrencia

La actualización del CSV es segura para ejecuciones paralelas multi-host:
`files/update_credentials_csv.py` usa un `flock` bloqueante alrededor del
ciclo de lectura-modificación-escritura y escribe de forma atómica (fichero
temporal + `os.replace`), así que varios hosts concurrentes delegando en el
mismo nodo de control nunca corrompen el fichero ni pierden una fila.

## Ejemplo


Generar las contraseñas y registrarlas en el CSV de accesos (es lo que hace el playbook de instalación antes de `kasm`):

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_credentials
      vars:
        node_name: kasmdemo
        kasm_domain: "{{ node_name }}.kasm.example.com"   # la dirección que se escribe en el CSV
```

Fijar usted algunas contraseñas y poner al CSV el nombre del curso, para que los despliegues de cursos distintos no compartan
fichero:

```yaml
- hosts: kasm
  roles:
    - role: pepesan.kasm.kasm_credentials
      vars:
        kasm_domain: "{{ node_name }}.example.com"
        kasm_admin_password: "{{ vault_kasm_admin_password }}"
        kasm_credentials_csv_name: "access-data-curso-2026.csv"
```

Vea el resultado sin imprimir ninguna contraseña:

```bash
head -1 access-data-*.csv                 # las columnas
cut -d, -f1-3 access-data-*.csv           # URL de Kasm, IP y nombre del inventario
ls -l .credentials/                       # un fichero por contraseña, modo 600
```

## CSV de acceso del clúster

El modo clúster (`pepesan.kasm.site_kasm_cluster`) escribe dos ficheros más con `tasks_from: cluster_csv.yml` y
`tasks_from: user_csv.yml`, junto a `access-data-*.csv`, en `kasm_credentials_csv_dir` (modo 600, con el nombre de
`kasm_training_project`). Están separados porque el CSV existente mezcla la contraseña de admin con la del alumno:

| Fichero | Para | Filas | Columnas |
|---|---|---|---|
| `cluster-access-<proyecto>.csv` | el operador; **no se reparte** | una por nodo (grupo `kasm_cluster`) | `role`, `node`, `fqdn`, `ip`, `ssh_user`, `ssh_password`, `kasm_url`, `kasm_admin_user`, `kasm_admin_password`, `kasm_manager_token`, `kasm_version` |
| `user-access-<proyecto>.csv` | alumnos | una por usuario de Kasm | `kasm_url`, `kasm_user`, `kasm_user_password`, `kasm_group`, `workspaces` (separados por `;`) |

- `role` es `manager` o `agent`; usuario/contraseña de admin y token solo se rellenan en la fila del manager;
  `ssh_password` va vacío si solo se usa clave. Las contraseñas de la base de datos y de Redis y la API key no van a ningún CSV.
- `files/update_cluster_csv.py` (`--kind cluster|user`; `files/update_user_csv.py` es `--kind user`) actualiza por `node` /
  `kasm_user`, ordena, toma un único `flock` para todo el ciclo y reemplaza el fichero de forma atómica. Los datos no
  secretos de la fila van por stdin en JSON; los secretos se leen de los ficheros `.pass` de `kasm_credentials_dir` (los
  que ya crean `kasm_manager`, `kasm_credentials` y `kasm_user`) o, si se indican, del entorno (`KASM_CSV_SSH_PASSWORD`,
  `KASM_CSV_KASM_ADMIN_PASSWORD`, `KASM_CSV_KASM_USER_PASSWORD`) y entonces se guardan en esos ficheros. Nunca por la línea de comandos.
- El CSV se genera siempre desde `<kasm_credentials_dir>/cluster-meta.json` (sin secretos) y esos ficheros, de modo que
  `--from-credentials` lo reconstruye **sin tocar los nodos** y con los mismos bytes. Si falta un secreto obligatorio
  falla, en vez de escribir una contraseña vacía.

| Variable | Por defecto | Para qué |
|---|---|---|
| `kasm_credentials_users` | `[]` | Usuarios de `user-access`: `{username, group, workspaces: [nombres], password (opcional)}` |
| `kasm_credentials_kasm_version` | `{{ kasm_version \| default('1.19.0') }}` | Valor de la columna `kasm_version` |

`cluster_csv.yml` se ejecuta en el manager y necesita `kasm_manager_hostname` y los grupos `kasm_cluster` / `kasm_manager`;
`user_csv.yml` necesita `kasm_manager_hostname`. Vea la [guía del clúster](../../docs/cluster.es.md).
