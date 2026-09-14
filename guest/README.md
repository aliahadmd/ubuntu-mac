# Guest — Ubuntu Mac factory builder

Builds the reproducible ARM64 Ubuntu 26.04.1 LTS factory image inside a
privileged `linux/arm64` Docker container:

1. `Containerfile` — the `ubuntu:26.04` builder image with debootstrap,
   e2fsprogs, zstd, and python3.
2. `build.sh` — debootstraps the pinned suite (see `spec.json` →
   `distribution`) into the persistent work volume, configures the
   primary+fallback apt mirror pair, installs `packages.ubuntu.txt`
   (kernel/headers without bootloader recommends, the integration
   dependencies, and the GNOME desktop), applies `native-overlay/`, runs the
   in-chroot finalizer, records the dpkg manifest, and packs the artifacts.
3. `scripts/pack-image.sh` — validates the PE32+ EFI-stub kernel and the
   newc initramfs, packs the raw ext4 factory disk with a pinned UUID, and
   emits `guest-manifest.json` + `SHA256SUMS`.

Trust model: every builder input is hashed into `provenance.json`; the dpkg
manifest records the resolved package closure; the Mac launcher re-validates
the artifact set at launch. The verified mirror map and boot ABI live in
`../plan/contract.md`.

Run through the repo root: `make guest` (or `make build`).
