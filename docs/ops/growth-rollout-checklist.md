# Growth rollout checklist

Purpose: turn the current local growth bundle into external impact without
leaking private engine state or losing attribution. This is an approval-gated
operator checklist. It does not authorize pushing, deploying, submitting, or
posting by itself.

## Scope

Use this when the public clone is ahead with growth-readiness commits such as:

- binary/container install-path fixes
- short install-route alignment guard
- installer attribution receipt support
- web prompt-copy `ACC_INSTALL_REF` stitching
- web prompt-copy `ACC_INSTALL_SOURCE` source/ref stitching
- attribution regression tests
- controlled install attribution receipt verifier
- approval-gated controlled live install receipt helper
- read-only live growth state auditor
- live prompt-copy attribution verifier
- static share/SEO metadata verifier
- LLM/agent discovery file
- MCPB promotion packet verifier
- official registry discovery docs/follow-up packet
- materialized PostHog dashboard spec
- approval-gated PostHog dashboard shell helper
- approval-gated PostHog growth funnel readout helper
- attribution dashboard/runbook docs
- social launch kit
- owner-reviewed social launch packet
- owner-reviewed social reply packet
- compact owner approval brief
- growth surface ref manifest
- tracked growth report
- directory priority report generator
- directory surface ref generator
- organic referrer classification
- dry-run rollout approval packet
- standard root `LICENSE` for GitHub license detection
- directory/listing factsheets

Do not run this from the private engine checkout. Public pushes must happen only
from the separate `maxbaluev/accreted-intelligence` clone.

## Before approval

These checks are safe before approval. All are local except
`scripts/check-growth-live-state.sh`, which performs read-only public lookups
and may report HOLD while the live site still lags local commits:

```bash
scripts/prepare-growth-rollout.sh
scripts/check-growth-live-state.sh v<tag>
bash scripts/check-growth-readiness.sh
scripts/run-approved-growth-rollout.sh v<tag>
scripts/run-approved-controlled-live-install.sh v<tag>
scripts/check-install-surface.sh
node scripts/check-site-metadata.js
bash scripts/check-controlled-install-attribution.sh
node scripts/prepare-posthog-dashboard.js --check
scripts/run-approved-posthog-dashboard.sh
scripts/run-approved-posthog-funnel-check.sh
scripts/check-mcpb-promotion-packet.sh v<tag>
node scripts/check-social-launch-kit.js --check
node scripts/prepare-growth-approval-brief.js --check v<tag>
node scripts/prepare-social-launch-packet.js --check
node scripts/prepare-social-launch-packet.js --decision-packet
node scripts/prepare-social-launch-packet.js --reply-packet hn-show
node scripts/check-growth-surfaces.js --check
scripts/check-directory-pr-state.sh docs/ops/growth-report.md
node scripts/prepare-directory-priority-report.js --check docs/ops/growth-report.md
node scripts/prepare-directory-surface-refs.js --check docs/ops/growth-report.md
node scripts/prepare-directory-followup-kit.js --check --actionable docs/ops/growth-report.md
node scripts/prepare-glama-submission-packet.js --check v<tag>
git status --short --branch
git log --oneline origin/main..HEAD
bash scripts/check-integrity.sh
git diff --check -- .
cmp -s LICENSE LICENSE-APACHE-2.0.txt
```

Expected state:

- working tree is clean
- branch is ahead only by intended public commits
- `scripts/prepare-growth-rollout.sh` prints `DRY RUN COMPLETE` and does not
  push, upload, dispatch, publish, post, or submit anything
- `scripts/check-growth-live-state.sh v<tag>` reports current live OK/HOLD/SKIP
  state without pushing, uploading, dispatching, publishing, posting, submitting,
  or creating dashboards/listings
- `scripts/check-growth-readiness.sh` passes
- `scripts/run-approved-growth-rollout.sh v<tag>` prints `DRY RUN COMPLETE`
  unless `ACC_APPROVE_GROWTH_ROLLOUT=1` is set, and its printed external actions
  are limited to `git push` plus the hosted live-site attribution workflow
  dispatch. Approved mode retries the workflow dispatch briefly because a
  just-pushed workflow file can take a moment to become dispatchable on GitHub.
- `scripts/run-approved-controlled-live-install.sh v<tag>` prints
  `DRY RUN COMPLETE` unless `ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1` is set. In
  approved mode it fetches the live POSIX installer, runs only the
  `ACC_INSTALL_ATTRIBUTION_ONLY=1` stop path in temp homes, and checks the
  receipt without doing a full install
