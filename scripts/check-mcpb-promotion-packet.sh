#!/usr/bin/env bash
# Build and verify the local MCPB promotion packet without uploading or advancing metadata.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

repo="${ACC_GROWTH_REPO:-maxbaluev/accreted-intelligence}"
tag="${1:-}"

usage() {
  cat <<'EOF'
usage: scripts/check-mcpb-promotion-packet.sh <tag>

Examples:
  scripts/check-mcpb-promotion-packet.sh v0.1.5

This is a local dry-run verifier for the MCPB release/MCP Registry promotion
step. It builds the ignored dist/ MCPB bundle, verifies local hashes and
generated registry metadata, confirms server.json was not modified, and prints
the owner-approved commands for upload, server.json advance, and registry
publish.

It refuses ACC_UPLOAD_MCPB_ASSETS=1 and ACC_ADVANCE_SERVER_JSON=1. It never
uploads release assets, overwrites server.json, dispatches workflows, or
publishes registry metadata.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ -z "$tag" ]; then
  usage >&2
  exit 2
fi

case "$tag" in
  v*) version="${tag#v}" ;;
  *) version="$tag"; tag="v$tag" ;;
esac

if [ "${ACC_UPLOAD_MCPB_ASSETS:-0}" = "1" ]; then
  printf 'refusing to run with ACC_UPLOAD_MCPB_ASSETS=1; this verifier is dry-run only\n' >&2
  exit 2
fi
if [ "${ACC_ADVANCE_SERVER_JSON:-0}" = "1" ]; then
  printf 'refusing to run with ACC_ADVANCE_SERVER_JSON=1; this verifier is dry-run only\n' >&2
  exit 2
fi

targets=(
  "aarch64-apple-darwin"
  "aarch64-unknown-linux-musl"
  "x86_64-unknown-linux-musl"
  "x86_64-pc-windows-msvc"
)

fail=0
note() { printf '  %s\n' "$1"; }
bad() { note "$1"; fail=1; }

server_before="$(sha256sum server.json | awk '{print $1}')"

echo "== MCPB promotion packet: $tag =="
note "repo: $repo"
note "mode: dry-run/no-upload/no-advance"

echo
echo "== build local MCPB upload bundle =="
ACC_UPLOAD_MCPB_ASSETS=0 scripts/prepare-mcpb-release-assets.sh "$tag"

server_after="$(sha256sum server.json | awk '{print $1}')"
echo
echo "== dry-run mutation check =="
if [ "$server_before" = "$server_after" ]; then
  note "server.json unchanged"
else
  bad "server.json changed during dry-run bundle build"
fi

echo
echo "== local MCPB sidecars =="
for target in "${targets[@]}"; do
  mcpb="dist/acc-mcp-${tag}-${target}.mcpb"
  sidecar="dist/acc-mcp-${tag}-${target}.sha256"
  if [ -f "$mcpb" ] && [ -f "$sidecar" ]; then
    sha256sum -c "$sidecar" || fail=1
  else
    bad "missing generated asset pair for $target"
  fi
done

echo
echo "== generated registry metadata =="
python3 - "$tag" "$version" "${targets[@]}" <<'PY'
import json
import sys
from pathlib import Path

tag = sys.argv[1]
version = sys.argv[2]
targets = sys.argv[3:]
metadata_path = Path("dist/server.mcpb-all.json")

if not metadata_path.exists():
    print("  METADATA: missing dist/server.mcpb-all.json")
    raise SystemExit(1)

data = json.loads(metadata_path.read_text())
failures = []

if data.get("version") != version:
    failures.append(f"version is {data.get('version')!r}, expected {version!r}")

packages = data.get("packages")
if not isinstance(packages, list):
    failures.append("packages is not a list")
    packages = []

expected_ids = {
    target: (
        "https://github.com/maxbaluev/accreted-intelligence/releases/download/"
        f"{tag}/acc-mcp-{tag}-{target}.mcpb"
    )
    for target in targets
}
seen_ids = set()

