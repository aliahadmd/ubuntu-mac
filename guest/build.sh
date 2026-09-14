#!/bin/bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: guest/build.sh [options]

  --output DIR       Artifact directory (default: dist/guest)
  --work DIR         Persistent build/cache directory (default: guest/.work)
  --spec FILE        Architecture build spec (default: guest/spec.json)
  --keep-rootfs      Keep the staged package root after a successful build

Run as root on arm64 Linux, or use the matching container wrapper.
USAGE
}

fail() {
  echo "guest-build: $*" >&2
  exit 1
}

guest_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$guest_dir/.." && pwd)
output="$repo_dir/dist/guest"
work="$guest_dir/.work"
spec="$guest_dir/spec.json"
keep_rootfs=0

while (($#)); do
  case "$1" in
    --output)
      output=${2:-}
      shift 2
      ;;
    --work)
      work=${2:-}
      shift 2
      ;;
    --spec)
      spec=${2:-}
      shift 2
      ;;
    --keep-rootfs)
      keep_rootfs=1
      shift
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

[[ $(uname -s) == "Linux" ]] || fail "full image builds require Linux"
[[ -f $spec ]] || fail "spec not found: $spec"
spec=$(cd "$(dirname "$spec")" && pwd)/$(basename "$spec")
architecture=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["architecture"])' "$spec")
packages_file=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["inputs"]["packages"])' "$spec")
packages_file="$guest_dir/$packages_file"
[[ $architecture == "aarch64" ]] || fail "native guest architecture must be aarch64"
[[ $(uname -m) == "$architecture" ]] || fail "guest packages for $architecture must be assembled on $architecture"
[[ -f $packages_file ]] || fail "package list not found: $packages_file"
(( EUID == 0 )) || fail "run as root (debootstrap and chroot require it)"
for command in debootstrap python3 mke2fs e2fsck zstd sha256sum mountpoint; do
  command -v "$command" >/dev/null || fail "$command is required; use the supplied Ubuntu builder container"
done

distribution_suite=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["distribution"]["suite"])' "$spec")
distribution_variant=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["distribution"]["debootstrapVariant"])' "$spec")
primary_mirror=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["distribution"]["primaryMirror"])' "$spec")
fallback_mirror=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["distribution"]["fallbackMirror"])' "$spec")
[[ -n $distribution_suite && -n $primary_mirror && -n $fallback_mirror ]] \
  || fail "spec distribution section must name the suite and both mirrors"

output=$(mkdir -p "$output" && cd "$output" && pwd)
work=$(mkdir -p "$work" && cd "$work" && pwd)

root=$(mktemp -d "$work/rootfs.XXXXXX")
apt_cache="$work/apt-cache"
[[ $apt_cache != *$'\n'* ]] || fail "work path cannot contain a newline"
install -d -m 0755 "$apt_cache/archives" "$apt_cache/lists"

