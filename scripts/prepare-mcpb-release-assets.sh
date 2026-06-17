#!/usr/bin/env bash
# Build MCPB release assets and optionally upload them after explicit approval.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

usage() {
  cat <<'EOF'
usage: scripts/prepare-mcpb-release-assets.sh <tag>

Examples:
  scripts/prepare-mcpb-release-assets.sh v0.1.5
  ACC_UPLOAD_MCPB_ASSETS=1 scripts/prepare-mcpb-release-assets.sh v0.1.5

Default mode is a dry run: build/verify dist assets and print the upload command.
Set ACC_UPLOAD_MCPB_ASSETS=1 only after owner approval to attach assets to the
GitHub Release.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

tag="${1:-}"
if [ -z "$tag" ]; then
  usage >&2
  exit 2
fi

case "$tag" in
  v*) : ;;
  *) tag="v$tag" ;;
esac

targets=(
  "aarch64-apple-darwin"
  "aarch64-unknown-linux-musl"
  "x86_64-unknown-linux-musl"
  "x86_64-pc-windows-msvc"
)

echo "== build MCPB assets: $tag =="
scripts/package-mcpb.sh "$tag" all

assets=()
for target in "${targets[@]}"; do
  mcpb="dist/acc-mcp-${tag}-${target}.mcpb"
  sidecar="dist/acc-mcp-${tag}-${target}.sha256"
  if [ ! -f "$mcpb" ] || [ ! -f "$sidecar" ]; then
    printf 'missing generated asset pair for %s\n' "$target" >&2
    exit 1
  fi
  sha256sum -c "$sidecar"
  assets+=("$mcpb" "$sidecar")
done

if [ ! -f dist/server.mcpb-all.json ]; then
  printf 'missing generated metadata: dist/server.mcpb-all.json\n' >&2
  exit 1
fi

echo "== upload command =="
printf 'gh release upload %q' "$tag"
for asset in "${assets[@]}"; do
  printf ' %q' "$asset"
done
printf ' --repo maxbaluev/accreted-intelligence --clobber\n'

if [ "${ACC_UPLOAD_MCPB_ASSETS:-0}" != "1" ]; then
  cat <<EOF

DRY RUN: no release assets were uploaded.
After owner approval, run:

  ACC_UPLOAD_MCPB_ASSETS=1 scripts/prepare-mcpb-release-assets.sh $tag

Then verify and advance registry metadata:

  scripts/advance-mcpb-server-json.sh $tag dist/server.mcpb-all.json
  ACC_ADVANCE_SERVER_JSON=1 scripts/advance-mcpb-server-json.sh $tag dist/server.mcpb-all.json
EOF
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  printf 'gh CLI is required for uploading release assets\n' >&2
  exit 2
fi

echo "== upload MCPB assets: $tag =="
gh release upload "$tag" "${assets[@]}" \
  --repo maxbaluev/accreted-intelligence \
  --clobber

echo "== verify uploaded MCPB assets =="
scripts/check-mcpb-release-assets.sh "$tag" dist/server.mcpb-all.json
