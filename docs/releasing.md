# Releasing

Releases are Apple Silicon-only and require macOS 15 or newer.

## Build and verify

```sh
make doctor
make test
make build
make release
```

When the release moves the Ubuntu pin forward (suite point release, kernel
meta, or a core package version), first update `guest/spec.json` per
`CONTRIBUTING.md` ("Updating Ubuntu"), then continue with the sequence above.

Outputs are written to:

- `dist/app.noindex/Try Ubuntu.app` (pre-rename layout: `Try Ubuntu.app`)
- `dist/TryUbuntu.dmg`
- `dist/guest/`

`make package` and `make release` both create distributable builds: they sign
the app and DMG with Developer ID, submit the DMG to Apple's notarization
service, and staple the resulting tickets. Neither command falls back to an
unnotarized build. Both commands first ensure the content-hashed guest and
runtime artifacts are current; packaging and signing themselves always run
freshly. Another maintainer can override the release defaults:

```sh
make release \
  RELEASE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
  RELEASE_NOTARY_PROFILE=example-profile
```

## Release checklist

1. Confirm `main` is clean and all pinned inputs have reviewable provenance.
2. Run all tests and perform a first-boot provisioning test on a clean Mac user
   (console account form, then GNOME session).
3. Verify networking, display scaling, keyboard/mouse, microphone and camera
   permission, on-demand FaceTime HD capture, audio-device changes, clipboard
   sharing in both directions, a shared folder read and written from both
   sides, persistence, reset, and ephemeral mode. Exercise the SSH preset with
   a provisioned guest: confirm the listener is bound only to `127.0.0.1`,
   normal and ephemeral TCP mappings to guest port 22 work, UDP port 22 does
   not request sshd, a normal restart preserves the persistent VM, and the
   documented endpoint-specific host-key recovery works after
   Reset/ephemeral replacement. Inspect the factory image to confirm it
   contains no SSH host private keys.
4. Install the release over a VM created by a different guest build. Confirm
   launch preserves its disk and user data and selects the saved boot kit
   instead of the release's bundled kernel/initramfs. Confirm both boot ABIs:
   VMs from the Ubuntu factory boot through the bundled UEFI firmware; VMs
   from the Ubuntu-era factory keep booting their raw Image kits directly.
   For a VM without a boot kit, confirm the one-time read-only `/boot` export
   completes, but only after the pre-launch dialog appears. Confirm **Cancel**
   starts no QEMU process and changes no disk contents; confirm **Continue**
   performs the recovery, the environment powers off without entering the old
   userspace, and later launches do not repeat it. Separately confirm that
   new, reset, and ephemeral VMs use the current factory.
5. Verify the app and DMG signatures with Apple's tools and confirm notarization.
6. Audit `THIRD_PARTY_NOTICES.md`, the bundle's license material, the dpkg
   manifest, and QEMU corresponding-source obligations. Confirm the
   not-affiliated-with-Canonical statement is present in the release notes.
7. State in release notes that installing the app preserves existing VM
   contents, and that Ubuntu-era VMs keep booting their own preserved guest
   until a confirmed reset.
8. Record SHA-256 digests for the final app archive/DMG and publish them with
   the release notes.

Never publish generated artifacts from an unreviewed or locally modified build
input.

The saved boot-kit ABI is a compatibility boundary (two ABIs are recognized:
`qemu-arm64-direct-v1` and `qemu-arm64-uefi-direct-v1`). Do not change either
or remove support for an existing value without a reviewed preserving
migration or an explicitly confirmed reset path.
