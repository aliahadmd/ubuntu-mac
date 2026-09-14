# Plan 6 — Launcher glue: run-qemu-gpu.sh validation rewrite + runtime transport → `make run` boots Ubuntu

Status: pending · Depends: plan4, plan5 · Est: 0.5–1 day

## Goal

Update the shell layer so the standard pipeline (`make build` / `make run`) builds the
runtime, validates the Ubuntu factory bundle, and boots the VM through the real app. This is
the first plan where the **app itself** runs the new guest.

## Inputs / touched files

- `macos/run-qemu-gpu.sh` — the bundle-identity validation heredoc (Python) currently
  cross-checks Ubuntu supply-chain digests (ttfx/yay/Vivaldi/Hyprland) between
  `guest-manifest.json` and `build-spec.json`; kernel cmdline ownership checks; initramfs
  raw-newc check; the `omarchy.*` token emitters (`omarchy.qemu_virgl=1`,
  `omarchy.shared_folder_name=`, `tryomarchy.ssh_access=1`).
- `macos/build-qemu-gpu-runtime.sh` + `pinned-runtime-bottles.sh` — transport fallback for
  GitHub-hosted bottles (virgl/ANGLE/epoxy from startergo releases are GitHub **release
  assets**, which are hard-blocked on this network; measured 0 B/s direct, ~575 KB/s via
  ghfast.top).
- `macos/Tests/` contract tests that pin launcher strings.

## Tasks

- [ ] Kernel-token rename, host side: emitters become `tryubuntu.qemu_virgl=1`,
      `tryubuntu.shared_folder_name=`, `tryubuntu.ssh_access=1`; the "must not already
      contain launcher-owned tokens" validation list updates in the same commit (plus
      recovery token `tryubuntu.export_boot=1` passed by the launcher's recovery mode).
      Update `macos/Tests/run-qemu-ssh-contract.test.sh` and any other tests asserting the
      old token strings.
- [ ] Bundle validation heredoc rewrite:
      - keep the launch-record output format byte-identical
        (`bundle_identity<TAB>source_disk_sha<TAB>source_disk_bytes<TAB>compressed_disk_bytes<TAB>expanded_disk_bytes<TAB>kernel_command_line`),
        so `build-app.sh` inspect-only `launch.plist` generation and Swift
        `QEMUGPUStorageSpaceEstimate.bundledMetrics` stay untouched;
      - keep required checks: sha256 of manifest vs SHA256SUMS, ARM64 kernel magic (0x38
        `ARM\x64`), **initramfs check relaxed** to decompress-verify (zstd/gzip magic →
        decompressed stream must be newc cpio) — per plan3 decision;
      - replace the Ubuntu supply-chain digest cross-check with the Ubuntu set (kernel
        package version pin, key package pins from the new spec — exact shape from plan8;
        until plan8 lands, validate structural consistency only and note the temporary
        gap);
      - ext4 superblock + zstd frame checks unchanged.
- [ ] QEMU invocation: unchanged (device list identical) **except the boot ABI branch**
      (contract.md §2): new kits (`qemu-arm64-uefi-direct-v1`) add
      `-drive if=pflash,format=raw,file=<runtime>/share/edk2-aarch64-code.fd,readonly=on`
      plus a per-run pristine copy of `share/edk2-arm-vars.fd` in the work dir as the
      varstore; legacy kits (`qemu-arm64-direct-v1`) boot exactly as today with no
      firmware. `runtime-files.txt` grows by the two firmware files (pinned digests in
      spec, verified like every other runtime file); `verify_runtime_tree` manifest and
      the runtime build must stage them from the QEMU build tree
      (`pc-bios/edk2-aarch64-code.fd`, `edk2-arm-vars.fd`). Confirm
      `-action 'reboot=reset,shutdown=poweroff'` behaves with Ubuntu userspace (reboot
      resets QEMU; shutdown exits app).
- [ ] Runtime transport fallback (per index decision 6): in the runtime builder, wrap the
      three startergo GitHub release-asset downloads (virgl, ANGLE, libepoxy bottles) with
      primary-URL-first, `https://ghfast.top/<url>` fallback; same for any github.com tarball
      fetch if the flakiness bites; all still sha256-gated. `git.kernel.org` dtc: add retry +
      optional jsDelivr kernel.org mirror fallback only if measured failure (it worked, slowly).
- [ ] Update `macos/Tests/qemu-persistent-storage.test.sh` expectations if any marker text
      referenced guest specifics (it shouldn't — storage is guest-agnostic).
- [ ] `make build && make run` — the app's start menu → Launch boots the Ubuntu VM.
      Verify: start menu shows, ready-handshake line parses (QMP socket path), activation
      policy flips, QEMU window shows Ubuntu console.

## Acceptance criteria

- `make build` completes end-to-end on this machine (guest via plan2–5 pipeline, runtime via
  patched builder, app assembled with the new `launch.plist`).
- `make run` boots the Ubuntu VM through the app; guest console reachable; sleep/wake QMP
  pause/resume still verified by existing tests (`swift test`) — run the full suite.
- All modified launcher contract tests pass; `git grep -n 'tryomarchy\.' macos/` shows only
  intended remnants (virtio port names — renamed in plan11).

## Risks & notes

- The runtime rebuild is the long pole (QEMU compile ~15–25 min); the content-hashed build
  cache invalidates it because the builder script changed — expected, one-time.
- If the startergo bottles' sha256s differ when fetched via ghfast (they shouldn't — the
  proxy serves the same blobs), the existing digest gates catch it loudly; that is the design.
- Do not touch `qemu-persistent-storage.sh` beyond test-string updates — boot-kit ABI and
  schema stay byte-compatible.
