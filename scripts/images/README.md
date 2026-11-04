# Local LXD VM image experiments

This tracked directory contains the image builders. Keep generated workspaces under `work/` ignored by Git. Downloaded ISOs belong in the dedicated ISO/storage partition; never place inventories or credentials here.

## Build from a versioned installer ISO

`build_rocky10_vm_image.sh` and `build_almalinux10_vm_image.sh` install from the selected distribution's boot ISO using Kickstart. The selected version is the real input: the script verifies the official SHA256, injects Kickstart into the ISO, installs from that version's BaseOS/AppStream repositories, boots the installed VM, checks its release and LXD agent, and publishes an LXD VM image.

Each script accepts an ISO version and architecture. The default is `10.2 x86_64`:

```bash
./build_rocky10_vm_image.sh --help
./build_rocky10_vm_image.sh 10.2 x86_64
ROCKY_ISO_VERSION=10.2 ./build_rocky10_vm_image.sh

./build_almalinux10_vm_image.sh --help
./build_almalinux10_vm_image.sh 10.2 x86_64
ALMALINUX_ISO_VERSION=10.2 ./build_almalinux10_vm_image.sh
```

The default ISO cache is `/media/pepesan/0c40c1c3-4dfe-4fa9-90e7-da72bcc3b6aa1/pepesan/isos`. The script refuses to use that default unless the partition is mounted; set `ISO_DIR` and, when needed, `ISO_MOUNT` to use another location. Existing cached ISOs are verified every run. Missing ISOs are downloaded to the cache and verified before ISO customization or VM creation. `LXD_POOL` defaults to `rocky-build`, whose directory pool is on the same storage partition. Recheck the mount, free space, and pool before running.

Images use versioned aliases such as `rockylinux/10.2/iso-vm` and `almalinux/10.2/iso-vm`. Existing aliases are never replaced. The builder creates a temporary VM, installs the OS noninteractively, detaches the installer ISO, validates the running guest, publishes the image, and removes only its temporary VM and ISO volume. Build workspaces remain under `scripts/images/work/`. Set `KEEP_BUILD_VM=1` to retain the temporary VM and installer volume for failure diagnosis.

The build scripts need `sudo` for apt dependencies and the ISO EFI filesystem helper. They pin the Lorax source used for `mkksiso`/`mkefiboot`. Ask whether class is in progress before starting a VM, as required by the test plan.

## Existing Distrobuilder images

These local aliases predate the ISO-based builder and are intentionally preserved:

- `rockylinux/10/vm` — Rocky Linux 10.2, built from the upstream `lxc/lxc-ci` Distrobuilder definition and package repositories; not built from the ISO.
- `almalinux/10/vm` — AlmaLinux 10.2, built from the upstream AlmaLinux Distrobuilder definition and package repositories; not built from the ISO.

Do not overwrite or delete those aliases when testing the ISO-based images. The boot ISO checksums verified locally are:

```text
bf3a75907948563d0c11f3d1b8546ee9216e18a3ea2dc0a67eb4c45452e210f9  Rocky-10.2-x86_64-boot.iso
b3f865468075bcada8f208d830289302c67529789d668041d24e8d6fc697ba6a  AlmaLinux-10.2-x86_64-boot.iso
```

## ISO image and role smoke tests

Both 10.2 ISO builds completed and published `rockylinux/10.2/iso-vm` and `almalinux/10.2/iso-vm`. The cached source ISOs passed their official SHA256 checks. Fresh VMs from both aliases reported version 10.2, had an active `incus-agent.service`, and did not contain the temporary build SSH key.

The first ISO boots exposed an SELinux denial when the LXD agent tried to listen on vsock. The Kickstart now installs `policycoreutils-python-utils`, assigns the agent executable the `bin_t` SELinux file context, and restores the context before starting the agent.

`roles/linux_user` was applied to fresh VMs from both ISO aliases and the existing AlmaLinux 10.2 Distrobuilder alias. It created `kasm-role-smoke` with its own primary group, supplementary `wheel`, `/bin/bash`, and a mode-700 home; `su -` succeeded. The second Ansible run returned `changed=0`. The temporary test credential is stored outside the repository under `/tmp/alma10-kasm-user-smoke/.credentials`.

## Safety

- Test guests are **virtual machines**, not LXC containers.
- Ask whether class is in progress before creating or starting a test VM.
- Recheck storage capacity, CPU/RAM, LXD pools, and image aliases immediately before a run.
- Keep inventories, private keys, passwords, and generated access CSVs outside the repository.

## References

- [Rocky Linux Kickstart automation](https://docs.rockylinux.org/10/guides/automation/kickstart-rocky/)
- [Rocky Linux custom ISO and `mkksiso`](https://docs.rockylinux.org/10/guides/isos/iso_creation/)
- [Lorax `mkksiso` documentation](https://weldr.io/lorax/mkksiso.html)
- [LXD image publishing](https://canonical.com/lxd/docs/default/reference/manpages/lxc/publish/)
- [LXC CI Rocky Linux image definition](https://github.com/lxc/lxc-ci/blob/main/images/rockylinux.yaml)
- [LXC CI AlmaLinux image definition](https://github.com/lxc/lxc-ci/blob/main/images/almalinux.yaml)
