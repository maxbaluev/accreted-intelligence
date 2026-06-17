#!/usr/bin/env bash
# Approval-gated live installer attribution receipt proof.
#
# Default mode is dry-run: run local preflight checks and print the exact approved
# command. Set ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1 only after owner approval.
# Approved mode fetches the live POSIX /install script, runs it in an isolated
# temp home with ACC_INSTALL_ATTRIBUTION_ONLY=1, and asserts the receipt. It does
# not perform a full install, start daemons, write to the operator's real acc
# home, send telemetry, post, comment, submit, pay, or use account identity.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

site_url="${ACC_LIVE_SITE_URL:-https://accint.xyz}"
site_url="${site_url%/}"
install_url="${ACC_LIVE_INSTALL_URL:-$site_url/install}"
tag="${1:-}"
ref_override="${ACC_CONTROLLED_INSTALL_REF:-}"
source_ref="${ACC_CONTROLLED_INSTALL_SOURCE:-ref=controlled-rollout}"
repo_url="${ACC_CONTROLLED_INSTALL_REPO:-https://github.com/maxbaluev/accreted-intelligence.git}"

usage() {
  cat <<'EOF'
usage: scripts/run-approved-controlled-live-install.sh [tag]

Dry-run default:
  scripts/run-approved-controlled-live-install.sh v0.1.6

Owner-approved live receipt proof:
  ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1 scripts/run-approved-controlled-live-install.sh v0.1.6

Optional:
  ACC_LIVE_SITE_URL=https://accint.xyz
  ACC_LIVE_INSTALL_URL=https://accint.xyz/install
  ACC_CONTROLLED_INSTALL_REF=controlled-0.1.6
  ACC_CONTROLLED_INSTALL_SOURCE=ref=controlled-rollout
  ACC_CONTROLLED_INSTALL_REPO=https://github.com/maxbaluev/accreted-intelligence.git
  ACC_KEEP_CONTROLLED_INSTALL_TMP=1

Approved mode runs only the attribution-receipt stop path:
  ACC_INSTALL_ATTRIBUTION_ONLY=1

It does not run a full install, send telemetry, post, comment, submit, pay, or
use account identity.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

server_version="$(
  python3 - <<'PY'
import json
from pathlib import Path

print(json.loads(Path("server.json").read_text()).get("version", ""))
PY
)"

if [ -z "$tag" ]; then
  tag="v${server_version}"
fi
case "$tag" in
  v*) : ;;
  *) tag="v$tag" ;;
esac

if [ -n "$ref_override" ]; then
  ref="$ref_override"
else
  ref="controlled-${tag#v}"
fi

