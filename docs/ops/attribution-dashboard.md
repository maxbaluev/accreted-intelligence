# Attribution dashboard runbook

Purpose: make the growth funnel measurable without weakening the public privacy
contract. This is an operator runbook for the PostHog project behind
`accint.xyz`; it does not change installer behavior and it does not require any
prompt, file, memory, or Work Model data.

## Event contract

The attribution chain is intentionally narrow:

| Stage | Event / artifact | Identity | Properties |
|---|---|---|---|
| Web page view | page script on `index.html` / `reddit/index.html` | generated `install_ref` via `posthog.identify(install_ref)` | `install_ref` session property plus `landing`, `utm_*`, `ref`, `rsub`, `thread`, `entry`, `ref_source`, and `ref_host` when present |
| Copy install text | `install_command_copied` | same generated `install_ref` | `method` (`agent_prompt` or `manual_command`), `os`, `placement`, `install_ref`, source props |
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

### 3. Attributed first runs

Type: SQL insight, number or table.

```sql
SELECT
    uniqExact(distinct_id) AS attributed_first_runs
FROM events
WHERE event = 'first_run'
  AND properties.has_install_ref = 'true'
  AND {filters}
```

Optional table version:

```sql
SELECT
    multiIf(
        match(distinct_id, '^[0-9a-f]{12}$'), 'web-copy-ref',
        match(distinct_id, '^gh-'), distinct_id,
        match(distinct_id, '^reddit'), distinct_id,
        'other-ref'
    ) AS ref_class,
    uniqExact(distinct_id) AS first_runs
FROM events
WHERE event = 'first_run'
  AND properties.has_install_ref = 'true'
  AND {filters}
GROUP BY ref_class
ORDER BY first_runs DESC
```

Expected use:

- `web-copy-ref` means the install came from a web-generated nonce; use the
  join tile below for the source.
- Direct labels such as `gh-awesome-list` show installs from docs, PRs, or
  directory listings where the command itself carried a stable surface label.

### 4. Copy to attributed first run by surface

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

### 5. Activation after install

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
4. A controlled install from the live page is run once with a test date range,
   then excluded from public reporting.
5. Dashboard tiles show the controlled install in both `install_command_copied`
   and `first_run` with the same `distinct_id`.

Do not rank directories or paid surfaces from copy events alone. Rank them from
attributed first runs and activation, then spend effort where reality moved.
