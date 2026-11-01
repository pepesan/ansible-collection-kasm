# Cómo contribuir

[English](CONTRIBUTING.md)

Gracias por ayudar con `pepesan.kasm`. Esta página explica cómo está organizado el repositorio, cómo comprobar un cambio y qué no
debe acabar nunca en él.

## Estructura

| Ruta | Qué es |
|---|---|
| `roles/<rol>/` | Un rol: `defaults/`, `tasks/`, `meta/`, `README.md` (inglés) y `README.es.md` (español) |
| `playbooks/` | Los cuatro playbooks que trae la colección, más scripts de ejemplo e `inventory.example` |
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

Necesita `ansible-core`, `ansible-lint`, `yamllint` y, para Molecule, `molecule` y Docker.

```bash
ansible-lint                      # perfil production, configurado en .ansible-lint
yamllint .
scripts/check-examples.sh         # cada play YAML de la documentación pasa --syntax-check
scripts/check-build.sh            # construye el tarball, lo inspecciona y lo instala en un entorno limpio
scripts/molecule.sh student       # Molecule de un rol, con nombres completos
```

Hay escenarios de Molecule para todos los roles, pero solo estos se ejecutan sin riesgo en una estación de trabajo: `linux_user`,
`student` y `kasm_credentials`. Los escenarios de `docker`, `kasm` y `kasm_uninstall` cargan módulos del kernel y fijan valores de
sysctl, lo que dentro de un contenedor privilegiado afecta al kernel **del anfitrión**, así que `scripts/molecule.sh` los rechaza
(ejecútelos en una máquina virtual desechable, o ponga `MOLECULE_ALLOW_UNSAFE=1` sabiendo lo que hace). Los roles que hablan con un
Kasm vivo (`kasm_workspace`, `kasm_session`, `kasm_group`, `kasm_user`, `kasm_docker_image`) no pueden ejecutarse en un contenedor
aislado: se verifican contra un servidor real.

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

La versión está en `galaxy.yml` y sigue el [Versionado Semántico](https://semver.org/lang/es/). Añada el cambio a `CHANGELOG.md`. Las
versiones publicadas en Ansible Galaxy no se pueden sobrescribir, así que construya y revise antes el tarball
(`scripts/check-build.sh`).
