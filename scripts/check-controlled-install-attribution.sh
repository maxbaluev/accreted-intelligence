#!/usr/bin/env bash
# Verify install attribution receipt writing in isolated temp homes.
#
# This does not run the live curl installer, download assets, start daemons, write to the
# operator's real acc home, or send telemetry. It uses the checked-out installer with
# ACC_INSTALL_ATTRIBUTION_ONLY=1 and asserts the local receipt shape that a controlled
# live install must produce later.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

ref="controlled-local"
source_ref="ref=controlled-rollout&utm_source=local-verifier"

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
  local file="$1" label="$2"
  [ -f "$file" ] || fail "$label receipt missing: $file"
  assert_line "$file" "ref=$ref"
  assert_line "$file" "source_ref=$source_ref"
  assert_line "$file" "source=ACC_INSTALL_REF+ACC_INSTALL_SOURCE"
  assert_line "$file" "note=local install attribution receipt; not sent by installer"
  grep -Eq '^captured_at_utc=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$file" \
    || fail "$label receipt missing captured_at_utc timestamp"
  note "$label receipt: ok"
}

echo "== controlled install attribution receipt =="

posix_home="$tmp/posix-home"
posix_data="$tmp/posix-data"
mkdir -p "$posix_home" "$posix_data"
HOME="$posix_home" \
XDG_DATA_HOME="$posix_data" \
ACC_NONINTERACTIVE=1 \
ACC_NO_BROWSER=1 \
ACC_INSTALL_REF="$ref" \
ACC_INSTALL_SOURCE="$source_ref" \
ACC_INSTALL_ATTRIBUTION_ONLY=1 \
  ./install.sh >"$tmp/posix.log" 2>&1
assert_receipt "$posix_data/acc/install-attribution.env" "POSIX"

if command -v pwsh >/dev/null 2>&1; then
  ps_home="$tmp/ps-home"
  ps_appdata="$tmp/ps-appdata"
  ps_local="$tmp/ps-local"
  mkdir -p "$ps_home" "$ps_appdata" "$ps_local"
  HOME="$ps_home" \
  APPDATA="$ps_appdata" \
  LOCALAPPDATA="$ps_local" \
  ACC_NONINTERACTIVE=1 \
  ACC_NO_BROWSER=1 \
  ACC_INSTALL_REF="$ref" \
  ACC_INSTALL_SOURCE="$source_ref" \
  ACC_INSTALL_ATTRIBUTION_ONLY=1 \
    pwsh -NoLogo -NoProfile -File install.ps1 >"$tmp/powershell.log" 2>&1
  assert_receipt "$ps_appdata/acc/install-attribution.env" "PowerShell"
else
  note "PowerShell receipt: skipped (pwsh not found)"
fi

echo "CONTROLLED INSTALL ATTRIBUTION: PASS"
