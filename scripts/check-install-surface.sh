#!/usr/bin/env bash
# Verify the public install surfaces that social/page prompt copies depend on.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
note() { printf '  %s\n' "$1"; }
bad() { note "$1"; fail=1; }

echo "== install surface =="

if cmp -s install bootstrap/install; then
  note "short POSIX route install matches bootstrap/install"
else
  bad "short POSIX route install drifted from bootstrap/install"
fi

for file in install bootstrap/install install.sh; do
  if bash -n "$file"; then
    note "$file: syntax ok"
  else
    bad "$file: syntax error"
  fi
done

if grep -q 'ACC_INSTALL_REF' install && grep -q 'ACC_INSTALL_SOURCE' install; then
  note "short POSIX route preserves install attribution env"
else
  bad "short POSIX route is missing install attribution env support"
fi

if grep -q 'exec bash ./install.sh "$@"' install; then
  note "short POSIX route explicitly hands off through bash"
else
  bad "short POSIX route does not explicitly hand off through bash"
fi

if grep -q 'ACC_INSTALL_REF' install.ps1 && grep -q 'ACC_INSTALL_SOURCE' install.ps1; then
  note "short PowerShell route preserves install attribution env"
else
  bad "short PowerShell route is missing install attribution env support"
fi

for page in index.html reddit/index.html docs/install/with-agent.md; do
  if grep -q 'https://accint.xyz/install' "$page" && grep -q 'https://accint.xyz/install.ps1' "$page"; then
    note "$page: short install URLs present"
  else
    bad "$page: short install URLs missing"
  fi
done

if grep -q 'raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install' index.html \
  && grep -q 'raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1' index.html; then
  note "home page manual install fallback points at raw bootstrap installers"
else
  bad "home page manual install fallback missing raw bootstrap installers"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "INSTALL SURFACE: PASS"
else
  echo "INSTALL SURFACE: FAIL"
fi
exit "$fail"
