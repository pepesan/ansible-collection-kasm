#!/usr/bin/env bash
# Install a versioned Rocky/Alma boot ISO with Kickstart, then publish the LXD VM.
set -euo pipefail

DISTRO="${1:?Usage: build_iso_vm_image.sh rocky|almalinux VERSION [ARCH]}"
ISO_VERSION="${2:?Usage: build_iso_vm_image.sh rocky|almalinux VERSION [ARCH]}"
ARCH="${3:-x86_64}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ISO_DIR="/media/pepesan/0c40c1c3-4dfe-4fa9-90e7-da72bcc3b6aa1/pepesan/isos"
ISO_DIR="${ISO_DIR:-${DEFAULT_ISO_DIR}}"
ISO_MOUNT="${ISO_MOUNT:-/media/pepesan/0c40c1c3-4dfe-4fa9-90e7-da72bcc3b6aa1}"
LXD_POOL="${LXD_POOL:-rocky-build}"
LORAX_COMMIT="30890c3483262a5b69612ce1e2b4d515d9b88f80"
if [[ "${ISO_DIR}" == "${DEFAULT_ISO_DIR}" ]] && ! mountpoint -q "${ISO_MOUNT}"; then
  echo "ISO storage is not mounted at ${ISO_MOUNT}; refusing to download to another filesystem." >&2
  exit 1
fi
if [[ ! -d "${ISO_DIR}" ]]; then
  echo "ISO directory does not exist: ${ISO_DIR}" >&2
  exit 1
fi

if [[ ! "${ISO_VERSION}" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "ISO version must be a major.minor value (for example 10.2): ${ISO_VERSION}" >&2
  exit 2
fi
if [[ "${ISO_VERSION%%.*}" != "10" ]]; then
  echo "These Rocky/Alma 10 builders require a version in the 10.x series: ${ISO_VERSION}" >&2
  exit 2
fi
case "${DISTRO}" in
  rocky)
    ISO_NAME="Rocky-${ISO_VERSION}-${ARCH}-boot.iso"
    ISO_BASE="https://download.rockylinux.org/pub/rocky/${ISO_VERSION}"
    REPO_BASE="${ISO_BASE}"
    IMAGE_ALIAS="rockylinux/${ISO_VERSION}/iso-vm"
    ;;
  almalinux)
    ISO_NAME="AlmaLinux-${ISO_VERSION}-${ARCH}-boot.iso"
    ISO_BASE="https://repo.almalinux.org/almalinux/${ISO_VERSION}"
    REPO_BASE="${ISO_BASE}"
    IMAGE_ALIAS="almalinux/${ISO_VERSION}/iso-vm"
    ;;
  *) echo "Unsupported distribution '${DISTRO}' (expected rocky or almalinux)" >&2; exit 2 ;;
esac
case "${ARCH}" in
  x86_64|aarch64) ;;
  *) echo "Unsupported architecture '${ARCH}' (expected x86_64 or aarch64)" >&2; exit 2 ;;
esac

mkdir -p "${SCRIPT_DIR}/work"
WORK_DIR="$(mktemp -d "${SCRIPT_DIR}/work/${DISTRO}-${ISO_VERSION}-iso.XXXXXX")"
ISO_PATH="${ISO_DIR}/${ISO_NAME}"
CHECKSUM_PATH="${WORK_DIR}/CHECKSUM"
CUSTOM_ISO="${WORK_DIR}/${ISO_NAME%.iso}-kickstart.iso"
KICKSTART="${WORK_DIR}/ks.cfg"
LORAX_SRC="${WORK_DIR}/lorax"
LORAX_BIN="${WORK_DIR}/bin"
VM="${DISTRO}-${ISO_VERSION//./}-iso-build-$$"
ISO_VOLUME="${VM}-installer"
VM_CREATED=0
ISO_IMPORTED=0
SSH_KEY="${WORK_DIR}/build_ssh_key"
ssh-keygen -q -t ed25519 -N "" -C kasm-image-build -f "${SSH_KEY}"
cleanup() {
  status=$?
  if [[ "${KEEP_BUILD_VM:-0}" != "1" ]]; then
    if (( VM_CREATED )); then lxc delete --force "${VM}" >/dev/null 2>&1 || true; fi
    if (( ISO_IMPORTED )); then lxc storage volume delete "${LXD_POOL}" "${ISO_VOLUME}" >/dev/null 2>&1 || true; fi
  else
    echo "Temporary VM retained: ${VM}" >&2
    echo "Installer ISO volume retained: ${ISO_VOLUME}" >&2
  fi
  echo "Build workspace retained at: ${WORK_DIR}" >&2
  exit "${status}"
}
trap cleanup EXIT

