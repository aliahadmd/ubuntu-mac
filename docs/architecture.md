# Architecture

Ubuntu Mac packages three pieces into one macOS app:

1. A small Swift/AppKit launcher for the macOS side.
2. A patched QEMU runtime that creates and runs the virtual machine.
3. An ARM64 Ubuntu 26.04.1 LTS (GNOME) image built from the pinned Ubuntu archive.

```text
Ubuntu Mac.app
└── Swift/AppKit launcher
    └── QEMU + Apple Hypervisor Framework
        └── project-built ARM64 Linux image
            └── Ubuntu GNOME desktop
```

## What happens when the app opens

The Swift launcher presents a start menu on every app open. It reports optional
macOS Accessibility, Microphone, and Camera permission state, handles confirmed factory
resets, startup, shutdown, and host audio devices. It prepares a writable copy
of the Linux disk and starts QEMU. QEMU's Cocoa input layer uses the shared
Accessibility grant to capture system-wide Command chords and deliver Command
as guest Super. Swift does not replace QEMU or run the Ubuntu desktop itself.

QEMU presents the hardware that Linux expects: CPUs, memory, storage, networking,
graphics, audio, keyboard, and pointer devices. Because both the Mac and the
guest are ARM64, Apple Hypervisor Framework runs the guest CPU instructions on
the Apple Silicon processor. QEMU provides the virtual devices around that CPU.

Linux then boots from the selected VM disk and its paired kernel and initramfs,
and Ubuntu runs inside Linux. For a new, reset, or ephemeral VM, that pair and
the disk originate in the current app's bundled factory. An existing persistent
VM instead keeps the boot pair created with its disk, even after the app bundle
is updated. Graphics travel from Linux through virtio-gpu and VirGL to the
native Cocoa window. Storage, networking, audio, and input use their matching
QEMU virtual devices and host backends.

The macOS helper opens an authenticated connection to QEMU's private,
single-client machine protocol socket before host sleep and retains that control
session through wake. Before macOS sleeps it synchronously pauses the guest
vCPUs, and after wake it resumes them only when that sleep handler observed the
pause transition. The bundled Cocoa runtime removes its in-process Pause and
Resume menu actions because they cannot participate in QMP connection
ownership. Abnormal QEMU states such as an I/O error are never overridden. This
preserves in-memory guest state across lid close while leaving safety stops
untouched.

One small host-integration channel sits beside those devices. A virtio-serial
port (`dev.tryomarchy.clipboard`) carries newline-delimited JSON between a
Swift bridge on the Mac, which watches the `NSPasteboard` change count, and a
Python agent in the Ubuntu session, which uses wl-clipboard's data-control
protocol. Text and PNG payloads flow both ways; each side remembers the
fingerprint of what it last wrote so the immediate echo is dropped. The marker
is cleared as soon as the other side moves on to new content, and expires after
a couple of seconds regardless, so a genuine repeat of the same content still flows.

A separate virtio-serial port (`dev.tryomarchy.camera`) carries fixed-size
1280×720 NV12 frames from an AVFoundation bridge in the signed Mac helper. The
guest feeds those frames into an exclusive-capabilities `v4l2loopback` device,
`/dev/video42`, labeled **Mac Camera**. The guest subscribes to the loopback
driver's client-usage events and requests capture only while a Linux application
is reading the camera. Camera permission, capture failure, or device removal is
non-fatal to the VM; the launcher can restart the optional bridge without
restarting Ubuntu.

When a folder is chosen on the start menu, QEMU exports it over virtio-9p with
`security_model=none`, so every host file operation runs as the Mac user and
the Mac keeps real modes and ownership. A small QEMU patch adds
`guest_owner_uid`/`guest_owner_gid` fsdev options that report the Mac user's
files as the first Ubuntu account (uid/gid 1000), which makes the guest
kernel's permission checks agree with what the host will actually allow. The
guest mounts the tag at `/mnt/mac` before the display manager starts, and a
user unit links `~/<folder name>` to it at login; the name travels on the
kernel command line as `omarchy.shared_folder_name=<base64url>`.

