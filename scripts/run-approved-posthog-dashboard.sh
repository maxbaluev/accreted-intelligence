#!/usr/bin/env bash
# Approval-gated PostHog dashboard handoff.
#
# Default mode is dry-run: validate the local dashboard spec and print the exact
# approved command. Approved mode creates only the dashboard shell and a markdown
# setup tile through documented PostHog dashboard endpoints, then points the
# owner at the local UI packet for creating the six insights. It does not create
# undocumented insight payloads, read events, export analytics, post, comment,
# submit, pay, or use account identity beyond the supplied PostHog API key.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

posthog_host="${POSTHOG_HOST:-https://app.posthog.com}"
posthog_host="${posthog_host%/}"
environment_id="${POSTHOG_ENVIRONMENT_ID:-}"
dashboard_name="${POSTHOG_DASHBOARD_NAME:-AccInt install attribution}"

usage() {
  cat <<'EOF'
usage: scripts/run-approved-posthog-dashboard.sh

Dry-run default:
  scripts/run-approved-posthog-dashboard.sh

Owner-approved dashboard shell creation:
  POSTHOG_HOST=https://app.posthog.com \
  POSTHOG_ENVIRONMENT_ID=<environment-id> \
  POSTHOG_PERSONAL_API_KEY=<personal-api-key> \
  ACC_APPROVE_POSTHOG_DASHBOARD=1 \
    scripts/run-approved-posthog-dashboard.sh

Optional:
  POSTHOG_DASHBOARD_NAME="AccInt install attribution"
  ACC_POSTHOG_ALLOW_DUPLICATE=1

Approved mode requires a personal API key with dashboard:read and
dashboard:write scopes. It checks for an existing exact dashboard name before
creating a new dashboard shell, then adds a markdown text tile with the six
required insight specs from docs/ops/posthog-dashboard.json. Use
`node scripts/prepare-posthog-dashboard.js --ui-packet` for field-by-field
PostHog UI input.

It does not create insight tiles through undocumented APIs, read event data,
export analytics, post, comment, submit, pay, or use account identity outside
the supplied PostHog API key.
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

echo "== PostHog dashboard handoff =="
printf '  host: %s\n' "$posthog_host"
printf '  environment: %s\n' "${environment_id:-<set POSTHOG_ENVIRONMENT_ID for approved mode>}"
printf '  dashboard: %s\n' "$dashboard_name"

echo
echo "== local dashboard spec =="
node scripts/prepare-posthog-dashboard.js --check

echo
echo "== handoff summary =="
POSTHOG_DASHBOARD_NAME="$dashboard_name" python3 - <<'PY'
import json
import os
from pathlib import Path

spec = json.loads(Path("docs/ops/posthog-dashboard.json").read_text())
tiles = spec["dashboard"]["tiles"]
print(f"  name: {os.environ['POSTHOG_DASHBOARD_NAME']}")
print(f"  tiles to create manually after shell: {len(tiles)}")
print("  UI packet: node scripts/prepare-posthog-dashboard.js --ui-packet")
for index, tile in enumerate(tiles, 1):
    if tile["type"] == "funnel":
        steps = " -> ".join(step["event"] for step in tile["steps"])
        print(f"  {index}. {tile['title']} [funnel: {steps}]")
    else:
        print(f"  {index}. {tile['title']} [sql: {tile['display']}]")
PY

cat <<EOF

== approved dashboard command ==
This helper can perform one approved PostHog dashboard mutation:

  POSTHOG_HOST=$posthog_host \\
  POSTHOG_ENVIRONMENT_ID=<environment-id> \\
  POSTHOG_PERSONAL_API_KEY=<personal-api-key> \\
  ACC_APPROVE_POSTHOG_DASHBOARD=1 \\
    scripts/run-approved-posthog-dashboard.sh

Approved mode:
  1. GET  $posthog_host/api/environments/<environment-id>/dashboards/?search=<dashboard>
  2. POST $posthog_host/api/environments/<environment-id>/dashboards/
  3. POST $posthog_host/api/environments/<environment-id>/dashboards/<id>/create_text_tile/

Then create the six insight tiles from:

  node scripts/prepare-posthog-dashboard.js --ui-packet
EOF

if [ "${ACC_APPROVE_POSTHOG_DASHBOARD:-0}" != "1" ]; then
  echo
  echo "DRY RUN COMPLETE: no PostHog API call was performed."
  exit 0
fi

if [ -z "${POSTHOG_PERSONAL_API_KEY:-}" ]; then
  printf 'refusing: POSTHOG_PERSONAL_API_KEY is required for approved mode\n' >&2
  exit 1
fi
if [ -z "$environment_id" ]; then
  printf 'refusing: POSTHOG_ENVIRONMENT_ID is required for approved mode\n' >&2
  exit 1
fi

echo
echo "== approved PostHog dashboard mutation =="
POSTHOG_HOST="$posthog_host" \
POSTHOG_ENVIRONMENT_ID="$environment_id" \
POSTHOG_DASHBOARD_NAME="$dashboard_name" \
POSTHOG_PERSONAL_API_KEY="$POSTHOG_PERSONAL_API_KEY" \
ACC_POSTHOG_ALLOW_DUPLICATE="${ACC_POSTHOG_ALLOW_DUPLICATE:-0}" \
  python3 - <<'PY'
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

host = os.environ["POSTHOG_HOST"].rstrip("/")
environment_id = os.environ["POSTHOG_ENVIRONMENT_ID"]
dashboard_name = os.environ["POSTHOG_DASHBOARD_NAME"]
api_key = os.environ["POSTHOG_PERSONAL_API_KEY"]
allow_duplicate = os.environ.get("ACC_POSTHOG_ALLOW_DUPLICATE") == "1"
spec = json.loads(Path("docs/ops/posthog-dashboard.json").read_text())

def request(method, path, payload=None):
    body = None
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
    }
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(f"{host}{path}", data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            data = response.read().decode("utf-8")
            if not data:
                return {}
            return json.loads(data)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"PostHog API {method} {path} failed: HTTP {exc.code}: {detail}") from exc

