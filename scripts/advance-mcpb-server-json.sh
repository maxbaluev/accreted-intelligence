#!/usr/bin/env bash
# Advance root server.json after release MCPB assets are uploaded and verified.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

usage() {
  cat <<'EOF'
usage: scripts/advance-mcpb-server-json.sh <tag> [generated-json]

Examples:
  scripts/advance-mcpb-server-json.sh v0.1.5 dist/server.mcpb-all.json
  ACC_ADVANCE_SERVER_JSON=1 scripts/advance-mcpb-server-json.sh v0.1.5

Default mode verifies uploaded release assets and prints the server.json diff.
Set ACC_ADVANCE_SERVER_JSON=1 only after owner approval to overwrite server.json.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

tag="${1:-}"
generated_json="${2:-dist/server.mcpb-all.json}"

if [ -z "$tag" ]; then
  usage >&2
  exit 2
fi

case "$tag" in
  v*) : ;;
  *) tag="v$tag" ;;
esac

if [ ! -f "$generated_json" ]; then
  printf 'generated metadata not found: %s\n' "$generated_json" >&2
  printf 'run: scripts/prepare-mcpb-release-assets.sh %s\n' "$tag" >&2
  exit 2
fi

echo "== verify uploaded MCPB assets before server.json advance =="
scripts/check-mcpb-release-assets.sh "$tag" "$generated_json"

echo "== proposed server.json diff =="
if cmp -s "$generated_json" server.json; then
  printf 'server.json already matches %s\n' "$generated_json"
else
  git diff --no-index -- server.json "$generated_json" || true
fi

if [ "${ACC_ADVANCE_SERVER_JSON:-0}" != "1" ]; then
  cat <<EOF

DRY RUN: server.json was not modified.
After owner approval and verified uploaded assets, run:

  ACC_ADVANCE_SERVER_JSON=1 scripts/advance-mcpb-server-json.sh $tag $generated_json

Then commit server.json and run:

  scripts/check-release-alignment.sh $tag server.json
EOF
  exit 0
fi

cp "$generated_json" server.json
echo "server.json updated from $generated_json"
scripts/check-release-alignment.sh "$tag" server.json
