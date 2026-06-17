#!/usr/bin/env bash
# Approval-gated PostHog growth funnel readout.
#
# Default mode is dry-run: validate the local dashboard spec and print the exact
# approved command. Approved mode runs small aggregate HogQL queries through the
# documented PostHog Query API so launch channels can be ranked by attributed
# first runs and activation, not copy clicks. It does not export raw events,
# mutate PostHog, post, comment, submit, pay, or use account identity beyond the
# supplied PostHog API key.
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
  1. copy events, copied people, attributed first runs, first retrieves, daily rollups
  2. copy-to-attributed-first-run conversion by surface and method
  3. activation after attributed first run
  4. optional controlled distinct_id event presence
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
    countIf(event = 'install_command_copied') AS copy_events,
    uniqExactIf(distinct_id, event = 'install_command_copied') AS copied_people,
    uniqExactIf(distinct_id, event = 'first_run' AND properties.has_install_ref = 'true') AS attributed_first_runs,
    uniqExactIf(distinct_id, event = 'first_retrieve') AS first_retrieves,
    uniqExactIf(distinct_id, event = 'daily_rollup') AS daily_rollups
FROM events
WHERE {window}
  AND event IN ('install_command_copied', 'first_run', 'first_retrieve', 'daily_rollup')
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
    ("surface conversion", surface_sql),
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
  AND event IN ('install_command_copied', 'first_run', 'first_retrieve', 'daily_rollup')
GROUP BY event
ORDER BY first_seen ASC
LIMIT 10
""".strip()
    queries.append((f"controlled distinct_id {controlled_id}", controlled_sql))

for name, sql in queries:
    print_table(name, run_query(name, sql))

print("\nPOSTHOG GROWTH FUNNEL CHECK: COMPLETE")
PY
