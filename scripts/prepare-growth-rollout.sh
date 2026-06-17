#!/usr/bin/env bash
# Print the approval packet for turning the local growth bundle into live impact.
#
# This script is intentionally dry-run only. It verifies local readiness and prints
# the exact commands that require owner approval, but it never pushes, uploads,
# dispatches workflows, publishes registry metadata, posts, or submits anything.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

repo="${ACC_GROWTH_REPO:-maxbaluev/accreted-intelligence}"
base_ref="${ACC_GROWTH_BASE_REF:-origin/main}"
growth_report="${ACC_GROWTH_REPORT:-}"
tag="${1:-}"

usage() {
  cat <<'EOF'
usage: scripts/prepare-growth-rollout.sh [tag]

Examples:
  scripts/prepare-growth-rollout.sh
  scripts/prepare-growth-rollout.sh v0.1.5

Default mode is local and read-only:
  - runs the growth-readiness gate
  - reports branch/release/registry state
  - reports read-only live public state and current holds
  - verifies live prompt-copy attribution in the read-only live-state audit
  - verifies the social launch kit
  - verifies growth surface refs and attributed landing URLs
  - optionally audits directory PR state when ACC_GROWTH_REPORT is set
  - prints the owner-approval commands for push, MCPB upload, server.json advance,
    MCP Registry workflow dispatch, controlled install, dashboard creation,
    social launch, and directory follow-up

It does not push, upload, dispatch, publish, post, or submit anything.
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

if [ -z "$tag" ] && command -v gh >/dev/null 2>&1; then
  tag="$(gh release view --repo "$repo" --json tagName --jq '.tagName' 2>/dev/null || true)"
fi
if [ -z "$tag" ]; then
  tag="v${server_version}"
fi
case "$tag" in
  v*) : ;;
  *) tag="v$tag" ;;
esac

branch="$(git branch --show-current 2>/dev/null || true)"
head_sha="$(git rev-parse --short HEAD)"
ahead="?"
behind="?"
if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  ahead="$(git rev-list --count "$base_ref"..HEAD)"
  behind="$(git rev-list --count HEAD.."$base_ref")"
fi

if [ -n "$growth_report" ]; then
  report_record_line="   Record published URLs and refs in: $growth_report"
  directory_pr_command="   scripts/check-directory-pr-state.sh \"$growth_report\""
else
  report_record_line="   Record published URLs and refs in the growth report."
  directory_pr_command="   scripts/check-directory-pr-state.sh path/to/report.md"
fi

echo "== local growth readiness =="
bash scripts/check-growth-readiness.sh

echo
echo "== rollout state =="
printf '  repo: %s\n' "$repo"
printf '  branch: %s @ %s\n' "${branch:-<detached>}" "$head_sha"
printf '  base ref: %s\n' "$base_ref"
printf '  ahead/behind: %s/%s\n' "$ahead" "$behind"
printf '  server.json version: %s\n' "${server_version:-<missing>}"
printf '  target release tag: %s\n' "$tag"

if command -v gh >/dev/null 2>&1; then
  release_json="$(gh release view "$tag" --repo "$repo" --json tagName,publishedAt,assets 2>/dev/null || true)"
  if [ -n "$release_json" ]; then
    RELEASE_JSON="$release_json" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["RELEASE_JSON"])
assets = [a.get("name", "") for a in data.get("assets", [])]
mcpb = [name for name in assets if name.endswith(".mcpb")]
sidecars = [name for name in assets if name.endswith(".sha256")]
print(f"  release published: {data.get('publishedAt', '<unknown>')}")
print(f"  release assets: {len(assets)} total, {len(mcpb)} MCPB, {len(sidecars)} MCPB sidecars")
if mcpb:
    for name in sorted(mcpb):
        print(f"    MCPB: {name}")
PY
  else
    printf '  release lookup: unavailable for %s\n' "$tag"
  fi
else
  printf '  release lookup: skipped (gh CLI not found)\n'
fi

echo
echo "== controlled install attribution pre-live proof =="
bash scripts/check-controlled-install-attribution.sh

echo
echo "== PostHog dashboard pre-live proof =="
node scripts/prepare-posthog-dashboard.js --check

echo
echo "== social launch kit pre-live proof =="
node scripts/check-social-launch-kit.js --check

echo
echo "== growth surface refs pre-live proof =="
node scripts/check-growth-surfaces.js --check

echo
echo "== directory PR state pre-live proof =="
if [ -n "$growth_report" ] && [ -f "$growth_report" ]; then
  scripts/check-directory-pr-state.sh "$growth_report"