note() { printf '  %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; exit 1; }

assert_line() {
  local file="$1" line="$2"
  grep -Fx "$line" "$file" >/dev/null 2>&1 || {
    printf 'receipt contents (%s):\n' "$file" >&2
    sed 's/^/    /' "$file" >&2 || true
    fail "missing line: $line"
  }
}

assert_receipt() {
  local file="$1"
  [ -f "$file" ] || fail "live receipt missing: $file"
  assert_line "$file" "ref=$ref"
  assert_line "$file" "source_ref=$source_ref"
  assert_line "$file" "source=ACC_INSTALL_REF+ACC_INSTALL_SOURCE"
  assert_line "$file" "note=local install attribution receipt; not sent by installer"
  grep -Eq '^captured_at_utc=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$file" \
    || fail "live receipt missing captured_at_utc timestamp"
}

echo "== controlled live install attribution receipt =="
printf '  site: %s\n' "$site_url"
printf '  install URL: %s\n' "$install_url"
printf '  release tag: %s\n' "$tag"
printf '  ref: %s\n' "$ref"
printf '  source ref: %s\n' "$source_ref"
printf '  repo clone URL: %s\n' "$repo_url"

echo
echo "== local preflight =="
bash scripts/check-controlled-install-attribution.sh
scripts/check-install-surface.sh

cat <<EOF

== approved live receipt command ==
This helper can perform one approved external read/install-path proof:

  ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1 scripts/run-approved-controlled-live-install.sh $tag

Approved mode fetches $install_url, clones the public repo into a temp ACC_SRC,
runs with ACC_INSTALL_ATTRIBUTION_ONLY=1, and checks the temp receipt for:

  ref=$ref
  source_ref=$source_ref

EOF

if [ "${ACC_APPROVE_CONTROLLED_LIVE_INSTALL:-0}" != "1" ]; then
  cat <<'EOF'
DRY RUN COMPLETE: no live install path was fetched or executed.
EOF
  exit 0
fi

need curl
need git
need bash

tmp="$(mktemp -d)"
keep_tmp="${ACC_KEEP_CONTROLLED_INSTALL_TMP:-0}"
cleanup() {
  if [ "$keep_tmp" = "1" ]; then
    printf '  kept temp proof dir: %s\n' "$tmp"
  else
    rm -rf "$tmp"
  fi
}
trap cleanup EXIT

home="$tmp/home"
data="$tmp/xdg-data"
cache="$tmp/xdg-cache"
config="$tmp/xdg-config"
state="$tmp/xdg-state"
src="$tmp/src"
browser_home="$tmp/browser"
bootstrap="$tmp/live-install"
run_log="$tmp/live-install.log"
mkdir -p "$home" "$data" "$cache" "$config" "$state" "$browser_home"

echo
echo "== approved live receipt proof =="
printf '  temp root: %s\n' "$tmp"
printf '  fetching: %s\n' "$install_url"
curl -fsSL --max-time 60 "$install_url" -o "$bootstrap"

grep -q 'exec bash ./install.sh "$@"' "$bootstrap" \
  || fail "live installer does not contain the expected bash handoff"
grep -q 'ACC_INSTALL_REF' "$bootstrap" \
  || fail "live installer does not mention ACC_INSTALL_REF"
grep -q 'ACC_INSTALL_SOURCE' "$bootstrap" \
  || fail "live installer does not mention ACC_INSTALL_SOURCE"
note "live installer handoff and attribution env markers: ok"

runner=(sh "$bootstrap")
if command -v timeout >/dev/null 2>&1; then
  runner=(timeout 180 sh "$bootstrap")
fi

if ! HOME="$home" \
  XDG_DATA_HOME="$data" \
  XDG_CACHE_HOME="$cache" \
  XDG_CONFIG_HOME="$config" \
  XDG_STATE_HOME="$state" \
  ACC_SRC="$src" \
  ACC_REPO="$repo_url" \
  ACC_BROWSER_HOME="$browser_home" \
  ACC_NONINTERACTIVE=1 \
  ACC_NO_BROWSER=1 \
  ACC_NO_TELEMETRY=1 \
  ACC_HOSTS_SYNC=off \
  GIT_TERMINAL_PROMPT=0 \
  ACC_INSTALL_REF="$ref" \
  ACC_INSTALL_SOURCE="$source_ref" \
  ACC_INSTALL_ATTRIBUTION_ONLY=1 \
    "${runner[@]}" >"$run_log" 2>&1; then
  printf 'live installer proof log (%s):\n' "$run_log" >&2
  sed 's/^/    /' "$run_log" >&2 || true
  fail "live installer attribution-only run failed"
fi

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin) receipt="$home/Library/Application Support/acc/install-attribution.env" ;;
  *)      receipt="$data/acc/install-attribution.env" ;;
esac

assert_receipt "$receipt"
note "live receipt: ok"

echo
echo "== live receipt contents =="
sed 's/^/  /' "$receipt"

cat <<'EOF'

CONTROLLED LIVE INSTALL ATTRIBUTION RECEIPT: PASS
No full install, daemon start, telemetry send, post, comment, submission,
payment, or real acc-home write was performed.
EOF
