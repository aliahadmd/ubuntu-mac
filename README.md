# Ubuntu Mac

Run a full **Ubuntu 26.04.1 LTS** desktop (GNOME, arm64) as a native,
hardware-accelerated app on an Apple Silicon Mac — no dual boot, no separate
VM tooling. One app bundles a project-built Ubuntu factory image, a patched
QEMU 11.1.1 runtime on Apple's Hypervisor.framework, and a small
Swift/AppKit launcher.

```text
Ubuntu Mac.app
└── Swift/AppKit launcher
    └── QEMU + Apple Hypervisor Framework (HVF, GICv3)
        └── Ubuntu 26.04.1 LTS — GNOME on Wayland
            └── VirGL → ANGLE → Metal acceleration
```

## Highlights

- Hardware-accelerated ARM64 virtualization with real GPU graphics
  (guest VirGL → ANGLE → Metal) in a resizable native window, with automatic
  guest resolution and HiDPI scaling
- **Adaptive memory**: the VM takes half of your Mac's RAM, clamped to 4–8 GB
- **35 GB sparse disk** that grows only as Ubuntu writes data
- Two-way **clipboard** sharing (text and images) with the Mac
- The Mac's **camera** appears in Ubuntu as an on-demand `/dev/video42`
  webcam — the camera light is on only while Ubuntu is actually using it
- Mac **audio** input/output selection inside Ubuntu, with live routing
- One optional **shared Mac folder**, mounted in Ubuntu under the same name
- Loopback-only **port forwarding**, plus opt-in **SSH** access (port 2222)
- Live, visible boot console; one-time in-VM account setup

## Quick start

1. Download the latest `.dmg` from
   [Releases](https://github.com/aliahadmd/ubuntu-mac/releases) and drag
   **Ubuntu Mac** to **Applications**.
2. Launch it. The build is ad-hoc signed, so macOS may warn on first launch —
   right-click the app and choose **Open**, or run:
   `xattr -cr "/Applications/Ubuntu Mac.app"`
3. Click **Launch Ubuntu**. On first boot, a console screen asks you to create
   your Linux account (one time), then the GNOME desktop starts.

Every launch begins at the start menu. While that menu is open the app
behaves like a normal Mac application; once the VM starts, Ubuntu takes over
the window. **Immersive** mode (default) hides the Mac menu bar and Dock;
turn it off for a windowed desktop. Rebooting inside Ubuntu reboots the VM in
place; shutting down Ubuntu closes the app.

## Sharing with Ubuntu

- **Shared folder** — pick a Mac folder on the start menu (**Choose…**) and it
  is linked into the Ubuntu home under the same name (`~/Work` on the Mac
  appears as `~/Work` in Ubuntu) with full read/write access. This is the
  recommended place for anything bulky, since it never consumes VM disk.
- **Clipboard** — copy and paste text and images in both directions as soon
  as you sign in; nothing transfers until something is copied.
- **Camera** — choose **Allow…** for camera access; Ubuntu sees a standard
  webcam named **Mac Camera** at `/dev/video42`, captured on demand only.
- **Audio** — pick any Mac output/input device from inside Ubuntu; switching
  applies live, and unused devices are released back to macOS.

## Ports and SSH

Use **Configure…** next to **Port forwarding** to map a Mac localhost port to
a port in Ubuntu (TCP or UDP). Mappings bind only to `127.0.0.1`, so other
devices on your network cannot reach them; the service inside Ubuntu must
listen on `0.0.0.0` or its network interface. To reach a Mac service from
Ubuntu, connect to `10.0.2.2:<port>` — no mapping needed.

**Add SSH** inserts the preset mapping (Mac `2222` → Ubuntu `22`). Ubuntu Mac
then starts `sshd` for boots that carry a TCP mapping to guest port 22:

```sh
ssh -p 2222 <guest-user>@127.0.0.1
```

After a Factory Reset the guest host key changes; remove the stale entry with
`ssh-keygen -R '[127.0.0.1]:2222'`. Loopback binding keeps the listener off
your network, but other local users on the Mac can still attempt login.

## Requirements

- Apple Silicon Mac (M1 or newer), macOS 15 or newer
- 16 GB RAM recommended (8 GB Macs get a 4 GB VM)
- ~8 GB of free disk to start; the disk is sparse and grows with use

## Your data

The persistent VM lives in `~/Library/Application Support/Ubuntu Mac/VM/v1`.
Installing a new version never touches it: an existing VM keeps its disk and
its exact boot files, so updates are safe and instant. VMs provisioned before
the rename are migrated from the older `Try Omarchy` folder automatically at
first launch. Ubuntu packages update normally with `apt` inside the VM; a
**Factory Reset** (typing the app name to confirm) discards the VM and
creates a fresh one from the bundled factory.

**VM Location** — **Change…** on the start menu moves *new* VMs to any empty
folder, including on an external APFS drive. Changing the location never
moves an existing VM.

## Building from source

Requirements: Xcode command-line tools (Swift 6), Python 3, `pkg-config`,
and a running Docker engine with privileged `linux/arm64` support, plus
~20 GB free for build outputs. Downloads are checksum-pinned with verified
mirror fallbacks (see `plan/contract.md`).

```sh
brew install pkg-config
make build run     # assemble guest + QEMU runtime + app, then launch
make test          # full contract and native test suite
make clean         # remove build outputs and caches
```

Component builds are content-hashed: unchanged inputs are skipped, outputs
are re-validated on every run, and `FORCE=1` rebuilds everything. Releases
are packaged with `make release` (requires a Developer ID certificate and a
notarytool profile for signing and notarization).

## Repository layout

```text
.
├── Makefile                 public build interface
├── macos/                   Swift launcher and QEMU/HVF runtime builder
├── guest/                   reproducible Ubuntu arm64 factory-image builder
├── plan/                    design record: conversion plan and verified contract
├── docs/                    architecture and release documentation
├── dist/                    generated output (ignored)
├── CONTRIBUTING.md          contribution guide
├── SECURITY.md              private vulnerability reporting
├── THIRD_PARTY_NOTICES.md   third-party license notices
└── LICENSE                  MIT
```

Architecture and trust boundaries: [`docs/architecture.md`](docs/architecture.md).
Verified build contract and network fallbacks: [`plan/contract.md`](plan/contract.md).

## License and credits

Original code is licensed under the [MIT License](LICENSE). Ubuntu and all
bundled dependencies keep their own licenses — see
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Not affiliated with
Canonical or the Ubuntu project.

by **[@aliahadmd1](https://x.com/aliahadmd1/)**
