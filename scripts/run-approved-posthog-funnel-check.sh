#!/usr/bin/env bash
# Approval-gated PostHog growth funnel readout.
#
# Default mode is dry-run: validate the local dashboard spec and print the exact
# approved command. Approved mode runs small aggregate HogQL queries through the
# documented PostHog Query API so launch channels can be ranked by attributed
# visitor-to-copy-to-first-run conversion, share-loop propagation, and
# activation, not copy clicks. It does not export raw events, mutate PostHog,
# post, comment, submit, pay, or use account identity beyond the supplied
# PostHog API key.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

posthog_host="${POSTHOG_HOST:-https://us.posthog.com}"
posthog_host="${posthog_host%/}"
project_id="${POSTHOG_PROJECT_ID:-}"
days="${POSTHOG_FUNNEL_DAYS:-7}"
controlled_id="${ACC_CONTROLLED_DISTINCT_ID:-}"

usage() {
  cat <<'EOF'
usage: scripts/run-approved-posthog-funnel-check.sh

Dry-run default:
  scripts/run-approved-posthog-funnel-check.sh

Owner-approved read-only funnel query:
  POSTHOG_HOST=https://us.posthog.com \
  POSTHOG_PROJECT_ID=<project-id> \
  POSTHOG_PERSONAL_API_KEY=<personal-api-key> \
  ACC_APPROVE_POSTHOG_QUERY=1 \
    scripts/run-approved-posthog-funnel-check.sh

Optional:
  POSTHOG_FUNNEL_DAYS=7
  ACC_CONTROLLED_DISTINCT_ID=<install_ref copied from the live page>

Approved mode requires a personal API key with Query Read permission. It runs
small aggregate HogQL queries through /api/projects/:project_id/query/ and does
not export raw event rows or mutate PostHog.
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

need node
need python3

case "$days" in
  ''|*[!0-9]*)
    printf 'refusing: POSTHOG_FUNNEL_DAYS must be an integer\n' >&2
    exit 1
    ;;
esac
if [ "$days" -lt 1 ] || [ "$days" -gt 90 ]; then
  printf 'refusing: POSTHOG_FUNNEL_DAYS must be between 1 and 90\n' >&2
  exit 1
fi

echo "== PostHog growth funnel check =="
printf '  host: %s\n' "$posthog_host"
printf '  project: %s\n' "${project_id:-<set POSTHOG_PROJECT_ID for approved mode>}"
printf '  lookback days: %s\n' "$days"
printf '  controlled distinct_id: %s\n' "${controlled_id:-<optional>}"

echo
echo "== local dashboard spec =="
node scripts/prepare-posthog-dashboard.js --check

cat <<EOF

== approved read-only query command ==
This helper can perform one approved PostHog read-only funnel check:

  POSTHOG_HOST=$posthog_host \\
  POSTHOG_PROJECT_ID=<project-id> \\
  POSTHOG_PERSONAL_API_KEY=<personal-api-key> \\
  ACC_APPROVE_POSTHOG_QUERY=1 \\
    scripts/run-approved-posthog-funnel-check.sh

Approved mode runs aggregate HogQL via:

  POST $posthog_host/api/projects/<project-id>/query/

Readouts:
  1. landing views, share events, Reddit community actions, copy events, attributed first-run events, first retrieves, daily rollups
  2. landing-to-copy-to-first-run conversion by surface
  3. copy-to-attributed-first-run conversion by surface and method
  4. direct install refs by source, including llms-txt discovery and gh-* directory/listing refs
  5. owned share loop
  6. Reddit community loop
  7. activation after attributed first run
  8. optional controlled distinct_id event presence
EOF

if [ "${ACC_APPROVE_POSTHOG_QUERY:-0}" != "1" ]; then
  echo
  echo "DRY RUN COMPLETE: no PostHog API call was performed."
  exit 0
fi

if [ -z "${POSTHOG_PERSONAL_API_KEY:-}" ]; then
  printf 'refusing: POSTHOG_PERSONAL_API_KEY is required for approved mode\n' >&2
  exit 1
fi
if [ -z "$project_id" ]; then
  printf 'refusing: POSTHOG_PROJECT_ID is required for approved mode\n' >&2
  exit 1
fi

