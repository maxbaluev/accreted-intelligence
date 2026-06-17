#!/usr/bin/env bash
# Self-validation for the Accreted Intelligence public repo.
# Run locally (`bash scripts/check-integrity.sh`) or in CI (.github/workflows/integrity.yml).
# This repo is the canonical, open home of the integration layer (plugins, installers, docs,
# site) — so it defends its own quality rather than relying on the engine repo to do it.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0
note() { printf '  %s\n' "$1"; }

echo "== install scripts: syntax =="
if bash -n install.sh; then note "install.sh: ok"; else note "install.sh: SYNTAX ERROR"; fail=1; fi
for f in \
  bootstrap/install \
  scripts/acc-docker.sh \
  scripts/advance-mcpb-server-json.sh \
  scripts/check-controlled-install-attribution.sh \
  scripts/check-directory-pr-state.sh \
  scripts/check-growth-live-state.sh \
  scripts/check-growth-readiness.sh \
  scripts/check-install-surface.sh \
  scripts/check-mcpb-promotion-packet.sh \
  scripts/check-live-attribution-flow.sh \
  scripts/check-mcpb-release-assets.sh \
  scripts/prepare-punkpeye-glama-followup.sh \
  scripts/check-release-alignment.sh \
  scripts/docker-entrypoint.sh \
  scripts/package-mcpb.sh \
  scripts/prepare-growth-rollout.sh \
  scripts/prepare-mcpb-release-assets.sh \
  scripts/run-approved-controlled-live-install.sh \
  scripts/run-approved-posthog-funnel-check.sh \
  scripts/run-approved-posthog-dashboard.sh \
  scripts/run-approved-growth-rollout.sh; do
  if [ -f "$f" ]; then
    if bash -n "$f"; then note "$f: ok"; else note "$f: SYNTAX ERROR"; fail=1; fi
  fi
done
if [ -f install.ps1 ]; then note "install.ps1: present"; fi

echo "== plugin discovery markers (one protocol, many hosts) =="
for host in claude codex cursor opencode; do
  if [ -d "plugins/$host" ]; then note "plugins/$host: present"; else note "plugins/$host: MISSING"; fail=1; fi
done
if [ -f "plugins/claude/.claude-plugin/plugin.json" ]; then note "claude plugin manifest: ok"; else note "claude plugin manifest: MISSING"; fail=1; fi

echo "== licensing boundary =="
for f in LICENSE LICENSE-APACHE-2.0.txt LICENSING.md EULA.md; do
  if [ -f "$f" ]; then note "$f: present"; else note "$f: MISSING"; fail=1; fi
done
if grep -q 'Apache License' LICENSE && cmp -s LICENSE LICENSE-APACHE-2.0.txt; then
  note "Apache license text: standard root LICENSE matches legacy license file"
else
  note "Apache license text: root LICENSE missing or diverges from LICENSE-APACHE-2.0.txt"
  fail=1
fi
if grep -qi 'proprietary binary' LICENSING.md && grep -q 'EULA.md' LICENSING.md; then
  note "proprietary binary split: documented"
else
  note "proprietary binary split: missing from LICENSING.md"
  fail=1
fi

echo "== attribution flow (web copy -> installer ref) =="
if bash scripts/check-install-surface.sh; then
  note "install surface: ok"
else
  fail=1
fi
if command -v node >/dev/null 2>&1; then
  if node scripts/check-attribution-flow.js; then note "web attribution flow: ok"; else fail=1; fi
else
  note "node: MISSING (required for attribution-flow verifier)"
  fail=1
fi
if bash scripts/check-controlled-install-attribution.sh; then
  note "controlled install attribution receipt: ok"
else
  fail=1
fi

echo "== PostHog dashboard spec =="
if command -v node >/dev/null 2>&1; then
  if node scripts/prepare-posthog-dashboard.js --check; then note "PostHog dashboard spec: ok"; else fail=1; fi
