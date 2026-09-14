# Ubuntu Conversion Contract (plan1 deliverable)

All facts below were verified empirically on 2026-09-06 on this machine (Apple Silicon,
macOS 26.6, Docker with daocloud/1ms mirrors). Sources are named per fact. This is the
single source of truth for plan2–plan12; later plans must not re-derive these decisions.

## 1. Target distribution facts

| Fact | Value | Source |
| --- | --- | --- |
| Suite / codename | `resolute` (26.04 LTS "Resolute Raccoon") | `/etc/os-release` inside `ubuntu:26.04` arm64 image |
| Base container sources | `http://ports.ubuntu.com/ubuntu-ports/`, suites `resolute resolute-updates resolute-security` (+ `-backports`), components main/universe/restricted/multiverse | image `/etc/apt/sources.list.d/ubuntu.sources` |
| Debootstrap suite | `resolute`, debootstrap 1.0.142ubuntu2 | `apt-cache policy debootstrap` |
| Kernel meta | `linux-image-generic 7.0.0-31.31` → `linux-image-7.0.0-31-generic` (7.0.14 upstream) | `apt-cache policy` + deb metadata |
| Kernel image format | **PE32+ EFI-stub image**: `MZ` at 0x00, PE header at 0x40 (machine 0xaa64), **not** gzip, **no** `ARM\x64` magic at 0x38 | deb extraction + hex dump, 2026-09-06 |
| v4l2loopback | `v4l2loopback-dkms 0.15.3-1ubuntu2` (Depends: dkms); `v4l2loopback-kmod-dkms` **absent** | `apt-cache show/policy` |
| Key versions observed | initramfs-tools 0.151ubuntu1, wl-clipboard 2.2.1-2build1, pipewire 1.6.2-1ubuntu1.1, wireplumber 0.5.13-1ubuntu1, gdm3 50.1-0ubuntu0.1, gnome-shell 50.1-0ubuntu1.2, ubuntu-desktop-minimal 1.570.3, network-manager 1.54.3-2ubuntu3, whiptail 0.52.25 | `apt-cache policy`, ubuntu:26.04 arm64 |
| `snapshot.ubuntu.com` | Reachable (HTTP 200) — available for optional point-in-time apt pinning | curl probe 2026-09-06 |

## 2. Boot ABI — the plan1 discovery (amends plan3, plan5, plan6)

Ubuntu's arm64 kernel cannot be direct-booted by QEMU `-kernel` (QEMU's aarch64 loader
accepts gzip/raw `ARM\x64` Images only; the PE kernel hangs silently — verified). Booting
**via UEFI firmware** works and is the new guest ABI:

- Verified working (Try Ubuntu 0.3.0 runtime, QEMU 11.1.1, HVF, `gic-version=3`):
  `-drive if=pflash,format=raw,file=edk2-aarch64-code.fd,readonly=on`
  `-drive if=pflash,format=raw,file=<per-run copy of edk2-arm-vars.fd>`
  `-kernel <PE vmlinuz> -initrd <zstd cpio> -append "<cmdline>"` → Linux 7.0 boots fully
  (EFI v2.7, ACPI tables, PSCI, earlycon).
- Firmware files come from **QEMU 11.1.1 itself** (Homebrew qemu 11.1.1 bottle confirmed
  byte-equivalent layout; our runtime build must bundle the same files from the QEMU build
  tree — `pc-bios/edk2-aarch64-code.fd` + `edk2-arm-vars.fd`). QEMU's own
  `firmware/60-edk2-aarch64.json` descriptor pairs exactly these two (vars template is
  arch-neutral). The 64 MiB pre-padded sizes match `-M virt` pflash directly.
- The per-run vars copy is **ephemeral** (pristine template each launch): no persisted EFI
  state exists; boot is always the fw_cfg kernel loader, so determinism is preserved.
- `console=ttyAMA0` works on the PL011; the guest base cmdline keeps
  `console=tty0 console=hvc0` (virtio-gpu fb + virtconsole); EFI GOP framebuffer is
  active during firmware phase.

**Dual-ABI policy** (amends index decision 7):

| Boot-kit ABI string | Kernel format | Boot method | Applies to |
| --- | --- | --- | --- |
| `qemu-arm64-direct-v1` (legacy, read-only honored) | raw arm64 Image (`ARM\x64` at 0x38) | plain `-kernel`, **no** pflash | all existing Ubuntu VMs; recovery-exported pairs |
| `qemu-arm64-uefi-direct-v1` (new) | PE32+ EFI-stub (`MZ`@0, `PE\0\0`@0x40) | pflash firmware + fw_cfg kernel | all new Ubuntu factory kits |

- Verified: legacy raw Image (Arch 7.2.2 from the 0.3.0 factory) still direct-boots with no
  firmware (2026-09-06) — existing VMs keep booting untouched.
