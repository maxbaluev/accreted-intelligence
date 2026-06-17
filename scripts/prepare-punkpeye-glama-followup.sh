#!/usr/bin/env bash
# Approval-gated helper for the punkpeye Glama badge requirement.
#
# Default mode is dry-run: verify whether Glama has a real AccInt listing and
# score badge, then print the exact README line and branch-update command. Set
# ACC_APPROVE_PUNKPEYE_GLAMA=1 only after owner approval and only when the Glama
# listing + badge checks pass. Approved mode updates the owned fork branch and
# pushes it; it never comments on the PR or submits any form.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

upstream_repo="${PUNKPEYE_UPSTREAM_REPO:-punkpeye/awesome-mcp-servers}"
fork_repo="${PUNKPEYE_FORK_REPO:-maxbaluev/awesome-mcp-servers}"
pr_number="${PUNKPEYE_PR_NUMBER:-8091}"
branch="${PUNKPEYE_BRANCH:-add-accint-knowledge-memory}"
fork_owner="${fork_repo%%/*}"
glama_path="${GLAMA_ACCINT_PATH:-maxbaluev/accreted-intelligence}"
glama_url="https://glama.ai/mcp/servers/${glama_path}"
badge_url="${glama_url}/badges/score.svg"

usage() {
  cat <<'EOF'
usage: scripts/prepare-punkpeye-glama-followup.sh

Dry-run default:
  scripts/prepare-punkpeye-glama-followup.sh

Owner-approved branch update:
  ACC_APPROVE_PUNKPEYE_GLAMA=1 scripts/prepare-punkpeye-glama-followup.sh

Optional:
  GLAMA_ACCINT_PATH=maxbaluev/accreted-intelligence
  PUNKPEYE_UPSTREAM_REPO=punkpeye/awesome-mcp-servers
  PUNKPEYE_FORK_REPO=maxbaluev/awesome-mcp-servers
  PUNKPEYE_BRANCH=add-accint-knowledge-memory
  PUNKPEYE_PR_NUMBER=8091

This helper never submits to Glama, comments on GitHub, opens PRs, pays, or
bypasses any anti-bot/security flow. Approved mode only pushes the owned fork
branch after Glama listing + badge checks pass.
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

need curl
need gh
need git
need python3

tmp_page="$(mktemp)"
tmp_badge="$(mktemp)"
cleanup() {
  rm -f "$tmp_page" "$tmp_badge"
}
trap cleanup EXIT

echo "== punkpeye Glama follow-up =="
printf '  upstream PR: %s#%s\n' "$upstream_repo" "$pr_number"
printf '  owned fork branch: %s:%s\n' "$fork_repo" "$branch"
printf '  Glama URL: %s\n' "$glama_url"
printf '  Glama badge: %s\n' "$badge_url"

echo
echo "== Glama listing check =="
page_status="$(curl -LsS -o "$tmp_page" -w '%{http_code}' --max-time 30 "$glama_url" 2>/dev/null || true)"
printf '  listing HTTP: %s\n' "${page_status:-<none>}"
if [ "$page_status" != "200" ]; then
  printf 'HOLD: Glama listing is not HTTP 200; refusing badge update\n' >&2
  listing_ok=0
elif grep -Eiq 'AccInt|accreted-intelligence|maxbaluev' "$tmp_page"; then
  printf '  listing marker: ok\n'
  listing_ok=1
else
  printf 'HOLD: Glama listing page lacks AccInt markers; refusing badge update\n' >&2
  listing_ok=0
fi

echo
echo "== Glama score badge check =="
badge_status="$(curl -LsS -o "$tmp_badge" -w '%{http_code}' --max-time 30 "$badge_url" 2>/dev/null || true)"
printf '  badge HTTP: %s\n' "${badge_status:-<none>}"
if [ "$badge_status" != "200" ]; then
  printf 'HOLD: Glama score badge is not HTTP 200; refusing badge update\n' >&2
  badge_ok=0
elif grep -Eiq '<svg|image/svg' "$tmp_badge"; then
  printf '  badge SVG: ok\n'
  badge_ok=1
else
  printf 'HOLD: Glama badge response is not SVG-like; refusing badge update\n' >&2
  badge_ok=0
fi

echo
echo "== punkpeye PR check =="
pr_json="$(gh pr view "$pr_number" --repo "$upstream_repo" --json state,isDraft,mergeStateStatus,headRefName,headRepositoryOwner,url,title 2>/dev/null || true)"
if [ -z "$pr_json" ]; then
  printf 'HOLD: could not read %s#%s\n' "$upstream_repo" "$pr_number" >&2
  pr_ok=0
else
  PR_JSON="$pr_json" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["PR_JSON"])