else
  note "node: MISSING (required for PostHog dashboard verifier)"
  fail=1
fi

echo "== social launch kit =="
if command -v node >/dev/null 2>&1; then
  if node scripts/check-social-launch-kit.js --check; then note "social launch kit: ok"; else fail=1; fi
else
  note "node: MISSING (required for social launch kit verifier)"
  fail=1
fi

echo "== growth surface refs =="
if command -v node >/dev/null 2>&1; then
  if node scripts/check-growth-surfaces.js --check; then note "growth surface refs: ok"; else fail=1; fi
  if printf '%s\n' '| 1 | example/list | 1 | Memory | https://github.com/example/list/pull/1 | ok |' | node scripts/prepare-directory-surface-refs.js --check - >/dev/null; then
    note "directory surface refs: ok"
  else
    note "directory surface refs: FAIL"
    fail=1
  fi
else
  note "node: MISSING (required for growth/directory surface verifiers)"
  fail=1
fi

echo "== MCP registry publish guard =="
if grep -q 'scripts/check-mcpb-release-assets.sh "v${version}" server.json' .github/workflows/publish-mcp.yml; then
  note "publish workflow release-asset guard: ok"
else
  note "publish workflow release-asset guard: MISSING"
  fail=1
fi
if grep -q 'bash scripts/check-release-alignment.sh' .github/workflows/publish-mcp.yml; then
  note "publish workflow latest-release guard: ok"
else
  note "publish workflow latest-release guard: MISSING"
  fail=1
fi
if command -v node >/dev/null 2>&1; then
  if node scripts/check-registry-discovery-docs.js; then note "registry discovery docs: ok"; else fail=1; fi
else
  note "node: MISSING (required for registry discovery docs verifier)"
  fail=1
fi

echo "== live growth workflow guard =="
live_workflow=".github/workflows/live-site-attribution.yml"
if [ -f "$live_workflow" ] &&
  grep -q 'scripts/check-live-attribution-flow.sh' "$live_workflow" &&
  grep -q 'scripts/check-growth-live-state.sh' "$live_workflow"; then
  note "live site attribution workflow: ok"
else
  note "live site attribution workflow: MISSING"
  fail=1
fi

echo "== no stale brand / no personal contact =="
if grep -rIn 'acc4' --include='*.md' --include='*.sh' --include='*.ps1' --include='*.json' --exclude=check-integrity.sh --exclude-dir=.git --exclude-dir=.worktrees . | grep -v 'CHANGELOG.md'; then
  note "FOUND stale 'acc4' references above"; fail=1
else note "no stale acc4: ok"; fi
if grep -nE 'maxbaluev@outlook|t\.me/' README.md 2>/dev/null; then
  note "FOUND personal contact in README (use GitHub Issues / accint.xyz)"; fail=1
else note "README contact neutral: ok"; fi

echo "== relative markdown links resolve =="
broken_list=$(
  find . -name '*.md' -not -path './.git/*' -not -path './.worktrees/*' | while IFS= read -r md; do
    dir=$(dirname "$md")
    grep -oE '\]\([^)]+\)' "$md" | sed -E 's/^\]\(//; s/\)$//' | while IFS= read -r link; do
      case "$link" in http://*|https://*|mailto:*|\#*|//*) continue ;; esac
      target="${link%% *}"     # strip optional "title"
      target="${target%%#*}"   # strip #fragment
      [ -z "$target" ] && continue
      case "$target" in /*) path=".$target" ;; *) path="$dir/$target" ;; esac
      [ -e "$path" ] || printf '%s -> %s\n' "$md" "$link"
    done
  done
)
if [ -n "$broken_list" ]; then
  printf '%s\n' "$broken_list" | sed 's/^/    BROKEN: /'
  fail=1
else note "all relative md links resolve: ok"; fi

echo
if [ "$fail" -eq 0 ]; then echo "INTEGRITY: PASS"; else echo "INTEGRITY: FAIL"; fi
exit $fail
