# pepesan.kasm.kasm_agent

Installs Kasm Workspaces on a host as a remote agent and registers it with an already-installed manager. The role invokes `pepesan.kasm.docker`; install third-party roles first with `ansible-galaxy role install -r requirements.yml`.

## Required variables

| Variable | Default | Description |
|---|---|---|
| `kasm_manager_hostname` | unset | Manager FQDN; required. |
| `kasm_manager_token` | read from `{{ kasm_credentials_dir }}/<manager-fqdn>-manager-token.pass` | Registration token. Prefer the control-node credential file; overrides are hidden from Ansible logs. |

## Optional variables

| Variable | Default | Description |
|---|---|---|
| `kasm_version` | `1.19.0` | Kasm release version; keep equal to the manager's version. |
| `kasm_dir` | `/opt/kasm` | Release and support-file directory. |
| `kasm_base_domain` | `example.com` | Domain suffix when deriving the public agent name. |
| `kasm_agent_public_hostname` | `inventory_hostname` when it is an FQDN, otherwise `{{ node_name }}.{{ kasm_base_domain }}` | Agent hostname registered with Kasm. |
| `kasm_credentials_dir` | `$KASM_DATA_DIR/.credentials` or `{{ playbook_dir }}/data/.credentials` | Control-node credential directory. |
| `kasm_agent_restrict_443_to_manager` | `false` | Restrict inbound TCP 443 to the manager address using UFW, firewalld, or iptables. Manager IP is resolved on the agent. With no supported firewall, the role reports that no restriction was applied. |

The role saves `install.sh --help` to `{{ kasm_dir }}/install-help.txt`, then installs the agent and accepts the EULA using the flag advertised by that installer. Installation is marked complete only after the `kasm_agent` container is running and its logs contain a successful registration without registration errors. Failed registration leaves no marker; the role retries transient installer failures up to three times. A second run skips installation when `/opt/kasm/.pepesan_install_complete_agent` exists.

## Example

```yaml
- hosts: kasm_agents
  become: true
  roles:
    - role: pepesan.kasm.kasm_agent
      vars:
        kasm_manager_hostname: manager.example.com
```

The token file is read on the Ansible control node and should be mode `0600`. An incorrect token or an unreachable manager causes a clear failure and does not create the installation marker.