build_ok=0
# A silent mid-build death (OOM-killed helper, killed chroot) must name
# its location; without this the only symptom is a missing success line.
trap 'echo "guest-build: failed at line $LINENO (exit $?): ${BASH_COMMAND:-?}" >&2' ERR
bind_mounts=()
bind_into_root() {
  local host_path=$1 root_path=$2
  mkdir -p "$root_path"
  mount --bind "$host_path" "$root_path"
  bind_mounts+=("$root_path")
}
detach_binds() {
  local reversed=()
  if ((${#bind_mounts[@]})); then
    for ((i=${#bind_mounts[@]} - 1; i >= 0; i--)); do
      reversed+=("${bind_mounts[i]}")
    done
    for target in "${reversed[@]}"; do
      if mountpoint -q "$target"; then
        umount "$target" || umount -l "$target" || true
      fi
    done
  fi
  bind_mounts=()
}
cleanup() {
  detach_binds
  if (( build_ok && !keep_rootfs )); then
    rm -rf "$root"
  else
    echo "Staged rootfs retained at $root"
  fi
}
trap cleanup EXIT

packages=()
firmwareless_packages=()
while IFS= read -r package; do
  [[ -n $package && $package != \#* ]] || continue
  if [[ $package == \!* ]]; then
    firmwareless_packages+=("${package#\!}")
  else
    packages+=("$package")
  fi
done <"$packages_file"

echo "Debootstrapping Ubuntu $distribution_suite ($distribution_variant) from $primary_mirror"
bootstrap_into() {
  debootstrap --arch=arm64 "--variant=$distribution_variant" \
    "$distribution_suite" "$root" "$1"
}
if ! bootstrap_into "$primary_mirror"; then
  echo "Primary mirror failed; retrying from $fallback_mirror" >&2
  rm -rf "$root"
  mkdir -m 0755 "$root"
  bootstrap_into "$fallback_mirror"
fi

# Both mirrors are recorded in the staged root: apt falls back per fetched
# file, so the build (and the guest) survive one mirror being unreachable.
install -d -m 0755 "$root/etc/apt/sources.list.d"
cat >"$root/etc/apt/sources.list.d/ubuntu.sources" <<EOF
Types: deb
URIs: $primary_mirror $fallback_mirror
Suites: $distribution_suite $distribution_suite-updates $distribution_suite-security
Components: main universe restricted multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

# Downloads persist in the work volume across builds; the staged root only
# ever sees them through the bind mounts, which are removed before packing.
# Package maintenance scripts expect the standard pseudo-filesystems, exactly
# as debootstrap's own second stage and arch-chroot provide them.
bind_into_root "$apt_cache/archives" "$root/mnt/tryubuntu-build/archives"
bind_into_root "$apt_cache/lists" "$root/mnt/tryubuntu-build/lists"
bind_into_root /proc "$root/proc"
bind_into_root /sys "$root/sys"
bind_into_root /dev "$root/dev"
cat >"$root/etc/apt/apt.conf.d/99tryubuntu-builder" <<'EOF'
Dir::Cache "/mnt/tryubuntu-build";
Dir::State::lists "/mnt/tryubuntu-build/lists";
EOF

chroot "$root" apt-get update

if ((${#firmwareless_packages[@]})); then
  echo "Installing ${#firmwareless_packages[@]} guest packages without recommends"
  DEBIAN_FRONTEND=noninteractive chroot "$root" \
    apt-get install -y --no-install-recommends "${firmwareless_packages[@]}" || {
    echo "guest-build: kernel package install failed with exit $?" >&2
    exit 1
  }
fi
echo "Installing ${#packages[@]} requested guest packages"
DEBIAN_FRONTEND=noninteractive chroot "$root" apt-get install -y "${packages[@]}" || {
  echo "guest-build: package install failed with exit $?" >&2
  exit 1
}

echo "Configuring the staged root"
bash -x "$guest_dir/scripts/configure-rootfs.sh" --root "$root" --spec "$spec"
echo "Finalizing the staged root"
chroot "$root" /usr/local/lib/tryubuntu/finalize-rootfs

# Record the complete resolved package closure as the build's provenance
# manifest. The file keeps the historical artifact name consumed by the
# packaging pipeline.
chroot "$root" dpkg-query -W -f='${binary:Package}\t${Version}\n' \
  | LC_ALL=C sort >"$root/usr/share/tryubuntu/dpkg-manifest.txt"

detach_binds
# Now that every bind is gone, the builder's cache mount points must not ship
# in the factory image.
rm -rf "$root/mnt/tryubuntu-build"

# The chroot bind-mounts the container resolver at this path. Replace it only
# after every chroot invocation has returned.
ln -sfn ../run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"

kernel_path=""
initrd_path=""
for candidate in "$root"/boot/vmlinuz-*-generic; do
  kernel_path=$candidate
done
for candidate in "$root"/boot/initrd.img-*-generic; do
  initrd_path=$candidate
done
[[ -n $kernel_path && -f $kernel_path ]] || fail "kernel not found in staged root"
[[ -n $initrd_path && -f $initrd_path ]] || fail "initramfs not found in staged root"
kernel_release=${kernel_path##*/vmlinuz-}
initrd_release=${initrd_path##*/initrd.img-}
[[ $kernel_release == "$initrd_release" ]] || fail "kernel and initramfs releases disagree: $kernel_release != $initrd_release"
echo "Guest kernel: $kernel_release"

"$guest_dir/scripts/pack-image.sh" \
  --root "$root" \
  --output "$output" \
  --spec "$spec" \
  --kernel "$kernel_path" \
  --initrd "$initrd_path"
build_ok=1
echo "Guest build complete: $output/guest-manifest.json"