- `scripts/check-install-surface.sh` passes and proves `https://accint.xyz/install`
  stays aligned with the raw POSIX bootstrap and preserves attribution env
  handoff
- `node scripts/check-site-metadata.js` passes and proves canonical URLs,
  Open Graph/Twitter tags, the 1200x630 `og.png`, `robots.txt`, `llms.txt`,
  and `sitemap.xml` are ready for launch previews, indexing, and agent
  discovery
- `scripts/check-controlled-install-attribution.sh` passes against temp
  POSIX/PowerShell installer homes without touching the operator's real acc home
- `node scripts/prepare-posthog-dashboard.js --check` passes and validates the
  nine required attribution dashboard tiles, including direct `llms-txt`
  discovery install-ref classification
- `scripts/run-approved-posthog-dashboard.sh` prints `DRY RUN COMPLETE` unless
  `ACC_APPROVE_POSTHOG_DASHBOARD=1` plus PostHog env vars are set. In approved
  mode it creates only the dashboard shell and a markdown setup tile through
  documented PostHog dashboard endpoints; insight tiles are still created from
  `docs/ops/posthog-dashboard.json` in the PostHog UI
- `scripts/run-approved-posthog-funnel-check.sh` prints `DRY RUN COMPLETE`
  unless `ACC_APPROVE_POSTHOG_QUERY=1` plus PostHog env vars are set. In
  approved mode it runs small aggregate HogQL queries through the documented
  PostHog Query API and does not export raw event rows or mutate PostHog
- `scripts/check-mcpb-promotion-packet.sh v<tag>` passes and proves the local
  MCPB upload bundle, generated registry metadata, and mutation guards before
  release upload/server metadata advance
- `node scripts/check-social-launch-kit.js --check` passes and validates
  owner-approved posting copy, attribution refs, and source-boundary wording
- `node scripts/prepare-social-launch-packet.js --check` passes and turns the
  HN/X/Reddit launch copy into exact owner-review packets without posting
- `node scripts/prepare-social-launch-packet.js --decision-packet` prints the
  one-page owner target choice packet without opening compose/submit URLs
- `node scripts/prepare-social-launch-packet.js --reply-packet hn-show` prints
  owner-reviewable response drafts for real launch comments without posting
- `node scripts/prepare-growth-approval-brief.js --check v<tag>` passes and
  prints the compact approval packet without running any external action
- `node scripts/prepare-growth-decision-queue.js --check v<tag>` passes and
  turns the approval actions into a dependency-aware critical path
- `node scripts/prepare-growth-owner-handoff.js --check v<tag>` passes and
  reduces the current owner ask to a one-page handoff
- `node scripts/check-growth-surfaces.js --check` passes and proves launch
  refs, README/docs attributed landing URLs, README install attribution, install
  snippets, and page prompt-copy source keys stay aligned
- `scripts/check-directory-pr-state.sh docs/ops/growth-report.md` reads the
  tracked directory/list PR table and reports current open/merged/closed
  status without posting
- `node scripts/prepare-directory-priority-report.js --check docs/ops/growth-report.md`
  ranks the tracked directory/list PR table by live PR state, repository reach,
  checks, and known blockers without posting
- `node scripts/prepare-directory-surface-refs.js --check docs/ops/growth-report.md`
  passes for the tracked directory/list PR table
- `node scripts/prepare-directory-followup-kit.js --check --actionable docs/ops/growth-report.md`
  passes for the tracked directory/list PR table and prepares owner-reviewable
  maintainer-note drafts without posting
- `node scripts/prepare-glama-submission-packet.js --check v<tag>` passes and
  prints the Glama submission fields without submitting anything
- `scripts/check-integrity.sh` passes
- root `LICENSE` exactly matches `LICENSE-APACHE-2.0.txt`
- `docs/ops/attribution-dashboard.md` exists
- `docs/ops/directory-listing.md` exists
- `docs/ops/growth-report.md` exists
- `docs/ops/growth-surfaces.json` exists
- `llms.txt` exists
- no private `src/**`, `Cargo.toml`, `Cargo.lock`, private tests, or substrate
  data appear in `git diff origin/main..HEAD --name-only`

## Approval boundary

Stop here unless the owner explicitly authorizes the public push/deploy/release
step. After approval, keep each action separate and verify before continuing.
The dry-run packet printed by `scripts/prepare-growth-rollout.sh` is the
canonical command list; copy from it rather than reconstructing the sequence.
For a one-page owner handoff, dependency queue, and exact approval commands, run:

