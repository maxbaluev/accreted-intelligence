# acc × Cursor

Cursor agent sessions **consume and feed** the accreted scored memory
(`acc.db`): two-verb MCP access (`acc_retrieve` / `acc_act`), an
always-apply rule carrying the substrate contract, and agent hooks that record
turn/edit boundaries through the ONE generic hook envelope
(`acc hook <event> --host generic`). Reasoning stays MaxSim-first in the
interactive session — the substrate is memory, not a second mind.

> **Honesty note:** these artifacts were authored against the Cursor docs
> (MCP config, `.mdc` rules, agent-hooks beta), not live-tested here — there
> is no local Cursor install. The `jq → acc` pipelines inside `hooks.json`
> WERE tested locally against the real binary; what is unverified is Cursor's
> side of the contract (event names, stdin payload fields like
> `conversation_id` / `workspace_roots` / `file_path`, and that hook commands
> are executed via a shell). If your Cursor version differs, the fail-open
> design means the hooks silently no-op rather than break the session.

## Wiring

Run **`acc hosts-sync`** (automatic at install; re-run — or just start a
session — after installing a new agent). It adds the `mcpServers.acc` entry
to the GLOBAL `~/.cursor/mcp.json` add-only, with a `.acc-backup-<ts>`
sibling per changed file; an existing acc entry is never rewritten (drift is
reported). The per-project rule and hooks (steps 3–4 below) stay DROP-IN —
they live inside each project, so the owner applies them per project.

### Manual fallback / reference (what hosts-sync converges toward)

1. **Binary.** Install acc so `acc` is on PATH; `jq` is required for the
   hooks.
2. **MCP.** Merge [`mcp.json`](mcp.json) into `~/.cursor/mcp.json` (global) or
   `<project>/.cursor/mcp.json`. Add `"env": {"ACC_DB": "/abs/path/acc.db"}`
   to the server block for cross-project memory.
3. **Rule.** `acc hosts-sync --project` writes
   `<project>/.cursor/rules/acc.mdc` for you; the checked-in
   [`rules-acc.mdc`](rules-acc.mdc) is the manual drop-in copy of the same
   bytes. **hosts-sync owns the teaching text** — the body is GENERATED from
   `HOST_TEACHING_CANONICAL` in the repo's `src/hosts.rs` (one canonical
   teaching, every carrier pinned verbatim by tests); it is `alwaysApply`, so
   every agent turn carries the retrieve-first / cite-ids / credit-honesty
   contract.
4. **Hooks.** Merge [`hooks.json`](hooks.json) into `~/.cursor/hooks.json`
   (or the project-level equivalent; `acc hosts-sync --project` merges it
   add-only):
   - `beforeSubmitPrompt` → `acc hook turn-start --host generic` (opens the
     per-turn guard window, so turn-end verdicts are symmetric with
     Claude/OpenCode)
   - `stop` → `acc hook turn-end --host generic` (the turn boundary)
   - `afterFileEdit` → `acc hook post-tool --host generic` (the edit trace)

All three hook commands build the generic envelope with `jq` when present, ELSE
`python3` (mirroring `plugins/codex/notify-acc.sh`) — a machine without `jq`
(but with the near-universal `python3`) still records lifecycle instead of
recording ZERO. They are strictly fail-open: missing `acc`, BOTH `jq` AND
`python3` absent, or unexpected stdin all exit 0 silently. The `stop` hook is
the one exception to the trailing `exit 0`: its final pipeline lets the `acc`
binary's own exit code surface (the inner `command -v acc || exit 0` keeps it
fail-open on a missing tool) so a real recording fault is observable.

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
  `brain_frame` via `continue`, and **close commitments with `outcome`** — the
  Stop guard you do not get for free, run by hand.

This is honest reach, not a defect: the MCP verbs are full-depth on Cursor; only
the hook-driven automation is shallow, and the rule + this recipe carry the loop.

## Timeouts — landed-slow is not dead (-32001)

The acc MCP server bounds every `acc_act` call with a server-side deadline
(`ACC_MCP_CALL_DEADLINE_SECS`, default 900s). Past it the call RETURNS a
resumable checkpoint — never a hang. But if your HOST's MCP client timeout is
SHORTER than the server deadline, the client reports `-32001 Request timed out`
while the work keeps running and usually LANDS server-side. The client cannot
tell landed-slow from dead.

**Fix: set the server deadline BELOW your host's client timeout** (the snippet
sets 45s for OpenCode's ~60s default), so slow calls return an honest
checkpoint payload the model can act on instead of an opaque client error.

Recovery recipes when a timeout still happens:
- `continue` (frame submission) is IDEMPOTENT — resubmit the exact same
  `{frame_id, submit_token, proposal_text}`; a landed submit replays its cached
  result instantly.
- For a long solve/browser act, the checkpoint payload names the resume handle;
  `acc frames` lists what is waiting.
- Never assume a timed-out external action did NOT happen — verify state first
  (the send may have landed).
