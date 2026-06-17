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
growth_report="${ACC_GROWTH_REPORT:-docs/ops/growth-report.md}"
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
  - verifies local install short-route alignment
  - verifies live prompt-copy attribution in the read-only live-state audit
  - verifies static share/SEO metadata for launch previews
  - verifies the social launch kit
  - verifies the owner-reviewable social launch packet
  - verifies the compact owner approval brief
  - verifies growth surface refs and attributed landing URLs
  - builds and verifies the local MCPB promotion packet without uploading
  - audits the tracked directory PR state from docs/ops/growth-report.md, or
    ACC_GROWTH_REPORT when set
  - ranks tracked directory/list PRs by live reach, state, and blockers
  - prepares directory/list attribution refs from the tracked report
  - prepares owner-reviewable directory/list follow-up notes from the tracked report
  - prepares the owner-held Glama submission packet for the punkpeye blocker
  - prints the approval-gated push + hosted live-site verifier command
  - prints the approval-gated controlled live install receipt verifier command
  - prints the approval-gated PostHog dashboard shell creation command
  - prints the approval-gated PostHog funnel readout command
  - prints the owner-approval commands for MCPB upload, server.json advance,
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
  directory_priority_command="   node scripts/prepare-directory-priority-report.js --markdown \"$growth_report\""
  directory_refs_command="   node scripts/prepare-directory-surface-refs.js --markdown \"$growth_report\""
  directory_followup_command="   node scripts/prepare-directory-followup-kit.js --markdown \"$growth_report\""
else
  report_record_line="   Record published URLs and refs in the growth report."
  directory_pr_command="   scripts/check-directory-pr-state.sh path/to/report.md"
  directory_priority_command="   node scripts/prepare-directory-priority-report.js --markdown path/to/report.md"
  directory_refs_command="   node scripts/prepare-directory-surface-refs.js --markdown path/to/report.md"
  directory_followup_command="   node scripts/prepare-directory-followup-kit.js --markdown path/to/report.md"
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
echo "== controlled live install receipt helper =="
scripts/run-approved-controlled-live-install.sh "$tag"

echo
echo "== install surface pre-live proof =="
scripts/check-install-surface.sh

echo
echo "== PostHog dashboard pre-live proof =="
node scripts/prepare-posthog-dashboard.js --check

echo
echo "== PostHog dashboard creation helper =="
scripts/run-approved-posthog-dashboard.sh

echo
echo "== PostHog funnel readout helper =="
scripts/run-approved-posthog-funnel-check.sh

echo
echo "== site metadata pre-live proof =="
node scripts/check-site-metadata.js

echo
echo "== MCPB promotion packet pre-live proof =="
scripts/check-mcpb-promotion-packet.sh "$tag"

echo
echo "== social launch kit pre-live proof =="
node scripts/check-social-launch-kit.js --check

echo
echo "== social launch packet pre-live proof =="
node scripts/prepare-social-launch-packet.js --check

echo
echo "== growth approval brief pre-live proof =="
ACC_GROWTH_REPORT="${growth_report:-}" node scripts/prepare-growth-approval-brief.js --check "$tag"

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
  echo "  skipped: no growth report configured"
fi

echo
echo "== directory priority report pre-live proof =="
if [ -n "$growth_report" ] && [ -f "$growth_report" ]; then
  node scripts/prepare-directory-priority-report.js --check "$growth_report"
elif [ -n "$growth_report" ]; then
  printf '  skipped: ACC_GROWTH_REPORT does not exist: %s\n' "$growth_report"
else
  echo "  skipped: no growth report configured"
fi

echo
echo "== directory surface refs pre-live proof =="
if [ -n "$growth_report" ] && [ -f "$growth_report" ]; then
  node scripts/prepare-directory-surface-refs.js --check "$growth_report"
elif [ -n "$growth_report" ]; then
  printf '  skipped: ACC_GROWTH_REPORT does not exist: %s\n' "$growth_report"
else
  echo "  skipped: no growth report configured"
fi

echo
echo "== directory follow-up kit pre-live proof =="
if [ -n "$growth_report" ] && [ -f "$growth_report" ]; then
  node scripts/prepare-directory-followup-kit.js --check "$growth_report"
elif [ -n "$growth_report" ]; then
  printf '  skipped: ACC_GROWTH_REPORT does not exist: %s\n' "$growth_report"
else
  echo "  skipped: no growth report configured"
fi

echo
echo "== Glama submission packet pre-live proof =="
node scripts/prepare-glama-submission-packet.js --check "$tag"

echo
echo "== punkpeye Glama follow-up pre-live proof =="
scripts/prepare-punkpeye-glama-followup.sh

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

   node scripts/prepare-growth-approval-brief.js --markdown $tag

   git push origin ${branch:-main}

   Or run the approval-gated helper after owner approval:

   ACC_APPROVE_GROWTH_ROLLOUT=1 scripts/run-approved-growth-rollout.sh $tag

2. Read-only verification after the push/site deploy:

   scripts/check-growth-live-state.sh $tag
   scripts/check-live-attribution-flow.sh https://accint.xyz
   scripts/check-install-surface.sh
   node scripts/check-site-metadata.js
   gh repo view $repo --json nameWithOwner,licenseInfo,homepageUrl,repositoryTopics
   gh workflow list --repo $repo
   curl -fsSI https://accint.xyz/
   curl -fsSI https://accint.xyz/reddit/
   curl -fsSL https://accint.xyz/ | grep -F "ACC_INSTALL_REF"
   curl -fsSL https://accint.xyz/ | grep -F "ACC_INSTALL_SOURCE"
   curl -fsSL https://accint.xyz/reddit/ | grep -F "ACC_INSTALL_REF"
   curl -fsSL https://accint.xyz/reddit/ | grep -F "ACC_INSTALL_SOURCE"

