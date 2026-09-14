# Plan 3 — Factory image packing + standalone boot proof

Status: pending · Depends: plan2 · Est: 0.5 day

## Goal

Produce the factory artifact set (`rootfs.ext4(.zst)`, kernel, initramfs, manifest, sums)
from the plan2 staged rootfs, and prove it boots by running QEMU **by hand** (outside the
launcher) to a working console login on `hvc0`. This de-risks the artifact contract before
any launcher glue is touched.

## Why before launcher work

The launcher's validation (bundle identity, kernel magic, cmdline ownership) is the strictest
gate in the project. Proving the artifacts satisfy it manually — with a direct `qemu-system-aarch64`
invocation — isolates image problems from shell-glue problems.

## Inputs / touched files

- Rewrite: `guest/scripts/pack-image.sh` — same output shape as today
- New: `guest/scripts/write-guest-manifest.py` adaptation (roles change slightly)
- Keep: `guest/scripts/source-digest.py` dies with Ubuntu (no upstream tree) — replace with
  nothing; provenance fields for Ubuntu come from plan8
- Manual test harness: a throwaway `dist/`-adjacent qemu invocation (not committed)

## Tasks

> **Plan1 amendment (2026-09-06, see contract.md §2):** Ubuntu's arm64 kernel is a PE32+
> EFI-stub image and requires UEFI boot. The kernel is packed **as-is** (no decompression
> step), validated by `MZ`@0 + `PE\0\0`@0x40 instead of `ARM\x64`@0x38, and the standalone
> boot proof must use the pflash firmware from the QEMU build tree
> (`pc-bios/edk2-aarch64-code.fd` + `edk2-arm-vars.fd`). New-kit ABI string:
> `qemu-arm64-uefi-direct-v1`. Legacy raw-Image kits keep the old no-firmware boot.

- [ ] `pack-image.sh`: from staged root, extract
      `/boot/vmlinuz-<ver>` → **keep as PE32+ EFI-stub image** → validate `MZ`@0 and
      `PE\0\0`@0x40 (machine 0xaa64) → emit `vmlinuz-linux` (name unchanged).
      Extract `/boot/initrd.img-<ver>` → `initramfs-linux.img` (name unchanged, zstd cpio fine).
- [ ] `mke2fs -d` the staged root into 6144 MiB raw ext4, label `ubuntu-factory` or keep
      `tryubuntu-factory`? → **rename label to `tryubuntu-factory`** and fix UUID in spec
      (label is cosmetic; schema UUID comes from spec.json — new spec lands plan8, so use a
      freshly generated UUID now and record it).
      `E2FSPROGS_FAKE_TIME`/`SOURCE_DATE_EPOCH` from spec for reproducibility; `e2fsck -fn`.
- [ ] `zstd -12` → `rootfs.ext4.zst`; emit `guest-manifest.json` (artifact roles/sha256s,
      builder image digest — port of write-guest-manifest.py minus Ubuntu fields) and
      `SHA256SUMS`.
- [ ] Standalone boot proof, run from the repo root (runtime from the v0.3.0 app bundle or a
      local `make runtime`): QEMU with pflash firmware from the QEMU build tree
      (`-drive if=pflash,format=raw,file=edk2-aarch64-code.fd,readonly=on` +
      per-run copy of `edk2-arm-vars.fd`), plus
      `-kernel <vmlinuz> -initrd <initrd> -append "root=/dev/vda rw rootwait console=tty0
      console=hvc0 ..." -drive file=rootfs.ext4,format=raw,if=none,id=root -device
      virtio-blk-pci,drive=root -nographic` (plus rng/balloon as convenient).
      Verified pattern on 2026-09-06 (contract.md §2): this boots Linux 7.0 fully.
- [ ] Confirm: systemd reaches multi-user, login prompt on hvc0, `dmesg` shows virtio disk,
      ext4 mounted with x-systemd.growfs noted (grow verified later against expanded disk),
      `journalctl` healthy, `apt` works over slirp NAT (`-nic user,model=virtio-net-pci`).
- [ ] Optional: growfs proof — attach a 24 GiB sparse copy, boot, verify `/` grew online.

## Acceptance criteria

- Artifact set exists with manifest + sums; `sha256sum -c SHA256SUMS` passes.
- Manual QEMU boot reaches a usable root console in under ~60 s; network (NAT) works.
- Kernel/initramfs pass the same magic checks the launcher will apply (plan3 validates by
  replicating those checks in a small script; full integration is plan6).

## Risks & notes

- Ubuntu initramfs is zstd-compressed cpio; the current launcher check requires raw newc
  magic. Do NOT force `COMPRESS=cat` (hundreds of MB); instead plan6 changes the check to
  "decompress then verify newc". Note this as a known intentional deviation in contract.md.
- The kernel is a PE32+ image — QEMU's `-kernel` alone hangs silently (verified); the
  pflash firmware is mandatory for new kits. If the console is silent in any boot test,
  check the pflash args first.
- If the arm64 kernel refuses `console=hvc0` early (virtio_console not in initramfs), the
  plan2 MODULES list fixes it; re-check here first when console is silent.
- Keep `initramfs-linux.img`/`vmlinuz-linux` names: the storage boot-kit code and
  `build-app.sh` reference them; renaming is avoided everywhere it is not required.
