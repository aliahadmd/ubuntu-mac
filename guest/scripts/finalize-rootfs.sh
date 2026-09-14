#!/bin/bash

# Runs inside the ARM64 Ubuntu root after packages are staged and the
# configuration overlay is applied.
set -euo pipefail

spec=/usr/share/tryubuntu/build-spec.json
[[ -f $spec ]] || { echo "Missing $spec" >&2; exit 1; }

read_spec() {
  python3 -c "import json; print(json.load(open('$spec'))$1)"
}

[[ $(read_spec '["image"]["architecture"]') == aarch64 ]] || {
  echo "Factory guest must be ARM64" >&2
  exit 1
}
[[ $(read_spec '["guest"].get("profile")') == factory ]] || {
  echo "Factory guest profile is required" >&2
  exit 1
}

# The core set is the ABI surface the Mac integration depends on. Fail the
# build when the archive serves anything other than the pinned versions; the
# pin refresh is a reviewed spec change, not a silent drift.
python3 -c "import json; pins = json.load(open('/usr/share/tryubuntu/build-spec.json'))['distribution']['corePackages']; [print(k + '=' + v) for k, v in sorted(pins.items())]" |
while IFS='=' read -r name version; do
  installed=$(dpkg-query -W -f='${Version}' "$name" 2>/dev/null) || {
    echo "Pinned core package is missing: $name" >&2
    exit 1
  }
  if [ "$installed" != "$version" ]; then
    echo "Core package pin drift for $name: pinned $version, staged $installed" >&2
    exit 1
  fi
done || {
  echo "Core package pin verification failed" >&2
  exit 1
}

locale-gen
passwd --lock root >/dev/null
systemctl enable NetworkManager.service
systemctl enable systemd-resolved.service

# Graphical default target; GDM greets the provisioned account.
ln -sfn /usr/lib/systemd/system/graphical.target /etc/systemd/system/default.target

# Ubuntu orders the display manager after snap seeding, which on first boot
# holds the desktop hostage to snap downloads over the VM's NAT link. Mask
# the boot-time wait only: snapd still runs and seeds in the background, so
# snap apps appear shortly after login instead of delaying the desktop.
systemctl mask snapd.seeded.service
[[ -x /usr/sbin/gdm3 ]] || { echo "Missing GDM for the graphical factory" >&2; exit 1; }

# The factory ships the vendor sshd unit for the boot-scoped ssh-access
# generator, but sshd must never run unless this boot's kernel command line
# carries the activation token.
systemctl disable ssh.service ssh.socket 2>/dev/null || true

# Deterministic initramfs: only the modules the QEMU virt machine needs, in a
# kernel-decompressible zstd cpio. The Mac launcher verifies both properties.
cat >/etc/initramfs-tools/conf.d/00-try-tryubuntu-factory <<'EOF'
MODULES=list
COMPRESS=zstd
EOF
cat >/etc/initramfs-tools/modules <<'EOF'
virtio_pci
virtio_blk
virtio_scsi
virtio_net
virtio_console
virtio_gpu
9p
9pnet
9pnet_virtio
ext4
EOF
# -c (create) is deterministic: the deferred dpkg trigger may never have
# generated an initramfs for the just-installed kernel.
update-initramfs -c -k all

# Identity gates for the packaged integration surface.
for required in \
  /usr/local/bin/tryubuntu-native-clipboard-bridge \
  /usr/local/bin/tryubuntu-native-camera-bridge \
  /usr/local/bin/tryubuntu-native-audio-bridge \
  /usr/local/bin/tryubuntu-native-mac-share \
  /usr/local/bin/tryubuntu-provision-owner \
  /usr/lib/systemd/system-generators/tryubuntu-ssh-access \
  /usr/share/initramfs-tools/scripts/local-bottom/tryubuntu-boot-export \
  /usr/share/tryubuntu/provenance.json; do
  [[ -e $required ]] || { echo "Missing required guest path: $required" >&2; exit 1; }
done
[[ -x /usr/share/initramfs-tools/scripts/local-bottom/tryubuntu-boot-export ]] \
  || { echo "Boot export hook is not executable" >&2; exit 1; }
if [[ -f /var/lib/tryubuntu/provisioning/done ]]; then
  echo "Provisioning marker must not ship in the factory image" >&2
  exit 1
fi
[[ -f /usr/share/tryubuntu/build-spec.json ]] || { echo "Missing embedded build spec" >&2; exit 1; }

echo "Finalized unprovisioned Ubuntu factory guest"