```bash
node scripts/prepare-growth-owner-handoff.js --markdown v<tag>
node scripts/prepare-growth-decision-queue.js --markdown v<tag>
node scripts/prepare-growth-approval-brief.js --markdown v<tag>
```

## Public push sequence

From the public clone only:

```bash
git push origin main
```

Or, after explicit owner approval, use the guarded helper that also dispatches
the hosted live-site verifier:

```bash
ACC_APPROVE_GROWTH_ROLLOUT=1 scripts/run-approved-growth-rollout.sh v<tag>
```

Immediately verify:

```bash
scripts/check-growth-live-state.sh v<tag>
gh repo view maxbaluev/accreted-intelligence --json nameWithOwner,licenseInfo,homepageUrl,repositoryTopics
gh workflow list --repo maxbaluev/accreted-intelligence
```

Expected:

- `licenseInfo.spdxId` is `Apache-2.0` after GitHub re-indexes the root
  `LICENSE`
- topics still include the discovery topics used for GitHub browsing
- no unexpected workflow failures appear after the push

If license detection is still null immediately after push, wait for GitHub to
re-index before re-submitting to OSS-first lists.

## Site verification

After GitHub Pages / site deploy completes, verify the deployed pages:

```bash
scripts/check-growth-live-state.sh v<tag>
curl -fsSI https://accint.xyz/
curl -fsSI https://accint.xyz/reddit/
curl -fsSL https://accint.xyz/install | grep -F "ACC_INSTALL_REF"
curl -fsSL https://accint.xyz/install | grep -F "exec bash ./install.sh"
curl -fsSL https://accint.xyz/ | grep -F "ACC_INSTALL_REF"
curl -fsSL https://accint.xyz/reddit/ | grep -F "ACC_INSTALL_REF"
curl -fsSL https://accint.xyz/ | grep -F "ACC_INSTALL_SOURCE"
curl -fsSL https://accint.xyz/reddit/ | grep -F "ACC_INSTALL_SOURCE"
curl -fsSL https://accint.xyz/ | grep -F 'data-share-surface="visitor-share"'
curl -fsSL https://accint.xyz/reddit/ | grep -F 'data-share-surface="reddit-share"'
curl -fsSL https://accint.xyz/ | grep -F "share_link_copied"
curl -fsSL https://accint.xyz/reddit/ | grep -F "share_link_copied"
curl -fsSL https://accint.xyz/llms.txt | grep -F "ACC_INSTALL_REF=llms-txt"
curl -fsSL https://accint.xyz/robots.txt | grep -F "LLMs: https://accint.xyz/llms.txt"
curl -fsSL https://accint.xyz/sitemap.xml | grep -F "<loc>https://accint.xyz/llms.txt</loc>"
scripts/check-live-attribution-flow.sh https://accint.xyz
scripts/check-live-llms-discovery.sh https://accint.xyz
```

`scripts/check-live-attribution-flow.sh` downloads served home/Reddit HTML into
a temp directory and reuses the static attribution verifier, proving live prompt
copies carry `ACC_INSTALL_REF`, `ACC_INSTALL_SOURCE`, and the source-only
fallback, and proving the home and Reddit pages serve tracked owned-share URLs.

If the local network path cannot fetch the custom domain, run the hosted
read-only verifier after the workflow file is pushed:

```bash
gh workflow run live-site-attribution.yml \
  --repo maxbaluev/accreted-intelligence \
  -f acc_version=v<tag> \
  -f site_url=https://accint.xyz \
  -f strict_live_state=false
gh run list --workflow live-site-attribution.yml \
  --repo maxbaluev/accreted-intelligence \
  --limit 3
```

That workflow runs the live prompt-copy attribution verifier from a GitHub-hosted
runner, verifies the deployed `llms.txt` discovery surface, then prints the
advisory full live growth audit. Keep
`strict_live_state=false` while Glama/punkpeye are still expected holds.

Also run a browser copy check if possible: copy the hero agent prompt and confirm
the copied text contains `ACC_INSTALL_REF=<install_ref>` plus
`ACC_INSTALL_SOURCE='ref=...'` / `utm_source=...` on POSIX, and matching
`$env:ACC_INSTALL_REF='<install_ref>'` plus `$env:ACC_INSTALL_SOURCE='...'` on
PowerShell snippets. The page should still display clean installer text; the
attribution env belongs only in copied text.

## Binary/release alignment

The attribution chain is incomplete until the private telemetry bridge is in a
released binary that the public installer fetches. Before treating attribution
as live:

