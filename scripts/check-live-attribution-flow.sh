#!/usr/bin/env bash
# Verify the deployed web -> installer attribution stitch without mutating anything.
#
# The static verifier already proves prompt copies carry ACC_INSTALL_REF and
# ACC_INSTALL_SOURCE in the checked-out HTML. This wrapper downloads the live
# pages into a temporary tree, then runs the same verifier against that served
# HTML so post-deploy checks catch stale pages, CDN lag, or partial deploys.
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

base_url="${1:-${ACC_LIVE_SITE_URL:-https://accint.xyz}}"
base_url="${base_url%/}"

usage() {
  cat <<'EOF'
usage: scripts/check-live-attribution-flow.sh [base-url]

Examples:
  scripts/check-live-attribution-flow.sh
  scripts/check-live-attribution-flow.sh https://accint.xyz
  ACC_LIVE_SITE_URL=https://preview.example.com scripts/check-live-attribution-flow.sh

This is read-only. It downloads the live home and Reddit pages into a temporary
directory and reuses scripts/check-attribution-flow.js against that HTML.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  printf 'curl is required for live attribution verification\n' >&2
  exit 2
fi
if ! command -v node >/dev/null 2>&1; then
  printf 'node is required for live attribution verification\n' >&2
  exit 2
fi

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/reddit"

fetch_page() {
  local path="$1"
  local dest="$2"
  local url="${base_url}${path}"

  printf '  fetch: %s\n' "$url"
  curl -fsSL --max-time 20 "$url" >"$dest"
}

echo "== live attribution flow =="
printf '  base: %s\n' "$base_url"
fetch_page "/" "$tmp/index.html"
fetch_page "/reddit/" "$tmp/reddit/index.html"

(
  cd "$tmp" || exit 1
  node "$repo_root/scripts/check-attribution-flow.js"
)

echo "LIVE ATTRIBUTION FLOW: PASS"
