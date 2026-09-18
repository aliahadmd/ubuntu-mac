#!/bin/bash
# Download the Ubuntu Mac installer from Cloudflare R2 via ranged requests.
#
# Long-lived streaming downloads of the ~1.96 GB installer can be
# interrupted by intermediate networks; this script instead fetches the
# installer as 8 MiB ranges (each a short-lived request), retries failures,
# reassembles the parts, and verifies the result against a pinned SHA-256.
#
# Requirements: bash, curl. Works on macOS and Linux.
set -u

BASE_URL="https://ubuntu-mac-dl.aliahad.workers.dev/d/9a5637e26107c735c236e387d1051a7d/UbuntuMac-1.0.5-arm64.dmg"
# On some networks (DNS fake-IP modes, poisoned resolvers) the workers.dev
# name resolves badly and requests return 404s or die mid-transfer. When the
# default path fails, requests are re-pinned to real Cloudflare edge IPs.
EDGE_IPS=("172.67.163.117" "104.21.66.187")

resolve_real_ips() {
  local json
  json=$(curl -sS --max-time 15 -H "accept: application/dns-json" \
    "https://cloudflare-dns.com/dns-query?name=ubuntu-mac-dl.aliahad.workers.dev&type=A" 2>/dev/null) \
  || json=$(curl -sS --max-time 15 -H "accept: application/dns-json" \
    "https://dns.google/resolve?name=ubuntu-mac-dl.aliahad.workers.dev&type=A" 2>/dev/null) \
  || json=""
  if [ -n "$json" ]; then
    printf '%s\n' "$json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    for answer in data.get("Answer", []):
        if answer.get("type") == 1:
            print(answer["data"])
except Exception:
    pass' 2>/dev/null
  fi
}
TOTAL_SIZE=1958914013
EXPECTED_SHA256="3a9f362869c124eb83585b544e99325ef6cdbcaad8b67c300dfbe7182368b35b"
CHUNK_SIZE=$((8 * 1024 * 1024))
CHUNK_RETRIES=6
OUTPUT="${1:-UbuntuMac-1.0.5-arm64.dmg}"
PARTS_DIR="${OUTPUT}.parts"

say() { echo "download-ubuntu-mac: $*"; }

command -v curl >/dev/null || { say "curl is required"; exit 1; }

chunk_count=$(( (TOTAL_SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE ))
mkdir -p "$PARTS_DIR"

fetch_chunk() {
  local index=$1
  local start=$(( index * CHUNK_SIZE ))
  local end=$(( start + CHUNK_SIZE - 1 ))
  (( end >= TOTAL_SIZE )) && end=$(( TOTAL_SIZE - 1 ))
  local expect=$(( end - start + 1 ))
  local part="$PARTS_DIR/$(printf 'chunk-%04d' "$index")"
  local existing=0
  [ -f "$part" ] && existing=$(stat -c %s "$part" 2>/dev/null || stat -f %z "$part" 2>/dev/null || echo 0)
  [ "$existing" = "$expect" ] && return 0
  local try
  for try in $(seq 1 "$CHUNK_RETRIES"); do
    curl -sS --fail --max-time 600 --retry 2 -r "$start-$end" -o "$part" "$BASE_URL" && {
      local got
      got=$(stat -c %s "$part" 2>/dev/null || stat -f %z "$part" 2>/dev/null || echo 0)
      [ "$got" = "$expect" ] && return 0
    }
    say "chunk $index/$((chunk_count - 1)) failed (try $try/$CHUNK_RETRIES); retrying"
    sleep 3
  done
  say "chunk $index failed normally; retrying via pinned Cloudflare edge IPs"
  for edge in "${EDGE_IPS[@]}"; do
    curl -sS --fail --max-time 600 -r "$start-$end" -o "$part" \
      --resolve "ubuntu-mac-dl.aliahad.workers.dev:443:$edge" "$BASE_URL" && {
      local got2
      got2=$(stat -c %s "$part" 2>/dev/null || stat -f %z "$part" 2>/dev/null || echo 0)
      [ "$got2" = "$expect" ] && return 0
    }
    sleep 2
  done
  say "chunk $index could not be downloaded"
  return 1
}

say "downloading $TOTAL_SIZE bytes in $chunk_count chunks from Cloudflare R2"
index=0
while [ "$index" -lt "$chunk_count" ]; do
  fetch_chunk "$index" || exit 1
  index=$(( index + 1 ))
  case $(( index % 10 )) in 0) say "progress: $index/$chunk_count chunks";; esac
done

say "reassembling parts"
: > "$OUTPUT"
index=0
while [ "$index" -lt "$chunk_count" ]; do
  cat "$PARTS_DIR/$(printf 'chunk-%04d' "$index")" >> "$OUTPUT"
  index=$(( index + 1 ))
done

say "verifying SHA-256"
actual=$(sha256sum "$OUTPUT" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$OUTPUT" | awk '{print $1}')
if [ "$actual" = "$EXPECTED_SHA256" ]; then
  say "OK: $OUTPUT is verified"
  rm -rf "$PARTS_DIR"
else
  say "SHA-256 mismatch: expected $EXPECTED_SHA256, got $actual"
  say "deleting the bad download and its parts; run this script again"
  rm -f "$OUTPUT"
  exit 1
fi
