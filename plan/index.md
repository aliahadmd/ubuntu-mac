# Try Ubuntu — Conversion Plan Index

Replace the Ubuntu (Arch Linux ARM) guest in this project with **Ubuntu 26.04.1 LTS, arm64**
(GNOME desktop), while keeping the entire macOS platform layer: the patched QEMU 11.1.1
runtime (HVF + GICv3 + VirGL/ANGLE), the Swift launcher, storage/boot-kit model, the three
native bridges (clipboard, camera, audio), 9p shared folder, SSH access, and the
sign/notarize release pipeline.

End state: the app is renamed **Try Ubuntu**, builds and ships a reproducible Ubuntu
26.04.1 arm64 factory image, boots it through the same start-menu flow, and no Ubuntu or
Arch-specific code remains. This file is the map; `plan1.md`…`plan12.md` are the work.

## Why this conversion

- The current guest build is **broken for everyone**: the pinned `hyprland 0.56.1-3` needs
  `libaquamarine.so=13-64`, but the rolling Arch Linux ARM repos purged `aquamarine 0.14.0`
  days after the pin (verified against all 12 regional mirrors, 2026-09-05). A rolling-repo
  lock is structurally fragile.
- Ubuntu ships a **versioned, mirrored, checksum-pinnable** archive (and point releases),
  which fits this project's reproducibility ethos better than Arch ARM's rolling repos.
- The Ubuntu-specific value (themes, tooling, backports) is not wanted; the platform layer
  (the hard 80% of this project) is distro-neutral and carries over.

## What stays / what changes

| Area | Status |
| --- | --- |
| QEMU runtime + all 10 patches (`macos/patches/`, runtime builder) | **Keep unchanged** (except product-identity patch strings in plan11) |
| Swift launcher: start menu, storage/boot kits, port forwarding, sleep/wake, immersive | **Keep unchanged** (strings only in plan11) |
| Bridges: clipboard / camera / audio (Swift host side + Python guest side) | **Keep** — guest Python scripts port verbatim, deps move to apt |
| 9p shared folder (`guest_owner_uid` patch, mount/link units) | **Keep**, guest units re-skinned |
| SSH access generator + `Add SSH` preset | **Keep**, token renamed |
| Storage/boot-kit model, recovery boot, ephemeral, reset, VM relocation | **Keep unchanged** (initcpio hook → initramfs-tools port, plan5) |
| `guest/` builder (Containerfile, build.sh, overlays, Arch lock) | **Replace** with Ubuntu debootstrap builder (plan2–plan4) |
| `guest/spec.json` + provenance model | **Replace** content, keep schema shape (plan8) |
| `guest/tests/verify.py` (~200 Arch checks) | **Rewrite** as Ubuntu contract checks (plan8) |
| Ubuntu backports (1Password, Vivaldi, notification patches), Hyprland rebuild | **Drop** (plan10) |
| Product identity: "Try Ubuntu" → **"Try Ubuntu"** (bundle id, icon, strings, kernel tokens) | plan11 |
| `make update-omarchy` | Replaced by `make update-ubuntu` pin refresh (plan9) |

## Phase graph

```
plan1 (strategy/decisions)
  └─ plan2 (Ubuntu builder core: debootstrap rootfs)
       └─ plan3 (factory image pack + standalone QEMU boot proof)
            ├─ plan4 (guest integration port: bridges, units, provisioning, tokens)
            └─ plan5 (initramfs-tools boot-export hook + recovery path)
                 └─ plan6 (launcher glue + runtime transport fallback → `make run` boots Ubuntu)
                      └─ plan7 (GNOME desktop E2E: graphics, display, bridges)
                           └─ plan8 (spec/provenance/verify.py rewrite)
                                └─ plan9 (make test green + docs)
                                     └─ plan10 (Ubuntu decommission + residue audit)
                                          └─ plan11 (rename → Try Ubuntu)
                                               └─ plan12 (release pipeline + clean-room validation)
```

plan8 can start in parallel after plan4 (it documents what plan2–4 produce).

## Status

