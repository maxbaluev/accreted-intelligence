#!/usr/bin/env bash
# Read-only audit of the public growth surfaces.
#
# This script checks external state that can legitimately lag the local growth
# bundle: GitHub metadata, live site attribution markers, GitHub Release MCPB
# assets, registry alignment, Glama listing visibility, and the punkpeye PR.
# It never pushes, uploads, dispatches workflows, publishes registry metadata,
# posts comments, submits PRs, or creates dashboard/listing state.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

repo="${ACC_GROWTH_REPO:-maxbaluev/accreted-intelligence}"
site_url="${ACC_LIVE_SITE_URL:-https://accint.xyz}"
tag="${1:-}"
strict="${ACC_LIVE_STATE_STRICT:-0}"
site_transport_needs_diagnostic=0

holds=0
skips=0
fails=0

usage() {
  cat <<'EOF'
usage: scripts/check-growth-live-state.sh [tag]

Examples:
  scripts/check-growth-live-state.sh
  scripts/check-growth-live-state.sh v0.1.5
  ACC_LIVE_STATE_STRICT=1 scripts/check-growth-live-state.sh v0.1.5

Default mode is read-only and advisory:
  - reports live public growth state as OK / HOLD / SKIP
  - exits zero even when public state is not caught up yet

Set ACC_LIVE_STATE_STRICT=1 to exit nonzero on any HOLD, SKIP, or FAIL.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

note() { printf '  %s\n' "$1"; }
ok() { note "OK: $1"; }
hold() { note "HOLD: $1"; holds=$((holds + 1)); }
skip() { note "SKIP: $1"; skips=$((skips + 1)); }
fail() { note "FAIL: $1"; fails=$((fails + 1)); }
section() { printf '\n== %s ==\n' "$1"; }

json_field() {
  local json="$1"
  local path="$2"
  JSON_INPUT="$json" JSON_PATH="$path" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["JSON_INPUT"])
value = data
for part in os.environ["JSON_PATH"].split("."):
    if not part:
        continue
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break
if value is None:
    print("")
elif isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (list, dict)):
    print(json.dumps(value, sort_keys=True))
else:
    print(value)
PY
}

server_version="$(
  python3 - <<'PY'
import json
from pathlib import Path

print(json.loads(Path("server.json").read_text()).get("version", ""))
PY
)"

site_host="$(
  SITE_URL="$site_url" python3 - <<'PY'
import os
from urllib.parse import urlparse

print(urlparse(os.environ["SITE_URL"]).hostname or "")
PY
)"

if [ -z "$tag" ] && command -v gh >/dev/null 2>&1; then
  tag="$(gh release view --repo "$repo" --json tagName --jq '.tagName' 2>/dev/null || true)"
fi
if [ -z "$tag" ]; then
  tag="v${server_version}"
fi
case "$tag" in
  v*) : ;;
  *) tag="v$tag" ;;
esac

section "live growth state"
note "repo: $repo"
note "site: $site_url"
note "release tag: $tag"
note "mode: read-only advisory"

section "GitHub repo metadata"
if ! command -v gh >/dev/null 2>&1; then
  skip "gh CLI not found; cannot read GitHub repository metadata"
else
  repo_json="$(gh repo view "$repo" --json nameWithOwner,licenseInfo,homepageUrl,repositoryTopics 2>/dev/null || true)"
  if [ -z "$repo_json" ]; then
    skip "gh repo view unavailable for $repo"
  else
    name="$(json_field "$repo_json" "nameWithOwner")"
    license="$(json_field "$repo_json" "licenseInfo.spdxId")"
    if [ -z "$license" ]; then
      license="$(json_field "$repo_json" "licenseInfo.key")"
    fi
    case "$license" in
      apache-2.0) license="Apache-2.0" ;;
    esac
    homepage="$(json_field "$repo_json" "homepageUrl")"
    topics="$(
      JSON_INPUT="$repo_json" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["JSON_INPUT"])
topics = [topic.get("name", "") for topic in data.get("repositoryTopics", [])]
print(", ".join(topic for topic in topics if topic))
PY
    )"

    note "repository: ${name:-<unknown>}"
    note "homepage: ${homepage:-<unset>}"
    note "topics: ${topics:-<none>}"
    if [ "$license" = "Apache-2.0" ]; then
      ok "GitHub license detection is Apache-2.0"
    else
      hold "GitHub license detection is ${license:-<null>}; wait for root LICENSE indexing before OSS-first list updates"
    fi
    case "$homepage" in
      *accint.xyz*) ok "repository homepage points at accint.xyz" ;;
      *) hold "repository homepage does not point at accint.xyz" ;;
    esac
  fi
