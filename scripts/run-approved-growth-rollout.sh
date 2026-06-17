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
base_ref="${ACC_GROWTH_BASE_REF:-$remote/main}"
site_url="${ACC_LIVE_SITE_URL:-https://accint.xyz}"
strict_live_state="${ACC_HOSTED_LIVE_STATE_STRICT:-false}"
workflow_dispatch_attempts="${ACC_WORKFLOW_DISPATCH_ATTEMPTS:-6}"
workflow_dispatch_sleep="${ACC_WORKFLOW_DISPATCH_SLEEP:-10}"
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
  ACC_WORKFLOW_DISPATCH_ATTEMPTS=6
  ACC_WORKFLOW_DISPATCH_SLEEP=10
  ACC_GROWTH_REPO=maxbaluev/accreted-intelligence
  ACC_GROWTH_REMOTE=origin
  ACC_GROWTH_BASE_REF=origin/main

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
case "$workflow_dispatch_attempts" in
  ''|*[!0-9]*)
    printf 'refusing: ACC_WORKFLOW_DISPATCH_ATTEMPTS must be a positive integer\n' >&2
    exit 2
    ;;
esac
if [ "$workflow_dispatch_attempts" -lt 1 ]; then
  printf 'refusing: ACC_WORKFLOW_DISPATCH_ATTEMPTS must be at least 1\n' >&2
  exit 2
fi
case "$workflow_dispatch_sleep" in
  ''|*[!0-9]*)
    printf 'refusing: ACC_WORKFLOW_DISPATCH_SLEEP must be a non-negative integer number of seconds\n' >&2
    exit 2
    ;;
esac

branch="$(git branch --show-current 2>/dev/null || true)"
if [ -z "$branch" ]; then
  printf 'refusing: detached HEAD; checkout a branch before rollout\n' >&2
  exit 1
fi
head_sha="$(git rev-parse HEAD)"

echo "== approval-gated growth rollout =="
printf '  repo: %s\n' "$repo"
printf '  branch: %s\n' "$branch"
printf '  approved head: %s\n' "$head_sha"
printf '  remote: %s\n' "$remote"
printf '  base ref: %s\n' "$base_ref"
printf '  release tag: %s\n' "$tag"
printf '  site: %s\n' "$site_url"
printf '  strict hosted live-state: %s\n' "$strict_live_state"
printf '  workflow dispatch attempts: %s\n' "$workflow_dispatch_attempts"
printf '  workflow dispatch sleep: %ss\n' "$workflow_dispatch_sleep"

echo
echo "== local readiness =="
bash scripts/check-growth-readiness.sh

echo
echo "== unpublished bundle =="
if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  commit_count="$(git rev-list --count "$base_ref..HEAD" 2>/dev/null || printf '?')"
  file_count="$(git diff --name-only "$base_ref..HEAD" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ')"
  shortstat="$(git diff --shortstat "$base_ref..HEAD" 2>/dev/null || true)"
  printf '  base ref: %s\n' "$base_ref"
  printf '  commits to push: %s\n' "$commit_count"
  printf '  files changed: %s\n' "$file_count"
  if [ -n "$shortstat" ]; then
    printf '  diffstat: %s\n' "$shortstat"
  fi
  git log --reverse --oneline "$base_ref..HEAD" | sed 's/^/  /'
else
  printf '  base ref unavailable: %s\n' "$base_ref"
fi

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
    -f expected_head=$head_sha \\
    -f strict_live_state=$strict_live_state

Read-only follow-up after deployment is visible:

  scripts/check-growth-live-state.sh $tag
  scripts/check-live-attribution-flow.sh $site_url
  scripts/check-live-llms-discovery.sh $site_url
  node scripts/check-site-metadata.js
  node scripts/prepare-growth-rollout-receipt.js --markdown $tag

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
attempt=1
while :; do
  if gh workflow run live-site-attribution.yml --repo "$repo" \
    -f "acc_version=$tag" \
    -f "site_url=$site_url" \
    -f "expected_head=$head_sha" \
    -f "strict_live_state=$strict_live_state"; then
    break
  fi
  if [ "$attempt" -ge "$workflow_dispatch_attempts" ]; then
    printf 'hosted verifier dispatch failed after %s attempts\n' "$attempt" >&2
    exit 1
  fi
  printf 'workflow dispatch failed; retrying after %ss (%s/%s)\n' \
    "$workflow_dispatch_sleep" "$attempt" "$workflow_dispatch_attempts" >&2
  sleep "$workflow_dispatch_sleep"
  attempt=$((attempt + 1))
done

echo
echo "recent hosted verifier runs:"
gh run list --workflow live-site-attribution.yml --repo "$repo" --limit 3

cat <<EOF

APPROVED ROLLOUT SUBMITTED.
No posts, comments, directory submissions, release uploads, registry publishes,
or dashboard mutations were performed.

Next read-only verification after the site deploy is visible:

  scripts/check-growth-live-state.sh $tag
  scripts/check-live-attribution-flow.sh $site_url
  scripts/check-live-llms-discovery.sh $site_url
  node scripts/check-site-metadata.js
  node scripts/prepare-growth-rollout-receipt.js --markdown $tag
EOF
