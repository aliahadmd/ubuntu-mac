# Plan 5 — initramfs-tools boot-export hook + recovery-boot validation

Status: pending · Depends: plan4 · Est: 1 day

## Goal

Port the `try-omarchy-boot-export` mkinitcpio hook to an initramfs-tools script so the
one-time preserving migration for legacy VMs (boot-kit recovery) still works, and validate
the full recovery path end-to-end against the shell layer.

## Why it matters

The boot-kit ABI (`qemu-arm64-direct-v1`) and the two-pass consent handshake are the
project's most carefully guarded storage contract. A VM created before boot kits existed is
recovered by booting its disk **read-only** with `tryubuntu.export_boot=1` (renamed token),
exporting `/boot` over a private 9p share, and powering off before pivoting to userspace.
If the hook can't run under Ubuntu's initramfs-tools, that migration path is dead.

## Design

mkinitcpio `run_latehook` (after root mount) ≈ initramfs-tools `local-bottom` script
(runs after the root device is mounted, before `init` pivots). Because the hook powers off
before the switch, `local-bottom` is sufficient — no need to survive pivot.

## Tasks

- [ ] Write `guest/native-overlay.ubuntu/usr/share/initramfs-tools/scripts/local-bottom/tryubuntu-boot-export`
      (POSIX sh): parse `/proc/cmdline` for the exact token `tryubuntu.export_boot=1`;
      require `/root` mounted read-only; validate `/root/boot/vmlinuz-linux` (renamed from
      Image? — decision: keep kernel/initramfs names identical to the factory's,
      i.e. whatever plan3 extracted, so the host validator's expectations match),
      `/root/boot/initramfs-*`, and `/root/usr/share/tryubuntu/build-spec.json`
      (size-bounded); mount the launcher's 9p share
      `mount_tag=try-omarchy-boot-export` (host-side tag name — keep exact, it's a host
      contract string) at `/run/tryubuntu-boot-export` (`nosuid,nodev,noexec`);
      copy kernel+initramfs+build-spec via `.tmp` + `sync` + `mv` + `sync`;
      write the completion marker (byte-exact `try-omarchy-boot-export-v1`, 27 bytes — keep
      verbatim, host validates it); unmount; `poweroff -f`. Any failure: withdraw marker,
      power off, never pivot into the old userspace.
- [ ] Initramfs hook config: ensure 9p modules are present in the recovery initramfs (the
      factory's initramfs already includes them via plan2 MODULES list — the recovery boot
      reuses the **factory** initramfs, so no separate hook-install script is needed; confirm
      by inspecting `unmkinitramfs` output).
- [ ] mkinitcpio parity check: the old factory overlay's `mkinitcpio.conf.d` hook ordering
      dies; document in contract.md that recovery now depends on
      (a) factory initramfs with 9p modules, (b) the local-bottom script present.
- [ ] Update the guest contract tests: port `guest/tests/test_boot_export.py` to the new
      script location/token names, keeping the same runtime-hook behavior assertions
      (isolated test with fake /proc/cmdline, fake mount, fake share).

## Validation (host side)

> **Plan1 amendment (2026-09-06, contract.md §2):** the recovery boot itself uses the
> current factory initramfs, which under the new ABI is a UEFI boot (pflash + fw_cfg
> kernel). The exported pair from the old Ubuntu disk is a raw arm64 Image → stored as a
> legacy kit (`qemu-arm64-direct-v1`) and booted thereafter without firmware. The host
> validator branches on ABI when checking exported/new kits.

- [ ] Craft a fake legacy VM on disk: take the plan3/4 factory disk, strip its
      `boot/<identity>/` kit from a scratch workspace (not the real one), so the launcher
      detects schema-2-without-kit and requests recovery.
- [ ] Run the **v0.3.0 app** (or current launcher once plan6 lands) against it with the new
      factory bundle? — No: recovery boots the OLD disk with the CURRENT factory initramfs.
      Since the old disk is an Ubuntu rootfs, its `/boot` layout is Arch
      (`/boot/Image`, `/boot/initramfs-linux.img`). The new hook must therefore keep
      supporting the legacy paths (`/boot/Image`) — make the script try
      `<factory-name-set>` then legacy `Image`/`initramfs-linux.img`, driven by
      `build-spec.json` found on the old disk when present, else the fixed legacy names.
      Document this dual-path requirement in contract.md **before** coding.
- [ ] End-to-end: consent dialog → recovery boot → export → host validates pair (type, size,
      hashes, boot ABI) → boot kit staged → normal launch boots Ubuntu VM with its own
      kernel. Confirm Cancel path starts no QEMU.

## Acceptance criteria

- Unit tests for the new hook pass (`guest/test`).
- One real recovery run completes against a staged fake-legacy workspace; the exported pair
  passes the host validator; second launch does not repeat recovery.
- Failure-path check: corrupt marker or missing `/boot` file → no marker → host reports
  recovery failure (exit 81 path) without touching the disk.

## Risks & notes

- The dual legacy/modern `/boot` path handling is the subtle part; get the contract.md
  decision reviewed before implementing.
- `poweroff -f` inside initramfs on Ubuntu: confirm systemd-shutdown interplay — the old
  hook used `poweroff -f` too; if Ubuntu's initramfs lacks it, use `echo o > /proc/sysrq-trigger`.