elif [ -n "$growth_report" ]; then
  printf '  skipped: ACC_GROWTH_REPORT does not exist: %s\n' "$growth_report"
else
  echo "  skipped: set ACC_GROWTH_REPORT=/path/to/report.md to audit tracked PRs"
fi

echo
echo "== read-only live growth state =="
ACC_LIVE_STATE_STRICT=0 bash scripts/check-growth-live-state.sh "$tag"

echo
echo "== registry alignment hold check =="
if command -v gh >/dev/null 2>&1; then
  if bash scripts/check-release-alignment.sh "$tag" server.json; then
    echo "  registry metadata is aligned with $tag"
  else
    cat <<EOF
  HOLD: registry metadata is not publish-ready for $tag.
  This is expected until MCPB assets are uploaded and server.json is advanced
  through scripts/advance-mcpb-server-json.sh.
EOF
  fi
else
  echo "  skipped: gh CLI is required for release alignment verification"
fi

cat <<EOF

== owner approval packet ==
Run these only after explicit owner approval for the named external action.

1. Push the public growth bundle:

   git push origin ${branch:-main}

2. Read-only verification after the push/site deploy:

   scripts/check-growth-live-state.sh $tag
   scripts/check-live-attribution-flow.sh https://accint.xyz
   gh repo view $repo --json nameWithOwner,licenseInfo,homepageUrl,repositoryTopics
   gh workflow list --repo $repo
   curl -fsSI https://accint.xyz/
   curl -fsSI https://accint.xyz/reddit/
   curl -fsSL https://accint.xyz/ | grep -F "ACC_INSTALL_REF"
   curl -fsSL https://accint.xyz/ | grep -F "ACC_INSTALL_SOURCE"
   curl -fsSL https://accint.xyz/reddit/ | grep -F "ACC_INSTALL_REF"
   curl -fsSL https://accint.xyz/reddit/ | grep -F "ACC_INSTALL_SOURCE"

3. Prepare MCPB release assets locally:

   scripts/prepare-mcpb-release-assets.sh $tag

4. Upload MCPB release assets after owner approval:

   ACC_UPLOAD_MCPB_ASSETS=1 scripts/prepare-mcpb-release-assets.sh $tag

5. Preview and then advance server.json after uploaded assets verify:

   scripts/advance-mcpb-server-json.sh $tag dist/server.mcpb-all.json
   ACC_ADVANCE_SERVER_JSON=1 scripts/advance-mcpb-server-json.sh $tag dist/server.mcpb-all.json
   git add server.json
   git commit -m "registry: advance MCPB metadata to $tag"
   bash scripts/check-growth-readiness.sh
   git push origin ${branch:-main}

6. Publish MCP Registry metadata after the pushed server.json passes alignment:

   gh workflow run publish-mcp.yml --repo $repo
   gh run list --workflow publish-mcp.yml --repo $repo --limit 3

7. Local controlled install attribution proof:

   scripts/check-controlled-install-attribution.sh

8. Live controlled install attribution proof after owner approval:

   ACC_INSTALL_REF=controlled-${tag#v} ACC_INSTALL_SOURCE='ref=controlled-rollout' \\
     bash -c 'curl -fsSL https://accint.xyz/install | sh'

   Expected local receipt:
     ref=controlled-${tag#v}
     source_ref=ref=controlled-rollout

9. Local PostHog dashboard spec proof:

   node scripts/prepare-posthog-dashboard.js --check
   node scripts/prepare-posthog-dashboard.js --print

10. Re-run the full read-only live-state audit:

   scripts/check-growth-live-state.sh $tag

11. Create the PostHog dashboard from:

   docs/ops/attribution-dashboard.md
   docs/ops/posthog-dashboard.json

12. Prepare owner-approved social launch copy:

   node scripts/check-social-launch-kit.js --check
   node scripts/check-growth-surfaces.js --check
   node scripts/check-growth-surfaces.js --print
   scripts/check-live-attribution-flow.sh https://accint.xyz
$report_record_line

   Review, then owner posts manually from:

   docs/ops/social-launch-kit.md

   Do not automate HN/X/Reddit posting, commenting, DMs, payment, or account
   identity use.

13. Read-only directory PR follow-up:

$directory_pr_command

   Do not comment, edit, close, merge, or push PR branches without explicit
   owner approval for that exact target.

Still hold if Glama has no real AccInt listing, if license detection is null for
OSS-first lists, if MCPB release alignment fails, or if a target directory needs
payment, CAPTCHA, anti-bot bypass, private account action, or owner identity input.

DRY RUN COMPLETE: no external mutation was performed.
EOF
