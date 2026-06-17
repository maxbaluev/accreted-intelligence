#!/usr/bin/env bash
# Read-only status audit for directory/listing pull requests.
#
# Pass one or more text/Markdown files, or "-" for stdin. The script extracts
# GitHub PR URLs, queries each with `gh pr view`, and prints a compact follow-up
# table plus attention items. It never comments, edits, closes, merges, pushes,
# dispatches workflows, or submits anything.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

strict="${ACC_DIRECTORY_PR_STRICT:-0}"

usage() {
  cat <<'EOF'
usage: scripts/check-directory-pr-state.sh <file-or-> [file-or-...]

Examples:
  scripts/check-directory-pr-state.sh docs/ops/some-report.md
  sed -n '/^| # | List |/,/^$/p' NIGHT-REPORT.md | scripts/check-directory-pr-state.sh -
  ACC_DIRECTORY_PR_STRICT=1 scripts/check-directory-pr-state.sh report.md

Default mode is read-only and advisory:
  - extracts unique https://github.com/<owner>/<repo>/pull/<number> URLs
  - queries GitHub with gh pr view
  - exits zero even when PRs need attention

Set ACC_DIRECTORY_PR_STRICT=1 to exit nonzero on failed lookups, closed PRs,
failing checks, requested changes, draft PRs, or blocked/dirty merge state.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi
if [ "$#" -eq 0 ]; then
  usage >&2
  exit 2
fi
if ! command -v gh >/dev/null 2>&1; then
  printf 'gh CLI is required for directory PR state checks\n' >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required for directory PR state checks\n' >&2
  exit 2
fi

tmp_files=()
cleanup() {
  if [ "${#tmp_files[@]}" -gt 0 ]; then
    rm -f "${tmp_files[@]}"
  fi
}
trap cleanup EXIT

inputs=()
stdin_used=0
for arg in "$@"; do
  if [ "$arg" = "-" ]; then
    if [ "$stdin_used" -eq 0 ]; then
      stdin_tmp="$(mktemp)"
      tmp_files+=("$stdin_tmp")
      cat >"$stdin_tmp"
      inputs+=("$stdin_tmp")
      stdin_used=1
    fi
  else
    inputs+=("$arg")
  fi
done

if python3 - "${inputs[@]}" <<'PY'
import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

URL_RE = re.compile(r"https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/pull/([0-9]+)")
FIELDS = "state,isDraft,mergeStateStatus,reviewDecision,statusCheckRollup,updatedAt,title,url"
STRICT = os.environ.get("ACC_DIRECTORY_PR_STRICT", "0") == "1"


def die(message, code=2):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def read_inputs(paths):
    chunks = []
    for arg in paths:
        path = Path(arg)
        if not path.exists():
            die(f"input not found: {arg}")
        chunks.append(path.read_text(encoding="utf-8", errors="replace"))
    return "\n".join(chunks)


def extract_prs(text):
    seen = set()
    prs = []
    for owner, repo, number in URL_RE.findall(text):
        key = (owner, repo, int(number))
        if key in seen:
            continue
        seen.add(key)
        prs.append(
            {
                "repo": f"{owner}/{repo}",
                "number": int(number),
                "url": f"https://github.com/{owner}/{repo}/pull/{number}",
            }
        )
    return prs


def run_gh(pr):
    cmd = [
        "gh",
        "pr",
        "view",
        str(pr["number"]),
        "--repo",
        pr["repo"],
        "--json",
        FIELDS,
    ]
    completed = subprocess.run(cmd, text=True, capture_output=True)
    if completed.returncode != 0:
        return None, (completed.stderr or completed.stdout or "gh pr view failed").strip()
    try:
        return json.loads(completed.stdout), None
    except json.JSONDecodeError as exc:
        return None, f"could not parse gh JSON: {exc}"


def run_direct_checks(pr):
    cmd = [
        "gh",
        "pr",
        "checks",
        str(pr["number"]),
        "--repo",
        pr["repo"],
        "--json",
        "name,state,workflow,link",
    ]
    completed = subprocess.run(cmd, text=True, capture_output=True)
    output = (completed.stdout or completed.stderr or "").strip()
    if completed.returncode != 0:
        if "no checks reported" in output.lower():
            return [], None
        return None, output or "gh pr checks failed"
    try:
        return json.loads(completed.stdout), None
    except json.JSONDecodeError as exc:
        return None, f"could not parse gh checks JSON: {exc}"


def summarize_checks(items):
    if not items:
        return "none", False, False

    failed = []
    pending = []
    ok = 0
    fail_conclusions = {
        "ACTION_REQUIRED",
        "CANCELLED",
        "ERROR",
        "FAILURE",
        "FAILED",
        "NEUTRAL_WITH_FAILURE",
        "STARTUP_FAILURE",
        "STALE",
        "TIMED_OUT",
    }
    fail_states = {
        "ACTION_REQUIRED",
        "CANCELLED",
        "ERROR",
        "FAILURE",
        "FAILED",
        "TIMED_OUT",
    }
    pending_statuses = {
        "EXPECTED",
        "IN_PROGRESS",
        "PENDING",
        "QUEUED",
        "REQUESTED",
        "WAITING",
    }
    ok_statuses = {
        "COMPLETED",
        "NEUTRAL",
        "SKIPPED",
        "SKIPPING",
        "SUCCESS",
    }

    for item in items:
        name = item.get("name") or item.get("context") or item.get("workflowName") or "check"
        status = str(item.get("status") or item.get("state") or "").upper()
        conclusion = str(item.get("conclusion") or "").upper()
        if conclusion in fail_conclusions or status in fail_states:
            failed.append(name)
        elif status in pending_statuses:
            pending.append(name)
        elif conclusion or status in ok_statuses:
            ok += 1
        else:
            pending.append(name)

    total = len(items)
    if failed:
        return f"fail {len(failed)}/{total}", True, False
    if pending:
        return f"pending {len(pending)}/{total}", False, True
    return f"ok {ok}/{total}", False, False


def escape_md(value):
    return str(value or "").replace("|", "\\|").replace("\n", " ").strip()


def attention_for(row):
    reasons = []
    state = row["state"]
    merge = row["merge"]
    review = row["review"]

    if row.get("error"):
        reasons.append("lookup failed")
    if state == "CLOSED":
        reasons.append("closed unmerged")
    if state == "OPEN" and row["draft"]:
        reasons.append("draft")
    if state == "OPEN" and row["check_failed"]:
        reasons.append("failing checks")
    if state == "OPEN" and review == "CHANGES_REQUESTED":
        reasons.append("changes requested")
    if state == "OPEN" and merge in {"BEHIND", "BLOCKED", "DIRTY", "HAS_HOOKS", "UNKNOWN"}:
        reasons.append(f"merge state {merge.lower()}")
    return reasons


text = read_inputs(sys.argv[1:])
prs = extract_prs(text)
if not prs:
    die("no GitHub PR URLs found", 1 if STRICT else 0)

rows = []
for index, pr in enumerate(prs, start=1):
    data, error = run_gh(pr)
    if error:
        row = {
            **pr,
            "state": "LOOKUP_FAILED",
            "draft": False,
            "merge": "",
            "review": "",
            "checks": "unknown",
            "check_failed": True,
            "check_pending": False,
            "updated": "",
            "title": "",
            "error": error,
        }
    else:
        direct_checks = None
        checks_error = None
        if data.get("state") == "OPEN":
            direct_checks, checks_error = run_direct_checks(pr)
        if direct_checks is None:
            checks, check_failed, check_pending = summarize_checks(data.get("statusCheckRollup") or [])
        else:
            checks, check_failed, check_pending = summarize_checks(direct_checks)
            if checks != "none":
                checks = f"{checks} direct"
        if checks_error and direct_checks is None and checks == "none":
            checks = "unknown"
            check_failed = True
        row = {
            **pr,
            "state": data.get("state") or "",
            "draft": bool(data.get("isDraft")),
            "merge": data.get("mergeStateStatus") or "",
            "review": data.get("reviewDecision") or "",
            "checks": checks,
            "check_failed": check_failed,
            "check_pending": check_pending,
            "updated": data.get("updatedAt") or "",
            "title": data.get("title") or "",
            "url": data.get("url") or pr["url"],
            "error": "",
        }
    row["attention"] = attention_for(row)
    rows.append(row)
    print(f"  checked {index}/{len(prs)}: {pr['repo']}#{pr['number']}", file=sys.stderr)

counts = Counter(row["state"] for row in rows)
attention = [row for row in rows if row["attention"]]
failed_lookups = [row for row in rows if row["state"] == "LOOKUP_FAILED"]
failing_checks = [row for row in rows if row["check_failed"] and row["state"] == "OPEN"]
pending_checks = [row for row in rows if row["check_pending"] and row["state"] == "OPEN"]

print("== directory PR state ==")
print(f"  PR URLs checked: {len(rows)}")
print(f"  open: {counts.get('OPEN', 0)}")
print(f"  merged: {counts.get('MERGED', 0)}")
print(f"  closed/unmerged: {counts.get('CLOSED', 0)}")
print(f"  lookup failed: {counts.get('LOOKUP_FAILED', 0)}")
print(f"  open with failing checks: {len(failing_checks)}")
print(f"  open with pending checks: {len(pending_checks)}")
print(f"  attention items: {len(attention)}")
print()

print("| PR | State | Checks | Merge | Review | Updated | Title |")
print("|---|---|---|---|---|---|---|")
for row in rows:
    pr_label = f"{row['repo']}#{row['number']}"
    state = row["state"] + (" draft" if row["draft"] else "")
    print(
        "| "
        + " | ".join(
            [
                f"[{escape_md(pr_label)}]({row['url']})",
                escape_md(state),
                escape_md(row["checks"]),
                escape_md(row["merge"]),
                escape_md(row["review"] or "-"),
                escape_md(row["updated"]),
                escape_md(row["title"]),
            ]
        )
        + " |"
    )

print()
print("== attention ==")
if attention:
    for row in attention:
        pr_label = f"{row['repo']}#{row['number']}"
        reason = ", ".join(row["attention"])
        suffix = f" ({row['error']})" if row["error"] else ""
        print(f"  HOLD: {pr_label}: {reason}{suffix}")
else:
    print("  none")

print()
print("READ ONLY: no PRs were commented, edited, closed, merged, or submitted.")
if attention:
    print("DIRECTORY PR STATE: HOLD")
else:
    print("DIRECTORY PR STATE: PASS")

if STRICT and attention:
    raise SystemExit(1)
PY
then
  exit 0
else
  status=$?
  if [ "$strict" = "1" ]; then
    exit "$status"
  fi
  exit 0
fi
