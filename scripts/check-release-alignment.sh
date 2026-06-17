#!/usr/bin/env bash
# Verify that registry metadata is aligned with the latest public release.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

usage() {
  cat <<'EOF'
usage: scripts/check-release-alignment.sh [tag] [server-json]

Examples:
  scripts/check-release-alignment.sh
  scripts/check-release-alignment.sh v0.1.5 dist/server.mcpb-all.json

Without a tag, the script reads the latest GitHub Release. It then requires the
server metadata version to match that tag and delegates package existence/hash
checks to scripts/check-mcpb-release-assets.sh.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

tag="${1:-}"
server_json="${2:-server.json}"

if ! command -v gh >/dev/null 2>&1; then
  printf 'gh CLI is required for release alignment verification\n' >&2
  exit 2
fi

if [ -z "$tag" ]; then
  tag="$(
    gh release view \
      --repo maxbaluev/accreted-intelligence \
      --json tagName \
      --jq '.tagName'
  )"
fi

case "$tag" in
  v*) version="${tag#v}" ;;
  *) version="$tag"; tag="v$tag" ;;
esac

metadata_version="$(
  python3 - "$server_json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
print(data.get("version", ""))
PY
)"

fail=0
note() { printf '  %s\n' "$1"; }
bad() { note "$1"; fail=1; }

echo "== release alignment =="
note "release tag: $tag"
note "metadata: $server_json"
note "metadata version: ${metadata_version:-<missing>}"

if [ "$metadata_version" = "$version" ]; then
  note "version alignment: ok"
else
  bad "version alignment: expected server metadata version $version"
fi

if bash scripts/check-mcpb-release-assets.sh "$tag" "$server_json"; then
  note "release asset alignment: ok"
else
  fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "RELEASE ALIGNMENT: PASS"
else
  echo "RELEASE ALIGNMENT: FAIL"
fi
exit "$fail"
