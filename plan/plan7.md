# Plan 7 — GNOME desktop E2E (VirGL/mutter, HiDPI, all bridges)

Status: pending · Depends: plan6 · Est: 1–2 days (graphics debugging heavy)

## Goal

Install the real Ubuntu desktop in the factory image and verify the full integration matrix
that the release checklist demands — the things that make this app feel native: accelerated
graphics, window-resize/HiDPI, audio in/out switching, clipboard both ways, camera on demand,
shared folder, SSH.

## Tasks

- [ ] Add desktop to `guest/packages.ubuntu.txt` (plan2 decision deferred here):
      `ubuntu-desktop-minimal gdm3` (+ `whiptail` for provisioning if not already).
      Accept snapd arriving with it; document that snap seeding needs first-boot network
      (VM has NAT). Re-record pinned versions in the build log for plan8.
- [ ] Rebuild factory; boot via `make run`.
- [ ] **Graphics**: confirm mutter/GNOME Shell renders accelerated on `virtio-gpu-gl-pci`
      (`glxinfo -B` in guest shows `virgl`/ANGLE-Metal renderer string via the chain;
      `EGL_CLIENT_APIS` includes OpenGL_ES). If mutter falls back to llvmpipe, investigate
      `GSK_RENDERER=gl`, `MUTTER_DEBUG_FORCE_KMS_MODE`, or the guest mesa virgl driver path
      before touching the host — the host chain is proven from the Ubuntu build.
- [ ] **Display/HiDPI**: resize the QEMU window across a HiDPI boundary; confirm guest
      resolution follows the patched EDID (dynamic-display patch) and mutter picks a sane
      scale. If mutter mis-scales, evaluate a small `tryubuntu-native-display-sync` variant
      (parse EDID → `gnome-monitor-config`/busctl call) — only as a measured fallback.
- [ ] **Provisioning UX**: first boot → whiptail owner form on tty1 → GDM greeter → login to
      GNOME session. Verify the provisioning service disables itself and the second boot
      goes straight to GDM.
- [ ] **Audio**: output/input device switching from the guest (PipeWire remap endpoints
      appear as `omarchy_host_*` sinks/sources; switching propagates via the audio-routes
      files to the patched QEMU SDL backend); play/pause cycle with no dropouts (quantum
      conf ported); mic capture only-while-recording behavior.
- [ ] **Clipboard**: text + PNG both directions; paste a screenshot Mac→guest; repeat-copy
      echo suppression.
- [ ] **Camera**: GNOME Cheese or Firefox `getUserMedia` → Mac camera indicator lights up
      only during use; `/dev/video42` exclusive-caps behavior; stop → indicator off.
- [ ] **Shared folder**: choose a Mac folder on the start menu; confirm `~/<name>` link,
      create/delete files both sides, uid/gid 1000 ownership parity via the 9p patch.
- [ ] **SSH**: Add SSH preset → connect `ssh -p 2222 user@127.0.0.1` after provisioning;
      confirm loopback-only bind; confirm UDP-22 mapping does NOT enable sshd.
- [ ] **Sleep/wake**: close lid / Apple-menu sleep; VM pauses over QMP, resumes after wake
      without guest corruption (existing Swift tests cover logic; do one manual pass).
- [ ] **Reboot vs shutdown**: guest reboot stays in-app; shutdown closes the app.
- [ ] Record every result in `plan/plan7-notes.md` — this becomes the seed of the plan12
      release checklist.

## Acceptance criteria

- The matrix above passes (or has a documented, accepted fallback) on a fresh VM from the
  new factory.
- Idle CPU sane (~15% of a core ballpark — the GICv3 work should carry over; regression
  here means the guest is busy-looping, investigate GNOME timers/journal flush).

## Risks & notes

- GNOME Shell on virgl is the single biggest unknown of the whole conversion. Timebox the
  accelerated-render investigation; if it blocks, a documented fallback is
  `ubuntu-server` + lighter WM — but that changes the product; surface to the user first.
- `ubuntu-desktop-minimal` pulls snapd + NetworkManager-configured defaults; ensure
  provisioning-created user gets `sudo` and NM manages eth0 (slirp) out of the box.
- Wayland clipboard under GNOME uses the same wl-clipboard data-control protocol the bridge
  already speaks — low risk, but test PNG paths explicitly (GNOME screenshot → PNG).
