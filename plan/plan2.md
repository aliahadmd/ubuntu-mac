# Plan 2 — Ubuntu 26.04.1 arm64 builder core (debootstrap)

Status: pending · Depends: plan1 · Est: 0.5–1 day (plus Docker build time)

## Goal

Replace the Arch-Linux-ARM bootstrap with an Ubuntu 26.04.1 arm64 rootfs assembled by
debootstrap inside the existing privileged arm64 Docker flow, producing a staged root
filesystem that plan3 can pack and plan4 can customize. Deliverable: `docker build` +
`build.sh` completes and the staged root boots `apt` inside a chroot.

## Why this design

The existing pipeline's shape (two-stage Containerfile → privileged arm64 container →
staged rootfs → `mke2fs -d` pack) is sound and stays. Only the bootstrap changes:
alpine+pacstrap → `ubuntu:26.04` + `debootstrap`. Debootstrap (not cloud images) keeps the
"no partition table, direct ext4" contract the launcher already validates, and gives us
snap-free control of the base (cloud images drag in GRUB, partitions, cloud-init).

## Inputs / touched files

- Rewrite: `guest/Containerfile` (stage 1 becomes `FROM ubuntu:26.04` + debootstrap;
  stage 2 stays `FROM scratch COPY /rootfs/ /`)
- Rewrite: `guest/build.sh` (apt-based; drop pacman config assembly, lock resolution, pins)
- Delete-with-replacement deferred to plan10: `guest/vendor/tryubuntu-pkgs/pacstrap-docker`,
  `guest/pacman.aarch64.conf`, `guest/mirrorlist.aarch64`, `guest/packages.txt`,
  `guest/packages.lock.json`
- New: `guest/packages.ubuntu.txt` (curated package list, reviewed like packages.txt was)
- New: `guest/mirrors.ubuntu` or inline TUNA ubuntu-ports mirror constant

## Tasks

- [ ] Stage 1 Containerfile: `FROM ubuntu:26.04` (arm64), `apt-get install debootstrap
      ubuntu-keyring zstd e2fsprogs`, then
      `debootstrap --arch=arm64 --variant=minbase resolute /rootfs https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports`
      (mirror per plan1 confirmation; primary `ports.ubuntu.com` first, TUNA fallback).
- [ ] Stage 2: install build tooling (git, python3, e2fsprogs, zstd, arch-test) — the exact
      Rust pin dies with ttfx; nothing Rust-based is needed for Ubuntu.
- [ ] New `guest/build.sh`: chroot into staged root, set
      `/etc/apt/sources.list.d/ubuntu.sources` (TUNA ubuntu-ports, suite `resolute`
      + `-updates` + `-security`), `apt-get update`, install from
      `guest/packages.ubuntu.txt`:
      - base: `systemd systemd-resolved? (default) locales sudo dbus network-manager`
      - kernel: `linux-image-generic linux-headers-generic` (headers for v4l2loopback dkms)
      - initramfs: `initramfs-tools` with `/etc/initramfs-tools/initramfs.conf`:
        `MODULES=list` + `/etc/initramfs-tools/modules` entries
        `virtio_pci virtio_blk virtio_net virtio_console 9p 9pnet 9pnet_virtio`
        and `COMPRESS=zstd` (kernel supports RD_ZSTD; plan6 adjusts the launcher check)
      - bridges: `python3 wl-clipboard pipewire pipewire-pulse wireplumber
        v4l2loopback-kmod-dkms` (name per plan1) `p2p? no — drop`
      - desktop (may defer to plan7 to keep plan3 boot light — decision recorded in plan7):
        defer. This plan ships a console-only root.
- [ ] Minimal system config in build.sh (mirror of configure-rootfs.sh essentials, desktop
      bits deferred): hostname `ubuntu-factory`, empty `/etc/machine-id`, `en_US.UTF-8`
      locale-gen, root password locked, `/etc/fstab` line
      `UUID=<spec uuid> / ext4 rw,relatime,x-systemd.growfs 0 1` (online grow to 24 GiB —
      replaces Arch's systemd-growfs-root unit trick), scrub journals/random-seed/package cache.
- [ ] Build-cache compatibility: keep component inputs under `guest/` only (the cache hashes
      everything except `.work`/tests/docs — automatic once files are renamed).
- [ ] Transport fallback: the ubuntu:26.04 base image pull goes through the Docker mirror
      config already installed on this machine (`~/.docker/daemon.json`); debootstrap fetches
      debs from TUNA. Record both in contract.md; no code beyond mirror constants here.

## Acceptance criteria

- `docker build -f guest/Containerfile` succeeds on this machine (arm64, via daocloud mirror).
- Running the builder entrypoint completes: staged rootfs exists, `chroot /rootfs apt-get -s install curl`
  (simulate) resolves against TUNA, `linux-image-generic` present at the version pinned in spec
  (spec update happens in plan8; for now record version in build log).
- Re-running the build reuses the Docker work volume (package cache) — second run is faster.

## Risks & notes

- `debootstrap --variant=minbase` + curated list = no snapd, no cloud-init. If snapd is later
  wanted (Firefox), plan7 adds `ubuntu-desktop-minimal` consciously.
- Universe packages (`v4l2loopback-*`) require the `universe` component in ubuntu.sources —
  include it.
- Docker build time for the first run is dominated by deb downloads; TUNA was measured
  ~460 KB/s+ for Arch — expect similar for ubuntu-ports; the work volume caches debs.
