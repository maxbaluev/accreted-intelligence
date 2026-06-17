# Growth rollout checklist

Purpose: turn the current local growth bundle into external impact without
leaking private engine state or losing attribution. This is an approval-gated
operator checklist. It does not authorize pushing, deploying, submitting, or
posting by itself.

## Scope

Use this when the public clone is ahead with growth-readiness commits such as:

- binary/container install-path fixes
- installer attribution receipt support
- web prompt-copy `ACC_INSTALL_REF` stitching
- web prompt-copy `ACC_INSTALL_SOURCE` source/ref stitching
- attribution regression tests
- controlled install attribution receipt verifier
- read-only live growth state auditor
- live prompt-copy attribution verifier
- materialized PostHog dashboard spec
- attribution dashboard/runbook docs
- social launch kit
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
bash scripts/check-controlled-install-attribution.sh
node scripts/prepare-posthog-dashboard.js --check
node scripts/check-social-launch-kit.js --check
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
- `scripts/check-controlled-install-attribution.sh` passes against temp
  POSIX/PowerShell installer homes without touching the operator's real acc home
- `node scripts/prepare-posthog-dashboard.js --check` passes and validates the
  five required attribution dashboard tiles
- `node scripts/check-social-launch-kit.js --check` passes and validates
  owner-approved posting copy, attribution refs, and source-boundary wording
- `scripts/check-integrity.sh` passes
- root `LICENSE` exactly matches `LICENSE-APACHE-2.0.txt`
- `docs/ops/attribution-dashboard.md` exists
- `docs/ops/directory-listing.md` exists
- no private `src/**`, `Cargo.toml`, `Cargo.lock`, private tests, or substrate
  data appear in `git diff origin/main..HEAD --name-only`

## Approval boundary

Stop here unless the owner explicitly authorizes the public push/deploy/release
step. After approval, keep each action separate and verify before continuing.
The dry-run packet printed by `scripts/prepare-growth-rollout.sh` is the
canonical command list; copy from it rather than reconstructing the sequence.

## Public push sequence

From the public clone only:

```bash
git push origin main
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
curl -fsSL https://accint.xyz/ | grep -F "ACC_INSTALL_REF"
curl -fsSL https://accint.xyz/reddit/ | grep -F "ACC_INSTALL_REF"
curl -fsSL https://accint.xyz/ | grep -F "ACC_INSTALL_SOURCE"
curl -fsSL https://accint.xyz/reddit/ | grep -F "ACC_INSTALL_SOURCE"
scripts/check-live-attribution-flow.sh https://accint.xyz
```

`scripts/check-live-attribution-flow.sh` downloads served home/Reddit HTML into
a temp directory and reuses the static attribution verifier, proving live prompt
copies carry `ACC_INSTALL_REF`, `ACC_INSTALL_SOURCE`, and the source-only
fallback.

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
4. Build MCPB bundles and print the release upload command:
   `scripts/prepare-mcpb-release-assets.sh v<tag>`.
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
9. Run the public install path in a controlled environment.

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
```

Minimum tiles:

1. copy to first run funnel
2. web copy source leaderboard
3. attributed first runs
4. copy to attributed first run by surface
5. activation after install

Do not rank acquisition surfaces from copy events alone. Rank from attributed
first runs and activation.

## Directory follow-up

After public push and site verification:

1. Run the advisory live-state audit:
   `scripts/check-growth-live-state.sh v<tag>`.
2. Re-check Glama:
   - `https://glama.ai/mcp/servers/maxbaluev/accreted-intelligence`
   - `https://glama.ai/mcp/servers?q=accint`
3. Only if Glama has a real AccInt listing and score badge, update
   `punkpeye/awesome-mcp-servers#8091` with the badge required by that repo.
4. Use `docs/ops/directory-listing.md` for future directory/list submissions
   and reviewer replies.
5. Audit tracked PR state without posting:
   `scripts/check-directory-pr-state.sh path/to/report.md`.
6. Do not retry lists that rejected the private-engine boundary unless the
   local fix is pushed and the target list's policy can accept the boundary.

## Social launch lane

After public push, site verification, and attribution checks pass, review
`docs/ops/social-launch-kit.md` for owner-approved HN/X/Reddit posting. The
kit is copy only; it does not authorize or perform any post. Validate before
posting:

```bash
node scripts/check-social-launch-kit.js --check
scripts/check-live-attribution-flow.sh https://accint.xyz
```

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
- the private release binary does not contain the attribution bridge
- controlled install cannot produce a matching web copy and `first_run`
  `distinct_id`
- Glama still has no real listing for the punkpeye badge requirement
- a target directory requires payment, CAPTCHA, anti-bot bypass, private account
  action, or owner identity input