1. Confirm the private binary release includes receipt reading from
   `install-attribution.env`.
2. Confirm the public installer resolves that release tag.
3. Confirm `sha256sums.txt` contains the expected artifact checksums.
4. Build and verify the full local MCPB promotion packet:
   `scripts/check-mcpb-promotion-packet.sh v<tag>`.
5. After owner approval, upload the generated `dist/acc-mcp-v<tag>-*.mcpb`
   files and `.sha256` sidecars to the same GitHub Release:
   `ACC_UPLOAD_MCPB_ASSETS=1 scripts/prepare-mcpb-release-assets.sh v<tag>`.
6. Run
   `scripts/check-mcpb-release-assets.sh v<tag> dist/server.mcpb-all.json`.
7. Only after that check passes, preview and advance `server.json`:
   `scripts/advance-mcpb-server-json.sh v<tag> dist/server.mcpb-all.json`, then
   `ACC_ADVANCE_SERVER_JSON=1 scripts/advance-mcpb-server-json.sh v<tag> dist/server.mcpb-all.json`.
   Publish registry metadata after the alignment check passes.
8. Run `scripts/check-controlled-install-attribution.sh` locally. It must pass
   before any live controlled install.
9. Run the live receipt proof helper in dry-run, then after explicit owner
   approval:
   `ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1 scripts/run-approved-controlled-live-install.sh v<tag>`.
10. Run a full public install path only in a controlled environment where
    dependency installation, daemon startup, and telemetry are acceptable.

The controlled install should produce:

- local `install-attribution.env` with the chosen `ref=...`
- `source_ref=...` in that receipt when `ACC_INSTALL_SOURCE` was copied or set
- `acc doctor` success
- `first_run` telemetry with `has_install_ref=true` when telemetry is enabled
- the same anonymous ref as `distinct_id` in PostHog

## PostHog dashboard

Create the dashboard from `docs/ops/attribution-dashboard.md` after the push and
binary release are live. The materialized local spec is
`docs/ops/posthog-dashboard.json`; validate and print it first:

```bash
node scripts/prepare-posthog-dashboard.js --check
node scripts/prepare-posthog-dashboard.js --print
node scripts/prepare-posthog-dashboard.js --ui-packet
scripts/run-approved-posthog-dashboard.sh
scripts/run-approved-posthog-funnel-check.sh
```

Minimum tiles:

1. copy to first run funnel
2. web copy source leaderboard
3. landing to copy to first run by surface
4. attributed first runs
5. copy to attributed first run by surface
6. owned share loop
7. reddit community loop
8. activation after install

Do not rank acquisition surfaces from copy events alone. Rank from visitor to
copy to attributed first run, then activation; use the owned share loop to
detect whether owned referrals are compounding instead of only being clicked.
Use the Reddit community loop to decide whether Reddit traffic is producing
community participation before treating a subreddit as a pure install channel.

After explicit owner approval, the shell and setup tile can be created through
the PostHog Dashboard API:

```bash
POSTHOG_HOST=https://app.posthog.com \
POSTHOG_ENVIRONMENT_ID=<environment-id> \
POSTHOG_PERSONAL_API_KEY=<personal-api-key> \
ACC_APPROVE_POSTHOG_DASHBOARD=1 \
  scripts/run-approved-posthog-dashboard.sh
```

The helper requires a personal API key with `dashboard:read` and
`dashboard:write`, checks for an existing exact dashboard name first, and does
not create undocumented insight payloads. Create the nine insight tiles from
the generated UI packet before using the dashboard for decisions:

```bash
node scripts/prepare-posthog-dashboard.js --ui-packet
```

After the dashboard is created and a controlled live install is run, query the
aggregate funnel, direct install refs, owned-share-loop, and Reddit community
readout:

```bash
POSTHOG_HOST=https://us.posthog.com \
POSTHOG_PROJECT_ID=<project-id> \
POSTHOG_PERSONAL_API_KEY=<personal-api-key> \
ACC_APPROVE_POSTHOG_QUERY=1 \
  scripts/run-approved-posthog-funnel-check.sh
```

Set `ACC_CONTROLLED_DISTINCT_ID=<install_ref copied from the live page>` when
checking a specific controlled browser-copy install. The helper requires Query
Read permission and uses only aggregate `LIMIT`ed HogQL queries; it is not an
event export path.

## Directory follow-up

After public push and site verification:

1. Run the advisory live-state audit:
   `scripts/check-growth-live-state.sh v<tag>`.