| Plan | Scope | Status |
| --- | --- | --- |
| [plan1](plan1.md) | Strategy, contract definition, global decisions | **done** (branch `ubuntu-guest`, [contract.md](contract.md), facts verified 2026-09-06) |
| [plan2](plan2.md) | Ubuntu 26.04.1 arm64 builder core (debootstrap) | **done** |
| [plan3](plan3.md) | Factory image packing + standalone boot proof | **done** (boots to `ubuntu-factory login`) |
| [plan4](plan4.md) | Guest integration port (bridges, units, provisioning, kernel tokens) | **done** (GNOME E2E pending in plan7) |
| [plan5](plan5.md) | initramfs-tools boot-export hook + recovery-boot validation | **done** (hook ported; host-side recovery E2E in plan12) |
| [plan6](plan6.md) | Launcher glue (`run-qemu-gpu.sh`) + runtime transport fallback → `make run` | pending |
| [plan7](plan7.md) | GNOME desktop E2E (VirGL/mutter, HiDPI, all bridges) | **automated gates done** (GDM starts headless; interactive E2E pending user) |
| [plan8](plan8.md) | Supply chain & provenance (spec.json, pinning, verify.py, notices) | **done** (core pins enforced in-chroot + launcher; notices rewritten) |
| [plan9](plan9.md) | Test suite & documentation green | pending |
| [plan10](plan10.md) | Ubuntu decommission & residue audit | pending |
| [plan11](plan11.md) | Rename & branding → Try Ubuntu | **done** (identity renamed; frozen contracts kept) |
| [plan12](plan12.md) | Release pipeline & final validation | **automated gates done** (clean-room build + test green); DMG signing awaits Developer ID credentials |

## Global decisions (set in plan1, binding everywhere)

1. **Full replacement, no dual-profile.** Ubuntu code is deleted (plan10), not gated behind
   a guest-profile flag. Git history on `main` preserves it.
2. **Branch model.** All work lands on branch `ubuntu-guest` (created in plan1, which also
   commits the pending network-transport edits first). `main` stays reference until plan12.
3. **Kernel-token rename happens early, not late.** The guest consumers are being rewritten
   anyway, so tokens move to `tryubuntu.*` in plan4/plan6 in one coordinated change
   (`omarchy.qemu_virgl=1` → `tryubuntu.qemu_virgl=1`, `omarchy.shared_folder_name` →
   `tryubuntu.shared_folder_name`, `tryomarchy.ssh_access=1`, `tryomarchy.export_boot=1`).
   plan11 renames only user-visible branding.
4. **Desktop = GNOME** (`ubuntu-desktop-minimal`, GDM, Wayland) — the canonical Ubuntu
   experience. Hyprland is out of scope.
5. **No proprietary post-build installers in v1.** 1Password/Vivaldi installer machinery is
   dropped with the Ubuntu tree. Firefox arrives via `ubuntu-desktop-minimal` (snap).
6. **Transport fallback policy.** Every network fetch gets: primary upstream URL first,
   then a verified mirror fallback (jsDelivr for GitHub raw, ghfast.top for GitHub release
   assets, TUNA/daocloud for archives), always gated by the existing sha256 verification.
   China-network realities are a first-class build requirement, not a local hack.
7. **Existing Ubuntu VMs are not migrated.** Disks created by v0.3.0 keep booting their own
   boot kit until the user resets; documented in release notes (plan12).
8. **Dual boot ABI (plan1 discovery, contract.md §2).** Ubuntu's arm64 kernel is a PE32+
   EFI-stub image: new kits boot via UEFI firmware (pflash `edk2-aarch64-code.fd` + per-run
   `edk2-arm-vars.fd` copy, both bundled in the runtime, fw_cfg kernel loader — verified
   2026-09-06); legacy raw-Image kits keep booting with plain `-kernel`, no firmware. The
   launcher branches on the kit's ABI metadata; new-kit ABI string is
   `qemu-arm64-uefi-direct-v1`. Kernel/initramfs validators branch accordingly.

## How to work through a plan

Each plan is self-contained: goal, inputs (real file paths), task checklist, acceptance
criteria, risks. Work one plan at a time; keep `make test` (where applicable) green before
checking boxes; update the Status table above as phases complete.
