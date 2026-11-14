# pepesan.kasm.kasm_agent

Instala Kasm Workspaces en un host como agente remoto y lo registra en un manager ya instalado. El rol invoca `pepesan.kasm.docker`; instala primero los roles de terceros con `ansible-galaxy role install -r requirements.yml`.

## Variables obligatorias

| Variable | Valor predeterminado | Descripción |
|---|---|---|
| `kasm_manager_hostname` | Sin definir | FQDN del manager; obligatorio. |
| `kasm_manager_token` | Se lee de `{{ kasm_credentials_dir }}/<fqdn-manager>-manager-token.pass` | Token de registro. Se recomienda el fichero de credenciales del nodo de control; los overrides se ocultan en los logs de Ansible. |

## Variables opcionales

| Variable | Valor predeterminado | Descripción |
|---|---|---|
| `kasm_version` | `1.19.0` | Versión de Kasm; debe coincidir con la del manager. |
| `kasm_dir` | `/opt/kasm` | Directorio del release y ficheros auxiliares. |
| `kasm_base_domain` | `example.com` | Sufijo de dominio para derivar el nombre público del agente. |
| `kasm_agent_public_hostname` | `inventory_hostname` si es FQDN; si no, `{{ node_name }}.{{ kasm_base_domain }}` | Nombre del agente registrado en Kasm. |
| `kasm_credentials_dir` | `$KASM_DATA_DIR/.credentials` o `{{ playbook_dir }}/data/.credentials` | Directorio de credenciales del nodo de control. |
| `kasm_agent_restrict_443_to_manager` | `false` | Restringe TCP 443 entrante a la dirección del manager mediante UFW, firewalld o iptables. La IP se resuelve desde el agente. Si no hay firewall compatible, informa que no se aplicó la restricción. |

El rol guarda `install.sh --help` en `{{ kasm_dir }}/install-help.txt` y acepta la EULA usando el flag anunciado por ese instalador. Marca la instalación completa solo cuando el contenedor `kasm_agent` está en marcha y sus logs muestran un registro correcto sin errores de registro. Ante fallos reintenta el instalador hasta tres veces; si el registro no termina correctamente, no crea el marcador. En ejecuciones posteriores omite la instalación si existe `/opt/kasm/.pepesan_install_complete_agent`.

## Ejemplo

```yaml
- hosts: kasm_agents
  become: true
  roles:
    - role: pepesan.kasm.kasm_agent
      vars:
        kasm_manager_hostname: manager.example.com
```

El token se lee en el nodo de control; el fichero debe tener permisos `0600`. Un token incorrecto o un manager inaccesible produce un error claro y no crea el marcador de instalación.
