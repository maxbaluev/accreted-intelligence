#!/usr/bin/env bash
# Verify deployed llms.txt discovery wiring without mutating anything.
#
# The static metadata verifier proves the checked-out files are aligned. This
# wrapper downloads the served home/Reddit pages, robots.txt, sitemap.xml, and
# llms.txt so post-deploy checks catch stale pages, CDN lag, or a missing
# discovery file.
set -euo pipefail

base_url="${1:-${ACC_LIVE_SITE_URL:-https://accint.xyz}}"
base_url="${base_url%/}"
canonical_url="${ACC_CANONICAL_SITE_URL:-https://accint.xyz}"
canonical_url="${canonical_url%/}"
llms_url="${canonical_url}/llms.txt"

usage() {
  cat <<'EOF'
usage: scripts/check-live-llms-discovery.sh [base-url]

Examples:
  scripts/check-live-llms-discovery.sh
  scripts/check-live-llms-discovery.sh https://accint.xyz
  ACC_LIVE_SITE_URL=https://preview.example.com scripts/check-live-llms-discovery.sh

This is read-only. It downloads live discovery files and checks that the
deployed site advertises and serves the llms.txt agent-discovery surface with
attributed install refs and the public/private trust boundary.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  printf 'curl is required for live llms.txt verification\n' >&2
  exit 2
fi

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/reddit"

fetch_path() {
  local path="$1"
  local dest="$2"
  local url="${base_url}${path}"

  printf '  fetch: %s\n' "$url"
  curl -fsSL --max-time 20 "$url" >"$dest"
}

require_marker() {
  local file="$1"
  local marker="$2"
  local context="$3"

  if ! grep -Fq "$marker" "$file"; then
    printf 'LIVE LLMS DISCOVERY: %s: missing %s\n' "$context" "$marker" >&2
    exit 1
  fi
}

echo "== live llms.txt discovery =="
printf '  base: %s\n' "$base_url"
printf '  canonical llms: %s\n' "$llms_url"

fetch_path "/" "$tmp/index.html"
fetch_path "/reddit/" "$tmp/reddit/index.html"
fetch_path "/robots.txt" "$tmp/robots.txt"
fetch_path "/sitemap.xml" "$tmp/sitemap.xml"
fetch_path "/llms.txt" "$tmp/llms.txt"

alternate_link="<link rel=\"alternate\" type=\"text/plain\" href=\"${llms_url}\" title=\"llms.txt\">"
require_marker "$tmp/index.html" "$alternate_link" "home alternate link"
require_marker "$tmp/reddit/index.html" "$alternate_link" "reddit alternate link"
require_marker "$tmp/robots.txt" "LLMs: ${llms_url}" "robots.txt"
require_marker "$tmp/sitemap.xml" "<loc>${llms_url}</loc>" "sitemap.xml"

require_marker "$tmp/llms.txt" "# AccInt" "llms.txt title"
require_marker "$tmp/llms.txt" "local-first Work Model" "llms.txt positioning"
require_marker "$tmp/llms.txt" "Claude Code, Codex, Cursor, and OpenCode" "llms.txt host fit"
require_marker "$tmp/llms.txt" "ACC_INSTALL_REF=llms-txt" "llms.txt POSIX attribution"
require_marker "$tmp/llms.txt" "\$env:ACC_INSTALL_REF='llms-txt'" "llms.txt PowerShell attribution"
require_marker "$tmp/llms.txt" "ref=llms-txt&utm_source=llm&utm_campaign=discovery" "llms.txt source attribution"
require_marker "$tmp/llms.txt" "Public Apache-2.0 installer, docs, plugins, and registry glue" "llms.txt source boundary"
require_marker "$tmp/llms.txt" "Proprietary local engine binary" "llms.txt private engine boundary"
require_marker "$tmp/llms.txt" "Telemetry excludes prompts, files, memory, and Work Model data" "llms.txt telemetry boundary"
require_marker "$tmp/llms.txt" "owner approval" "llms.txt approval boundary"

echo "LIVE LLMS DISCOVERY: PASS"
