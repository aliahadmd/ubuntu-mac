#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: configure-rootfs.sh --root ROOT [--guest-dir GUEST_DIR] [--spec SPEC]"
}

fail() {
  echo "configure-rootfs: $*" >&2
  exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
guest_dir=$(cd "$script_dir/.." && pwd)
root=""
spec=""

while (($#)); do
  case "$1" in
    --root)
      root=${2:-}
      shift 2
      ;;
    --guest-dir)
      guest_dir=${2:-}
      shift 2
      ;;
    --spec)
      spec=${2:-}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -n $root ]] || fail "--root is required"
[[ $root == /* ]] || fail "--root must be an absolute path"
case "$root" in
  /|/bin|/boot|/etc|/home|/opt|/root|/usr|/var)
    fail "refusing unsafe root: $root"
    ;;
esac
[[ -x $root/usr/bin/apt ]] || fail "staged Ubuntu root not found at: $root"
[[ -n $spec ]] || spec="$guest_dir/spec.json"
[[ -f $spec ]] || fail "guest spec not found: $spec"

architecture=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["architecture"])' "$spec")
profile=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["guest"].get("profile"))' "$spec")
[[ $architecture == aarch64 ]] || fail "native guest architecture must be aarch64"
[[ $profile == factory ]] || fail "native guest profile must be factory"

# Guest integration overlay: tryubuntu-named bridges, units, generators, and
# the first-boot provisioner. The virtio port names are frozen host
# contracts; see plan/residue-allowed.txt and plan/contract.md section 3.
if [[ -d $guest_dir/native-overlay ]]; then
  cp -a "$guest_dir/native-overlay/." "$root/"
  find "$root/usr/local/bin" "$root/usr/bin" "$root/usr/lib/systemd/system-generators" \
    "$root/usr/share/initramfs-tools" -type f -name 'tryubuntu-*' -exec chmod 0755 {} + 2>/dev/null || true
fi

mkdir -p "$root/etc/systemd/system/multi-user.target.wants" \
  "$root/usr/lib/systemd/user/default.target.wants" \
  "$root/usr/lib/systemd/user/graphical-session.target.wants"
ln -sfn /usr/lib/systemd/system/tryubuntu-provision-owner.service \
  "$root/etc/systemd/system/multi-user.target.wants/tryubuntu-provision-owner.service"
ln -sfn /usr/lib/systemd/system/tryubuntu-native-mac-share.service \
  "$root/etc/systemd/system/multi-user.target.wants/tryubuntu-native-mac-share.service"
mkdir -p "$root/var/lib/tryubuntu/provisioning"

# The shared Mac folder mounts system-wide at the spec's mount point; at login
# each account links ~/<Mac folder name> to it. QEMU maps the Mac user's files
# to the first provisioned user (uid 1000).
shared_folder_mount_point=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runtime"]["sharedFolder"]["guestMountPoint"])' "$spec")
[[ $shared_folder_mount_point == /mnt/mac ]] || fail "shared folder mount point must match the link unit"
ln -sfn /usr/lib/systemd/user/tryubuntu-native-mac-share-link.service \
  "$root/usr/lib/systemd/user/default.target.wants/tryubuntu-native-mac-share-link.service"
ln -sfn /usr/lib/systemd/user/tryubuntu-native-audio-bridge.service \
  "$root/usr/lib/systemd/user/default.target.wants/tryubuntu-native-audio-bridge.service"
ln -sfn /usr/lib/systemd/user/tryubuntu-native-camera-bridge.service \
  "$root/usr/lib/systemd/user/default.target.wants/tryubuntu-native-camera-bridge.service"
# The clipboard agent needs the Wayland socket, so it follows the graphical
# session rather than the plain user manager.
ln -sfn /usr/lib/systemd/user/tryubuntu-native-clipboard-bridge.service \
  "$root/usr/lib/systemd/user/graphical-session.target.wants/tryubuntu-native-clipboard-bridge.service"

hostname=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["guest"]["hostname"])' "$spec")
printf '%s\n' "$hostname" >"$root/etc/hostname"
cat >"$root/etc/hosts" <<EOF
127.0.0.1 localhost
::1 localhost
127.0.1.1 $hostname
EOF
printf 'en_US.UTF-8 UTF-8\n' >"$root/etc/locale.gen"
printf 'LANG=en_US.UTF-8\n' >"$root/etc/locale.conf"
printf 'KEYMAP=us\n' >"$root/etc/vconsole.conf"
# An unprovisioned machine receives a new identity from systemd on first boot.
: >"$root/etc/machine-id"
rm -f "$root/var/lib/dbus/machine-id"
ln -sfn /etc/machine-id "$root/var/lib/dbus/machine-id"
ln -sfn /usr/share/zoneinfo/UTC "$root/etc/localtime"

# The writable VM disk is an APFS clone expanded to spec storage capacity by
# the Mac app; x-systemd.growfs grows the filesystem online at boot.
filesystem_uuid=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["filesystemUuid"])' "$spec")
printf 'UUID=%s  /  ext4  rw,relatime,x-systemd.growfs  0  1\n' "$filesystem_uuid" >"$root/etc/fstab"

# The builder binds its persistent download cache into the staged root; that
# configuration is build-time only and must not ship in the guest. The mount
# itself is detached and its mount points removed by build.sh after every
# chroot step has finished.
rm -f "$root/etc/apt/apt.conf.d/99tryubuntu-builder"

# No persistent logs, random seed, journal state, or package indexes should
# ship in the factory image.
rm -rf "$root/var/log/journal" "$root/var/lib/systemd/random-seed"
rm -rf "$root/var/lib/apt/lists"/*
mkdir -p "$root/var/log" "$root/var/lib/systemd" "$root/var/cache/apt/archives/partial"
rm -f "$root/var/cache/apt/archives"/*.deb 2>/dev/null || true
rm -rf "$root/tmp"/* 2>/dev/null || true
chmod 1777 "$root/tmp"

mkdir -p "$root/usr/local/lib/tryubuntu" "$root/usr/share/tryubuntu"
install -m 0755 "$guest_dir/scripts/finalize-rootfs.sh" "$root/usr/local/lib/tryubuntu/finalize-rootfs"
install -m 0644 "$spec" "$root/usr/share/tryubuntu/build-spec.json"

python3 "$guest_dir/scripts/write-provenance.py" \
  --guest-dir "$guest_dir" \
  --spec "$spec" \
  --output "$root/usr/share/tryubuntu/provenance.json"

echo "Configured Ubuntu $profile profile in $root"
