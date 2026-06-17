#!/usr/bin/env bash
# Verify that a GitHub Release has the MCPB assets referenced by server.json.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

usage() {
  cat <<'EOF'
usage: scripts/check-mcpb-release-assets.sh <tag> [server-json]

Examples:
  scripts/check-mcpb-release-assets.sh v0.1.5 dist/server.mcpb-all.json
  scripts/check-mcpb-release-assets.sh v0.1.4 server.json

Run after scripts/package-mcpb.sh and after uploading the generated .mcpb and
.sha256 assets to the GitHub Release. This script is read-only.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

tag="${1:-}"
server_json="${2:-server.json}"

if [ -z "$tag" ]; then
  usage >&2
  exit 2
fi

case "$tag" in
  v*) version="${tag#v}" ;;
  *) version="$tag"; tag="v$tag" ;;
esac

if ! command -v gh >/dev/null 2>&1; then
  printf 'gh CLI is required for release asset verification\n' >&2
  exit 2
fi

if [ ! -f "$server_json" ]; then
  printf 'server metadata not found: %s\n' "$server_json" >&2
  exit 2
fi

targets=(
  "aarch64-apple-darwin"
  "aarch64-unknown-linux-musl"
  "x86_64-unknown-linux-musl"
  "x86_64-pc-windows-msvc"
)

native_asset_for_target() {
  case "$1" in
    *-pc-windows-msvc) printf 'acc-%s-%s.zip' "$tag" "$1" ;;
    *) printf 'acc-%s-%s.tar.gz' "$tag" "$1" ;;
  esac
}

asset_names="$(
  gh release view "$tag" \
    --repo maxbaluev/accreted-intelligence \
    --json assets \
    --jq '.assets[].name'
)"

fail=0
note() { printf '  %s\n' "$1"; }
bad() { note "$1"; fail=1; }

has_asset() {
  printf '%s\n' "$asset_names" | grep -Fxq "$1"
}

echo "== release assets: $tag =="
if has_asset "sha256sums.txt"; then
  note "sha256sums.txt: present"
else
  bad "sha256sums.txt: MISSING"
fi

for target in "${targets[@]}"; do
  native="$(native_asset_for_target "$target")"
  mcpb="acc-mcp-${tag}-${target}.mcpb"
  sidecar="acc-mcp-${tag}-${target}.sha256"

  if has_asset "$native"; then note "$native: present"; else bad "$native: MISSING"; fi
  if has_asset "$mcpb"; then note "$mcpb: present"; else bad "$mcpb: MISSING"; fi
  if has_asset "$sidecar"; then note "$sidecar: present"; else bad "$sidecar: MISSING"; fi
done

echo "== release metadata: $server_json =="
python3 - "$server_json" "$tag" "$version" "${targets[@]}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
tag = sys.argv[2]
version = sys.argv[3]
targets = sys.argv[4:]
data = json.loads(path.read_text())
failures = []

if data.get("version") != version:
    failures.append(f"version is {data.get('version')!r}, expected {version!r}")

packages = data.get("packages")
if not isinstance(packages, list):
    failures.append("packages is not a list")
    packages = []

expected_names = {f"acc-mcp-{tag}-{target}.mcpb" for target in targets}
seen_names = set()

for package in packages:
    identifier = str(package.get("identifier", ""))
    name = identifier.rsplit("/", 1)[-1]
    seen_names.add(name)
    if name not in expected_names:
        failures.append(f"unexpected package identifier asset {name!r}")
    sha = str(package.get("fileSha256", ""))
    if len(sha) != 64 or any(ch not in "0123456789abcdef" for ch in sha):
        failures.append(f"invalid fileSha256 for {name!r}")
    transport = package.get("transport", {})
    if transport.get("type") != "stdio":
        failures.append(f"{name!r} transport is not stdio")

missing = expected_names - seen_names
if missing:
    failures.append("missing package entries: " + ", ".join(sorted(missing)))

if failures:
    for failure in failures:
        print(f"  METADATA: {failure}")
    raise SystemExit(1)

print("  server metadata: ok")
PY
metadata_status=$?
if [ "$metadata_status" -ne 0 ]; then
  fail=1
fi

echo "== local package hashes =="
for target in "${targets[@]}"; do
  sidecar="dist/acc-mcp-${tag}-${target}.sha256"
  if [ -f "$sidecar" ]; then
    if sha256sum -c "$sidecar"; then
      :
    else
      fail=1
    fi
  else
    note "$sidecar: not present locally (skip local hash check)"
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "MCPB RELEASE ASSETS: PASS"
else
  echo "MCPB RELEASE ASSETS: FAIL"
fi
exit "$fail"
