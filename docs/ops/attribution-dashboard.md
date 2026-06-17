# Attribution dashboard runbook

Purpose: make the growth funnel measurable without weakening the public privacy
contract. This is an operator runbook for the PostHog project behind
`accint.xyz`; it does not change installer behavior and it does not require any
prompt, file, memory, or Work Model data.

## Event contract

The attribution chain is intentionally narrow:

| Stage | Event / artifact | Identity | Properties |
|---|---|---|---|
| Web page view | `landing_viewed` on `index.html` / `reddit/index.html` | generated `install_ref` via `posthog.identify(install_ref)` | `install_ref`, `landing`, `utm_*`, `ref`, `rsub`, `thread`, `entry`, `ref_source`, and `ref_host` when present |
| Copy install text | `install_command_copied` | same generated `install_ref` | `method` (`agent_prompt` or `manual_command`), `os`, `placement`, `install_ref`, source props |
| Share AccInt link | `share_link_clicked`, `share_link_copied` | same generated `install_ref` | `surface` such as `visitor-share` or `reddit-share`, `mode` for copied/shared completion, source props; no raw inbound referrer URL |
| Reddit community action | `reddit_community_clicked`, `reddit_post_template_clicked` | same generated `install_ref` | `destination`, `template`, `placement`, source props; no raw inbound referrer URL or account identity |
| Installer | `install-attribution.env` local receipt | copied `ACC_INSTALL_REF` | local `ref` plus optional `source_ref` from copied `ACC_INSTALL_SOURCE`; not sent by the installer |
| App telemetry | `first_run`, `daily_rollup`, lifecycle events | `distinct_id = telemetry_install_ref` when present, otherwise random device UUID | `first_run.has_install_ref`, `os`, `agent`, `project_lang`; no raw prompt/file/memory data |

The app side uses the sanitized attribution ref as the anonymous `distinct_id`
so web copy events and app first-run events can join without adding raw refs to
every event payload. Prompt copies also carry coarse source context in
`ACC_INSTALL_SOURCE` so a forwarded/pasted prompt can preserve `ref`, UTM, or
referrer category in the local receipt. Keep this boundary: raw installer refs
and sources are not normal event properties. `scripts/check-attribution-flow.js`
guards the web side, and private telemetry tests guard the app side.

For organic inbound links without explicit campaign parameters, the page records
only a coarse referrer source and host such as `github` / `github.com`. It does
not record the full inbound URL or path.

PostHog mechanics this relies on:

- `identify()` creates identified events/person profiles when
  `person_profiles` is `identified_only`.
- Funnels can break down by event properties, person properties, or cohorts.
- HogQL / SQL insights can query `events`, `distinct_id`, and `properties.*`
  directly, including `uniqExact()` for exact distinct counts.

