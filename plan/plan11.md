# Plan 11 — Rename & branding → Try Ubuntu

Status: pending · Depends: plan10 · Est: 1 day

## Goal

One atomic rebranding pass: "Try Ubuntu" → "Try Ubuntu", bundle id `dev.tryubuntu.native`
→ `dev.tryubuntu.native`, and the few host-contract strings that still carry the old name —
each updated together with its counterpart so no layer disagrees.

## Scope (every rename site, by layer)

- **QEMU patch**: `macos/patches/qemu-cocoa-product-identity.patch` — process name, icon
  resource name (`TryUbuntu.icns` → `TryUbuntu.icns`), menu item strings. Requires runtime
  rebuild (cache invalidates by design).
- **Runtime validation**: `macos/run-qemu-gpu.sh` icns-identity-marker check + audio symbol
  probes; `macos/prepare-qemu-gpu-runtime.sh`/`runtime-files.txt` unchanged (file names same).
- **App bundle**: `macos/Info.plist` (CFBundleName/DisplayName/Identifier
  `dev.tryubuntu.native`, executable `tryubuntu-vm-helper`? — decision: keep executable name
  `tryubuntu-vm-helper`? No — rename to `tryubuntu-vm-helper` and update `build-app.sh`,
  Makefile references, and `open-qemu-gpu.sh` expectations in the same commit),
  `macos/TryUbuntuIcon.svg` → `UbuntuIcon`-equivalent (new icon asset: rendered from a simple
  Ubuntu-circle-of-friends-style placeholder — do NOT ship Canonical's trademarked logo
  without permission; generate an original "TU" mark via the existing icon pipeline
  `render-app-icon.swift` + `pack-app-icon.py`), entitlements file names.
- **Swift sources** (`macos/Sources/TryUbuntuVMHelper/`): reset-confirmation string
  ("Try Ubuntu" typed text → "Try Ubuntu" — `ResetConfirmationPolicy`), storage root URL
  `~/Library/Application Support/Try Omarchy/VM/v1` → `Try Ubuntu/VM/v1`,
  `StartMenuPresentation` copy, `QEMUGPULauncher` strings, audit-log labels, test bundle
  directory name `TryUbuntuVMHelperTests` → `TryUbuntuVMHelperTests`, target name.
- **Virtio port names** `dev.tryomarchy.{audio,clipboard,camera}` → `dev.tryubuntu.*`:
  host (run-qemu-gpu.sh chardev wiring + Swift bridge scripts/constants) **and** guest
  (bridge scripts, udev rules) in the same commit. These are the last `tryomarchy` strings.
- **Recovery contract strings**: `try-omarchy-boot-export` mount tag + marker
  `try-omarchy-boot-export-v1` + storage marker `omarchy-qemu-storage-root-v1` + metadata
  kinds — **decision point**: renaming these breaks cross-version storage compatibility
  (a v0.3.0-era VM's workspace markers would no longer be recognized). Recommendation:
  **keep the storage/recovery contract strings as-is** (they are invisible to users), note
  them permanently in `plan/residue-allowed.txt`, and only rename the user-visible items.
  If renamed anyway, a workspace-recognizer must accept both spellings — do not take that
  risk for cosmetics.
- **Kernel tokens**: already `tryubuntu.*` since plan4/6 — verify nothing remains.
- **Docs/README/title lines**, `plan/index.md` product references (docs rewrite from plan9
  already used sparing naming; finish the sweep).

## Tasks

- [ ] Contract-string inventory first: `git grep -in 'omarchy' -- ':!plan'` → classify each
      hit into (a) user-visible → rename, (b) storage/recovery contract → keep + document,
      (c) build-internal already renamed in plan10. Commit the inventory to
      `plan/rename-inventory.md` before touching code.
- [ ] Execute renames per classification; QEMU patch edit + `make runtime` rebuild.
- [ ] Icon: new original artwork through the existing pipeline (1024px SVG → icns),
      update `render-app-icon.swift` input path + `build-app.sh`.
- [ ] Support-path migration: the new default root is `~/Library/Application Support/Try
      Ubuntu/VM/v1`; existing "Try Ubuntu" workspaces are **not** auto-migrated (same
      stance as Ubuntu legacy disks; document). `StorageLocation.swift` default constant +
      `clean-all` paths in the Makefile (`app_support`, caches, plist names
      `dev.tryubuntu.native.plist`).
- [ ] Tests: update every Swift/shell assertion pinned to renamed strings; allowed-list in
      verify.py shrinks to the kept contract strings only.
- [ ] Full `make test` + `make build` + `make run` pass; start menu, About panel, Dock
      name/icon all read Try Ubuntu.

## Acceptance criteria

- `git grep -in 'omarchy' -- ':!plan'` returns only the documented keep-list (storage
  contract strings), each justified in `plan/residue-allowed.txt`.
- App identity coherent end-to-end (bundle id, process name, window title, icon, support
  path, Docker names, plist names).
- v0.3.0-era VM still launches from the renamed app (storage compatibility preserved).

## Risks & notes

- This plan is wide but shallow — the danger is partial renames breaking cross-layer
  equality checks (e.g. launcher expects marker the QEMU patch no longer writes). The
  inventory-then-execute order is the mitigation.
- Canonical's Ubuntu trademark: the app name "Try Ubuntu" describes function; the icon must
  be original artwork. Note this in plan12 release notes; consider a legal disclaimer line
  in the README ("not affiliated with Canonical").
