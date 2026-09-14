#!/usr/bin/env python3
"""Record the build inputs and overlay digests for the factory image.

The Ubuntu-era provenance model distinguished verbatim upstream trees from
hash-pinned backports. The Ubuntu factory has no upstream source tree: every
byte comes from the pinned distribution archive plus the project overlay, so
provenance is the digest of every builder input plus the overlay file map
(plan4 populates the overlay; plan8 extends verification).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

INPUT_FILES = [
    "Containerfile",
    "build.sh",
    "packages.ubuntu.txt",
    "scripts/configure-rootfs.sh",
    "scripts/finalize-rootfs.sh",
    "scripts/pack-image.sh",
    "scripts/write-guest-manifest.py",
    "scripts/write-provenance.py",
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--guest-dir", required=True, type=Path)
    parser.add_argument("--spec", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    spec = json.loads(args.spec.read_text())

    inputs = {}
    for name in INPUT_FILES:
        path = args.guest_dir / name
        if path.is_file():
            inputs[name] = sha256(path)

    overlay = {}
    for overlay_name in ("factory-overlay", "native-overlay"):
        overlay_root = args.guest_dir / overlay_name
        if not overlay_root.is_dir():
            continue
        files = {}
        for path in sorted(overlay_root.rglob("*")):
            if path.is_file() and not path.is_symlink():
                files[path.relative_to(overlay_root).as_posix()] = sha256(path)
        overlay[overlay_name] = files

    payload = {
        "schemaVersion": 1,
        "kind": "tryubuntu-guest-provenance",
        "distribution": spec["distribution"],
        "build": {
            "builderImageDigest": os.environ.get("TRYUBUNTU_BUILDER_IMAGE_DIGEST"),
            "sourceDateEpoch": spec["image"]["sourceDateEpoch"],
        },
        "inputs": inputs,
        "overlay": overlay,
    }
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