See PostHog docs:
[identify](https://posthog.com/docs/product-analytics/identify),
[funnels](https://posthog.com/docs/product-analytics/funnels),
[SQL](https://posthog.com/docs/sql), and
[SQL expressions](https://posthog.com/docs/sql/expressions).

## Dashboard tiles

Create a dashboard named `AccInt install attribution`.

The materialized dashboard spec lives at
[`posthog-dashboard.json`](posthog-dashboard.json). Before creating or changing
the live PostHog dashboard, run:

```bash
node scripts/prepare-posthog-dashboard.js --check
node scripts/prepare-posthog-dashboard.js --print
node scripts/prepare-posthog-dashboard.js --ui-packet
scripts/run-approved-posthog-dashboard.sh
scripts/run-approved-posthog-funnel-check.sh
```

This is local-only: it validates and prints the dashboard shape without calling
PostHog or using credentials.

After explicit owner approval, create the live dashboard shell and setup tile
through the PostHog Dashboard API:

```bash
POSTHOG_HOST=https://app.posthog.com \
POSTHOG_ENVIRONMENT_ID=<environment-id> \
POSTHOG_PERSONAL_API_KEY=<personal-api-key> \
ACC_APPROVE_POSTHOG_DASHBOARD=1 \
  scripts/run-approved-posthog-dashboard.sh
```

The helper requires `dashboard:read` and `dashboard:write`, checks for an
existing exact dashboard name before creating a new shell, and does not create
undocumented insight payloads. Add the nine insight tiles from the generated UI
packet in the PostHog UI:

```bash
node scripts/prepare-posthog-dashboard.js --ui-packet
```

After the live dashboard exists and a controlled install has been run, read the
aggregate funnel, direct install refs, owned share loop, and Reddit community
loop:

```bash
POSTHOG_HOST=https://us.posthog.com \
POSTHOG_PROJECT_ID=<project-id> \
POSTHOG_PERSONAL_API_KEY=<personal-api-key> \
ACC_APPROVE_POSTHOG_QUERY=1 \
  scripts/run-approved-posthog-funnel-check.sh
```

Set `ACC_CONTROLLED_DISTINCT_ID=<install_ref copied from the live page>` to
verify one controlled browser-copy install. This uses the documented PostHog
Query API for small aggregate HogQL readouts, including `share_link_copied`
counts, direct `llms-txt` and `gh-*` install refs, owned-share referred
visitor/install conversion, and Reddit community action rates; it is not an
event export path.

### 1. Copy to first run funnel

Type: Funnel.

Steps:

1. `install_command_copied`
2. `first_run`

Settings:

- Conversion window: 7 days.
- Breakdown: `method`, then duplicate the insight with `placement`.
- Filter step 2: `has_install_ref = true`.
- Exclude internal QA by date range or a PostHog cohort if one exists; do not
  encode maintainer identity into event payloads.

Expected use:

- `method=agent_prompt` should be the primary lane. If manual converts better,
  the copy or agent prompt is leaking trust.
- `placement=hero` vs `placement=final` tells whether readers convert early or
  only after the full explanation.

### 2. Web copy source leaderboard

Type: SQL insight, table.

```sql
SELECT
    multiIf(
        properties.utm_campaign IS NOT NULL AND properties.utm_campaign != '', properties.utm_campaign,
        properties.rsub IS NOT NULL AND properties.rsub != '', properties.rsub,
        properties.ref IS NOT NULL AND properties.ref != '', properties.ref,
        properties.utm_source IS NOT NULL AND properties.utm_source != '', properties.utm_source,
        properties.ref_source IS NOT NULL AND properties.ref_source != '', properties.ref_source,
        properties.ref_host IS NOT NULL AND properties.ref_host != '', properties.ref_host,
        properties.placement IS NOT NULL AND properties.placement != '', properties.placement,
        'unknown'
    ) AS surface,
    properties.method AS method,
    uniqExact(distinct_id) AS copied_people,
    count() AS copy_events
FROM events
WHERE event = 'install_command_copied'
  AND {filters}
GROUP BY surface, method
ORDER BY copied_people DESC
LIMIT 25
```

Expected use:

- This ranks where install intent begins, not whether the install finished.
- `surface=unknown` should shrink as campaign links and Reddit thread params
  are used consistently.

### 3. Landing to copy to first run by surface

Type: SQL insight, table.

```sql
WITH
landings AS (
    SELECT
        distinct_id,
        min(timestamp) AS landed_at,
        any(properties.landing) AS landing,
        any(properties.utm_source) AS utm_source,
        any(properties.utm_campaign) AS utm_campaign,
        any(properties.ref) AS ref,
        any(properties.ref_source) AS ref_source,
        any(properties.ref_host) AS ref_host,
        any(properties.rsub) AS rsub
    FROM events
    WHERE event = 'landing_viewed'
      AND {filters}
    GROUP BY distinct_id
),
copies AS (
    SELECT
        distinct_id,
        min(timestamp) AS copied_at
    FROM events
    WHERE event = 'install_command_copied'
      AND {filters}
    GROUP BY distinct_id
),
first_runs AS (
    SELECT
        distinct_id,
        min(timestamp) AS first_run_at
    FROM events
    WHERE event = 'first_run'
      AND properties.has_install_ref = 'true'
      AND {filters}
    GROUP BY distinct_id
)
SELECT
    multiIf(
        l.utm_campaign IS NOT NULL AND l.utm_campaign != '', l.utm_campaign,
        l.rsub IS NOT NULL AND l.rsub != '', l.rsub,
        l.ref IS NOT NULL AND l.ref != '', l.ref,
        l.utm_source IS NOT NULL AND l.utm_source != '', l.utm_source,
        l.ref_source IS NOT NULL AND l.ref_source != '', l.ref_source,
        l.ref_host IS NOT NULL AND l.ref_host != '', l.ref_host,
        l.landing IS NOT NULL AND l.landing != '', l.landing,
        'unknown'
    ) AS surface,
    l.landing AS landing,
    uniqExact(l.distinct_id) AS visitors,
    uniqExact(c.distinct_id) AS copied_people,
    uniqExact(f.distinct_id) AS first_runs,
    round(100.0 * copied_people / visitors, 1) AS copy_rate_pct,
    round(100.0 * first_runs / visitors, 1) AS visit_to_run_pct
FROM landings l
LEFT JOIN copies c ON c.distinct_id = l.distinct_id
    AND c.copied_at >= l.landed_at
    AND c.copied_at < l.landed_at + interval 7 day
LEFT JOIN first_runs f ON f.distinct_id = l.distinct_id
    AND f.first_run_at >= l.landed_at
    AND f.first_run_at < l.landed_at + interval 7 day
GROUP BY surface, landing
ORDER BY first_runs DESC, copied_people DESC, visitors DESC
LIMIT 25
```

Expected use:

- This is the traffic quality tile: it shows whether a launch surface sends
  readers who copy and run, not only whether copied users complete install.
- High visitors with low `copy_rate_pct` means the landing copy or channel fit
  is weak; high copy rate with low `visit_to_run_pct` means install trust or
  first-run reliability needs work.

### 4. Attributed first runs

Type: SQL insight, number or table.

```sql
SELECT
    uniqExact(distinct_id) AS attributed_first_runs
FROM events
WHERE event = 'first_run'
  AND properties.has_install_ref = 'true'
  AND {filters}
```

Expected use:

- This is the compact headline count for attributed app starts.
- Use the direct-ref tile below to split stable installer refs from generated
  web-copy refs.

### 5. Direct install refs by source

Type: SQL insight, table.

```sql
SELECT
    multiIf(
        distinct_id = 'llms-txt', 'llm-discovery',
        match(distinct_id, '^gh-'), 'github-directory-pr',
        match(distinct_id, '^github-'), 'github-owned-surface',
        match(distinct_id, '^reddit-'), 'reddit-surface',
        match(distinct_id, '^(hn|x)-'), 'social-surface',
        match(distinct_id, '^[0-9a-f]{12}$'), 'web-copy-ref',
        'other-ref'
    ) AS ref_class,
    distinct_id AS install_ref,
    count() AS first_run_events,
    min(timestamp) AS first_seen,
    max(timestamp) AS last_seen
FROM events
WHERE event = 'first_run'
  AND properties.has_install_ref = 'true'
  AND {filters}
GROUP BY ref_class, install_ref
ORDER BY first_run_events DESC, last_seen DESC
LIMIT 50
```

This is the directory win tile: it catches installs where a reader copied an
attributed command from a listing, PR, docs page, or maintainer reply and went
straight to first run.

Expected use:

- Treat `github-directory-pr` rows as the first signal that directory/listing
  placements are producing installs.
- Treat `llm-discovery` rows as direct installs from `llms.txt` or an agent that
  copied the discovery-file installer without a preceding browser copy event.
- `first_run_events` is intentionally event-count based because stable direct
  refs can be reused by many installs.
- Use `install_ref` to map back to generated refs from
  `node scripts/prepare-directory-surface-refs.js --markdown docs/ops/growth-report.md`.
- Use the web-copy source and landing tiles for `web-copy-ref` rows, because
  those generated refs need their source context from page events.

### 6. Copy to attributed first run by surface

Type: SQL insight, table.

```sql
WITH
copies AS (
    SELECT
        distinct_id,
        min(timestamp) AS copied_at,
        any(properties.method) AS method,
        any(properties.placement) AS placement,
        any(properties.utm_source) AS utm_source,
        any(properties.utm_campaign) AS utm_campaign,
        any(properties.ref) AS ref,
        any(properties.ref_source) AS ref_source,
        any(properties.ref_host) AS ref_host,
        any(properties.rsub) AS rsub
    FROM events
    WHERE event = 'install_command_copied'
      AND {filters}
    GROUP BY distinct_id
),
first_runs AS (
    SELECT
        distinct_id,
        min(timestamp) AS first_run_at
    FROM events
    WHERE event = 'first_run'
      AND properties.has_install_ref = 'true'
      AND {filters}
    GROUP BY distinct_id
)
SELECT
    multiIf(
        c.utm_campaign IS NOT NULL AND c.utm_campaign != '', c.utm_campaign,
        c.rsub IS NOT NULL AND c.rsub != '', c.rsub,
        c.ref IS NOT NULL AND c.ref != '', c.ref,
        c.utm_source IS NOT NULL AND c.utm_source != '', c.utm_source,
        c.ref_source IS NOT NULL AND c.ref_source != '', c.ref_source,
        c.ref_host IS NOT NULL AND c.ref_host != '', c.ref_host,
        c.placement IS NOT NULL AND c.placement != '', c.placement,
        'unknown'
    ) AS surface,
    c.method AS method,
    uniqExact(c.distinct_id) AS copied_people,
    uniqExact(f.distinct_id) AS first_runs,
    round(100.0 * first_runs / copied_people, 1) AS conversion_pct
FROM copies c
LEFT JOIN first_runs f ON f.distinct_id = c.distinct_id
    AND f.first_run_at >= c.copied_at
    AND f.first_run_at < c.copied_at + interval 7 day
GROUP BY surface, method
ORDER BY first_runs DESC, copied_people DESC
LIMIT 25
```

Expected use:

- This is the core growth tile: rank surfaces by completed attributed installs,
  not by impressions or copy clicks.
- If `copied_people` is high and `first_runs` is low, fix installer trust,
  prompt wording, or first-run reliability before adding more traffic.

### 7. Owned share loop

Type: SQL insight, table.

```sql
WITH
shares AS (
    SELECT
        properties.surface AS surface,
        uniqExact(distinct_id) AS sharers,
        count() AS share_events
    FROM events
    WHERE event = 'share_link_copied'
      AND properties.surface IS NOT NULL
      AND properties.surface != ''
      AND {filters}
    GROUP BY surface
),
landings AS (
    SELECT
        distinct_id,
        min(timestamp) AS landed_at,
        properties.ref AS surface
    FROM events
    WHERE event = 'landing_viewed'
      AND properties.utm_source = 'share'
      AND properties.ref IS NOT NULL
      AND properties.ref != ''
      AND {filters}
    GROUP BY distinct_id, surface
),
copies AS (
    SELECT
        distinct_id,
        min(timestamp) AS copied_at
    FROM events
    WHERE event = 'install_command_copied'
      AND {filters}
    GROUP BY distinct_id
),
first_runs AS (
    SELECT
        distinct_id,
        min(timestamp) AS first_run_at
    FROM events
    WHERE event = 'first_run'
      AND properties.has_install_ref = 'true'
      AND {filters}
    GROUP BY distinct_id
)
SELECT
    s.surface AS surface,
    s.sharers AS sharers,
    s.share_events AS share_events,
    uniqExact(l.distinct_id) AS referred_visitors,
    uniqExact(c.distinct_id) AS referred_copied_people,
    uniqExact(f.distinct_id) AS referred_first_runs,
    if(s.share_events = 0, 0, round(1.0 * referred_visitors / s.share_events, 2)) AS visitors_per_share,
    if(referred_visitors = 0, 0, round(100.0 * referred_first_runs / referred_visitors, 1)) AS referred_visit_to_run_pct
FROM shares s
LEFT JOIN landings l ON l.surface = s.surface
LEFT JOIN copies c ON c.distinct_id = l.distinct_id
    AND c.copied_at >= l.landed_at
    AND c.copied_at < l.landed_at + interval 7 day
LEFT JOIN first_runs f ON f.distinct_id = l.distinct_id
    AND f.first_run_at >= l.landed_at
    AND f.first_run_at < l.landed_at + interval 7 day
GROUP BY s.surface, s.sharers, s.share_events
```

Expected use:

- This is the organic loop tile: it shows whether visitors are copying/sharing
  owned share URLs and whether the resulting share traffic reaches install copy
  and first run, broken out by share surface.
- `visitors_per_share` below 1 means the share CTA is not propagating yet; high
  referred visitors with low `referred_visit_to_run_pct` means the shared
  landing traffic needs stronger trust or channel fit before scaling it.

### 8. Reddit community loop

Type: SQL insight, table.

```sql
WITH
views AS (
    SELECT
        distinct_id,
        min(timestamp) AS landed_at,
        any(properties.ref) AS ref,
        any(properties.rsub) AS rsub,
        any(properties.utm_campaign) AS utm_campaign,
        any(properties.ref_source) AS ref_source
    FROM events
    WHERE event = 'reddit_landing_viewed'
      AND {filters}
    GROUP BY distinct_id
),
community AS (
    SELECT
        distinct_id,
        min(timestamp) AS community_at
    FROM events
    WHERE event = 'reddit_community_clicked'
      AND {filters}
    GROUP BY distinct_id
),
templates AS (
    SELECT
        distinct_id,
        min(timestamp) AS template_at
    FROM events
    WHERE event = 'reddit_post_template_clicked'
      AND {filters}
    GROUP BY distinct_id
)
SELECT
    multiIf(
        v.rsub IS NOT NULL AND v.rsub != '', v.rsub,
        v.ref IS NOT NULL AND v.ref != '', v.ref,
        v.utm_campaign IS NOT NULL AND v.utm_campaign != '', v.utm_campaign,
        v.ref_source IS NOT NULL AND v.ref_source != '', v.ref_source,
        'reddit'
    ) AS surface,
    uniqExact(v.distinct_id) AS reddit_visitors,
    uniqExactIf(c.distinct_id, c.community_at >= v.landed_at AND c.community_at < v.landed_at + interval 7 day) AS community_clickers,
    uniqExactIf(t.distinct_id, t.template_at >= v.landed_at AND t.template_at < v.landed_at + interval 7 day) AS template_clickers,
    if(reddit_visitors = 0, 0, round(100.0 * community_clickers / reddit_visitors, 1)) AS community_click_rate_pct,
    if(reddit_visitors = 0, 0, round(100.0 * template_clickers / reddit_visitors, 1)) AS template_click_rate_pct
FROM views v
LEFT JOIN community c ON c.distinct_id = v.distinct_id
LEFT JOIN templates t ON t.distinct_id = v.distinct_id
GROUP BY surface
ORDER BY community_clickers DESC, template_clickers DESC, reddit_visitors DESC
LIMIT 25
```

Expected use:

- This is the community-growth tile: it shows whether Reddit landing traffic
  turns into subreddit visits or concrete post-template starts.
- Use it beside install conversion. A source can be worth nurturing even before
  install conversion if it creates high-signal community posts; a source with
  visits but no community action needs a sharper community ask.

### 9. Activation after install

Type: Funnel.

Steps:

1. `first_run` with `has_install_ref = true`
2. `first_retrieve`
3. `daily_rollup`

Settings:

- Conversion window: 7 days.
- Breakdown: `agent`, then duplicate with `project_lang`.
- Optional filter: exclude `project_lang = unknown` only after enough volume.

Expected use:

- `first_run -> first_retrieve` measures whether the newcomer reaches first
  signal.
- `first_retrieve -> daily_rollup` measures whether the install survives past
  novelty.

## Release checklist

Before using this dashboard for decisions:

1. Public commits with web attribution and installer receipt are pushed and
   deployed.
2. Private telemetry bridge is released in the binary that the public installer
   fetches.
3. `bash scripts/check-integrity.sh` passes in the public repo.
4. `node scripts/prepare-posthog-dashboard.js --check` passes in the public repo.
5. A controlled install from the live page is run once with a test date range,
   then excluded from public reporting.
6. Dashboard tiles show the controlled install in `landing_viewed`,
   `install_command_copied`, and `first_run` with the same `distinct_id`.

Do not rank directories or paid surfaces from copy events alone. Rank them from
visitor-to-copy-to-first-run conversion and activation, then spend effort where
reality moved.
