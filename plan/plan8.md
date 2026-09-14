# Plan 8 — Supply chain & provenance (spec.json, pinning, verify.py, notices)

Status: pending · Depends: plan4 (parallelizable with plan6/7) · Est: 1–2 days

## Goal

Rebuild the trust layer for Ubuntu: a new `guest/spec.json` (same schema shape), an apt-based
pinning/manifest model that honestly matches what debootstrap can guarantee, the rewritten
`guest/tests/verify.py` contract suite, and updated third-party notices.

## Why honest pinning matters here

Arch's lock pinned 614 exact package versions resolved from a mirror. Apt point releases
don't give byte-identical resolution across time the same way — the honest model is:
pin the **base image inputs** (debootstrap suite + point-release date, kernel meta package
version, a reviewed core-package version set), record the **complete dpkg manifest** for
provenance, and hard-fail the build when the pinned set drifts. Optional hardening:
`snapshot.ubuntu.com` for point-in-time apt (reachability from this network per plan1).

## Tasks

- [ ] New `guest/spec.json` (schemaVersion 2, same top-level shape):
      - `image`: aarch64 / ext4 / label `tryubuntu-factory` / new UUID / 6144 MiB /
        `sourceDateEpoch` tied to the Ubuntu point-release date used.
      - `guest`: profile `factory`, hostname `ubuntu-factory`, `username: null` (unprovisioned).
      - `upstream` section replaced by `distribution`: suite `resolute`, point release
        `26.04.1`, mirror + fallback mirror, kernel meta version (`linux-image-generic=...`
        as observed at plan2), debootstrap program version.
      - `supplyChain`: builder base image digest, debootstrap sha256? (from apt), the
        reviewed core-version map (kernel, initramfs-tools, pipewire, wireplumber,
        v4l2loopback, wl-clipboard, gdm3, gnome-shell — the packages whose ABI/behavior the
        host integration depends on), each `name=version`.
      - `authenticity`: `verbatimRuntimeTrees: []` / `backportedRuntimeTrees: []` — replaced
        by an `overlay` object: overlay tree sha256 + the per-file digest map of every file
        the overlay replaces or adds (no upstream-tree backport concept anymore);
        `postBuildUserInstallers: []` (decision 5 — none in v1); `requiredPaths`: the guest
        paths that must exist (`/usr/local/bin/tryubuntu-native-*-bridge`, units, generator,
        initramfs script, build-spec embed path).
      - `runtime` section: byte-identical contract values as today (devices, ports, camera
        geometry, storage, sshAccess preset/token names updated to `tryubuntu.*`,
        sharedFolder param `tryubuntu.shared_folder_name`).
- [ ] `packages.lock.txt` → `dpkg-manifest.txt`: full `dpkg-query -W` snapshot at pack time
      recorded as an artifact; build fails if any `supplyChain` core pin mismatches the
      staged root (small `verify-pins.py`).
- [ ] Rewrite `guest/tests/verify.py` (the ~200 Arch checks → Ubuntu equivalents):
      spec shape/schema, uuid/label agreement with pack script, token names in
      `macos/run-qemu-gpu.sh` agree with spec (`tryubuntu.*`), dpkg manifest present +
      core pins verified against a fixture, overlay file digests, requiredPaths,
      `bash -n` over shell scripts, `py_compile` over bridges, unit/drop-in contents,
      initramfs hook contract (plan5 script), kernel cmdline base string exact, no
      `omarchy` strings outside the allowed list (ported from the old suite's hygiene
      checks), camera entitlement cross-check into `macos/tryubuntu-vm-helper.entitlements`
      (file renames in plan11 — reference by content not name where sensible).
- [ ] Port the still-relevant unit tests (`test_native_clipboard_bridge.py`,
      `test_native_camera_bridge.py`, `test_native_audio_bridge.py`,
      `test_audio_input_helper.py`, `test_ssh_access.py`, `test_boot_export.py` per plan5);
      drop Ubuntu-only tests (`test_rounded_border_coverage.py`, `test_apply_omarchy_backports.py`,
      `test_update_upstream_pin.py`, `test_fetch_source.py` — replaced by pin-verify tests).
- [ ] `THIRD_PARTY_NOTICES.md` rewrite: project MIT unchanged; Ubuntu aggregate notice
      (GPLv3 etc. recorded via dpkg-manifest), QEMU GPL-2.0 corresponding-source obligation
      stays, bridges keep wl-clipboard/PipeWire/v4l2loopback attributions; remove Ubuntu,
      Hyprland, Glaze, mise, ttfx, yay, Vivaldi, 1Password entries.
- [ ] Provenance surfaces in the image: `/usr/share/tryubuntu/build-spec.json` +
      `provenance.json` (overlay digest model) + `dpkg-manifest.txt`; keep
      `write-provenance.py` generalized (from plan4's minimal version).

## Acceptance criteria

- `guest/test` passes the new suite against the real plan7 artifacts.
- A deliberate pin drift (bump a core pin in a fixture) fails the build with a reviewable
  diff — mirroring the old resolve-package-lock behavior.
- Notices complete per the plan12 checklist audit.

## Risks & notes

- Do not over-pin: pinning every dpkg entry recreates the Arch brittleness. Pins protect
  the ABI surface the host integration touches; the manifest is provenance, not enforcement.
- Keep spec `runtime` values byte-equal to the old contract wherever the host validates
  them (devices list, camera protocol, ssh preset) — the Swift side reads some of these.