for package in packages:
    identifier = str(package.get("identifier", ""))
    seen_ids.add(identifier)
    name = identifier.rsplit("/", 1)[-1]
    matched_target = None
    for target, expected_identifier in expected_ids.items():
        if identifier == expected_identifier:
            matched_target = target
            break
    if matched_target is None:
        failures.append(f"unexpected package identifier {identifier!r}")
        continue

    sidecar = Path(f"dist/acc-mcp-{tag}-{matched_target}.sha256")
    if not sidecar.exists():
        failures.append(f"missing sidecar for {matched_target}")
        continue
    expected_sha = sidecar.read_text().split()[0]
    sha = str(package.get("fileSha256", ""))
    if sha != expected_sha:
        failures.append(f"{name!r} fileSha256 does not match local sidecar")

    transport = package.get("transport", {})
    if transport.get("type") != "stdio":
        failures.append(f"{name!r} transport is not stdio")

expected_id_set = set(expected_ids.values())
missing = expected_id_set - seen_ids
if missing:
    failures.append("missing package identifiers: " + ", ".join(sorted(missing)))
extra = seen_ids - expected_id_set
if extra:
    failures.append("extra package identifiers: " + ", ".join(sorted(extra)))

meta = data.get("_meta", {}).get("io.modelcontextprotocol.registry/publisher-provided", {})
if meta.get("packager") != "scripts/package-mcpb.sh":
    failures.append("publisher-provided packager metadata is missing")
if meta.get("releaseTargets") != targets:
    failures.append("publisher-provided releaseTargets do not match target order")

if failures:
    for failure in failures:
        print(f"  METADATA: {failure}")
    raise SystemExit(1)

print("  dist/server.mcpb-all.json: ok")
print(f"  version: {version}")
print(f"  packages: {len(packages)}")
PY
metadata_status=$?
if [ "$metadata_status" -ne 0 ]; then
  fail=1
fi

echo
echo "== mutation guards =="
if grep -q 'ACC_UPLOAD_MCPB_ASSETS' scripts/prepare-mcpb-release-assets.sh; then
  note "upload helper requires ACC_UPLOAD_MCPB_ASSETS"
else
  bad "upload helper guard missing"
fi
if grep -q 'ACC_ADVANCE_SERVER_JSON' scripts/advance-mcpb-server-json.sh; then
  note "server.json advance helper requires ACC_ADVANCE_SERVER_JSON"
else
  bad "server.json advance guard missing"
fi
if grep -q 'scripts/check-mcpb-release-assets.sh "v${version}" server.json' .github/workflows/publish-mcp.yml; then
  note "publish workflow checks uploaded release assets before auth/publish"
else
  bad "publish workflow release-asset guard missing"
fi
if grep -q 'bash scripts/check-release-alignment.sh' .github/workflows/publish-mcp.yml; then
  note "publish workflow checks latest release alignment"
else
  bad "publish workflow alignment guard missing"
fi

cat <<EOF

== owner-approved release commands ==
Run only after explicit owner approval for each external action:

  ACC_UPLOAD_MCPB_ASSETS=1 scripts/prepare-mcpb-release-assets.sh $tag
  scripts/check-mcpb-release-assets.sh $tag dist/server.mcpb-all.json
  scripts/advance-mcpb-server-json.sh $tag dist/server.mcpb-all.json
  ACC_ADVANCE_SERVER_JSON=1 scripts/advance-mcpb-server-json.sh $tag dist/server.mcpb-all.json
  git add server.json
  git commit -m "registry: advance MCPB metadata to $tag"
  bash scripts/check-growth-readiness.sh
  git push origin main
  gh workflow run publish-mcp.yml --repo $repo
  gh run list --workflow publish-mcp.yml --repo $repo --limit 3
EOF

echo
if [ "$fail" -eq 0 ]; then
  echo "MCPB PROMOTION PACKET: PASS"
else
  echo "MCPB PROMOTION PACKET: FAIL"
fi
exit "$fail"
