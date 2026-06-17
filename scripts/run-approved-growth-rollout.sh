#!/usr/bin/env bash
# Approval-gated executor for the public growth push plus hosted live-site audit.
#
# Default mode is dry-run: it verifies local readiness and prints the exact
# external commands. Set ACC_APPROVE_GROWTH_ROLLOUT=1 only after owner approval
# to push the public branch and dispatch the hosted live-site attribution
# workflow. It never posts, comments, submits directory PRs, creates dashboards,
# uploads release assets, or publishes registry metadata.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

repo="${ACC_GROWTH_REPO:-maxbaluev/accreted-intelligence}"
remote="${ACC_GROWTH_REMOTE:-origin}"
site_url="${ACC_LIVE_SITE_URL:-https://accint.xyz}"
strict_live_state="${ACC_HOSTED_LIVE_STATE_STRICT:-false}"
tag="${1:-}"

usage() {
  cat <<'EOF'
usage: scripts/run-approved-growth-rollout.sh [tag]

Dry-run default:
  scripts/run-approved-growth-rollout.sh v0.1.6

Owner-approved external action:
  ACC_APPROVE_GROWTH_ROLLOUT=1 scripts/run-approved-growth-rollout.sh v0.1.6

Optional:
  ACC_LIVE_SITE_URL=https://accint.xyz
  ACC_HOSTED_LIVE_STATE_STRICT=false
  ACC_GROWTH_REPO=maxbaluev/accreted-intelligence
  ACC_GROWTH_REMOTE=origin

This script only covers the public push and hosted live-site attribution audit.
It does not upload assets, publish registry metadata, post, comment, submit
directory PRs, create dashboards, pay, or use account identity outside GitHub.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

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

branch="$(git branch --show-current 2>/dev/null || true)"
if [ -z "$branch" ]; then
  printf 'refusing: detached HEAD; checkout a branch before rollout\n' >&2
  exit 1
fi

echo "== approval-gated growth rollout =="
printf '  repo: %s\n' "$repo"
printf '  branch: %s\n' "$branch"
printf '  remote: %s\n' "$remote"
printf '  release tag: %s\n' "$tag"
printf '  site: %s\n' "$site_url"
printf '  strict hosted live-state: %s\n' "$strict_live_state"

echo
echo "== local readiness =="
bash scripts/check-growth-readiness.sh

if command -v actionlint >/dev/null 2>&1; then
  echo
  echo "== workflow syntax =="
  actionlint .github/workflows/live-site-attribution.yml
fi

if ! command -v gh >/dev/null 2>&1; then
  printf 'gh CLI is required for the hosted verifier dispatch\n' >&2
  exit 1
fi

echo
echo "== remote visibility =="
gh repo view "$repo" --json nameWithOwner,defaultBranchRef --jq '.nameWithOwner + " default=" + .defaultBranchRef.name'

cat <<EOF

== external commands ==
These are the only external mutations this script can perform when approved:

  git push $remote $branch
  gh workflow run live-site-attribution.yml --repo $repo \\
    -f acc_version=$tag \\
    -f site_url=$site_url \\
    -f strict_live_state=$strict_live_state

Read-only follow-up:

  gh run list --workflow live-site-attribution.yml --repo $repo --limit 3

EOF

if [ "${ACC_APPROVE_GROWTH_ROLLOUT:-0}" != "1" ]; then
  cat <<EOF
DRY RUN COMPLETE: no external mutation was performed.

After explicit owner approval, run:

  ACC_APPROVE_GROWTH_ROLLOUT=1 scripts/run-approved-growth-rollout.sh $tag

EOF
  exit 0
fi

echo "== approved external action =="
echo "pushing public branch..."
git push "$remote" "$branch"

echo
echo "dispatching hosted live-site attribution verifier..."
gh workflow run live-site-attribution.yml --repo "$repo" \
  -f "acc_version=$tag" \
  -f "site_url=$site_url" \
  -f "strict_live_state=$strict_live_state"

echo
echo "recent hosted verifier runs:"
gh run list --workflow live-site-attribution.yml --repo "$repo" --limit 3

cat <<EOF

APPROVED ROLLOUT SUBMITTED.
No posts, comments, directory submissions, release uploads, registry publishes,
or dashboard mutations were performed.
EOF
