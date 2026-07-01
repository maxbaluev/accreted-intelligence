# acc × Cursor

Cursor agent sessions **consume and feed** the accreted scored memory
(`acc.db`): two-verb MCP access (`acc_retrieve` / `acc_act`), an
always-apply rule carrying the substrate contract, and agent hooks that record
turn/edit boundaries. Each hook command is the **bare** `acc hook <event>
--host cursor` — Cursor pipes its agent-hook JSON straight to the command's
stdin, and acc's **native `--host cursor` parser** (`cursor_map` in
`src/hook.rs`) maps Cursor's fields into the generic lifecycle envelope
in-process. No `/bin/sh`, no `jq`, no `python3` — one binary, every OS.
Reasoning stays MaxSim-first in the interactive session — the substrate is
memory, not a second mind.

> **Honesty note:** these artifacts were authored against the Cursor docs
> (MCP config, `.mdc` rules, agent-hooks beta), not live-tested here — there
> is no local Cursor install. The `acc hook … --host cursor` parser is unit-
> tested in Rust (`cursor_map`), and `plugins/cursor/hooks.json` is pinned
> byte-for-byte against the wired constants by `tests/hosts_sync.rs`. What is
> unverified is Cursor's SIDE of the contract: the exact event names
> (`beforeSubmitPrompt` / `stop` / `afterFileEdit`), the stdin payload field
> names the parser reads (`conversation_id` / `workspace_roots` /
> `file_path`), and the precise MCP env-key shape. The parser is fail-open: a
> missing binary, junk stdin, or an unresolvable cwd all exit 0 silently, so a
> field-name mismatch no-ops the hook rather than breaking the session.

## Wiring

Run **`acc hosts-sync`** (automatic at install; re-run — or just start a
session — after installing a new agent). It adds the `mcpServers.acc` entry
to the GLOBAL `~/.cursor/mcp.json` add-only, with a `.acc-backup-<ts>`
sibling per changed file; an existing acc entry is never rewritten (drift is
reported). Cursor's **hooks and rules are PROJECT files**, so the global sync
wires Cursor MCP only — run **`acc hosts-sync --project`** inside a project (it
writes `<project>/.cursor/rules/acc.mdc` and merges `<project>/.cursor/hooks.json`
add-only, on the same rails). The checked-in artifacts here are the manual
drop-in copies of exactly what `--project` writes.

### Manual fallback / reference (what hosts-sync converges toward)

1. **Binary.** Install acc so `acc` is on PATH. That is the only dependency —
   the hooks parse their stdin natively in Rust, so there is no `jq` /
   `python3` / shell requirement.
2. **MCP.** Merge [`mcp.json`](mcp.json) into `~/.cursor/mcp.json` (global) or
   `<project>/.cursor/mcp.json`. The server block carries the deadline contract
   (`env.ACC_MCP_CALL_DEADLINE_SECS`) and uses the global canonical Work Model.
   Do not set `ACC_DB` in Cursor config.
3. **Rule.** `acc hosts-sync --project` writes
   `<project>/.cursor/rules/acc.mdc` for you; the checked-in
   [`rules-acc.mdc`](rules-acc.mdc) is the manual drop-in copy of the same
   bytes. **hosts-sync owns the teaching text** — the body is GENERATED from
   `HOST_TEACHING_CANONICAL` in the repo's `src/hosts.rs` (one canonical
   teaching, every carrier pinned verbatim by tests); it is `alwaysApply`, so
   every agent turn carries the retrieve-first / cite-ids / credit-honesty
   contract.
4. **Hooks.** Merge [`hooks.json`](hooks.json) into `<project>/.cursor/hooks.json`
   (`acc hosts-sync --project` merges it add-only). Each entry is a bare
   command — no shell wrapper:
   - `beforeSubmitPrompt` → `acc hook turn-start --host cursor` (opens the
     per-turn guard window, so turn-end verdicts are symmetric with
     Claude/OpenCode)
   - `stop` → `acc hook turn-end --host cursor` (the turn boundary)
   - `afterFileEdit` → `acc hook post-tool --host cursor` (the edit trace)

