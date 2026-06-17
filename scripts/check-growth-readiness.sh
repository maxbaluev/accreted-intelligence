#!/usr/bin/env bash
# Local launch-readiness gate for the approval-gated growth bundle.
# Run this from the public accreted-intelligence clone before asking to push,
# deploy, release, or submit directory/list updates.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
base_ref="${ACC_GROWTH_BASE_REF:-origin/main}"

note() { printf '  %s\n' "$1"; }
bad() { note "$1"; fail=1; }

echo "== growth readiness: repository state =="
if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  note "base ref: $base_ref"
else
  bad "base ref missing: $base_ref"
fi

if [ -z "$(git status --porcelain)" ]; then
  note "working tree: clean"
else
  git status --short | sed 's/^/    /'
  bad "working tree: DIRTY"
fi

if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  ahead=$(git rev-list --count "$base_ref"..HEAD)
  behind=$(git rev-list --count HEAD.."$base_ref")
  if [ "$ahead" -gt 0 ] && [ "$behind" -eq 0 ]; then
    note "branch position: ahead $ahead, behind 0"
  elif [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
    bad "branch position: no local growth bundle ahead of $base_ref"
  else
    bad "branch position: ahead $ahead, behind $behind"
  fi
fi

echo "== growth readiness: public/private boundary =="
if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  changed_paths=$(git diff --name-only "$base_ref"..HEAD)
  private_paths=$(printf '%s\n' "$changed_paths" | grep -E '(^src/|^tests/|^Cargo\.toml$|^Cargo\.lock$|^build\.rs$|(^|/)acc[0-9]*\.db$|(^|/)substrate/|^target/)' || true)
  if [ -n "$private_paths" ]; then
    printf '%s\n' "$private_paths" | sed 's/^/    PRIVATE: /'
    bad "ahead diff contains private engine/substrate paths"
  else
    note "ahead diff: no private engine/substrate paths"
  fi
fi

echo "== growth readiness: required growth assets =="
for f in \
  docs/ops/attribution-dashboard.md \
  docs/ops/directory-listing.md \
  docs/ops/growth-rollout-checklist.md \
  docs/ops/growth-surfaces.json \
  docs/ops/posthog-dashboard.json \
  docs/ops/social-launch-kit.md \
  scripts/advance-mcpb-server-json.sh \
  scripts/check-attribution-flow.js \
  scripts/check-controlled-install-attribution.sh \
  scripts/check-directory-pr-state.sh \
  scripts/check-growth-live-state.sh \
  scripts/check-live-attribution-flow.sh \
  scripts/check-growth-surfaces.js \
  scripts/check-mcpb-promotion-packet.sh \
  scripts/check-mcpb-release-assets.sh \
  scripts/check-release-alignment.sh \
  scripts/check-social-launch-kit.js \
  scripts/prepare-directory-surface-refs.js \
  scripts/prepare-growth-rollout.sh \
  scripts/prepare-posthog-dashboard.js \
  scripts/prepare-mcpb-release-assets.sh \
  scripts/check-integrity.sh; do
  if [ -f "$f" ]; then
    note "$f: present"
  else
    bad "$f: MISSING"
  fi
done

if cmp -s LICENSE LICENSE-APACHE-2.0.txt; then
  note "LICENSE: matches LICENSE-APACHE-2.0.txt"
else
  bad "LICENSE: missing or diverges from LICENSE-APACHE-2.0.txt"
fi

echo "== growth readiness: integrity gate =="
if bash scripts/check-integrity.sh; then
  note "integrity gate: ok"
else
  bad "integrity gate: FAIL"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "GROWTH READINESS: PASS"
else
  echo "GROWTH READINESS: FAIL"
fi
exit "$fail"