- The launcher selects the boot method from the staged kit's ABI metadata. New factory kits
  are written with the new ABI string. Kit staging/storage code stays generic; only the
  QEMU arg assembly branches.
- Kernel/initramfs validators branch on ABI: legacy kit → `ARM\x64` at 0x38; new kit →
  `MZ` at 0x00 + `PE\0\0` at 0x40. Initramfs check becomes decompress-verify (zstd/gzip
  → newc) for both.
- Recovery boot (plan5) boots old disks with the **current** factory initramfs → that boot
  itself is a UEFI boot; the exported pair is the old disk's raw Image → stored as a legacy
  kit, booted via the legacy path.

## 3. Artifact contract (unchanged from plan1 draft, with updates)

| Artifact | Requirement |
| --- | --- |
| `rootfs.ext4` / `rootfs.ext4.zst` | raw ext4, no partition table, 6144 MiB, label `tryubuntu` (ext4 labels cap at 16 bytes), fresh UUID (in spec), zstd -12 |
| kernel (`vmlinuz-linux`) | PE32+ EFI-stub Image, validated per §2 |
| `initramfs-linux.img` | cpio newc, zstd-compressed OK (launcher decompress-verifies) |
| `build-spec.json` | byte-identical to `guest/spec.json` |
| `guest-manifest.json` | schemaVersion 1, kind `tryubuntu-guest-artifacts` (renamed in plan11), identity = its sha256 |
| `SHA256SUMS`, `provenance.json`, dpkg manifest | same roles as the Arch artifacts |
| Runtime bundle | current 16 files **plus** `share/edk2-aarch64-code.fd` and `share/edk2-arm-vars.fd` (sha-pinned from the QEMU build tree; pinned digest in spec) |
| Base kernel cmdline (unchanged) | `root=/dev/vda rw rootwait console=tty0 console=hvc0 loglevel=4 systemd.show_status=false rd.systemd.show_status=false mitigations=off nowatchdog` |

Kernel cmdline tokens (launcher-owned; guest consumers per plan4):

- `tryubuntu.qemu_virgl=1` (was `omarchy.qemu_virgl=1`)
- `tryubuntu.shared_folder_name=<urlsafe-base64>` (was `omarchy.shared_folder_name=`)
- `tryubuntu.ssh_access=1` (was `tryomarchy.ssh_access=1`)
- `tryubuntu.export_boot=1` (was `tryomarchy.export_boot=1`; consumed by the plan5
  initramfs-tools hook; recovery cmdline `rootflags=noload fsck.mode=skip` unchanged)

Frozen host-contract strings (renamed only in plan11 if at all): virtio port names
`dev.tryomarchy.{audio,clipboard,camera}`, boot-export mount tag
`try-omarchy-boot-export`, marker `try-omarchy-boot-export-v1`, storage root marker
`omarchy-qemu-storage-root-v1`, metadata kind strings, bundle identity kind.

## 4. Network map (2026-09-06)

| Host | Status | Fallback used |
| --- | --- | --- |
| auth.docker.io / registry-1.docker.io | **BLOCKED** (DNS poisoning) | Docker registry-mirrors: docker.m.daocloud.io, docker.1ms.run (configured in `~/.docker/daemon.json`) |
| github.com | **BLOCKED this day** (flaky historically) | ghfast.top proxy prefix (release assets verified byte-identical) |
| raw.githubusercontent.com | **BLOCKED** | cdn.jsdelivr.net/gh (`@<ref>` refs, sha-verified) |
| objects.githubusercontent.com (release assets) | **BLOCKED** (0 B/s) | ghfast.top (~575 KB/s measured) |
| ports.ubuntu.com | OK (direct) | mirrors.tuna.tsinghua.edu.cn/ubuntu-ports (fallback) |
| snapshot.ubuntu.com | OK | — (optional apt pinning) |
| mirrors.tuna.tsinghua.edu.cn | OK (~460–550 KB/s) | — |
| gitlab.com | OK (browse/archive); raw endpoint 403 | use archive endpoints or other mirrors |
| git.kernel.org | OK (slow) | retry logic |
| ghcr.io, pypi.org | OK | — |
| cdn.jsdelivr.net, ghfast.top | OK | — |

Transport policy (index decision 6) applies to every fetch: primary first, verified
mirror fallback, always sha256-gated.

## 5. Compatibility statement (for docs/release notes)

Installing the Ubuntu version of the app preserves existing VM disks and their contents.
VMs created by Try Ubuntu releases keep booting their own preserved kernel/initramfs
(legacy ABI, verified above) until the user performs an explicitly confirmed Factory
Reset, which creates a fresh Ubuntu VM from the new factory. Schema-2 VMs without a saved
boot kit go through the existing consent-gated recovery export (plan5) and then keep
booting as legacy kits.
