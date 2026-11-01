# kasm_credentials

**Nombre completo:** `pepesan.kasm.kasm_credentials` (colección [`pepesan.kasm`](https://galaxy.ansible.com/ui/repo/published/pepesan/kasm/))

Genera contraseñas aleatorias de admin/user de Kasm por host (persistidas en
el nodo de control para que ejecuciones repetidas las reutilicen) y registra
las credenciales de este host en un CSV compartido con el nombre del
inventario usado (`access-data-<inventario>.csv`, p. ej. `-i inventory-my-course`
→ `access-data-inventory-my-course.csv`), una fila por IP. Lo usa
[`kasm`](../kasm/README.es.md) y lee el mismo fichero de
contraseña de `student` que genera [`student`](../student/README.es.md),
para incluirla en la misma fila del CSV.

No cubierto por ningún rol o collection de Galaxy — es contabilidad
específica de Kasm sin equivalente upstream.

## Dónde consultar cada contraseña

Todo está en la máquina que ejecuta Ansible (nunca en el repositorio):

| Contraseña | Dónde | Fijar una concreta con |
|---|---|---|
| Usuario Linux `student` | CSV de accesos (`student_password`) y `.credentials/<host>-<student_name>.pass` | `-e student_password_plain=...` |
| Kasm `admin@kasm.local` | CSV de accesos (`kasm_admin_password`) y `.credentials/<host>-kasm-admin.pass` | `-e kasm_admin_password=...` |
| Kasm integrado `user@kasm.local` | CSV de accesos (columna `kasm_user_password`) y `.credentials/<host>-kasm-user.pass` | `-e kasm_default_user_password=...` |
| Usuarios de Kasm creados con [`kasm_user`](../kasm_user/README.es.md) | solo `.credentials/<host>-kasm-user-<usuario>.pass` (el CSV tiene una fila por host) | `-e kasm_user_password=...` |

Cualquiera se puede pasar como parámetro; si no, se genera una aleatoria una sola vez y se reutiliza en ejecuciones
posteriores. El CSV recoge el valor realmente en uso, también cuando es fijo.

## Variables

| Variable | Valor por defecto | Propósito |
|---|---|---|
| `kasm_credentials_dir` | `{{ playbook_dir }}/.credentials` | Dónde viven los ficheros de contraseña generados (mantener sincronizado con `student_credentials_dir`) |
| `kasm_admin_password` / `kasm_default_user_password` | aleatoria, persistida | Sobreescribir con `-e` para fijar contraseñas concretas |
| `kasm_credentials_admin_user` / `_user_user` | `admin@kasm.local` / `user@kasm.local` | Usuarios registrados en el CSV |
| `kasm_credentials_student_name` | `{{ student_name | default("student") }}` | Nombre del usuario Linux creado por [`student`](../student/README.es.md); sigue a `student_name` automáticamente para leer el fichero de contraseña correcto |
| `kasm_credentials_csv_prefix` | `access-data` | Prefijo del nombre del CSV (letras, dígitos, `.`, `_`, `-`). El `.gitignore` del repositorio solo cubre `access-data-*` (y el antiguo `datos-acceso-*`): añada su patrón si lo cambia |
| `kasm_credentials_csv_name` | `access-data-<nombre del fichero de inventario>.csv` | Nombre exacto del CSV, derivado del fichero de inventario de la ejecución (`inventory_file`). Sin fecha: todas las ejecuciones del mismo inventario caen en el mismo fichero y el nombre indica qué hosts contiene. Poner `""` para usar la fecha del día de ejecución (abajo). Debe ser un nombre `*.csv` simple; el script rechaza rutas |
| `kasm_training_project` | `""` | Solo cuando `kasm_credentials_csv_name` es `""`: prefijo de curso opcional en `access-data[-<proyecto>]-<fecha de ejecución>.csv`; un fichero nuevo cada día |
| `kasm_credentials_csv_dir` | `{{ playbook_dir }}` | Dónde se escribe el CSV |

Requiere que quien llame al rol fije `kasm_domain` (normalmente lo aporta
`kasm`).

## Orden de las filas

Las filas se ordenan por el nombre de host de la URL de Kasm en orden natural (`nodo2` antes que `nodo10`,
`nodo30` antes que `nodo31`), desempatando por IP. Un CSV existente y desordenado se reordena en la siguiente ejecución.

## Idempotencia

`files/update_credentials_csv.py` compara la fila que va a escribir contra
lo que ya hay para la IP de este host; solo reescribe el fichero (e imprime
`CHANGED ...`) cuando algo difiere de verdad, imprimiendo
`OK ... already up to date` en caso contrario. El `changed_when` de la task
de Ansible lee esa marca, así que una segunda ejecución con las mismas
entradas no reporta cambios.

## Concurrencia

La actualización del CSV es segura para ejecuciones paralelas multi-host:
`files/update_credentials_csv.py` usa un `flock` bloqueante alrededor del
ciclo de lectura-modificación-escritura y escribe de forma atómica (fichero
temporal + `os.replace`), así que varios hosts concurrentes delegando en el
mismo nodo de control nunca corrompen el fichero ni pierden una fila.

## Ejemplo


Generar las contraseñas y registrarlas en el CSV de accesos (es lo que hace el playbook de instalación antes de `kasm`):

```yaml
- hosts: ubuntu
  roles:
    - role: pepesan.kasm.kasm_credentials
      vars:
        node_name: kasmdemo
        kasm_domain: "{{ node_name }}.kasm.example.com"   # la dirección que se escribe en el CSV
```

Fijar usted algunas contraseñas y poner al CSV el nombre del curso, para que los despliegues de cursos distintos no compartan
fichero:

```yaml
- hosts: ubuntu
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
cut -d, -f1,3 access-data-*.csv           # IP y URL de Kasm de cada servidor, ordenados por nombre de host
ls -l .credentials/                       # un fichero por contraseña, modo 600
```