fi

fetch_status() {
  local url="$1"
  curl -fsSL -o /dev/null -w '%{http_code}' --max-time 20 "$url" 2>/dev/null || true
}

fetch_body() {
  local url="$1"
  curl -fsSL --max-time 20 "$url" 2>/dev/null || true
}

check_live_page() {
  local label="$1"
  local url="$2"
  shift 2
  local status body marker missing

  status="$(fetch_status "$url")"
  if [ "$status" = "200" ]; then
    ok "$label returns HTTP 200"
  else
    site_transport_needs_diagnostic=1
    hold "$label returned HTTP ${status:-<none>}"
    return
  fi

  body="$(fetch_body "$url")"
  if [ -z "$body" ]; then
    hold "$label body is empty or unavailable"
    return
  fi

  missing=0
  for marker in "$@"; do
    if printf '%s' "$body" | grep -Fq "$marker"; then
      :
    else
      note "MISSING: $label marker $marker"
      missing=1
    fi
  done

  if [ "$missing" -eq 0 ]; then
    ok "$label serves attribution copy markers"
  else
    hold "$label does not yet serve all attribution copy markers"
  fi
}

diagnose_site_transport() {
  local pages_json status cname html_url https_enforced cert_state pending
  local records expected_matches tls_probe http_probe

  section "live site transport diagnostics"
  note "diagnostic only: explains this runner's custom-domain reachability; it does not prove live attribution markers"
  note "host: ${site_host:-<unknown>}"

  if [ -n "$site_host" ] && command -v gh >/dev/null 2>&1; then
    pages_json="$(gh api "repos/${repo}/pages" 2>/dev/null || true)"
    if [ -n "$pages_json" ]; then
      status="$(json_field "$pages_json" "status")"
      cname="$(json_field "$pages_json" "cname")"
      html_url="$(json_field "$pages_json" "html_url")"
      https_enforced="$(json_field "$pages_json" "https_enforced")"
      cert_state="$(json_field "$pages_json" "https_certificate.state")"
      pending="$(json_field "$pages_json" "pending_domain_unverified_at")"
      note "GitHub Pages status: ${status:-<unknown>}"
      note "GitHub Pages cname: ${cname:-<unset>}"
      note "GitHub Pages html_url: ${html_url:-<unset>}"
      note "GitHub Pages https_enforced: ${https_enforced:-<unknown>}"
      note "GitHub Pages certificate: ${cert_state:-<unknown>}"
      if [ -n "$pending" ]; then
        note "GitHub Pages pending_domain_unverified_at: $pending"
      fi
      if [ "$status" = "built" ] && [ "$https_enforced" = "true" ] && [ "$cert_state" = "approved" ]; then
        ok "GitHub Pages reports built custom domain with approved enforced HTTPS"
      fi
    else
      note "GitHub Pages API unavailable for diagnostics"
    fi
  fi

  if [ -n "$site_host" ] && command -v dig >/dev/null 2>&1; then
    records="$(dig +short "$site_host" A 2>/dev/null | sort)"
    if [ -n "$records" ]; then
      note "A records: $(printf '%s\n' "$records" | tr '\n' ' ' | sed 's/ $//')"
      expected_matches="$(
        printf '%s\n' "$records" |
          grep -Ec '^(185\.199\.108\.153|185\.199\.109\.153|185\.199\.110\.153|185\.199\.111\.153)$' ||
          true
      )"
      if [ "$expected_matches" -eq 4 ]; then
        ok "apex A records match GitHub Pages"
      fi
    else
      note "A records: <none>"
    fi
  fi

  if [ -n "$site_host" ] && command -v openssl >/dev/null 2>&1; then
    tls_probe="$(
      timeout 10 openssl s_client -connect "${site_host}:443" -servername "$site_host" -brief </dev/null 2>&1 |
        sed -n '1,4p' ||
        true
    )"
    printf '%s\n' "$tls_probe" | sed 's/^/  TLS probe: /'
    case "$tls_probe" in
      *"CONNECTION ESTABLISHED"*) ok "local TLS probe completes for $site_host" ;;
      *"unexpected eof"*) note "local TLS probe ended with unexpected EOF before a certificate was served" ;;
      *) note "local TLS probe did not complete cleanly" ;;
    esac
  fi

  if [ -n "$site_host" ] && command -v curl >/dev/null 2>&1; then
    http_probe="$(
      curl -Is --connect-timeout 10 --max-time 20 "http://${site_host}/" 2>/dev/null |
        tr -d '\r' |
        sed -n '1,6p' ||
        true
    )"
    if [ -n "$http_probe" ]; then
      printf '%s\n' "$http_probe" | sed 's/^/  HTTP probe: /'
    else
      note "HTTP probe: <no headers>"
    fi
  fi
}