if lxc image info "${IMAGE_ALIAS}" >/dev/null 2>&1; then
  echo "Refusing to replace existing image alias ${IMAGE_ALIAS}; existing images are preserved." >&2
  exit 1
fi
if ! lxc storage show "${LXD_POOL}" >/dev/null 2>&1; then
  echo "LXD storage pool '${LXD_POOL}' does not exist." >&2
  exit 1
fi

# Resolve and verify the versioned official ISO before creating the build VM.
CHECKSUM_URL="${ISO_BASE}/isos/${ARCH}/CHECKSUM"
ISO_URL="${ISO_BASE}/isos/${ARCH}/${ISO_NAME}"
curl --fail --location --silent --show-error "${CHECKSUM_URL}" --output "${CHECKSUM_PATH}"
CHECKSUM_LINE="$(grep -F "SHA256 (${ISO_NAME}) = " "${CHECKSUM_PATH}" || true)"
EXPECTED_SHA="$(printf '%s\n' "${CHECKSUM_LINE}" | awk '{print $4}')"
if [[ ! "${EXPECTED_SHA}" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "Official CHECKSUM does not contain a SHA256 entry for ${ISO_NAME}." >&2
  exit 1
fi
if [[ ! -f "${ISO_PATH}" ]]; then
  echo "Downloading ${ISO_NAME} to ${ISO_PATH}"
  curl --fail --location --retry 3 --silent --show-error "${ISO_URL}" --output "${ISO_PATH}.part"
  printf '%s  %s\n' "${EXPECTED_SHA}" "${ISO_PATH}.part" | sha256sum --check --status
  mv -- "${ISO_PATH}.part" "${ISO_PATH}"
else
  echo "Using cached ISO ${ISO_PATH}"
fi
printf '%s  %s\n' "${EXPECTED_SHA}" "${ISO_PATH}" | sha256sum --check

# Install the ISO customizer and its EFI/MD5 tools only after the source ISO is verified.
if ! command -v git >/dev/null || ! command -v python3 >/dev/null || \
   ! command -v xorriso >/dev/null || ! command -v implantisomd5 >/dev/null || \
   ! command -v mcopy >/dev/null || ! command -v mkfs.vfat >/dev/null; then
  sudo apt-get update
  sudo apt-get install -y curl git python3 xorriso isomd5sum mtools dosfstools
fi

git clone --quiet https://github.com/weldr/lorax.git "${LORAX_SRC}"
git -C "${LORAX_SRC}" fetch --quiet --depth 1 origin "${LORAX_COMMIT}"
git -C "${LORAX_SRC}" checkout --quiet --detach "${LORAX_COMMIT}"
mkdir -p "${LORAX_BIN}"
cat > "${LORAX_BIN}/mkefiboot" <<'PYEOF'
#!/usr/bin/env python3
import os
import runpy
import sys
import types

lorax_src = os.environ["LORAX_SRC"]
sys.path.insert(0, os.path.join(lorax_src, "src"))
package = types.ModuleType("pylorax")
package.__path__ = [os.path.join(lorax_src, "src", "pylorax")]
sys.modules["pylorax"] = package
runpy.run_path(os.path.join(lorax_src, "src", "pylorax/cmdline/mkefiboot.py"), run_name="__main__")
PYEOF
chmod 0755 "${LORAX_BIN}/mkefiboot"

BASEOS_URL="${REPO_BASE}/BaseOS/${ARCH}/os/"
APPSTREAM_URL="${REPO_BASE}/AppStream/${ARCH}/os/"
SSH_PUBLIC_KEY="$(cat "${SSH_KEY}.pub")"
cat > "${KICKSTART}" <<KSEOF
lang en_US.UTF-8
keyboard us
timezone UTC --utc
rootpw --lock
text
url --url="${BASEOS_URL}"
repo --name=AppStream --baseurl="${APPSTREAM_URL}"
bootloader --append="console=tty1 console=ttyS0,115200n8"
zerombr
clearpart --all --initlabel --disklabel=gpt
autopart --type=lvm
network --device=link --bootproto=dhcp --activate --onboot=yes
skipx
firstboot --disable
selinux --enforcing
firewall --enabled --ssh
%packages --ignoremissing
@^minimal-environment
openssh-server
python3
sudo
policycoreutils-python-utils
%end
%post
install -d -m 0700 /root/.ssh
printf '%s\n' '${SSH_PUBLIC_KEY}' > /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys

cat > /usr/lib/udev/rules.d/99-lxd-agent.rules <<'RULES'
SYMLINK=="virtio-ports/org.linuxcontainers.lxd", TAG+="systemd", ENV{SYSTEMD_WANTS}+="incus-agent.service"
SYMLINK=="virtio-ports/org.linuxcontainers.incus", TAG+="systemd", ENV{SYSTEMD_WANTS}+="incus-agent.service"
RULES
cat > /usr/lib/systemd/system/incus-agent.service <<'UNIT'
[Unit]
Description=Linux Containers VM agent
Before=multi-user.target
DefaultDependencies=no

[Service]
Type=notify
WorkingDirectory=-/run/incus_agent
ExecStartPre=/usr/lib/systemd/incus-agent-setup
ExecStart=/run/incus_agent/incus-agent
Restart=on-failure
RestartSec=5s
StartLimitInterval=60
StartLimitBurst=10

UNIT
cat > /usr/lib/systemd/incus-agent-setup <<'SETUP'
#!/bin/sh
set -eu
PREFIX=/run/incus_agent
CDROM=/dev/disk/by-id/scsi-0QEMU_QEMU_CD-ROM_incus_agent
mount_virtiofs() { mount -t virtiofs config "\${PREFIX}.mnt" >/dev/null 2>&1; }
mount_9p() {
    modprobe 9pnet_virtio >/dev/null 2>&1 || true
    mount -t 9p config "\${PREFIX}.mnt" -o access=0,trans=virtio,size=1048576 >/dev/null 2>&1
}
mount_cdrom() { mount "\${CDROM}" "\${PREFIX}.mnt" >/dev/null 2>&1; }
fail() {
    if [ -x "\${PREFIX}/incus-agent" ]; then exit 0; fi
    umount -l "\${PREFIX}" >/dev/null 2>&1 || true
    eject "\${CDROM}" >/dev/null 2>&1 || true
    rmdir "\${PREFIX}" >/dev/null 2>&1 || true
    echo "\${1}, failing"
    exit 1
}
mkdir -p "\${PREFIX}.mnt"
mount_9p || mount_virtiofs || mount_cdrom || fail "Couldn't mount config drive"
umount -l "\${PREFIX}" >/dev/null 2>&1 || true
mkdir -p "\${PREFIX}"
mount -t tmpfs tmpfs "\${PREFIX}" -o mode=0700,size=50M
cp -Ra "\${PREFIX}.mnt/"* "\${PREFIX}"
if [ ! -e "\${PREFIX}/incus-agent" ] && [ -e "\${PREFIX}/lxd-agent" ]; then
    ln -s lxd-agent "\${PREFIX}/incus-agent"
fi
umount "\${PREFIX}.mnt"
rmdir "\${PREFIX}.mnt"
eject "\${CDROM}" >/dev/null 2>&1 || true
chown -R root:root "\${PREFIX}"
semanage fcontext -a -t bin_t "\${PREFIX}/lxd-agent"
restorecon -R "\${PREFIX}"
SETUP
chmod 0755 /usr/lib/systemd/incus-agent-setup
%end
poweroff
KSEOF

# --cmdline carries serial output to the VM console and runs the Kickstart noninteractively.
sudo env PATH="${LORAX_BIN}:${PATH}" LORAX_SRC="${LORAX_SRC}" PYTHONPATH="${LORAX_SRC}/src" \
  python3 "${LORAX_SRC}/src/pylorax/cmdline/mkksiso.py" \
  --ks "${KICKSTART}" --cmdline "inst.text console=ttyS0,115200n8" "${ISO_PATH}" "${CUSTOM_ISO}"

lxc storage volume import "${LXD_POOL}" "${CUSTOM_ISO}" "${ISO_VOLUME}" --type=iso
ISO_IMPORTED=1
lxc init --empty "${VM}" --vm --storage "${LXD_POOL}" \
  --device root,size=30GiB --config limits.cpu=2 --config limits.memory=4GiB </dev/null
VM_CREATED=1
lxc config device add "${VM}" installer disk pool="${LXD_POOL}" source="${ISO_VOLUME}" boot.priority=10
lxc start "${VM}"

echo "Waiting for the ${DISTRO} ${ISO_VERSION} installer to power off the VM..."
INSTALL_DEADLINE=$((SECONDS + 3600))
while (( SECONDS < INSTALL_DEADLINE )); do
  STATE="$(lxc list "${VM}" --format csv -c s)"
  if [[ "${STATE}" == "STOPPED" ]]; then break; fi
  if [[ "${STATE}" != "RUNNING" ]]; then
    echo "Unexpected installer VM state: ${STATE}" >&2
    exit 1
  fi
  sleep 5
done
if [[ "$(lxc list "${VM}" --format csv -c s)" != "STOPPED" ]]; then
  echo "Installer did not power off within one hour; set KEEP_BUILD_VM=1 to inspect a future run." >&2
  exit 1
fi

lxc config device remove "${VM}" installer
lxc start "${VM}"
echo "Waiting for the LXD guest agent..."
AGENT_READY=0
for _ in $(seq 1 120); do
  if lxc exec "${VM}" -- true >/dev/null 2>&1; then AGENT_READY=1; break; fi
  sleep 5
done
if (( ! AGENT_READY )); then
  GUEST_IPV4="$(lxc list "${VM}" --format csv -c 4 | cut -d' ' -f1)"
  if [[ -n "${GUEST_IPV4}" ]]; then
    ssh -i "${SSH_KEY}" -o BatchMode=yes -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "root@${GUEST_IPV4}" \
      'systemctl status incus-agent.service --no-pager || true; journalctl -b -u incus-agent.service --no-pager -n 100 || true; ls -l /dev/virtio-ports /run/incus_agent 2>&1 || true' \
      || echo "Could not retrieve guest agent diagnostics over SSH." >&2
  else
    echo "No guest IPv4 address available for SSH diagnostics." >&2
  fi
  echo "LXD guest agent did not start after ISO installation." >&2
  exit 1
fi
lxc exec "${VM}" -- rm -f /root/.ssh/authorized_keys
lxc exec "${VM}" -- rmdir /root/.ssh

ACTUAL_VERSION="$(lxc exec "${VM}" -- sh -c '. /etc/os-release; printf "%s" "$VERSION_ID"')"
if [[ "${ACTUAL_VERSION}" != "${ISO_VERSION}" ]]; then
  echo "Installed version ${ACTUAL_VERSION} does not match selected ISO/repository ${ISO_VERSION}." >&2
  exit 1
fi
lxc exec "${VM}" -- systemctl is-system-running || true
lxc stop "${VM}" --timeout=60
lxc publish "${VM}" --alias "${IMAGE_ALIAS}"
lxc image info "${IMAGE_ALIAS}"
rm -f "${SSH_KEY}" "${SSH_KEY}.pub"
echo "Published ISO-built VM image: ${IMAGE_ALIAS}"