The native `--host cursor` parser reads Cursor's stdin JSON directly: it maps
`conversation_id` → session id (falling back to a stable default), the first
`workspace_roots` entry (else `$PWD`) → cwd, `prompt` → the turn prompt, and
`file_path` → the edited path. Because the binary IS the parser, the hooks run
unchanged on Linux, macOS, and Windows (`acc` resolves `acc.exe` via PATHEXT) —
no `jq`/`python3`/`/bin/sh` to be present-or-absent. They are strictly
fail-open: a missing `acc`, junk stdin, or an unresolvable cwd all exit 0
silently rather than break a Cursor session.

## Depth limitations (honest four-link reach)

Cursor's hook surface gives acc turn-start / turn-end / edit boundaries, but it
is **shallower than the Claude Code / OpenCode reference depth** — and what
follows is **doc-authored, not live-tested** (there is no local Cursor install,
so `acc hosts-sync --survey` flags the cursor hook row `unverified`):

- **No per-prompt retrieval-inject.** Cursor has no hook that can INJECT
  retrieved memory into the model's context before it answers (the top law:
  knowledge compounds only when retrieval is behaviorally binding). The
  `beforeSubmitPrompt` hook only RECORDS the turn boundary; it cannot rewrite the
  prompt the way Claude Code's `UserPromptSubmit` / OpenCode's message-part
  injection do. So acc's depth line names cursor's inject as
  `unsupported (platform limit, unverified)`, not `wired`.
- **No fail-closed Stop guard.** The `stop` hook records the turn boundary but
  cannot BLOCK a turn that mutated the repo without recording a commitment
  (Claude Code's Stop guard exits 2; Cursor hooks cannot fail a session). It is
  log-only.
- **No session / compact / subagent events.** Cursor exposes only
  `beforeSubmitPrompt` / `stop` / `afterFileEdit` — the SessionStart bootstrap,
  PreCompact open-loop preservation, and Subagent lifecycle hooks have no Cursor
  equivalent.

**Compensating MCP discipline (the recipe that closes the gap).** Because the
binding is shallow, the model must self-enforce the loop through the two MCP
verbs every turn:

- **Call `acc_retrieve` at the START of every turn** (the always-apply
  `.cursor/rules/acc.mdc` carries this contract) and **cite the `[ids]`** you
  build on — this hand-runs the inject the platform cannot.
- Route non-trivial work through `acc_act` `solve`, answer any returned
  `brain_frame` via `continue`, end `proposal_text` with `PREDICT: <0.00-1.00> <why>`,
  and **close commitments with `outcome`** — the Stop guard you do not get for free,
  run by hand.

This is honest reach, not a defect: the MCP verbs are full-depth on Cursor; only
the hook-driven automation is shallow, and the rule + this recipe carry the loop.

## Timeouts — landed-slow is not dead (-32001)

The acc MCP server bounds every `acc_act` call with a server-side stall deadline
(`ACC_MCP_CALL_DEADLINE_SECS`, default 45s) plus an absolute ceiling
(`ACC_MCP_CALL_CEILING_SECS`, default 240s). Progress resets the stall clock; a
silent call RETURNS a resumable checkpoint — never a hang. But if your HOST's
MCP client timeout is SHORTER than the server return point, the client reports
`-32001 Request timed out` while the work keeps running and usually LANDS
server-side. The client cannot tell landed-slow from dead.

**Fix: keep the server return points BELOW your host's client timeout** (the
host-sync entries use a 45s stall window under 300s client walls, and acc's
built-in ceiling is 240s), so slow calls return an honest checkpoint payload the
model can act on instead of an opaque client error.

Recovery recipes when a timeout still happens:
- `continue` (frame submission) is IDEMPOTENT — resubmit the exact same
  `{frame_id, submit_token, proposal_text}`; a landed submit replays its cached
  result instantly.
- For a long solve/browser act, the checkpoint payload names the resume handle;
  `acc frames` lists what is waiting.
- Never assume a timed-out external action did NOT happen — verify state first
  (the send may have landed).
