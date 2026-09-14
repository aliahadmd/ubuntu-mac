# Ubuntu Mac

Run a native Ubuntu desktop as a hardware-accelerated app on an Apple Silicon Mac.

Ubuntu Mac packages a project-built ARM64 Ubuntu 26.04.1 LTS (GNOME) image, a QEMU runtime
using Apple Hypervisor Framework, and a small Swift/AppKit launcher into one macOS app. The
image is built from the pinned Ubuntu archive (suite `resolute`) plus a reviewed overlay;
every network input is checksum-verified and mirrors are verified fallbacks.

> This project began as **Ubuntu Mac** (the Basecamp Ubuntu desktop in a VM); the guest
> was replaced with Ubuntu in the 2026 conversion. The Ubuntu line remains available in
> the repository history and as the v0.3.0 release of the previous line.

## Highlights

- Hardware-accelerated ARM64 virtualization and VirGL graphics
- Resizable native window with automatic guest resolution and HiDPI scale updates
- Mac audio input/output selection inside Ubuntu, with live routing and system-default fallback
- FaceTime HD and other Mac cameras exposed to Ubuntu as an on-demand 720p webcam
- Two-way clipboard sharing for text and PNG images between macOS and Ubuntu
- One optional shared Mac folder, available inside Ubuntu under the same name
- Loopback-only TCP and UDP port forwarding from the Mac into Ubuntu
- Boot-scoped opt-in SSH access (host port 2222 to guest port 22 by default)

## Quick start

