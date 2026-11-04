# Cómo contribuir

[English](CONTRIBUTING.md)

Gracias por ayudar con `pepesan.kasm`. Esta página explica cómo está organizado el repositorio, cómo comprobar un cambio y qué no
debe acabar nunca en él.

## Estructura

| Ruta | Qué es |
|---|---|
| `roles/<rol>/` | Un rol: `defaults/`, `tasks/`, `meta/`, `README.md` (inglés) y `README.es.md` (español) |
| `playbooks/` | Los playbooks que incluye la colección |
| `examples/` | `ansible.cfg` seguro, inventario de ejemplo, instalador de dependencias y scripts de uso |
| `docs/` | La guía de uso, en inglés y en español |
| `scripts/` | `molecule.sh`, `check-build.sh` y `check-examples.sh` |
| `galaxy.yml`, `meta/runtime.yml` | Metadatos de la colección |
| `requirements.yml` | Los roles de terceros (de Jeff Geerling) que la colección usa pero no incluye |

## Convenciones

- **Inglés en el código.** Los nombres de roles, variables y tareas y los comentarios van en inglés. Cada rol tiene un `README.md`
  en inglés y un `README.es.md` en español; mantenga los dos al día.
- **Variables.** Las variables públicas se documentan en el README del rol y empiezan por el prefijo del rol. Las variables
  `kasm_*` compartidas por varios roles (`kasm_dir`, `kasm_url`, `kasm_admin_password`...) son la única excepción, a propósito.
- **Nombres completos** (`pepesan.kasm.<rol>`) en playbooks, `include_role` y documentación.
- **Idempotente.** Ejecutar un rol dos veces no debe cambiar nada la segunda vez.
- **Contraseñas.** Cualquier contraseña debe poder pasarse como parámetro y, si no se pasa, ser aleatoria y persistida. Las tareas
  que manejan un secreto usan `no_log: true` y no se imprime nada secreto.
- **Roles de terceros:** se incluyen desde las tareas (no como dependencias de `meta`, que una colección no puede declarar) y el
  fallo cuando falta uno explica cómo instalarlo.

## Comprobar un cambio

Ejecute en local, uno por uno, los mismos gates que usan CI y la publicación:

```bash
ansible-lint
yamllint .
scripts/check-build.sh
scripts/check-examples.sh
scripts/molecule.sh linux_user test
scripts/molecule.sh student test
scripts/molecule.sh kasm_credentials test
```

`check-build.sh` comprueba el archivo de la colección, hace una instalación limpia, resuelve los playbooks por nombre y ejecuta
Galaxy importer. `check-examples.sh` valida la sintaxis de todos los playbooks YAML documentados. El workflow de publicación
ejecuta estos checks antes de construir o publicar.

Solo tres roles tienen escenario de Molecule porque se pueden probar en un contenedor aislado: `linux_user`, `student` y
`kasm_credentials`. El resto se cubre con `ansible-lint` y pruebas manuales de extremo a extremo, no con Molecule: `docker`,
`kasm` y `kasm_uninstall` cargan módulos del kernel y fijan sysctl, lo que dentro de un contenedor privilegiado afecta al kernel
**del anfitrión**; `kasm_workspace`, `kasm_session`, `kasm_group`, `kasm_user` y `kasm_docker_image` necesitan un Kasm activo.
Consulte [`MATRIX.md`](MATRIX.md), en inglés, para ver la evidencia de compatibilidad y los escenarios aún no verificados. CI
no se conecta a servidores reales.

### Prueba de extremo a extremo en un servidor real

Para cambios de instalación o de los roles Kasm, use un servidor desechable con un sistema operativo de la matriz de
[`MATRIX.md`](MATRIX.md):

1. Construya e instale la colección desde su copia en un directorio temporal e instale los roles de terceros desde
   `requirements.yml`, para probar el código actual.
2. Mantenga el inventario **fuera del repositorio** y guarde cada ejecución en un log:
   `ansible-playbook ... 2>&1 | tee e2e.log`.
3. Ejecute `pepesan.kasm.site_kasm` dos veces y compruebe que la segunda no cambia nada. Pruebe operaciones de workspace,
   sesión y usuario.
4. Para probar persistencia tras reinicio, use exactamente una sesión existente: cree un fichero en su home, reinicie, recupere
   esa misma sesión y compruebe el fichero y el ID. No cree una segunda sesión ni un workspace de reemplazo.
5. Guarde resultados sin datos sensibles y las versiones del entorno en el log privado. No declare aprobada una plataforma o
   escenario sin evidencia.

### De extremo a extremo en un servidor real

Para un cambio que toque la instalación o los roles de Kasm, pruebe en un servidor Ubuntu desechable que sea suyo, desde un estado
limpio:

1. Construya e instale la colección desde su copia en un directorio temporal, y los roles de terceros desde `requirements.yml`, para
   probar su código y no una copia antigua.
2. Guarde el inventario **fuera del repositorio** (la IP de un servidor es un secreto) y envíe cada ejecución a un log:
   `ansible-playbook ... 2>&1 | tee e2e.log`.
3. Ejecute `pepesan.kasm.site_kasm`, luego **vuelva a ejecutarlo y compruebe que no cambia nada**, después registre un workspace,
   inicie una sesión y borre ambos.

## No suba nunca secretos

Ni un token, ni una clave de API, ni una contraseña, ni la IP de un servidor real, ni en el código, ni en la documentación, ni en un
ejemplo ni en un workflow. En los ejemplos use `203.0.113.x` y `example.com`. El `.gitignore` ya cubre lo que generan los roles y las
pruebas (`.credentials/`, `access-data-*.csv`, `inventory-*`, `kasm-api-key-*.json`, logs, tarballs...), pero no se fíe solo de él:
antes de cada commit y de cada push ejecute `git status` y `git diff --cached` y lea lo que va a publicar.

`scripts/check-build.sh` también falla si el tarball contiene ficheros de desarrollo o una dirección IPv4 que no sea de ejemplo de
documentación.

## Commits

Un resumen corto en imperativo en la primera línea y luego un cuerpo que explique el *porqué*. Un cambio lógico por commit.

## Versiones

La versión está en `galaxy.yml` y sigue el [Versionado Semántico](https://semver.org/lang/es/). Añada los cambios a
`CHANGELOG.md`. Las versiones publicadas en Ansible Galaxy no se pueden sobrescribir.

Ejecute solo uno de estos comandos para incrementar `galaxy.yml`:

```bash
python3 scripts/bump_version.py patch
python3 scripts/bump_version.py minor
python3 scripts/bump_version.py major
```

El script solo modifica `galaxy.yml`; actualice manualmente `Unreleased` en `CHANGELOG.md`. No hace commit, tag, push ni
publica.

Antes de crear una etiqueta:

1. Ejecute secuencialmente todos los comandos de **Comprobar un cambio** y revise el tarball para confirmar que no contiene datos privados.
2. Inicie manualmente el workflow `Release`: valida y construye el paquete, pero el dry run no publica.
3. Compruebe que `vX.Y.Z` coincide con `galaxy.yml`. Al subir la etiqueta se publica en Galaxy y se crea la GitHub Release;
   se necesita el secret `GALAXY_API_KEY`.
4. Si el cambio requiere validar comportamiento de servidor, complete y registre aparte la prueba E2E manual. CI no despliega
   en servidores reales.
