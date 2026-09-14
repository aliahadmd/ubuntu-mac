#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: pack-image.sh --root ROOT --output DIR --spec SPEC --kernel FILE --initrd FILE"
}

fail() {
  echo "pack-image: $*" >&2
  exit 1
}

script_dir=$(cd "$(dirname "$0")" && pwd)
guest_dir=$(cd "$script_dir/.." && pwd)
spec="$guest_dir/spec.json"
root=""
output=""
kernel_path=""
initrd_path=""

while (($#)); do
  case "$1" in
    --root)
      root=${2:-}
      shift 2
      ;;
    --output)
      output=${2:-}
      shift 2
      ;;
    --spec)
      spec=${2:-}
      shift 2
      ;;
    --kernel)
      kernel_path=${2:-}
      shift 2
      ;;
    --initrd)
      initrd_path=${2:-}
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

for required in root output kernel_path initrd_path; do
  [[ -n ${!required} ]] || fail "--${required//_/} is required"
done
[[ $root == /* && $output == /* ]] || fail "root and output paths must be absolute"
[[ -f $kernel_path && ! -L $kernel_path ]] || fail "kernel not found: $kernel_path"
[[ -f $initrd_path && ! -L $initrd_path ]] || fail "initramfs not found: $initrd_path"
[[ -f $root/usr/share/tryubuntu/build-spec.json ]] || fail "build spec missing from staged root"
[[ -f $root/usr/share/tryubuntu/provenance.json ]] || fail "provenance missing from staged root"
[[ -f $root/usr/share/tryubuntu/dpkg-manifest.txt ]] || fail "dpkg manifest missing from staged root"
for command in mke2fs e2fsck zstd python3; do
  command -v "$command" >/dev/null || fail "$command is required"
done

# The new guest kernel is a PE32+ EFI-stub image and boots through the bundled
# UEFI firmware (plan/contract.md section 2). Validate the exact format the
# Mac launcher will accept.
kernel_magic=$(head -c 2 "$kernel_path")
[[ $kernel_magic == $'MZ' ]] || fail "kernel is not a PE32+ EFI-stub image (missing MZ)"
pe_offset_bytes=$(od -A n -t u1 -j 60 -N 4 "$kernel_path" | tr -s ' ' | sed 's/^ //')
set -- $pe_offset_bytes
pe_offset=$(( $1 + $2 * 256 + $3 * 65536 + $4 * 16777216 ))
pe_sig=$(dd if="$kernel_path" bs=1 skip="$pe_offset" count=4 2>/dev/null)
[[ $pe_sig == $'PE\x00\x00' ]] || fail "kernel PE header pointer is invalid"
machine_sig=$(dd if="$kernel_path" bs=1 skip=$((pe_offset + 4)) count=2 2>/dev/null | od -A n -t x1 | tr -d ' \n')
[[ $machine_sig == "64aa" ]] || fail "kernel is not an ARM64 PE image (machine $machine_sig)"

# The initramfs may be compressed; decompress and require a newc cpio stream.
initrd_probe=$(mktemp)
if head -c 4 "$initrd_path" | grep -q $'\x28\xb5\x2f\xfd'; then
  zstd -d -q -c "$initrd_path" >"$initrd_probe"
elif head -c 2 "$initrd_path" | grep -q $'\x1f\x8b'; then
  gzip -d -c "$initrd_path" >"$initrd_probe"
else
  cp "$initrd_path" "$initrd_probe"
fi
newc_magic=$(head -c 6 "$initrd_probe")
[[ $newc_magic == "070701" ]] || fail "initramfs does not decompress to a newc cpio archive"
rm -f "$initrd_probe"

size_mib=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["sizeMiB"])' "$spec")
label=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["filesystemLabel"])' "$spec")
uuid=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["filesystemUuid"])' "$spec")
source_date_epoch=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["image"]["sourceDateEpoch"])' "$spec")
used_kib=$(du -sk "$root" | awk '{print $1}')
capacity_kib=$((size_mib * 1024))
(( used_kib < capacity_kib * 85 / 100 )) || fail "staged root uses ${used_kib} KiB; ${size_mib} MiB image has insufficient headroom"

mkdir -p "$output"
raw="$output/rootfs.ext4"
compressed="$output/rootfs.ext4.zst"
truncate -s "${size_mib}M" "$raw"
blocks=$((size_mib * 1024 * 1024 / 4096))

export SOURCE_DATE_EPOCH="$source_date_epoch"
export E2FSPROGS_FAKE_TIME="$source_date_epoch"
mke2fs -q -F -t ext4 -b 4096 -L "$label" -U "$uuid" \
  -E lazy_itable_init=0,lazy_journal_init=0 \
  -d "$root" "$raw" "$blocks"
e2fsck -fn "$raw"

install -m 0644 "$kernel_path" "$output/vmlinuz-linux"
install -m 0644 "$initrd_path" "$output/initramfs-linux.img"
install -m 0644 "$root/usr/share/tryubuntu/build-spec.json" "$output/build-spec.json"
install -m 0644 "$root/usr/share/tryubuntu/provenance.json" "$output/provenance.json"
install -m 0644 "$root/usr/share/tryubuntu/dpkg-manifest.txt" "$output/packages.lock.txt"

zstd --force --quiet -12 --threads=0 "$raw" -o "$compressed"
python3 "$guest_dir/scripts/write-guest-manifest.py" --directory "$output" --spec "$spec"

(
  cd "$output"
  sha256sum \
    build-spec.json \
    guest-manifest.json \
    initramfs-linux.img \
    packages.lock.txt \
    provenance.json \
    rootfs.ext4 \
    rootfs.ext4.zst \
    vmlinuz-linux >SHA256SUMS
)

echo "Packed guest artifacts in $output"