1. Open [Releases](https://github.com/aliahadmd/ubuntu-mac/releases) and download the latest
   signed and notarized `.dmg`.
2. Open the DMG and drag **Ubuntu Mac** to **Applications**.
3. Launch **Ubuntu Mac** from Applications.

Every launch begins at the start menu. While that menu is open, the app behaves like a
regular Mac application; after the VM starts, the Ubuntu desktop takes over. **Immersive**
is on by default (Full Screen with the Mac menu bar and Dock hidden); turn it off for a
resizable window. The first launch prepares the VM disk and then shows the guest's
console-based account setup; after creating your Linux account, the GNOME desktop starts.

Restarting from inside Ubuntu reboots the VM in the same app. Shutting down Ubuntu closes
the app.

## Camera sharing

Choose **Allow…** next to **Camera access** on the start menu to make the Mac's FaceTime HD
camera available in Ubuntu as **Mac Camera**. The bridge publishes a standard Linux V4L2
camera at `/dev/video42`, so browser calls and Linux camera apps can use it without special
configuration. Capture is on demand: the Mac camera and its indicator turn on only while an
Ubuntu application is actively using the virtual camera. Denying camera permission does not
prevent Ubuntu from launching.

## Clipboard sharing

Copy and paste work in both directions once you sign in to Ubuntu: text and PNG images
copied on the Mac appear in the Ubuntu clipboard, and content copied in Ubuntu lands on the
Mac pasteboard. Nothing is transferred until something is copied.

## Sharing a folder with the Mac

Folder sharing is off until you pick a folder. Use **Choose…** next to **Shared folder** on
the start menu to select one Mac folder; Ubuntu links it into its home under the same name
(`~/Work` on the Mac becomes `~/Work` in Ubuntu) with full read and write access, so choose
a folder you intend Linux software to modify. The whole home folder, `~/Library`, and
system directories cannot be shared. **Turn Off** keeps the choice but stops exporting it
on the next launch. The share belongs to the first Ubuntu account created during
provisioning.

## Forwarding ports to Ubuntu

Use **Configure…** next to **Port forwarding** on the start menu to map a Mac localhost
port to a service port in Ubuntu. Each mapping can use TCP or UDP; the same Mac port may be
used once for each protocol. Forwarded ports bind only to `127.0.0.1`, so other devices on
the network cannot connect to them. The service inside Ubuntu must listen on `0.0.0.0` or
the guest network interface, not only on the guest's own localhost.

The reverse direction does not need a mapping. From Ubuntu, connect to `10.0.2.2:<Mac
port>` to reach a service running on the Mac.

### SSH access

After completing the guest account setup, open **Port forwarding**, choose **Add SSH**, and
save the prefilled TCP mapping from Mac port `2222` to Ubuntu port `22`. Ubuntu Mac then
requests `sshd` for boots that contain a TCP mapping to guest port 22; it does not change
guest accounts, SSH server configuration, or authorized keys.

```sh
ssh -p 2222 <guest-user>@127.0.0.1
```

Factory Reset creates a new guest host key, and every ephemeral VM has its own disposable
host key. If OpenSSH reports that the key for the reused endpoint changed, remove only that
endpoint's old entry:

```sh
ssh-keygen -R '[127.0.0.1]:2222'
```

Loopback binding prevents devices on Wi-Fi, Ethernet, or the wider LAN from connecting. It
does not isolate the listener from other users or processes on the same Mac; guest SSH
authentication is still required.

## Requirements

- Apple Silicon Mac (`arm64`)
- macOS 15 or newer
- At least 8 GB free initially

## Data and updates

Normal launches keep one persistent VM under
`~/Library/Application Support/Try Omarchy/VM/v1` (the storage path predates the Ubuntu
rename and is retained for compatibility). Removing or updating the app does not remove or
replace this data. An existing VM keeps both its writable disk and the exact kernel,
initramfs, and base command line that were paired with that disk. A newer app's bundled
factory image is used only to create a new VM, after a confirmed **Factory Reset**, or for
an ephemeral launch.

VMs created by the previous Ubuntu Mac releases keep booting their own preserved kernel
and initramfs; they are not migrated to Ubuntu. A confirmed Factory Reset (which requires
typing the app name exactly) creates a fresh Ubuntu VM from the bundled factory.

The guest's Ubuntu packages can be updated inside the VM with apt. The factory pins the
kernel and a reviewed core package set (recorded in `guest/spec.json` and the dpkg
manifest); a reset is the way to move an existing VM to a new factory image wholesale.

### Choosing where the VM lives

**Change…** on the start menu's **VM Location** row moves new VMs to any folder you pick,
including one on an external drive. The folder must be **empty** (or one the app already
used) and the drive must be **APFS**; the disk grows sparsely, which only APFS supports
reliably here. Changing the location never moves an existing VM.

## Development requirements

- Xcode command-line tools with Swift 6
- Python 3
- `pkg-config` (Homebrew is the simplest way to install it)
- A running Docker-compatible engine that supports privileged `linux/arm64` containers
- Roughly 20 GB free for guest, runtime, caches, and assembled output
- A network that can reach at least one of: `ports.ubuntu.com`,
  `mirrors.tuna.tsinghua.edu.cn`, plus the QEMU build inputs (see
  `plan/contract.md` for the verified mirror map and fallbacks)

`make doctor` performs the basic preflight. `make build` assembles the guest in privileged
ARM64 Docker, builds QEMU 11.1.1 for macOS 15.0 with VirGL/ANGLE graphics, compiles the
Swift launcher, and stages everything into `dist/app.noindex/`.

## Build and run

```sh
make build run
```

Later builds hash the effective inputs and validate the existing outputs, then rebuild only
the components that changed. `make test` runs the complete contract and native test suite;
`make help` lists component builds, persistent-storage reset, ephemeral mode, and cleanup.

For a complete local reset, first quit the app and then run `make clean-all` (interactive
confirmation required; it deletes persistent VM data).

## Repository layout

```text
.
├── Makefile                 public build interface
├── macos/                   Swift launcher and QEMU/HVF runtime builder
├── guest/                   reproducible Ubuntu ARM64 factory-image builder
├── plan/                    conversion plan series and verified contract
├── docs/                    architecture and release documentation
├── dist/                    generated output (ignored)
└── CONTRIBUTING.md, SECURITY.md, THIRD_PARTY_NOTICES.md, LICENSE
```

The architecture and trust boundaries are documented in
[`docs/architecture.md`](docs/architecture.md); the conversion contract in
[`plan/contract.md`](plan/contract.md). Contributors should start with
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Project status and support

Ubuntu Mac is pre-1.0 and under active development. Ubuntu and bundled dependencies retain
their own licenses; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Report ordinary
bugs through GitHub Issues and suspected vulnerabilities through
[`SECURITY.md`](SECURITY.md). Original code is licensed under the
[MIT License](LICENSE).

by [@aliahadmd1](https://x.com/aliahadmd1/)
