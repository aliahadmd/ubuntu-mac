# Plan 1 — Strategy, contract definition, global decisions

Status: pending · Depends: none · Est: half day

## Goal

Freeze the conversion contract so every later plan can proceed independently: define the
exact artifact interface the Ubuntu factory must satisfy, record the binding decisions from
[index.md](index.md), and set up the working branch with the current tree preserved.

## Why first

Every failure mode we hit during the Ubuntu build (launcher validation gates, boot-kit ABI,
network blocks) comes from contract drift between the three layers (Swift ↔ shell ↔ guest).
Writing the Ubuntu contract down once — before any code changes — is what keeps plan2–plan6
from re-breaking each other.

## Tasks

- [ ] Create branch `ubuntu-guest` from `main`; commit the currently-uncommitted network
      transport edits (`guest/Containerfile` jsDelivr + TUNA, `guest/scripts/register-pinned-yay.sh`)
      as their own commit with a message noting they will be superseded by plan2's rewrite.
- [ ] Write `plan/contract.md` (the Ubuntu artifact contract; content below) and reference it
      from plan2–plan6 instead of re-deriving it.
- [ ] Confirm Ubuntu 26.04.1 facts at execution time (do not assume):
      - suite/codename for debootstrap (`resolute` expected — verify against
        `https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/dists/`),
      - `linux-image-generic` version on arm64 and that `/boot/vmlinuz-*` is gzip-compressed
        (affects plan3 kernel handling),
      - `v4l2loopback` package name in universe (`v4l2loopback-kmod-dkms` vs
        `v4l2loopback-dkms`) and that `linux-headers-generic` satisfies its build,
      - reachability of `snapshot.ubuntu.com` from this network (optional hardening for
        point-in-time apt pinning; not a hard requirement).
- [ ] Re-verify the network map (hosts reachable/blocked) and record it in `plan/contract.md`;
      this drives the transport fallback list in plan2 (apt) and plan6 (runtime bottles).
- [ ] Decide and record the exact set of **kept kernel command line tokens** and their new
      names (see plan4) plus the base command line, which is unchanged:
      `root=/dev/vda rw rootwait console=tty0 console=hvc0 loglevel=4 systemd.show_status=false rd.systemd.show_status=false mitigations=off nowatchdog`
- [ ] Record the "existing Ubuntu VMs keep booting until reset" compatibility statement for
      later use in plan9 docs and plan12 release notes.

## The Ubuntu artifact contract (summary; full version goes in plan/contract.md)

The launcher (run-qemu-gpu.sh, qemu-persistent-storage.sh, build-app.sh) consumes:

| Artifact | Requirement |
| --- | --- |
| `rootfs.ext4` / `rootfs.ext4.zst` | raw ext4, no partition table, 6144 MiB, label + fixed UUID in spec, zstd -12 |
| kernel (`vmlinuz-*`) | raw arm64 Image — decompress if gzip'd; `ARM\x64` magic at offset 0x38; QEMU direct-boots it |
| `initramfs-linux.img` (name kept) | cpio newc (Ubuntu default zstd compression is fine; plan6 relaxes the launcher's raw-newc check to decompress-verify) |
| `build-spec.json` | byte-identical to `guest/spec.json` |
| `guest-manifest.json` | same schema/kind/roles as today; bundle identity = sha256 of it |
| `SHA256SUMS`, `provenance.json`, `packages.lock.txt` (becomes dpkg manifest) | same roles |
| kernel cmdline | base line above + launcher-appended tokens only; must not pre-contain launcher-owned tokens |

Unchanged invariants: storage schema 2 metadata, boot-kit ABI `qemu-arm64-direct-v1`,
`launch.plist` fields, device list, QMP/virtio-serial port names.

## Acceptance criteria

- `plan/contract.md` exists and is referenced by later plans; decisions table matches index.md.
- Branch `ubuntu-guest` exists with the transport commit; working tree clean.
- All Ubuntu facts listed above are confirmed with sources noted in contract.md.

## Risks & notes

- Do not start plan2 before the debootstrap suite name is confirmed — guessing burns a full
  Docker build cycle.
- Keep this plan documentation-only; no build-script behavior changes here.