if command -v curl >/dev/null 2>&1; then
  section "live site attribution markers"
  check_live_page \
    "home page" \
    "$site_url/" \
    "ACC_INSTALL_REF" \
    "ACC_INSTALL_SOURCE" \
    "posthog.identify(install_ref)" \
    "install_agent_prompt_copied"
  check_live_page \
    "reddit page" \
    "$site_url/reddit/" \
    "ACC_INSTALL_REF" \
    "ACC_INSTALL_SOURCE" \
    "posthog.identify(install_ref)" \
    "reddit_agent_prompt_copied"
else
  section "live site attribution markers"
  skip "curl not found; cannot read live site"
fi

if [ "$site_transport_needs_diagnostic" -eq 1 ]; then
  diagnose_site_transport
fi

section "live prompt-copy attribution flow"
if command -v curl >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  live_flow_output="$(bash scripts/check-live-attribution-flow.sh "$site_url" 2>&1)"
  live_flow_status=$?
  printf '%s\n' "$live_flow_output" | sed 's/^/    /'
  if [ "$live_flow_status" -eq 0 ]; then
    ok "live served HTML passes the prompt-copy attribution verifier"
  else
    hold "live served HTML does not yet pass the prompt-copy attribution verifier"
  fi
else
  skip "curl and node are required for live prompt-copy attribution verification"
fi

section "GitHub Release MCPB assets"
if ! command -v gh >/dev/null 2>&1; then
  skip "gh CLI not found; cannot read GitHub Release assets"
else
  release_json="$(gh release view "$tag" --repo "$repo" --json tagName,publishedAt,assets 2>/dev/null || true)"
  if [ -z "$release_json" ]; then
    hold "release $tag is unavailable"
  else
    RELEASE_JSON="$release_json" EXPECTED_TAG="$tag" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["RELEASE_JSON"])
tag = os.environ["EXPECTED_TAG"]
assets = [a.get("name", "") for a in data.get("assets", [])]
mcpb = sorted(name for name in assets if name.startswith(f"acc-mcp-{tag}-") and name.endswith(".mcpb"))
sidecars = sorted(name for name in assets if name.startswith(f"acc-mcp-{tag}-") and name.endswith(".sha256"))
native = sorted(
    name
    for name in assets
    if name.startswith(f"acc-{tag}-") and (name.endswith(".tar.gz") or name.endswith(".zip"))
)
print(f"  release published: {data.get('publishedAt', '<unknown>')}")
print(f"  assets: {len(assets)} total, {len(native)} native, {len(mcpb)} MCPB, {len(sidecars)} MCPB sidecars")
for name in mcpb:
    print(f"    MCPB: {name}")
PY
    counts="$(
      RELEASE_JSON="$release_json" EXPECTED_TAG="$tag" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["RELEASE_JSON"])
tag = os.environ["EXPECTED_TAG"]
assets = [a.get("name", "") for a in data.get("assets", [])]
mcpb = [name for name in assets if name.startswith(f"acc-mcp-{tag}-") and name.endswith(".mcpb")]
sidecars = [name for name in assets if name.startswith(f"acc-mcp-{tag}-") and name.endswith(".sha256")]
print(len(mcpb), len(sidecars))
PY
    )"
    set -- $counts
    mcpb_count="${1:-0}"
    sidecar_count="${2:-0}"
    if [ "$mcpb_count" -eq 4 ] && [ "$sidecar_count" -eq 4 ]; then
      ok "release has four MCPB assets and four sidecars"
    else
      hold "release needs four MCPB assets and four sidecars before MCP Registry publish"
    fi
  fi
fi

section "registry alignment"
if command -v gh >/dev/null 2>&1; then
  alignment_output="$(bash scripts/check-release-alignment.sh "$tag" server.json 2>&1)"
  alignment_status=$?
  printf '%s\n' "$alignment_output" | sed 's/^/    /'
  if [ "$alignment_status" -eq 0 ]; then
    ok "server.json is aligned with $tag release assets"
  else
    hold "server.json is not aligned with $tag release assets yet"
  fi
else
  skip "gh CLI not found; cannot run release alignment check"
fi

section "Official MCP Registry"
if command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  registry_server="$(
    python3 - <<'PY'
import json
from pathlib import Path
from urllib.parse import quote