echo
echo "== approved PostHog read-only funnel query =="
POSTHOG_HOST="$posthog_host" \
POSTHOG_PROJECT_ID="$project_id" \
POSTHOG_PERSONAL_API_KEY="$POSTHOG_PERSONAL_API_KEY" \
POSTHOG_FUNNEL_DAYS="$days" \
ACC_CONTROLLED_DISTINCT_ID="$controlled_id" \
  python3 - <<'PY'
import json
import os
import urllib.error
import urllib.request

host = os.environ["POSTHOG_HOST"].rstrip("/")
project_id = os.environ["POSTHOG_PROJECT_ID"]
api_key = os.environ["POSTHOG_PERSONAL_API_KEY"]
days = int(os.environ["POSTHOG_FUNNEL_DAYS"])
controlled_id = os.environ.get("ACC_CONTROLLED_DISTINCT_ID", "")

def run_query(name, sql):
    payload = {"query": {"kind": "HogQLQuery", "query": sql, "name": name}}
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{host}/api/projects/{project_id}/query/",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"PostHog Query API failed for {name}: HTTP {exc.code}: {detail}") from exc

def print_table(name, result):
    print(f"\n== {name} ==")
    columns = result.get("columns") or []
    rows = result.get("results") or []
    if not rows:
        print("  <no rows>")
        return
    print("  " + " | ".join(str(col) for col in columns))
    for row in rows:
        print("  " + " | ".join(str(value) for value in row))

window = f"timestamp >= now() - INTERVAL {days} DAY"

summary_sql = f"""
SELECT
    countIf(event = 'landing_viewed') AS landing_events,
    uniqExactIf(distinct_id, event = 'landing_viewed') AS landing_people,
    countIf(event = 'reddit_landing_viewed') AS reddit_landing_events,
    uniqExactIf(distinct_id, event = 'reddit_landing_viewed') AS reddit_landing_people,
    countIf(event = 'share_link_copied') AS share_events,
    uniqExactIf(distinct_id, event = 'share_link_copied') AS sharers,
    countIf(event = 'reddit_community_clicked') AS reddit_community_click_events,
    uniqExactIf(distinct_id, event = 'reddit_community_clicked') AS reddit_community_clickers,
    countIf(event = 'reddit_post_template_clicked') AS reddit_template_click_events,
    uniqExactIf(distinct_id, event = 'reddit_post_template_clicked') AS reddit_template_clickers,
    countIf(event = 'install_command_copied') AS copy_events,
    uniqExactIf(distinct_id, event = 'install_command_copied') AS copied_people,
    countIf(event = 'first_run' AND properties.has_install_ref = 'true') AS attributed_first_run_events,
    uniqExactIf(distinct_id, event = 'first_run' AND properties.has_install_ref = 'true') AS attributed_first_runs,
    uniqExactIf(distinct_id, event = 'first_retrieve') AS first_retrieves,
    uniqExactIf(distinct_id, event = 'daily_rollup') AS daily_rollups
FROM events
WHERE {window}
  AND event IN ('landing_viewed', 'reddit_landing_viewed', 'share_link_copied', 'reddit_community_clicked', 'reddit_post_template_clicked', 'install_command_copied', 'first_run', 'first_retrieve', 'daily_rollup')
""".strip()

traffic_sql = f"""
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
      AND {window}
    GROUP BY distinct_id
),
copies AS (
    SELECT
        distinct_id,
        min(timestamp) AS copied_at
    FROM events
    WHERE event = 'install_command_copied'
      AND {window}
    GROUP BY distinct_id
),
first_runs AS (
    SELECT
        distinct_id,
        min(timestamp) AS first_run_at
    FROM events
    WHERE event = 'first_run'
      AND properties.has_install_ref = 'true'
      AND {window}
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
""".strip()

surface_sql = f"""
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
      AND {window}
    GROUP BY distinct_id
),
first_runs AS (
    SELECT
        distinct_id,
        min(timestamp) AS first_run_at
    FROM events
    WHERE event = 'first_run'
      AND properties.has_install_ref = 'true'
      AND {window}
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
""".strip()