3. Hosted live-site attribution verification after owner approval:

   gh workflow run live-site-attribution.yml --repo $repo \\
     -f acc_version=$tag \\
     -f site_url=https://accint.xyz \\
     -f strict_live_state=false
   gh run list --workflow live-site-attribution.yml --repo $repo --limit 3

4. Build and verify the local MCPB promotion packet:

   scripts/check-mcpb-promotion-packet.sh $tag

5. Upload MCPB release assets after owner approval:

   ACC_UPLOAD_MCPB_ASSETS=1 scripts/prepare-mcpb-release-assets.sh $tag

6. Preview and then advance server.json after uploaded assets verify:

   scripts/advance-mcpb-server-json.sh $tag dist/server.mcpb-all.json
   ACC_ADVANCE_SERVER_JSON=1 scripts/advance-mcpb-server-json.sh $tag dist/server.mcpb-all.json
   git add server.json
   git commit -m "registry: advance MCPB metadata to $tag"
   bash scripts/check-growth-readiness.sh
   git push origin ${branch:-main}

7. Publish MCP Registry metadata after the pushed server.json passes alignment:

   gh workflow run publish-mcp.yml --repo $repo
   gh run list --workflow publish-mcp.yml --repo $repo --limit 3

8. Local controlled install attribution proof:

   scripts/check-controlled-install-attribution.sh

9. Live controlled install attribution receipt proof after owner approval:

   scripts/run-approved-controlled-live-install.sh $tag
   ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1 \\
     scripts/run-approved-controlled-live-install.sh $tag

   Expected local receipt:
     ref=controlled-${tag#v}
     source_ref=ref=controlled-rollout

   This helper runs the live POSIX installer with
   ACC_INSTALL_ATTRIBUTION_ONLY=1 inside a temp home. It proves the live route
   can write the attribution receipt without doing a full install or touching
   the operator's real acc home.

10. Local PostHog dashboard spec proof:

   node scripts/prepare-posthog-dashboard.js --check
   node scripts/prepare-posthog-dashboard.js --print

11. Re-run the full read-only live-state audit:

   scripts/check-growth-live-state.sh $tag

12. Create the PostHog dashboard from:

   docs/ops/attribution-dashboard.md
   docs/ops/posthog-dashboard.json
   scripts/run-approved-posthog-dashboard.sh
   POSTHOG_HOST=https://app.posthog.com \\
   POSTHOG_ENVIRONMENT_ID=<environment-id> \\
   POSTHOG_PERSONAL_API_KEY=<personal-api-key> \\
   ACC_APPROVE_POSTHOG_DASHBOARD=1 \\
     scripts/run-approved-posthog-dashboard.sh

   The helper creates only the dashboard shell and a markdown setup tile through
   documented PostHog dashboard endpoints. Add the five insight tiles from
   docs/ops/posthog-dashboard.json in the PostHog UI, then confirm the
   controlled install appears in both web copy and first-run events.

13. Read the PostHog growth funnel after the dashboard and controlled install:

   scripts/run-approved-posthog-funnel-check.sh
   POSTHOG_HOST=https://us.posthog.com \\
   POSTHOG_PROJECT_ID=<project-id> \\
   POSTHOG_PERSONAL_API_KEY=<personal-api-key> \\
   ACC_APPROVE_POSTHOG_QUERY=1 \\
     scripts/run-approved-posthog-funnel-check.sh

   Optional controlled probe:

   ACC_CONTROLLED_DISTINCT_ID=<install_ref copied from the live page> \\
     ACC_APPROVE_POSTHOG_QUERY=1 scripts/run-approved-posthog-funnel-check.sh

   Use this aggregate readout to rank surfaces by attributed first runs and
   activation, not by copy events alone.

14. Prepare owner-approved social launch copy:

   node scripts/check-social-launch-kit.js --check
   node scripts/prepare-social-launch-packet.js --check
   node scripts/prepare-social-launch-packet.js --markdown
   node scripts/check-site-metadata.js
   node scripts/check-growth-surfaces.js --check
   node scripts/check-growth-surfaces.js --print
   scripts/check-live-attribution-flow.sh https://accint.xyz
$report_record_line

   Review, then owner posts manually from:

   docs/ops/social-launch-kit.md

   Do not automate HN/X/Reddit posting, commenting, DMs, payment, or account
   identity use.

15. Read-only directory PR follow-up:

$directory_pr_command
$directory_priority_command
$directory_refs_command
$directory_followup_command

16. punkpeye Glama badge follow-up after a real Glama listing exists:

   node scripts/prepare-glama-submission-packet.js --markdown $tag

   Owner submits manually at https://glama.ai/mcp/servers using the packet's
   repository URL, root Dockerfile path, release tag, default MCP command, and
   expected tools. Do not automate the Glama form, browser session, payment,
   CAPTCHA, or account identity.

   scripts/prepare-punkpeye-glama-followup.sh
   ACC_APPROVE_PUNKPEYE_GLAMA=1 scripts/prepare-punkpeye-glama-followup.sh

   This helper refuses to update the owned PR branch unless both the Glama
   listing page and score badge are real.

   Do not comment, edit, close, merge, or push PR branches without explicit
   owner approval for that exact target.

Still hold if Glama has no real AccInt listing, if license detection is null for
OSS-first lists, if MCPB release alignment fails, or if a target directory needs
payment, CAPTCHA, anti-bot bypass, private account action, or owner identity input.

DRY RUN COMPLETE: no external mutation was performed.
EOF
