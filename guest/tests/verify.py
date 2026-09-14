#!/usr/bin/env python3
"""Contract checks for the Ubuntu Mac factory build.

This suite pins the Ubuntu builder pipeline (plan2+), the runtime contract the
Mac launcher validates, and the guest integration surface. It replaces the
Arch/Ubuntu contract suite; the live-behavior checks exercise the guest
overlay scripts that ship in the factory image.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import py_compile
import stat
import subprocess
import tempfile
import time
from pathlib import Path

GUEST = Path(__file__).resolve().parents[1]
REPO = GUEST.parent


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def json_file(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    check(isinstance(value, dict), f"{path.name} contains a JSON object")
    return value


def encoded_share_name(name: str) -> str:
    return base64.urlsafe_b64encode(name.encode()).decode().rstrip("=")


def main() -> None:
    parser = argparse.ArgumentParser()
    args = parser.parse_args()

    spec = json_file(GUEST / "spec.json")
    check(spec.get("schemaVersion") == 2, "guest spec schema is supported")
    check(spec["image"]["architecture"] == "aarch64", "guest is ARM64-only")
    check(spec["guest"].get("profile") == "factory", "guest is an unprovisioned factory image")
    check(spec["guest"].get("username") is None, "factory image has no baked-in user")
    distribution = spec["distribution"]
    check(
        distribution["name"] == "Ubuntu"
        and distribution["release"].startswith("26.04.")
        and distribution["suite"] == "resolute"
        and distribution["architecture"] == "arm64"
        and distribution["debootstrapVariant"] == "minbase",
        "factory pins the Ubuntu 26.04 arm64 suite",
    )
    check(
        distribution["primaryMirror"].startswith("http")
        and distribution["fallbackMirror"].startswith("https")
        and distribution["primaryMirror"] != distribution["fallbackMirror"],
        "bootstrap records a primary and a verified fallback mirror",
    )
    core = distribution["corePackages"]
    check(
        set(core) == {
            "gdm3", "gnome-shell", "initramfs-tools", "linux-image-generic",
            "network-manager", "pipewire", "v4l2loopback-dkms", "wireplumber",
            "wl-clipboard",
        }
        and all(re.fullmatch(r"[0-9]+[:.][0-9][A-Za-z0-9.+~-]*", v) for v in core.values())
        and core["linux-image-generic"] == distribution["kernelMetaVersion"],
        "core ABI packages are version-pinned in the distribution section",
    )
    check(spec["runtime"]["virtualMachineMonitor"] == "qemu-system-aarch64", "runtime uses native ARM QEMU")
    check(spec["runtime"]["hypervisor"] == "hvf", "runtime uses Apple Hypervisor.framework")
    boot = spec["runtime"]["boot"]
    check(
        boot["abi"] == "qemu-arm64-uefi-direct-v1"
        and boot["kernelImageFormat"] == "pe32plus-efi-stub"
        and boot["firmware"]["mode"] == "pflash"
        and boot["firmware"]["varsPolicy"] == "ephemeral-per-run"
        and boot["firmware"]["code"] == "share/edk2-aarch64-code.fd"
        and boot["firmware"]["varsTemplate"] == "share/edk2-arm-vars.fd",
        "new kits boot through bundled UEFI firmware with ephemeral variables",
    )
    check(
        spec["runtime"]["network"].get("sshAccess")
        == {
            "activation": {
                "guestPort": 22,
                "kernelToken": "tryubuntu.ssh_access=1",
                "protocol": "tcp",
                "scope": "boot",
                "service": "sshd.service",
            },
            "preset": {
                "guestPort": 22,
                "hostAddress": "127.0.0.1",
                "hostPort": 2222,
                "protocol": "tcp",
            },
        },
        "SSH preset and boot activation are an exact loopback-only runtime contract",
    )
    check(spec["runtime"]["storage"]["expandedSizeMiB"] == 102400, "working disk expands to 100 GiB")
    check(set(spec["inputs"]) == {"packages"}, "spec has a minimal input set")
    for path in spec["inputs"].values():
        check((GUEST / path).is_file(), f"spec input exists: {path}")

    requested_packages = {
        line.strip().removeprefix("!")
        for line in (GUEST / spec["inputs"]["packages"]).read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    check(
        "!linux-image-generic" in (GUEST / spec["inputs"]["packages"]).read_text(),
        "kernel packages install without bootloader recommends (no GRUB in the factory)",
    )
    check(
        "linux-image-generic" in requested_packages and "linux-headers-generic" in requested_packages,
        "package set requests the ARM64 kernel with matching headers",
    )
    check(
        "v4l2loopback-dkms" in requested_packages and "wl-clipboard" in requested_packages,
        "package set requests the camera loopback module and Wayland clipboard tools",
    )
    check(
        "openssh-server" in requested_packages and "whiptail" in requested_packages,
        "package set ships the vendor sshd unit and the provisioning UI",
    )
    check(
        "ubuntu-desktop-minimal" in requested_packages and "gnome-terminal" in requested_packages,
        "package set requests the GNOME desktop",
    )

    required_paths = spec["authenticity"]["requiredPaths"]
    check(
        required_paths == sorted(required_paths)
        and all(not path.startswith("/") and ".." not in Path(path).parts for path in required_paths),
        "required guest paths are declared as sorted relative paths",
    )
    check(spec["authenticity"]["postBuildUserInstallers"] == [], "factory has no post-build installer boundaries")

    base_command_line = spec["runtime"]["kernelCommandLine"]
    for token in ("root=/dev/vda", "rw", "rootwait", "console=tty0", "console=hvc0"):
        check(base_command_line.split().count(token) == 1, f"base command line carries exactly one {token}")
    for owned in ("tryubuntu.qemu_virgl=", "tryubuntu.shared_folder_name=", "tryubuntu.ssh_access=", "tryubuntu.export_boot="):
        check(owned not in base_command_line, f"base command line leaves {owned} to the launcher")

    container = read(GUEST / "build-container.sh")
    check("linux/arm64" in container and '"$guest_dir/Containerfile"' in container, "container builder targets ARM64")
    check('output="$repo_dir/dist/guest"' in container, "guest output defaults to dist/guest")
    check("tryubuntu-guest-work" in container, "guest cache has a project-scoped Docker volume")
    check("--refresh-package-lock" not in container, "container wrapper has no Arch lock-refresh mode")

    containerfile = read(GUEST / "Containerfile")
    check(
        "FROM docker.io/library/ubuntu:26.04" in containerfile
        and 'test "$TARGETARCH" = arm64' in containerfile
        and "debootstrap e2fsprogs zstd python3" in containerfile
        and 'ENTRYPOINT ["/workspace/guest/build.sh"]' in containerfile,
        "guest builder is the pinned Ubuntu arm64 image with bootstrap tooling",
    )

    build = read(GUEST / "build.sh")
    check(
        'bootstrap_into "$primary_mirror"' in build
        and "bootstrap_into \"$fallback_mirror\"" in build
        and 'rm -rf "$root"' in build,
        "guest build debootstraps from the primary mirror with a full rootfs retry",
    )
    check(
        "URIs: $primary_mirror $fallback_mirror" in build
        and "$distribution_suite-updates $distribution_suite-security" in build,
        "staged root apt sources record both mirrors and the security suite",
    )
    check(
        build.index("apt-get update") < build.index("apt-get install")
        < build.index("configure-rootfs.sh")
        < build.index("finalize-rootfs")
        < build.index("dpkg-query")
        < build.index("pack-image.sh"),
        "guest build orders bootstrap, packages, configuration, manifest, and packing",
    )
    check("pacman" not in build, "guest build has no pacman path")

    configure = read(GUEST / "scripts/configure-rootfs.sh")
    check("machine-id" in configure and ': >"$root/etc/machine-id"' in configure, "factory image mints its identity on first boot")
    check("x-systemd.growfs" in configure and "filesystemUuid" in configure, "root filesystem grows online from the spec UUID")
    check("var/log/journal" in configure and "random-seed" in configure, "factory image scrubs logs and identity state")
    check("build-spec.json" in configure and "write-provenance.py" in configure, "rootfs embeds the build spec and provenance")

    finalizer = read(GUEST / "scripts/finalize-rootfs.sh")
    check("aarch64" in finalizer and "factory" in finalizer, "finalizer enforces the native factory contract")
    check("systemctl disable ssh.service ssh.socket" in finalizer, "vendor sshd stays off without the activation token")
    check("MODULES=list" in finalizer and "COMPRESS=zstd" in finalizer, "initramfs is deterministic, compressed, and minimal")
    for module in ("virtio_pci", "virtio_blk", "virtio_console", "9p", "9pnet_virtio", "ext4"):
        check(module in finalizer, f"initramfs carries the {module} module")
    check("graphical.target" in finalizer, "graphical default target with GDM")

    pack = read(GUEST / "scripts/pack-image.sh")
    check(
        "MZ" in pack and "PE\\x00\\x00" in pack and '"64aa"' in pack,
        "packer validates the PE32+ ARM64 kernel image",
    )
    check(
        "070701" in pack and "zstd -d" in pack and "gzip -d" in pack,
        "packer decompress-verifies the newc initramfs",
    )
    check(
        "mke2fs" in pack and "e2fsck -fn" in pack and "zstd" in pack,
        "packer builds and verifies the raw ext4 factory disk",
    )
    checksum_list = read(GUEST / "scripts/pack-image.sh")
    for artifact in ("build-spec.json", "guest-manifest.json", "initramfs-linux.img", "packages.lock.txt", "provenance.json", "rootfs.ext4", "rootfs.ext4.zst", "vmlinuz-linux"):
        check(artifact in checksum_list, f"SHA256SUMS covers {artifact}")
    check("guest-license" not in pack, "packer emits no legacy license artifact")

    manifest_writer = read(GUEST / "scripts/write-guest-manifest.py")
    check('"kind": "tryubuntu-guest-artifacts"' in manifest_writer, "new artifacts use the native manifest identity")
    check('spec["distribution"]["name"]' in manifest_writer, "manifest records the Ubuntu distribution")

    provenance_writer = read(GUEST / "scripts/write-provenance.py")
    check(
        '"packages.ubuntu.txt"' in provenance_writer and "overlay" in provenance_writer,
        "provenance records builder inputs and the overlay digest map",
    )

    check(
        spec["runtime"]["clipboard"]["port"] == "dev.tryomarchy.clipboard",
        "clipboard contract names the virtio port",
    )
    camera = spec["runtime"]["camera"]
    check(
        camera
        == {
            "activation": "on-demand",
            "device": "virtserialport",
            "framesPerSecond": 30,
            "guestDevice": "/dev/video42",
            "height": 720,
            "pixelFormat": "NV12",
            "port": "dev.tryomarchy.camera",
            "protocolVersion": 1,
            "width": 1280,
        },
        "camera contract exposes an on-demand 720p NV12 stream over virtio",
    )
    camera_launcher = read(REPO / "macos/run-qemu-gpu.sh")
    camera_entitlements = read(REPO / "macos/tryubuntu-vm-helper.entitlements")
    check(
        "virtserialport,bus=tryubuntu-serial.0,nr=4" in camera_launcher
        and "name=dev.tryomarchy.camera" in camera_launcher
        and "--bridge-native-camera" in camera_launcher
        and "camera_bridge_restarts < 5" in camera_launcher
        and "com.apple.security.device.camera" in camera_entitlements,
        "Mac launcher carries the camera entitlement and supervised virtio bridge",
    )
    shared_folder = spec["runtime"]["sharedFolder"]
    check(
        shared_folder["device"] == "virtio-9p-pci"
        and shared_folder["securityModel"] == "none"
        and shared_folder["guestOwnerUid"] == 1000
        and shared_folder["guestOwnerGid"] == 1000
        and shared_folder["mountTag"] == "mac"
        and shared_folder["guestMountPoint"] == "/mnt/mac"
        and shared_folder["guestLinkNameParameter"] == "tryubuntu.shared_folder_name"
        and "virtio-9p-pci" in spec["runtime"]["devices"],
        "shared folder contract maps Mac files to the first Ubuntu user over virtio-9p",
    )

    # Guest overlay surface (paths update with the plan4 overlay rename).
    ssh_generator_path = (
        GUEST
        / "native-overlay/usr/lib/systemd/system-generators/tryubuntu-ssh-access"
    )
    ssh_generator = read(ssh_generator_path)
    check(
        ssh_generator_path.is_file()
        and ssh_generator_path.stat().st_mode & stat.S_IXUSR != 0
        and "tryubuntu.ssh_access=1" in ssh_generator
        and "/proc/cmdline" in ssh_generator
        and "multi-user.target.wants" in ssh_generator
        and '"$wants/sshd.service"' in ssh_generator,
        "SSH generator requests only the boot-scoped vendor sshd unit",
    )

    audio_bridge = GUEST / "native-overlay/usr/local/bin/tryubuntu-native-audio-bridge"
    check(audio_bridge.stat().st_mode & stat.S_IXUSR != 0, "native audio bridge is executable")
    with tempfile.TemporaryDirectory() as temporary:
        py_compile.compile(str(audio_bridge), cfile=str(Path(temporary) / "audio.pyc"), doraise=True)
    check(True, "native audio bridge compiles")

    camera_bridge = GUEST / "native-overlay/usr/local/bin/tryubuntu-native-camera-bridge"
    check(camera_bridge.stat().st_mode & stat.S_IXUSR != 0, "native camera bridge is executable")
    with tempfile.TemporaryDirectory() as temporary:
        py_compile.compile(str(camera_bridge), cfile=str(Path(temporary) / "camera.pyc"), doraise=True)
    check(True, "native camera bridge compiles")
    camera_unit = read(GUEST / "native-overlay/usr/lib/systemd/user/tryubuntu-native-camera-bridge.service")
    camera_rule = read(GUEST / "native-overlay/etc/udev/rules.d/94-tryubuntu-native-camera.rules")
    camera_module = read(GUEST / "native-overlay/etc/modprobe.d/90-tryubuntu-camera.conf")
    check(
        "tryubuntu-native-camera-bridge" in camera_unit
        and "Restart=always" in camera_unit
        and 'ATTR{name}=="dev.tryomarchy.camera"' in camera_rule
        and 'KERNEL=="video42"' in camera_rule
        and "exclusive_caps=1" in camera_module,
        "camera service reconnects its virtio port to an exclusive-capability V4L2 device",
    )

    clipboard_bridge = GUEST / "native-overlay/usr/local/bin/tryubuntu-native-clipboard-bridge"
    check(clipboard_bridge.stat().st_mode & stat.S_IXUSR != 0, "native clipboard bridge is executable")
    with tempfile.TemporaryDirectory() as temporary:
        py_compile.compile(str(clipboard_bridge), cfile=str(Path(temporary) / "clipboard.pyc"), doraise=True)
    check(True, "native clipboard bridge compiles")
    clipboard_unit = read(GUEST / "native-overlay/usr/lib/systemd/user/tryubuntu-native-clipboard-bridge.service")
    check(
        "PartOf=graphical-session.target" in clipboard_unit
        and "ConditionPathExists=/dev/virtio-ports/dev.tryomarchy.clipboard" in clipboard_unit,
        "clipboard bridge follows the graphical session and its virtio port",
    )
    clipboard_rule = read(GUEST / "native-overlay/etc/udev/rules.d/92-tryubuntu-native-clipboard.rules")
    check(
        'ATTR{name}=="dev.tryomarchy.clipboard"' in clipboard_rule and 'GROUP="users"' in clipboard_rule,
        "clipboard port is readable by the provisioned users group",
    )
    mac_share = GUEST / "native-overlay/usr/local/bin/tryubuntu-native-mac-share"
    check(mac_share.stat().st_mode & stat.S_IXUSR != 0, "native Mac share mounter is executable")
    with tempfile.TemporaryDirectory() as temporary:
        temporary_path = Path(temporary)
        virtio_root = temporary_path / "9pnet_virtio"
        other = virtio_root / "virtio2"
        other.mkdir(parents=True)
        (other / "mount_tag").write_bytes(b"other\0")
        share = virtio_root / "virtio3"
        share.mkdir()
        (share / "mount_tag").write_bytes(b"mac\0")
        environment = os.environ.copy()
        environment["TRYUBUNTU_MAC_SHARE_VIRTIO_ROOT"] = str(virtio_root)
        found = subprocess.run(
            [str(mac_share), "--find-device"],
            text=True,
            env=environment,
            capture_output=True,
            check=True,
        )
        check(found.stdout.strip() == "virtio3", "Mac share mounter finds the virtio-9p device by mount tag")
        environment["TRYUBUNTU_MAC_SHARE_TAG"] = "absent"
        missing = subprocess.run(
            [str(mac_share), "--find-device"],
            text=True,
            env=environment,
            capture_output=True,
            check=False,
        )
        check(missing.returncode == 1 and missing.stdout == "", "Mac share mounter reports an absent share")

        cmdline = temporary_path / "cmdline"
        # "Wörk Files" as URL-safe base64 without padding, as the launcher emits it.
        cmdline.write_text("root=/dev/vda rw tryubuntu.qemu_virgl=1 tryubuntu.shared_folder_name=V8O2cmsgRmlsZXM\n")
        home = temporary_path / "home"
        (home / "Documents").mkdir(parents=True)
        (home / "OldName").symlink_to("/mnt/mac")
        environment["TRYUBUNTU_MAC_SHARE_CMDLINE"] = str(cmdline)
        environment["TRYUBUNTU_MAC_SHARE_ASSUME_MOUNTED"] = "1"
        environment["HOME"] = str(home)
        name = subprocess.run([str(mac_share), "--name"], text=True, env=environment, capture_output=True, check=True)
        check(name.stdout == "Wörk Files\n", "Mac share link name decodes from the kernel command line")
        for option_like_name in ("-n", "-e", "-E"):
            cmdline.write_text(
                f"root=/dev/vda rw tryubuntu.shared_folder_name={encoded_share_name(option_like_name)}\n"
            )
            decoded = subprocess.run(
                [str(mac_share), "--name"], text=True, env=environment, capture_output=True, check=True
            )
            check(
                decoded.stdout == f"{option_like_name}\n",
                f"Mac share link preserves option-like name {option_like_name}",
            )
        cmdline.write_text("root=/dev/vda rw tryubuntu.qemu_virgl=1 tryubuntu.shared_folder_name=V8O2cmsgRmlsZXM\n")
        subprocess.run([str(mac_share), "--link"], env=environment, check=True, capture_output=True)
        check(
            os.readlink(home / "Wörk Files") == "/mnt/mac" and not (home / "OldName").exists(),
            "Mac share link uses the Mac folder name and drops stale links",
        )
        cmdline.write_text("root=/dev/vda rw tryubuntu.shared_folder_name=RG9jdW1lbnRz\n")
        subprocess.run([str(mac_share), "--link"], env=environment, check=True, capture_output=True)
        check(
            os.readlink(home / "Documents") == "/mnt/mac" and not (home / "Wörk Files").exists(),
            "Mac share link replaces an empty xdg folder of the same name",
        )
        (home / "Documents").unlink()
        (home / "Documents").mkdir()
        (home / "Documents" / "keep.txt").write_text("keep")
        subprocess.run([str(mac_share), "--link"], env=environment, check=True, capture_output=True)
        check(
            (home / "Documents" / "keep.txt").exists() and os.readlink(home / "Mac") == "/mnt/mac",
            "Mac share link keeps a populated folder and falls back to ~/Mac",
        )
        cmdline.write_text("root=/dev/vda rw\n")
        check(
            subprocess.run([str(mac_share), "--name"], text=True, env=environment, capture_output=True, check=True).stdout == "Mac\n",
            "Mac share link name falls back to Mac without a launcher parameter",
        )

        # Sharing turned off: the link service still runs, drops every link to
        # the mount point, and gives back an xdg folder that a link displaced.
        (home / "Documents" / "keep.txt").unlink()
        (home / "Documents").rmdir()
        (home / "Documents").symlink_to("/mnt/mac")
        (home / ".config").mkdir()
        (home / ".config" / "user-dirs.dirs").write_text(
            'XDG_DESKTOP_DIR="$HOME/Desktop"\nXDG_DOCUMENTS_DIR="$HOME/Documents"\n'
        )
        environment["TRYUBUNTU_MAC_SHARE_ASSUME_MOUNTED"] = "0"
        subprocess.run([str(mac_share), "--link"], env=environment, check=True, capture_output=True)
        check(
            not (home / "Mac").is_symlink()
            and not (home / "Mac").exists()
            and (home / "Documents").is_dir()
            and not (home / "Documents").is_symlink(),
            "Mac share link cleanup runs without a mount and restores a displaced xdg folder",
        )

        # Existing non-XDG directories belong to the guest, even when empty.
        # Use ~/Mac as the fallback instead of deleting the existing folder.
        work = home / "Work"
        work.mkdir()
        cmdline.write_text(
            f"root=/dev/vda rw tryubuntu.shared_folder_name={encoded_share_name('Work')}\n"
        )
        environment["TRYUBUNTU_MAC_SHARE_ASSUME_MOUNTED"] = "1"
        subprocess.run([str(mac_share), "--link"], env=environment, check=True, capture_output=True)
        check(
            work.is_dir() and not work.is_symlink() and os.readlink(home / "Mac") == "/mnt/mac",
            "Mac share link preserves an empty non-xdg folder and falls back to ~/Mac",
        )
        environment["TRYUBUNTU_MAC_SHARE_ASSUME_MOUNTED"] = "0"
        subprocess.run([str(mac_share), "--link"], env=environment, check=True, capture_output=True)
        check(work.is_dir(), "Mac share cleanup leaves the preserved non-xdg folder intact")

        # Names beginning with two dots are valid Mac basenames and must be
        # included when stale links are removed.
        cmdline.write_text(
            f"root=/dev/vda rw tryubuntu.shared_folder_name={encoded_share_name('..Work')}\n"
        )
        environment["TRYUBUNTU_MAC_SHARE_ASSUME_MOUNTED"] = "1"
        subprocess.run([str(mac_share), "--link"], env=environment, check=True, capture_output=True)
        hidden_share = home / "..Work"
        check(
            hidden_share.is_symlink() and os.readlink(hidden_share) == "/mnt/mac",
            "Mac share link supports a name beginning with two dots",
        )
        environment["TRYUBUNTU_MAC_SHARE_ASSUME_MOUNTED"] = "0"
        subprocess.run([str(mac_share), "--link"], env=environment, check=True, capture_output=True)
        check(not hidden_share.exists() and not hidden_share.is_symlink(), "Mac share cleanup removes a ..-prefixed link")
        cmdline.write_text("root=/dev/vda rw\n")
        environment["TRYUBUNTU_MAC_SHARE_ASSUME_MOUNTED"] = "1"

        # Sharing turned off: --mount returns at once instead of polling for
        # a device that will never appear.
        environment["TRYUBUNTU_MAC_SHARE_TAG"] = "mac"
        started = time.monotonic()
        skipped = subprocess.run(
            [str(mac_share), "--mount"], text=True, env=environment, capture_output=True, check=False
        )
        check(
            skipped.returncode == 0
            and "sharing is off" in skipped.stderr
            and time.monotonic() - started < 2,
            "Mac share mount returns immediately when the launcher shares nothing",
        )
        check(
            subprocess.run([str(mac_share), "--enabled"], env=environment, check=False).returncode == 1,
            "Mac share reports sharing off without a launcher parameter",
        )
        cmdline.write_text("root=/dev/vda rw tryubuntu.shared_folder_name=RG9jdW1lbnRz\n")
        check(
            subprocess.run([str(mac_share), "--enabled"], env=environment, check=False).returncode == 0,
            "Mac share reports sharing on with a launcher parameter",
        )
    share_unit = read(GUEST / "native-overlay/usr/lib/systemd/system/tryubuntu-native-mac-share.service")
    check(
        "ExecStart=/usr/local/bin/tryubuntu-native-mac-share --mount" in share_unit
        and "Before=display-manager.service gdm.service" in share_unit,
        "Mac share mounts before the display manager",
    )
    link_unit = read(GUEST / "native-overlay/usr/lib/systemd/user/tryubuntu-native-mac-share-link.service")
    check(
        "ExecStart=/usr/local/bin/tryubuntu-native-mac-share --link" in link_unit
        and "ConditionPathIsMountPoint" not in link_unit,
        "Mac share link service runs at login even when nothing is mounted",
    )

    audio_input_helper = GUEST / "native-overlay/usr/bin/tryubuntu-audio-input-set-default"
    check(audio_input_helper.stat().st_mode & stat.S_IXUSR != 0, "native audio input helper is executable")

    shell_files = [
        GUEST / "test",
        mac_share,
        *GUEST.glob("*.sh"),
        *GUEST.glob("scripts/*.sh"),
    ]
    for path in sorted(set(shell_files)):
        subprocess.run(["bash", "-n", str(path)], check=True)
    check(True, f"{len(set(shell_files))} guest shell scripts pass bash syntax checks")

    forbidden_names = {"package.json", "package-lock.json", "next.config.ts", "vite.config.ts"}
    check(not any((REPO / name).exists() for name in forbidden_names), "repository has no web or Node build entrypoint")

    # Residue audit (plan10/plan11): every remaining legacy-era string in
    # the tree must be a frozen host-contract entry of
    # plan/residue-allowed.txt. The scanned token is assembled here so this
    # file does not contain it verbatim.
    allowed = [
        line.strip()
        for line in (REPO / "plan/residue-allowed.txt").read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    legacy_token = "om" + "archy"
    scan_roots = [GUEST, REPO / "macos", REPO / "scripts", REPO / "tests", REPO / "Makefile"]
    offenders = []
    for scan_root in scan_roots:
        paths = scan_root.rglob("*") if scan_root.is_dir() else [scan_root]
        for path in paths:
            if any(part in {".build", ".swiftpm", "dist", "__pycache__"} for part in path.parts):
                continue
            if not path.is_file() or path.suffix not in {
                ".sh", ".swift", ".py", ".plist", ".md", ".json", ".txt", ".applescript", ""
            }:
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for line in text.splitlines():
                if legacy_token not in line.lower():
                    continue
                if any(token in line for token in allowed):
                    continue
                offenders.append(f"{path}: {line.strip()[:120]}")
    check(
        not offenders,
        "no legacy residue outside the frozen contract allow-list: " + " | ".join(offenders[:4]),
    )

    print("native guest contract verified")


if __name__ == "__main__":
    main()