owner = (data.get("headRepositoryOwner") or {}).get("login", "<unknown>")
print(f"  title: {data.get('title', '<unknown>')}")
print(f"  url: {data.get('url', '<unknown>')}")
print(f"  state: {data.get('state', '<unknown>')}")
print(f"  draft: {data.get('isDraft', '<unknown>')}")
print(f"  merge state: {data.get('mergeStateStatus', '<unknown>')}")
print(f"  head: {owner}:{data.get('headRefName', '<unknown>')}")
PY
  pr_state="$(PR_JSON="$pr_json" python3 - <<'PY'
import json, os
data = json.loads(os.environ["PR_JSON"])
print(data.get("state", ""))
PY
  )"
  pr_draft="$(PR_JSON="$pr_json" python3 - <<'PY'
import json, os
data = json.loads(os.environ["PR_JSON"])
print("true" if data.get("isDraft") else "false")
PY
  )"
  pr_head="$(PR_JSON="$pr_json" python3 - <<'PY'
import json, os
data = json.loads(os.environ["PR_JSON"])
print(data.get("headRefName", ""))
PY
  )"
  pr_owner="$(PR_JSON="$pr_json" python3 - <<'PY'
import json, os
data = json.loads(os.environ["PR_JSON"])
print((data.get("headRepositoryOwner") or {}).get("login", ""))
PY
  )"
  if [ "$pr_state" = "OPEN" ] && [ "$pr_draft" != "true" ] && [ "$pr_head" = "$branch" ] && [ "$pr_owner" = "$fork_owner" ]; then
    pr_ok=1
  else
    printf 'HOLD: PR is not open/non-draft on expected owned branch; refusing badge update\n' >&2
    pr_ok=0
  fi
fi

badge_markdown="[![${glama_path} MCP server](${badge_url})](${glama_url})"
old_line="- [maxbaluev/accreted-intelligence](https://github.com/maxbaluev/accreted-intelligence) 🦀 🏠 🍎 🪟 🐧 - A local-first learning substrate that slots under Claude Code, OpenCode, Codex, and Cursor: it builds a Work Model from what actually worked — graded by real outcomes, not the model's own word — and predicts the better path, so the same job gets faster and lands better every run."
new_line="- [maxbaluev/accreted-intelligence](https://github.com/maxbaluev/accreted-intelligence) ${badge_markdown} 🦀 🏠 🍎 🪟 🐧 - A local-first learning substrate that slots under Claude Code, OpenCode, Codex, and Cursor: it builds a Work Model from what actually worked — graded by real outcomes, not the model's own word — and predicts the better path, so the same job gets faster and lands better every run."

cat <<EOF

== badge patch preview ==
$new_line

== external commands ==
Approved mode can perform only this branch update:

  gh repo clone $fork_repo /tmp/accint-punkpeye-glama
  cd /tmp/accint-punkpeye-glama
  git checkout $branch
  # replace the AccInt README row with the badge row shown above
  git diff --check
  git commit -am "Add Glama badge for AccInt"
  git push origin $branch

It will not comment on the PR.
EOF

if [ "$listing_ok" != "1" ] || [ "$badge_ok" != "1" ] || [ "${pr_ok:-0}" != "1" ]; then
  printf '\nPUNKPEYE GLAMA FOLLOW-UP: HOLD\n'
  exit 0
fi

if [ "${ACC_APPROVE_PUNKPEYE_GLAMA:-0}" != "1" ]; then
  cat <<EOF

PUNKPEYE GLAMA FOLLOW-UP: READY (dry-run)
No external mutation was performed.

After explicit owner approval, run:

  ACC_APPROVE_PUNKPEYE_GLAMA=1 scripts/prepare-punkpeye-glama-followup.sh

EOF
  exit 0
fi

workdir="$(mktemp -d)"
echo
echo "== approved branch update =="
printf '  workdir: %s\n' "$workdir"
gh repo clone "$fork_repo" "$workdir/repo"
cd "$workdir/repo"
git checkout "$branch"
git pull --ff-only origin "$branch"

python3 - "$old_line" "$new_line" <<'PY'
import sys
from pathlib import Path

old, new = sys.argv[1], sys.argv[2]
path = Path("README.md")
text = path.read_text()
if new in text:
    print("README already contains the Glama badge row")
    raise SystemExit(0)
if old not in text:
    raise SystemExit("expected AccInt README row not found; refusing blind edit")
path.write_text(text.replace(old, new, 1))
PY

if git diff --quiet; then
  echo "no README change needed"
  exit 0
fi
git diff --check
git add README.md
git commit -m "Add Glama badge for AccInt"
git push origin "$branch"

cat <<EOF

PUNKPEYE GLAMA FOLLOW-UP: PUSHED
Updated the owned PR branch. No PR comment was posted.
EOF
