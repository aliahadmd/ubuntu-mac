# Plan 10 — Ubuntu decommission & residue audit

Status: pending · Depends: plan9 · Est: 0.5 day

## Goal

Delete every Ubuntu/Arch-specific artifact that plan2–plan9 replaced or obsoleted, and run
a repo-wide residue audit so nothing dead or misleading survives. The repo should read as
"always been Ubuntu" (modulo git history).

## Inputs / touched files (deletions)

- `guest/vendor/tryubuntu-pkgs/` (pacstrap-docker)
- `guest/pacman.aarch64.conf`, `guest/mirrorlist.aarch64`, `guest/packages.txt`,
  `guest/packages.lock.json`
- `guest/patches/` (hyprland rounded-border, omarchy backports: 1password, vivaldi,
  notifications, free-space) — all dead with the Ubuntu tree
- `guest/fragments/` (hypr monitors append, pacman restore)
- `guest/factory-overlay/` (mkinitcpio conf, zram, xdg-terminal-exec — replaced by the
  Ubuntu overlay's equivalents in plan2/plan4)
- `guest/scripts/`: `fetch-source.sh`, `materialize-omarchy.sh`,
  `apply-tryubuntu-backports.py`, `update-upstream-pin.py`, `refresh-package-lock.sh`,
  `resolve-package-lock.py`, `register-{tryubuntu-runtime,pinned-mise,pinned-yay,pinned-ttfx,
  patched-hyprland,local-repository}.sh`, `verify-{screensaver,background-switcher}-override.py`,
  `source-digest.py` — each replaced by the plan2/plan4/plan8 equivalents
- `guest/native-overlay/` (the Ubuntu tree — superseded by `guest/native-overlay.ubuntu/`;
  at this point rename the new overlay to `guest/native-overlay/` so the layout matches the
  build scripts' expectations)
- `guest/keys/` (vivaldi key), `guest/test` runner updated paths only
- Old guest tests dropped in plan8 are confirmed gone here
- Makefile: `clean-guest` alias audit; any `tryubuntu-*` Docker filter names in `clean`
  (Docker builder image name `tryubuntu-guest-builder` — rename to `tryubuntu-guest-builder`
  in plan11 with the branding pass, or here; decision: **here**, it's a build-internal name
  with no user surface — do it in this plan and update `build-container.sh` + Makefile filters)

## Tasks

- [ ] Execute deletions above; ensure `build-container.sh`/`build.sh` reference only
      surviving paths; `guest/test` green.
- [ ] Rename `guest/native-overlay.ubuntu/` → `guest/native-overlay/` (and
      `factory-overlay.ubuntu` equivalent if plan2 introduced one); update configure/finalize
      scripts.
- [ ] Docker naming: builder image tag, work-volume label filters (`dev.tryubuntu.role=` →
      `dev.tryubuntu.role=`), stale-resource cleanup in `make clean` — update all three
      (build-container.sh, Makefile clean targets, docs).
- [ ] Residue audit:
      - `git grep -in 'omarchy' -- ':!plan' ':!*.md'` → every hit is justified (host contract
        strings: virtio port names `dev.tryomarchy.*`, QEMU product identity marker
        `TryUbuntu.icns`, support path `Try Ubuntu`, boot-export mount tag
        `try-omarchy-boot-export`, marker `try-omarchy-boot-export-v1`, storage root marker
        `omarchy-qemu-storage-root-v1`, schema metadata kind strings). Maintain an
        **allowed-list file** (`plan/residue-allowed.txt`) with one line per justified hit +
        reason; plan11 shrinks it to (ideally) zero and plan12 enforces it in verify.py.
      - `git grep -in 'arch\|pacman\|hyprland\|pacstrap\|mkinitcpio' -- macos/ guest/` →
        reviewed to empty (except comments explaining history if any are kept — prefer none).
- [ ] Sanity: `make clean` still selects only project Docker resources (labels changed
      coherently); no orphan volume/image names.

## Acceptance criteria

- Deletions complete; `make test` green; fresh `make build` succeeds from the trimmed tree.
- Residue audit report exists (`plan/residue-allowed.txt`) with every remaining hit
  justified; anything not on the list is a bug caught by the new verify.py check (added in
  plan8's suite — wire the allowed-list into it here).

## Risks & notes

- Do NOT rename host-contract strings in this plan (port names, markers, mount tag, storage
  root marker, support path) — they are cross-layer contracts with storage compatibility and
  the QEMU patch; they all get the plan11 treatment in one atomic pass.
- Deleting `test_update_upstream_pin.py`-era tooling while keeping `make update-ubuntu` (plan9)
  coherent: double-check the Makefile target wiring survives.
