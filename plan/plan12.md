# Plan 12 — Release pipeline & final validation

Status: pending · Depends: plan11 · Est: 0.5–1 day

## Goal

Produce the first signed, notarized **Try Ubuntu** DMG from the converted tree, run the full
release checklist adapted from `docs/releasing.md`, validate a clean-room build, and merge
`ubuntu-guest` to `main`.

## Tasks

- [ ] Preflight: `make doctor && make test && make build` from clean on this machine.
- [ ] `make release` (Developer ID + notarization; credentials as configured): app + DMG
      signed, notarized, stapled — verify with `codesign --verify --deep --strict` and
      `stapler validate`.
- [ ] Adapted release checklist (rewrite into docs/releasing.md happened in plan9; execute it):
      - first-boot provisioning on a clean macOS user; GNOME session reachable;
      - graphics acceleration + HiDPI resize; audio switching both directions; mic
        only-while-recording; clipboard text/PNG both ways; camera on-demand indicator;
        shared folder rw both sides; persistence across relaunch; reset (typed
        confirmation "Try Ubuntu") and ephemeral mode; VM location change to external APFS;
      - SSH preset: listener loopback-only, TCP mapping works, UDP-22 does not enable sshd,
        endpoint host-key recovery after reset documented;
      - legacy paths: a v0.3.0 Ubuntu VM preserves its disk and boot kit; schema-2 without
        kit triggers the consent + recovery export once (plan5 path);
      - inspect the factory image: no SSH host keys, no user accounts, no secrets;
      - third-party notices audit vs `dpkg-manifest.txt`; QEMU corresponding-source shipped
        per obligation; SHA-256 digests of the DMG recorded in release notes.
- [ ] Release-notes content: features (Ubuntu 26.04.1 LTS arm64, GNOME), the
      "existing Ubuntu VMs keep booting until reset" statement, the "not affiliated with
      Canonical" line, the snapd first-boot-network note.
- [ ] Clean-room validation: fresh clone of the branch into a new directory, `make build`
      — proves the transport fallbacks (Docker mirror, TUNA, jsDelivr/ghfast) are committed
      policy, not local state. Time the guest build for the README's expectations section.
- [ ] Merge `ubuntu-guest` → `main` (no-ff, release-notes-linked). Tag `v0.4.0-ubuntu.0`
      (or per project convention). Publish artifacts + digests. Post-merge: delete stale
      Ubuntu Docker images/volumes via `make clean`.
- [ ] Archive: keep the v0.3.0 Ubuntu DMG URL referenced in the release notes as the
      Ubuntu-era artifact; the source remains in git history at tag `v0.3.0`.

## Acceptance criteria

- Signed/notarized DMG passes Gatekeeper on a clean machine; release checklist fully
  executed with results recorded; clean-room build succeeds; `main` is the Ubuntu tree;
  CI green on the merge commit.

## Risks & notes

- Notarization requires network to Apple (reachable — v0.3.0 was notarized from this
  environment lineage; if the submit stalls, retry logic in package-dmg handles it).
- If the checklist surfaces GNOME/virgl issues late, do not hotfix on main — fix on the
  branch, re-run, then merge. The plan series ends here; new work gets a fresh plan.
