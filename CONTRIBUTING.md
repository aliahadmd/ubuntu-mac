# Contributing

Thanks for helping improve Ubuntu Mac. The project has one product target: a
native Apple Silicon macOS app that runs a project-built ARM64 Ubuntu 26.04.1
LTS virtual machine image.

## Before opening a pull request

1. Open an issue for large behavioral or architecture changes.
2. Keep changes within the current Apple Silicon, QEMU/HVF, and ARM64 guest
   architecture unless an architecture change has been discussed first.
   The guest is Ubuntu 26.04.1 LTS (`resolute`) arm64 with GNOME; other
   distributions or compositors are out of scope without discussion.
3. Run `make test`.
4. If build inputs changed, run the relevant component build and explain how
   its pinned versions or checksums were reviewed.
5. Update documentation when commands, requirements, output paths, or security
   boundaries change.

The guest and QEMU supply chains are deliberately pinned. Do not update a URL,
mirror, package version, archive, or checksum independently of its associated
validation code. The guest's Ubuntu archive inputs are recorded in
`guest/spec.json` (suite, mirrors, kernel meta, core package pins) and the
complete resolved set ships as the dpkg manifest; refresh pins through the
review process, never as a drive-by edit.

Generated files in `dist/` and build caches in `macos/.build/` and
`guest/.work/` are not committed. Use `make clean` to remove project build
artifacts and caches. `make clean-all` additionally destroys persistent local
VM data and should only be used when a complete reset is intended.

Component builds use content-hashed state under `.build/state/`. A state file is
published only after the build succeeds and its output passes validation. Use
`FORCE=1` when reviewing reproducibility or when an intentionally unchanged
input must be rebuilt; do not work around the cache by editing generated state.

## Updating Ubuntu

The factory pins the Ubuntu suite, kernel meta, and a reviewed core package
set in `guest/spec.json`. To move the pin forward:

1. Confirm the new versions in the target suite (the apt queries are documented
   in `plan/contract.md`).
2. Update `distribution.kernelMetaVersion` and the `supplyChain` core pins in
   `guest/spec.json`.
3. Run `make guest` and `make test`; the build hard-fails if the pinned set
   drifts from the resolved transaction, so review the recorded diff.

A pinned-version change is a supply-chain review, not a chore: update the
specification, the contract tests, the third-party notices, and the dpkg
manifest expectations together.

## Tests

Tests should describe a user-visible behavior, policy, data contract, or
process boundary. Keep presentation and edit rules in deterministic models that
can be exercised without opening AppKit windows. Do not make CI depend on pixel
coordinates, font metrics, display size, global window lookup, fixed run-loop
delays, or an assumed free network port.

Platform integration tests are appropriate when the operating-system boundary
is itself the contract. Use isolated temporary state, inject controllable
probes where the real resource is incidental, and use bounded readiness checks
instead of fixed settling delays.

By contributing, you agree that your contribution is licensed under the MIT
License in this repository.