def setup_markdown():
    lines = [
        "# AccInt install attribution setup",
        "",
        "This dashboard shell was created from `docs/ops/posthog-dashboard.json`.",
        "Create the insight tiles below in PostHog's UI from `node scripts/prepare-posthog-dashboard.js --ui-packet`, then use this dashboard to rank growth surfaces from visitor-to-copy-to-first-run conversion and activation, not copy events alone.",
        "",
        "Privacy contract: no raw prompt text, file contents, memory contents, Work Model data, or full inbound referrer URLs.",
        "",
        "## Required tiles",
    ]
    for index, tile in enumerate(spec["dashboard"]["tiles"], 1):
        lines.extend(["", f"### {index}. {tile['title']}", "", f"Type: `{tile['type']}`."])
        if tile["type"] == "funnel":
            steps = " -> ".join(step["event"] for step in tile["steps"])
            breakdowns = ", ".join(tile["breakdowns"])
            lines.extend([
                "",
                f"Steps: `{steps}`.",
                f"Conversion window: `{tile['conversion_window_days']} days`.",
                f"Breakdowns: `{breakdowns}`.",
            ])
        else:
            lines.extend(["", f"Display: `{tile['display']}`.", "", "```sql", tile["hogql"], "```"])
    lines.extend([
        "",
        "Release gate: run a controlled install from the live page, then confirm `install_command_copied` and `first_run` share the same `distinct_id` before ranking surfaces.",
    ])
    return "\n".join(lines)

search = urllib.parse.urlencode({"search": dashboard_name})
existing = request("GET", f"/api/environments/{environment_id}/dashboards/?{search}")
matches = [
    item for item in existing.get("results", [])
    if item.get("name") == dashboard_name and not item.get("deleted")
]
if matches and not allow_duplicate:
    ids = ", ".join(str(item.get("id")) for item in matches)
    raise SystemExit(
        f"refusing: dashboard named {dashboard_name!r} already exists (id(s): {ids}); "
        "set ACC_POSTHOG_ALLOW_DUPLICATE=1 only if a duplicate shell is intentional"
    )

dashboard_payload = {
    "name": dashboard_name,
    "description": spec["dashboard"]["description"],
    "pinned": True,
    "tags": ["accint", "growth", "attribution"],
}
dashboard = request("POST", f"/api/environments/{environment_id}/dashboards/", dashboard_payload)
dashboard_id = dashboard.get("id")
if dashboard_id is None:
    raise SystemExit(f"PostHog dashboard response did not include an id: {dashboard!r}")

text_tile = request(
    "POST",
    f"/api/environments/{environment_id}/dashboards/{dashboard_id}/create_text_tile/",
    {"body": setup_markdown()},
)

print(f"  dashboard id: {dashboard_id}")
print(f"  setup text tile id: {text_tile.get('id', '<unknown>')}")
print("POSTHOG DASHBOARD SHELL: CREATED")
PY
