#!/usr/bin/env bash
# acc × Codex CLI notify hook — Codex calls this after each completed turn with ONE
# argument: the notification JSON, e.g.
#   {"type":"agent-turn-complete","turn-id":"…","input-messages":[…],
#    "last-assistant-message":"…"}
# It builds the ONE cross-host generic envelope {"session_id","cwd"} (jq when
# available, python3 fallback) and records the turn boundary into the substrate:
#   acc hook turn-end --host generic
# FAIL-OPEN: any fault (no jq/python3, junk JSON, missing acc binary) exits 0 and
# prints nothing — a notify hook must never break the host. ACC_DB in the
# environment points the recording at a specific substrate (cross-project memory);
# default resolution is <cwd>/acc.db.

main() {
  raw="${1:-}"
  [ -n "$raw" ] || return 0
  command -v acc >/dev/null 2>&1 || return 0

  envelope=""
  if command -v jq >/dev/null 2>&1; then
    envelope=$(printf '%s' "$raw" | jq -c '{
      session_id: ((.["thread-id"] // .["session-id"] // .["turn-id"] // "codex") | tostring),
      cwd: ((.cwd // .["workspace-dir"] // env.PWD) | tostring)
    }' 2>/dev/null) || envelope=""
  elif command -v python3 >/dev/null 2>&1; then
    envelope=$(python3 -c '
import json, os, sys
try:
    n = json.loads(sys.argv[1])
    if not isinstance(n, dict):
        raise ValueError
    sid = n.get("thread-id") or n.get("session-id") or n.get("turn-id") or "codex"
    cwd = n.get("cwd") or n.get("workspace-dir") or os.getcwd()
    print(json.dumps({"session_id": str(sid), "cwd": str(cwd)}))
except Exception:
    pass
' "$raw" 2>/dev/null) || envelope=""
  fi
  [ -n "$envelope" ] || return 0

  printf '%s' "$envelope" | acc hook turn-end --host generic >/dev/null 2>&1 || true
  return 0
}

main "$@" || true
exit 0
