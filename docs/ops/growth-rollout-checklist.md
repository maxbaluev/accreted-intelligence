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
- attribution regression tests
- attribution dashboard/runbook docs
- organic referrer classification
- standard root `LICENSE` for GitHub license detection
- directory/listing factsheets

Do not run this from the private engine checkout. Public pushes must happen only
from the separate `maxbaluev/accreted-intelligence` clone.

## Before approval

These checks are local and safe:

```bash
bash scripts/check-growth-readiness.sh
git status --short --branch
git log --oneline origin/main..HEAD
bash scripts/check-integrity.sh
git diff --check -- .
cmp -s LICENSE LICENSE-APACHE-2.0.txt
```

Expected state:

- working tree is clean
- branch is ahead only by intended public commits
- `scripts/check-growth-readiness.sh` passes
- `scripts/check-integrity.sh` passes
- root `LICENSE` exactly matches `LICENSE-APACHE-2.0.txt`
- `docs/ops/attribution-dashboard.md` exists
- `docs/ops/directory-listing.md` exists
- no private `src/**`, `Cargo.toml`, `Cargo.lock`, private tests, or substrate
  data appear in `git diff origin/main..HEAD --name-only`

## Approval boundary

Stop here unless the owner explicitly authorizes the public push/deploy/release
step. After approval, keep each action separate and verify before continuing.

## Public push sequence

From the public clone only:

```bash
git push origin main
```

Immediately verify:

```bash
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
curl -fsSI https://accint.xyz/
curl -fsSI https://accint.xyz/reddit/
curl -fsSL https://accint.xyz/ | grep -F "ACC_INSTALL_REF"
curl -fsSL https://accint.xyz/reddit/ | grep -F "ACC_INSTALL_REF"
```

Also run a browser copy check if possible: copy the hero agent prompt and confirm
the copied text contains `ACC_INSTALL_REF=<install_ref>` on POSIX and
`$env:ACC_INSTALL_REF='<install_ref>'` on PowerShell snippets. The page should
still display clean installer text; the ref belongs only in copied text.

## Binary/release alignment

The attribution chain is incomplete until the private telemetry bridge is in a
released binary that the public installer fetches. Before treating attribution
as live:

1. Confirm the private binary release includes receipt reading from
   `install-attribution.env`.
2. Confirm the public installer resolves that release tag.
3. Confirm `sha256sums.txt` contains the expected artifact checksums.
4. Run the public install path in a controlled environment.

The controlled install should produce:

- local `install-attribution.env` with the chosen `ref=...`
- `acc doctor` success
- `first_run` telemetry with `has_install_ref=true` when telemetry is enabled
- the same anonymous ref as `distinct_id` in PostHog

## PostHog dashboard

Create the dashboard from `docs/ops/attribution-dashboard.md` after the push and
binary release are live.

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

1. Re-check Glama:
   - `https://glama.ai/mcp/servers/maxbaluev/accreted-intelligence`
   - `https://glama.ai/mcp/servers?q=accint`
2. Only if Glama has a real AccInt listing and score badge, update
   `punkpeye/awesome-mcp-servers#8091` with the badge required by that repo.
3. Use `docs/ops/directory-listing.md` for future directory/list submissions
   and reviewer replies.
4. Do not retry lists that rejected the private-engine boundary unless the
   local fix is pushed and the target list's policy can accept the boundary.

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