2. Generate the owner-held Glama submission packet:
   `node scripts/prepare-glama-submission-packet.js --form-packet v<tag>`.
   The owner can use it manually at `https://glama.ai/mcp/servers`; do not
   automate the form, logged-in browser, payment, CAPTCHA, or account identity.
3. Re-check Glama:
   - `https://glama.ai/mcp/servers/maxbaluev/accreted-intelligence`
   - `https://glama.ai/mcp/servers?q=accint`
4. Only if Glama has a real AccInt listing and score badge, update
   `punkpeye/awesome-mcp-servers#8091` with the badge required by that repo.
   Use the dry-run helper first:
   `scripts/prepare-punkpeye-glama-followup.sh`. After explicit owner approval,
   and only if the helper reports `READY`, run
   `ACC_APPROVE_PUNKPEYE_GLAMA=1 scripts/prepare-punkpeye-glama-followup.sh`.
   The helper updates only the owned fork branch and does not comment on the PR.
5. Use `docs/ops/directory-listing.md` for future directory/list submissions
   and reviewer replies.
6. Audit tracked PR state without posting:
   `scripts/check-directory-pr-state.sh docs/ops/growth-report.md`.
7. Generate the directory priority queue without posting:
   `node scripts/prepare-directory-priority-report.js --markdown docs/ops/growth-report.md`.
8. Generate directory attribution refs without posting:
   `node scripts/prepare-directory-surface-refs.js --markdown docs/ops/growth-report.md`.
9. Prepare owner-reviewable registry/source-boundary follow-up notes without
   posting:
   `node scripts/prepare-directory-followup-kit.js --markdown --actionable docs/ops/growth-report.md`.
10. Do not retry lists that rejected the private-engine boundary unless the
   local fix is pushed and the target list's policy can accept the boundary.

## Social launch lane

After public push, site verification, and attribution checks pass, review
`docs/ops/social-launch-kit.md` for owner-approved HN/X/Reddit posting. The
kit is copy only; it does not authorize or perform any post. Validate before
posting:

```bash
node scripts/check-social-launch-kit.js --check
node scripts/prepare-social-launch-packet.js --check
node scripts/prepare-social-launch-packet.js --decision-packet
node scripts/prepare-social-launch-packet.js --receipt-packet hn-show <published-url>
node scripts/prepare-social-launch-packet.js --reply-packet hn-show
node scripts/prepare-social-launch-packet.js --markdown
node scripts/check-growth-surfaces.js --check
node scripts/check-growth-surfaces.js --print
scripts/check-live-attribution-flow.sh https://accint.xyz
scripts/check-live-llms-discovery.sh https://accint.xyz
```

Use the attributed landing URLs printed by the growth-surface checker when a
post links to `accint.xyz` instead of carrying a long installer command. Those
URLs populate `source_props` on the page, and the deployed copy buttons then add
the same `ref`/source envelope to copied prompt and installer text. Keep the
`llms.txt` discovery verifier in this preflight so social launch copy never
points agents at a stale or unserved discovery file.

## Docker registry lane

Do not submit to `docker/mcp-registry` until Docker-host smoke passes after the
public binary/container commits are pushed:

```bash
gh workflow run docker-container-smoke.yml -f acc_version=<tag>
```

If running locally on a Docker host:

```bash
ACC_VERSION=<tag> scripts/acc-docker.sh status
ACC_VERSION=<tag> scripts/acc-docker.sh doctor
ACC_VERSION=<tag> scripts/acc-docker.sh start
docker exec -i acc acc --db /data/acc.db status
```

Only then run the registry's own `task validate` / `task build` requirements.

## Hold rules

Hold instead of continuing when:

- the public working tree is dirty after push
- GitHub license detection remains null for OSS-first target lists
- the live site does not serve copied `ACC_INSTALL_REF` text
- the live site does not advertise or serve `llms.txt` from home, Reddit,
  `robots.txt`, and `sitemap.xml`
- the private release binary does not contain the attribution bridge
- controlled install cannot produce a matching web copy and `first_run`
  `distinct_id`
- controlled live receipt proof cannot fetch the live installer or produce the
  expected temp receipt
- PostHog dashboard shell/setup tile cannot be created or the nine insight tiles
  are not present before ranking growth surfaces
- PostHog aggregate funnel readout cannot confirm attributed first runs and
  direct `gh-*` directory install refs before deciding which launch/listing
  surfaces to double down on
- Glama still has no real listing for the punkpeye badge requirement
- a target directory requires payment, CAPTCHA, anti-bot bypass, private account
  action, or owner identity input
