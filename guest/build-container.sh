#!/bin/bash

set -euo pipefail

fail() {
  echo "guest-container-build: $*" >&2
  exit 1
}

guest_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(cd "$guest_dir/.." && pwd)
spec="$guest_dir/spec.json"
output="$repo_dir/dist/guest"
work_volume=""
dry_run=0

while (($#)); do
  case "$1" in
    --output)
      output=${2:-}
      shift 2
      ;;
    --work-volume)
      work_volume=${2:-}
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: guest/build-container.sh [options]

  --output DIR                   Artifact directory (default: dist/guest)
  --work-volume NAME             Persistent Docker build/cache volume
  --dry-run                      Print the selected immutable build plan
USAGE
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -f $spec ]] || fail "spec not found: $spec"
container_spec=/workspace/guest/spec.json
plan_fields=$(python3 - "$spec" <<'PY'
import json
import pathlib
import sys

spec = json.loads(pathlib.Path(sys.argv[1]).read_text())
architecture = spec["image"]["architecture"]
profile = spec["guest"].get("profile")
if architecture != "aarch64":
    raise SystemExit(f"ARM builder requires an aarch64 spec, got {architecture}")
if profile != "factory":
    raise SystemExit(f"native guest requires the factory profile, got {profile}")
print(f"{architecture}\t{profile}")
PY
) || fail "invalid native guest spec"
IFS=$'\t' read -r architecture profile <<<"$plan_fields"
[[ -n $architecture && -n $profile ]] || fail "could not read ARM64 build spec"

if [[ -z $work_volume ]]; then
  repo_checksum=$(printf '%s' "$repo_dir" | cksum)
  repo_checksum=${repo_checksum%% *}
  work_volume="tryubuntu-guest-work-$repo_checksum"
fi
[[ $work_volume =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || fail "invalid Docker volume name: $work_volume"

if (( dry_run )); then
  printf 'architecture=%s\nplatform=linux/arm64\nprofile=%s\nspec=%s\noutput=%s\nwork-volume=%s\nmode=build\n' \
    "$architecture" "$profile" "$spec" "$output" "$work_volume"
  exit 0
fi

command -v docker >/dev/null || fail "docker is required"

builder_image=tryubuntu-guest-builder
docker build --platform linux/arm64 -f "$guest_dir/Containerfile" -t "$builder_image" "$repo_dir"
builder_digest=$(docker image inspect --format '{{.Id}}' "$builder_image")

mkdir -p "$output"
output=$(cd "$output" && pwd)
docker volume create --label dev.tryubuntu.role=guest-work "$work_volume" >/dev/null
docker run --rm --platform linux/arm64 --privileged \
  -e TRYUBUNTU_BUILDER_IMAGE_DIGEST="$builder_digest" \
  -v "$repo_dir:/workspace:ro" \
  -v "$output:/output" \
  -v "$work_volume:/work" \
  "$builder_image" \
  --spec "$container_spec" --output /output --work /work