Optional port mappings are stored as a versioned launcher preference, validated
again at every Swift-to-shell boundary, and translated into QEMU user-network
`hostfwd` rules. The host side is always bound explicitly to `127.0.0.1`; the
launcher never creates wildcard or LAN-facing listeners. TCP and UDP occupy
separate host-port namespaces, matching QEMU's socket behavior.

**Add SSH** inserts an ordinary `tcp:2222:22` mapping into that same preference;
there is no second SSH forwarding store or QEMU argument path. After the shell
parser accepts the complete mapping list, any TCP rule targeting guest port 22
also adds the fixed `tryomarchy.ssh_access=1` boot token. UDP port 22 and other
guest ports do not. A guest systemd generator consumes only that exact token and
adds the vendor `sshd.service` to the current boot's runtime wants directory,
without modifying persistent systemd or SSH configuration.

SSH host keys belong to the writable guest disk. Persistent compatible VMs keep
them; Factory Reset and each ephemeral disk generate new keys. Reusing the same
Mac endpoint after either operation can require removing that endpoint from the
Mac's `known_hosts`. Loopback prevents LAN access but other local Mac processes
and users can still attempt authentication.

## The ARM64 image

The guest image is built by this project from the Ubuntu archive; it is not an
official Canonical image. The `guest/` builder debootstraps the pinned suite
(`resolute`, the 26.04.1 point release) from a primary mirror with a verified
fallback, installs a reviewed package list (`guest/packages.ubuntu.txt`), applies
the project's integration overlay, and packs a single raw ext4 image. Every
build records the complete dpkg manifest, and a small core set of packages is
version-pinned in `guest/spec.json`.

The image boots through the UEFI firmware bundled with the app runtime
(`edk2-aarch64-code.fd` + an ephemeral per-run copy of `edk2-arm-vars.fd`),
with the kernel and initramfs passed over fw_cfg as direct-kernel boot. The
Ubuntu arm64 kernel is a PE32+ EFI-stub image; that boot method is the new
factory's ABI (`qemu-arm64-uefi-direct-v1`, documented in
`plan/contract.md`). VMs created by the Ubuntu-era releases keep their raw
Image kits and continue to boot with plain `-kernel` (`qemu-arm64-direct-v1`).

The image has no preconfigured user. On first boot a console form creates the
owner account (username, password) before the display manager starts; that
account is the target of every Mac integration (uid 1000).

## What this project changes

- The Swift code is a separate macOS launcher and helper.
- A few QEMU C and Objective-C files are patched before QEMU is compiled. These
  patches cover the Cocoa app identity, display behavior, graphics integration,
  host audio-device routing, and shared-folder ownership mapping.
- The guest overlay adds the QEMU and ARM64 integration around stock Ubuntu:
  the clipboard, camera, and audio bridges; the 9p shared-folder mount/link
  units; the boot-scoped SSH-access generator; the PipeWire quantum override
  for the emulated HDA ring; the first-boot owner provisioner; and the
  initramfs boot-export hook used for one-time legacy VM migration. Virtio
  serial port names (`dev.tryomarchy.*`) and the recovery marker strings are
  frozen cross-version contracts.
- The default wallpaper is set for the provisioned account during first boot.
- The guest normally consumes Ubuntu archive packages. The factory pins the
  kernel and core integration packages in `guest/spec.json`; the complete dpkg
  manifest ships as provenance. `IgnorePkg`-style protection is not needed: apt
  holds nothing, and the direct-boot kernel ABI is validated at every launch.
- Guest apt sources carry the primary mirror and the verified fallback mirror,
  so the VM survives one mirror being unreachable.

