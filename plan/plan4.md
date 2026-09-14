# Plan 4 — Guest integration port (bridges, units, provisioning, kernel tokens)

Status: pending · Depends: plan3 · Est: 1–2 days

## Goal

Port every guest-side integration the host expects into a new Ubuntu overlay tree, and
rename the kernel command line tokens in the same pass. Deliverable: the plan3 image, rebuilt
with the overlay, activates clipboard/camera/audio bridges, mounts/links the 9p share,
honors `tryubuntu.ssh_access=1`, and creates a user account on first boot — all verified
against the manual QEMU boot from plan3.

## Component disposition (from the Ubuntu native-overlay)

| Ubuntu component | Ubuntu disposition |
| --- | --- |
| `tryubuntu-native-clipboard-bridge` (Python, wl-clipboard data-control) | **Port verbatim**, rename `tryubuntu-native-clipboard-bridge` |
| `tryubuntu-native-camera-bridge` (TOCM → v4l2loopback `/dev/video42`) | **Port verbatim** (pure Python/ctypes), rename |
| `tryubuntu-native-audio-bridge` (pactl remap endpoints) | **Port verbatim** (pipewire-pulse on Ubuntu exposes pactl), rename |
| `90-try-tryubuntu-quantum.conf` (PipeWire quantum 4096) | **Port** — fixes HDA DMA xruns on any distro |
| `tryubuntu-native-mac-share` (9p mount + home link) | **Port** — distro-neutral POSIX sh |
| `try-tryubuntu-ssh-access` systemd generator | **Port verbatim**, token renamed |
| `try-omarchy-boot-export` initcpio hook | **Not here** — plan5 (initramfs-tools port) |
| `tryubuntu-native-display-sync` (EDID → hyprctl) | **Drop** (GNOME/mutter follows EDID; plan7 verifies, re-adds a mutter variant only if needed) |
| `tryubuntu-native-cursor-restore` (hyprctl) | **Drop** (QEMU composes the cursor; Hyprland-specific) |
| `tryubuntu-screensaver` / `tryubuntu-theme-bg-switcher` overrides | **Drop** (Ubuntu-tree commands) |
| `tryubuntu-audio-input-set-default` (pactl source-output mover) | **Port** — still meaningful with the audio bridge |
| pacman pre-refresh hook, zram lzo-rle, bt-agent/fcitx5 guards, environment.d Wayland forcing, xdg-terminal-exec shim | **Drop** (Arch/Ubuntu-specific; GNOME is Wayland natively) |
| Wallpaper seeding into a themed directory | **Replace**: drop a default wallpaper into `/usr/local/share/tryubuntu/wallpaper.jpg`; GNOME default set via `gsettings` in provisioning (cosmetic, plan7) |

## Tasks

- [ ] Create `guest/native-overlay.ubuntu/` mirroring the old layout:
      `usr/local/bin/tryubuntu-native-{clipboard,camera,audio}-bridge`,
      `usr/lib/systemd/user/tryubuntu-native-*.service` (clipboard in
      `graphical-session.target.wants`; audio/camera in `default.target.wants` — same
      conditions: clipboard needs the Wayland socket, camera/audio don't),
      `etc/udev/rules.d/9{1,2,4}-tryubuntu-native-*.rules` (port grants + video node),
      `etc/modules-load.d/` + `etc/modprobe.d/` for v4l2loopback
      (`video_nr=42 card_label="Ubuntu Mac Camera" exclusive_caps=1 max_openers=10`),
      `etc/systemd/system/tryubuntu-native-mac-share.service` (Before=gdm.service),
      `usr/lib/systemd/user/tryubuntu-native-mac-share-link.service` (WantedBy=default.target).
- [ ] Kernel token rename, guest side: the mac-share unit and ssh generator now read
      `tryubuntu.shared_folder_name` and `tryubuntu.ssh_access=1`; the cursor/virgl token
      consumers are dropped, but record that the launcher still appends
      `tryubuntu.qemu_virgl=1` (renamed in plan6) for future use.
- [ ] First-boot provisioning replacement for `tryubuntu-provision-owner`:
      `tryubuntu-provision-owner.service` (Before=gdm.service, After=systemd-user-sessions.service)
      running a small POSIX-sh + whiptail TUI on tty1: username/full name/password →
      `useradd -m -G sudo,audio,video,input,users` → `passwd` → write
      `/var/lib/tryubuntu/provisioning/done` marker → disable itself. Ship the service
      enabled but gated on the marker's absence. (GNOME Initial Setup rejected: heavy,
      hard to automate headlessly; whiptail keeps parity with Ubuntu's owner flow.)
- [ ] Enable NetworkManager (systemd unit already ships on Ubuntu); ensure
      `systemd-resolved` default config untouched.
- [ ] Port `write-provenance.py` minimally now (verbatim/backported tree split is vacuous
      for Ubuntu — emit a manifest with the overlay digest only; full provenance is plan8).
- [ ] Rebuild via plan2/plan3 pipeline with overlay applied; boot manually (plan3 harness).

## Manual verification checklist (against manual QEMU boot)

- [ ] `ls /dev/virtio-ports/` shows `dev.tryomarchy.audio|clipboard|camera` (port names are
      host-side constants — they stay `tryomarchy`-named until plan11 decision; only kernel
      cmdline tokens rename now). Note this asymmetry in contract.md.
- [ ] With a fake host bridge (socat piped to a file) or the real v0.3.0 app running the VM:
      clipboard unit starts after graphical-session.target; audio bridge creates
      `omarchy_host_*` remap endpoints on catalog receipt; camera bridge primes
      `/dev/video42` black frame.
- [ ] `tryubuntu.shared_folder_name=<b64>` on cmdline → `/mnt/mac` mounted, `~/Work` linked.
- [ ] `tryubuntu.ssh_access=1` → generator symlinks vendor `ssh.service` into runtime wants;
      without token → absent.
- [ ] First boot shows provisioning TUI; account created; second boot skips it.

## Acceptance criteria

- All services listed above enabled in the image; image boots to GDM (or console if desktop
  deferred to plan7) with provisioning completed once.
- Contract-test groundwork: guest unit/integration python tests (`guest/tests/test_*.py`)
  for the three bridges port with renames (they are subprocess-stubbed and distro-neutral).

## Risks & notes

- v4l2loopback dkms must build against the pinned kernel at image build time; if dkms build
  is slow/fragile in the container, precompile in build.sh via `dkms install` inside the
  chroot and verify `modinfo v4l2loopback` in the staged root before packing.
- The bridge scripts' virtio port names stay `dev.tryomarchy.*` (host contract) — only the
  unit/renamed filenames change. Do not "helpfully" rename the ports here.
