# Third-party notices

Ubuntu Mac builds and redistributes third-party components under their own
licenses. The repository's MIT license applies only to this project's original
code.

- **QEMU** — GPL-2.0 and other component licenses. Release maintainers must
  provide the corresponding source and notices required by the exact bundled
  build.
- **Ubuntu** — the guest factory image is assembled from Ubuntu archive
  packages (suite `resolute`, 26.04.1 point release). Each package retains its
  own license; the complete resolved set with versions is recorded in
  `packages.lock.txt` (the dpkg manifest), which is the license-aggregation
  record for the guest image. Ubuntu is a trademark of Canonical Ltd.; this
  project is not affiliated with or endorsed by Canonical.
- **edk2 (AAVMF UEFI firmware)** — BSD-3-Clause and other component licenses;
  the firmware blobs bundled in the app runtime are taken verbatim from the
  pinned QEMU 11.1.1 build (`share/edk2-aarch64-code.fd`,
  `share/edk2-arm-vars.fd`), with digests pinned in
  `macos/prepare-qemu-gpu-runtime.sh`.
- **ANGLE, VirGLRenderer, libepoxy, SDL, libslirp, GLib, Pixman, and other QEMU
  dependencies** — retain their respective upstream licenses.
- **wl-clipboard, PipeWire, WirePlumber, v4l2loopback** — guest-side
  integration dependencies installed from the Ubuntu archive; they retain
  their respective upstream licenses and are recorded in the dpkg manifest.

The Ubuntu-era artifacts (pinned Ubuntu source tree, rebuilt Hyprland,
mise, ttfx, yay, and the 1Password/Vivaldi post-build installers) were removed
with the Ubuntu conversion; they remain available in the repository history at
the `v0.3.0` tag of the Ubuntu line.

See `guest/spec.json`, `guest/packages.ubuntu.txt`,
`macos/prepare-qemu-gpu-runtime.sh`, and `macos/build-qemu-gpu-runtime.sh` for
exact source identities and checksums. Before distributing a release, follow
`docs/releasing.md` and audit the assembled bundle's notices and
corresponding-source obligations.