Nothing is overwritten while the app runs. The app bundle and packaged factory
disk remain unchanged. Normal user launches use one private writable disk under
the app's Application Support directory. The disk metadata retains the identity
of the factory that created it, and `boot/<identity>/` retains a validated copy
of that VM's kernel, initramfs, and base command line. Normal launch selects
those saved boot files instead of combining an older root filesystem with a
newer bundled kernel. Consequently, a new app release can launch the existing
VM without decompressing, cloning, expanding, or charging free space for its new
factory disk.

The current bundled factory applies only when no persistent VM exists, after an
explicitly confirmed reset, or in ephemeral mode. New and reset VMs atomically
stage the current factory's boot kit with the new writable disk. A compatible
legacy identity-keyed disk can be migrated into the single workspace without
discarding its contents. If several recognized legacy disks exist, normal
launch stops at the start menu; confirmed reset safely removes them before
publishing one fresh workspace. Unrecognized host files are always left
untouched.

Older VMs that predate saved boot kits go through a one-time consent-gated
recovery boot: the storage launcher selects and locks the old disk and exits
before QEMU starts; the Mac app explains the transition and offers **Cancel**
or **Continue**; only Continue retries with a one-launch recovery
authorization. The authorized recovery boots the old disk read-only with the
current factory's initramfs, exports the disk's installed kernel and initramfs
over a private virtio-9p share, and powers off without switching into the old
userspace. The host accepts the pair only after validating its type, size,
hashes, ownership, and boot ABI, then stores it atomically for subsequent
launches. Cancel does not start recovery, reset the VM, or alter its disk
contents. Unsupported storage or boot ABIs still require a confirmed reset.

The workspace does not have to live in Application Support. The start menu can
put it in any folder the user picks, including one on an external drive, and
the launcher receives that choice as `TRYUBUNTU_QEMU_GPU_STATE_ROOT`. The chosen
folder is used as-is, must already be empty (or already be a workspace the app
has used), and must sit on a local APFS volume: the storage library clones the
factory image with `cp -c`, expands the working disk sparsely, and serializes
launches with a `lockf` advisory lock. A location change never moves the
existing VM; unrecognized host files stay untouched, as everywhere else here.

## Build layout

- `guest/` reproducibly assembles the unprovisioned ARM64 image in a privileged
  ARM64 Docker container. Inputs are commit-, version-, and checksum-pinned.
- `macos/` builds the Swift launcher and a patched QEMU runtime. The runtime is
  isolated, relocated, and signed before it enters the app bundle.
- `dist/` is the only public output directory. It is generated and ignored by
  Git.

## Trust model

The app validates the bundled factory's exact file set, JSON schemas, hashes,
sizes, distribution identity, runtime contract, kernel command line, kernel
image format, architecture, and factory profile. For an existing VM it
independently validates the saved boot kit's ABI, metadata, ownership, sizes,
and hashes before QEMU starts, and selects the matching boot method (UEFI
firmware for new PE kits, plain direct boot for legacy raw Image kits). The
overlay's file digests and the builder inputs are recorded in
`provenance.json`; the dpkg manifest records the complete resolved package
closure. The app also verifies the app signature and required QEMU features.
Updates to a pinned dependency should update its digest, contract tests,
notices, and review evidence together.

App releases and guest updates are deliberately separate channels. Ordinary
Ubuntu packages inside the VM may advance with apt, but the direct-boot kernel,
matching headers, and the reviewed core integration set remain pinned in the
factory; reusing a disk therefore does not silently import a newer app's
factory contents. Moving an existing VM to a new factory requires an explicitly
confirmed reset.

The guest image contains no secrets and no user account: root is locked, the
machine identity is minted on first boot, journals and random seeds are
scrubbed, and no SSH host keys ship. Everything identity-related belongs to the
first-boot provisioning form.

Optional, user-initiated installs inside the guest are the user's decision and
outside factory provenance; the factory ships none.