direct_refs_sql = f"""
SELECT
    multiIf(
        distinct_id = 'llms-txt', 'llm-discovery',
        match(distinct_id, '^gh-'), 'github-directory-pr',
        match(distinct_id, '^github-'), 'github-owned-surface',
        match(distinct_id, '^reddit-'), 'reddit-surface',
        match(distinct_id, '^(hn|x)-'), 'social-surface',
        match(distinct_id, '^[0-9a-f]{{12}}$'), 'web-copy-ref',
        'other-ref'
    ) AS ref_class,
    distinct_id AS install_ref,
    count() AS first_run_events,
    min(timestamp) AS first_seen,
    max(timestamp) AS last_seen
FROM events
WHERE event = 'first_run'
  AND properties.has_install_ref = 'true'
  AND {window}
GROUP BY ref_class, install_ref
ORDER BY first_run_events DESC, last_seen DESC
LIMIT 50
""".strip()

share_loop_sql = f"""
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
      AND {window}
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
      AND {window}
    GROUP BY distinct_id, surface
),
copies AS (
    SELECT
        distinct_id,
        min(timestamp) AS copied_at
    FROM events
    WHERE event = 'install_command_copied'
      AND {window}
    GROUP BY distinct_id
),
first_runs AS (
    SELECT
        distinct_id,
        min(timestamp) AS first_run_at
    FROM events
    WHERE event = 'first_run'
      AND properties.has_install_ref = 'true'
      AND {window}
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
""".strip()

reddit_community_sql = f"""
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
      AND {window}
    GROUP BY distinct_id
),
community AS (
    SELECT
        distinct_id,
        min(timestamp) AS community_at
    FROM events
    WHERE event = 'reddit_community_clicked'
      AND {window}
    GROUP BY distinct_id
),
templates AS (
    SELECT
        distinct_id,
        min(timestamp) AS template_at
    FROM events
    WHERE event = 'reddit_post_template_clicked'
      AND {window}
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
""".strip()

activation_sql = f"""
WITH
first_runs AS (
    SELECT distinct_id, min(timestamp) AS first_run_at
    FROM events
    WHERE event = 'first_run'
      AND properties.has_install_ref = 'true'
      AND {window}
    GROUP BY distinct_id
),
retrieves AS (
    SELECT distinct_id, min(timestamp) AS first_retrieve_at
    FROM events
    WHERE event = 'first_retrieve'
      AND {window}
    GROUP BY distinct_id
),
rollups AS (
    SELECT distinct_id, min(timestamp) AS daily_rollup_at
    FROM events
    WHERE event = 'daily_rollup'
      AND {window}
    GROUP BY distinct_id
)
SELECT
    uniqExact(f.distinct_id) AS attributed_first_runs,
    uniqExactIf(r.distinct_id, r.first_retrieve_at >= f.first_run_at AND r.first_retrieve_at < f.first_run_at + interval 7 day) AS reached_first_retrieve,
    uniqExactIf(d.distinct_id, d.daily_rollup_at >= f.first_run_at AND d.daily_rollup_at < f.first_run_at + interval 7 day) AS reached_daily_rollup
FROM first_runs f
LEFT JOIN retrieves r ON r.distinct_id = f.distinct_id
LEFT JOIN rollups d ON d.distinct_id = f.distinct_id
""".strip()

queries = [
    ("summary", summary_sql),
    ("traffic to first run by surface", traffic_sql),
    ("surface conversion", surface_sql),
    ("direct install refs by source", direct_refs_sql),
    ("owned share loop", share_loop_sql),
    ("reddit community loop", reddit_community_sql),
    ("activation", activation_sql),
]
if controlled_id:
    safe_controlled = controlled_id.replace("'", "''")
    controlled_sql = f"""
SELECT
    event,
    count() AS events,
    min(timestamp) AS first_seen,
    max(timestamp) AS last_seen
FROM events
WHERE {window}
  AND distinct_id = '{safe_controlled}'
  AND event IN ('landing_viewed', 'reddit_landing_viewed', 'share_link_clicked', 'share_link_copied', 'reddit_community_clicked', 'reddit_post_template_clicked', 'install_command_copied', 'first_run', 'first_retrieve', 'daily_rollup')
GROUP BY event
ORDER BY first_seen ASC
LIMIT 10
""".strip()
    queries.append((f"controlled distinct_id {controlled_id}", controlled_sql))

for name, sql in queries:
    print_table(name, run_query(name, sql))

print("\nPOSTHOG GROWTH FUNNEL CHECK: COMPLETE")
PY