name = json.loads(Path("server.json").read_text()).get("name", "")
print(quote(name, safe=""))
PY
  )"
  registry_url="https://registry.modelcontextprotocol.io/v0.1/servers/${registry_server}/versions/latest"
  registry_json="$(fetch_body "$registry_url")"
  if [ -z "$registry_json" ]; then
    hold "official MCP Registry latest endpoint is empty or unavailable"
  else
    REGISTRY_JSON="$registry_json" EXPECTED_VERSION="${tag#v}" python3 - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["REGISTRY_JSON"])
expected = os.environ["EXPECTED_VERSION"]
server = data.get("server", {})
official = data.get("_meta", {}).get("io.modelcontextprotocol.registry/official", {})
name = server.get("name", "<unknown>")
version = server.get("version", "<unknown>")
status = official.get("status", "<unknown>")
is_latest = official.get("isLatest")
published = official.get("publishedAt", "<unknown>")
print(f"  registry server: {name}")
print(f"  registry version: {version}")
print(f"  registry status: {status}")
print(f"  registry latest: {is_latest}")
print(f"  registry published: {published}")
if version == expected and status == "active" and is_latest is True:
    sys.exit(0)
sys.exit(1)
PY
    registry_status=$?
    if [ "$registry_status" -eq 0 ]; then
      ok "official MCP Registry serves ${tag#v} as active latest"
    else
      hold "official MCP Registry is not serving ${tag#v} as active latest"
    fi
  fi
else
  skip "curl and python3 are required for the official MCP Registry check"
fi

glama_check() {
  local label="$1"
  local url="$2"
  local tmp status

  tmp="$(mktemp)"
  status="$(curl -LsS -o "$tmp" -w '%{http_code}' --max-time 20 "$url" 2>/dev/null || true)"
  if [ "$status" = "200" ]; then
    if grep -Eiq 'AccInt|accreted-intelligence|maxbaluev' "$tmp"; then
      ok "$label visible at $url"
    else
      hold "$label returned HTTP 200 but no AccInt marker was visible"
    fi
  else
    hold "$label returned HTTP ${status:-<none>}"
  fi
  rm -f "$tmp"
}

section "Glama listing"
if command -v curl >/dev/null 2>&1; then
  glama_check "Glama direct server page" "https://glama.ai/mcp/servers/maxbaluev/accreted-intelligence"
  glama_check "Glama search for accint" "https://glama.ai/mcp/servers?q=accint"
else
  skip "curl not found; cannot read Glama"
fi

section "punkpeye PR"
if ! command -v gh >/dev/null 2>&1; then
  skip "gh CLI not found; cannot read punkpeye PR state"
else
  pr_json="$(gh pr view 8091 --repo punkpeye/awesome-mcp-servers --json state,isDraft,title,url,mergeStateStatus,reviewDecision,headRefName,updatedAt 2>/dev/null || true)"
  if [ -z "$pr_json" ]; then
    skip "punkpeye/awesome-mcp-servers#8091 unavailable via gh"
  else
    PR_JSON="$pr_json" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["PR_JSON"])
print(f"  title: {data.get('title', '<unknown>')}")
print(f"  url: {data.get('url', '<unknown>')}")
print(f"  state: {data.get('state', '<unknown>')}")
print(f"  draft: {data.get('isDraft', '<unknown>')}")
print(f"  merge state: {data.get('mergeStateStatus', '<unknown>')}")
print(f"  review decision: {data.get('reviewDecision', '<unknown>')}")
print(f"  updated: {data.get('updatedAt', '<unknown>')}")
PY
    pr_state="$(json_field "$pr_json" "state")"
    is_draft="$(json_field "$pr_json" "isDraft")"
    if [ "$pr_state" = "MERGED" ]; then
      ok "punkpeye PR is merged"
    elif [ "$pr_state" = "OPEN" ] && [ "$is_draft" != "true" ]; then
      hold "punkpeye PR is still open; do not update/comment until the Glama badge prerequisite is real"
    else
      hold "punkpeye PR state is $pr_state"
    fi
  fi
fi

section "summary"
note "holds: $holds"
note "skips: $skips"
note "fails: $fails"
note "READ ONLY: no external mutation was performed"

if [ "$fails" -eq 0 ] && [ "$holds" -eq 0 ] && [ "$skips" -eq 0 ]; then
  echo "LIVE GROWTH STATE: PASS"
else
  echo "LIVE GROWTH STATE: HOLD"
fi

if [ "$strict" = "1" ] && { [ "$fails" -gt 0 ] || [ "$holds" -gt 0 ] || [ "$skips" -gt 0 ]; }; then
  exit 1
fi
exit 0
