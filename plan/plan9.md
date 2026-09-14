# Plan 9 — Test suite & documentation green

Status: pending · Depends: plan6, plan8 · Est: 1 day

## Goal

Make `make test` fully green with the Ubuntu guest, and bring every document in line with
reality (README, architecture, releasing, contributing). No new features.

## Tasks

- [ ] Sweep `macos/Tests/` for guest-specific assertions:
      - `FullscreenNativeContractTests` / `CocoaDynamicDisplayContractTests` pin strings in
        run-qemu-gpu.sh and QEMU patches — mostly guest-agnostic; fix only token mentions.
      - `run-qemu-ssh-contract.test.sh` — token rename fallout (done in plan6) + fixture
        kernel cmdline strings updated.
      - `qemu-persistent-storage.test.sh`, `qemu-power-actions.test.sh`,
        `qemu-port-forwarding.test.sh`, `runtime-relocation.test.sh`,
        `macos-compatibility.test.sh` — expected green without guest coupling; verify.
      - Swift suites referencing "Try Ubuntu" presentation strings — keep for plan11; only
        fix anything asserting guest identity (`bootRecovery` texts mention Ubuntu — update
        copy to Ubuntu-neutral or defer to plan11 deliberately; record the decision).
- [ ] `guest/test` (new verify.py + unit tests) green — from plan8.
- [ ] `make test` end-to-end green on this machine; CI (`make test` on macos-15) unchanged.
- [ ] Docs rewrite:
      - `README.md`: product story (Ubuntu 26.04.1 LTS arm64, GNOME), quick start,
        requirements, data/updates section (update-ubuntu flow), remove Ubuntu sections
        (1Password, Quattro), keep SSH/port-forward/camera/clipboard/shared-folder sections
        (they survive), repository layout (guest/ = Ubuntu builder).
      - `docs/architecture.md`: replace the ARM64-image chapter with the Ubuntu builder;
        trust model (debootstrap pinning, dpkg manifest, overlay digests); keep everything
        storage/boot-kit/sleep/ports unchanged; update kernel token names.
      - `docs/releasing.md`: checklist adapted (drop Ubuntu provisioning references; add
        Ubuntu first-boot, GNOME graphics, snapd caveat).
      - `CONTRIBUTING.md`: "Updating Ubuntu" → "Updating Ubuntu" (pin refresh workflow via
        the new `make update-ubuntu` from the next task).
      - `macos/README.md` if it references guest specifics.
- [ ] `make update-omarchy` target → `make update-ubuntu`: new semantics = bump the pinned
      point release / kernel meta / core pins in spec.json (a small script analogous to
      `update-upstream-pin.py`, but apt-based: query TUNA for current kernel meta version in
      the suite, update spec, require contract re-run). Implement + document.
- [ ] Full clean build from the branch (`make clean && make build`) to prove the docs' commands.

## Acceptance criteria

- `make test` green end-to-end; `make build` from clean succeeds.
- Docs contain no stale Ubuntu/Arch references except intentional history notes
  (`git grep -in omarchy README.md docs/ CONTRIBUTING.md` → reviewed list).
- `make update-ubuntu` runs and updates spec pins with a dry-run/verify mode.

## Risks & notes

- Keep plan11 rename out of these docs where possible (use "the app"/"Try Ubuntu" sparingly)
  so plan11's mechanical sweep stays mechanical.
