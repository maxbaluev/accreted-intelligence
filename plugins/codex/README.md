# acc × Codex CLI

Codex sessions **consume and feed** the accreted scored memory (`acc.db`):
two-verb MCP access (`acc_retrieve` / `acc_act`) plus **full 8/8 lifecycle
binding parity** with Claude Code and OpenCode. Codex 0.139 ships a STABLE,
default-on `hooks` feature whose JSON contract IS Claude Code's hook protocol
VERBATIM — so `acc hosts-sync` wires a [`hooks.json`](hooks.json) at
`~/.codex/hooks.json` (sibling of `config.toml`) carrying 7 lifecycle events,
each piping into `acc hook <event> --host claude-code`. Reasoning stays
MaxSim-first in the interactive session — the substrate is memory, not a second
mind.

## Binding parity (the loop made hard, not advisory)

The hooks.json gives Codex the SAME structural binding the reference hosts have:

| Codex event | acc subcommand | what it binds |
|---|---|---|
| `SessionStart` | `session-start` | kernel bootstrap + grounding |
| `UserPromptSubmit` | `turn-start` | **per-prompt retrieval-inject** (the top law) |
| `PostToolUse` (matcher `Bash`) | `post-tool` | verify-evidence capture |
| `Stop` | `turn-end` | the **fail-closed substrate-binding guard** |
| `PreCompact` | `compact` | open-loop preservation |
| `SubagentStart` | `subagent-start` | subagent lifecycle |
| `SubagentStop` | `subagent-end` | subagent exit-check |

acc reuses the `--host claude-code` reader lane: Codex invokes hooks from the
project cwd and passes Claude-shaped stdin JSON (`session_id`, `cwd`, `prompt`,
`tool_*`), which acc's existing hook reader already consumes — no Codex-specific
wrapper is needed. The converger substitutes the absolute `acc` binary into each
command (exactly as the `[mcp_servers.acc]` block does), and config.toml gains
`[features]\nhooks = true` (belt-and-suspenders — the feature is default-on).

### The ONE manual step — trust the hooks

Codex's trust model SKIPS new/changed command hooks until you trust them: run
**`/hooks`** in a Codex session once to review and trust acc's hooks. Trust is
**SHA-keyed** — if a hook command changes, Codex prompts a re-review. Until you
trust, the hooks.json entries are inert; the `notify` line (below) keeps recording
turn-end as the **pre-trust fallback**, so no turn goes unrecorded in the gap.

The same wiring rails as every host: `acc hosts-sync` writes `hooks.json` if
absent and ADD-ONLY merges acc's entries into an existing one (foreign events,
matchers, and handlers are never touched; an existing acc entry is never amended
— drift is reported); a `.acc-backup-<ts>` sibling is written before any edit;
`acc hosts-sync --remove` strips ONLY acc-owned entries, leaving foreign entries
and the file intact. `acc hosts-sync --project` writes the project's
`<dir>/.codex/hooks.json` on the same rails.

The `notify` line stays as the pre-trust turn-end telemetry fallback — it fires
once per completed turn through the ONE generic hook envelope
(`acc hook turn-end --host generic`) and is harmless once the hooks.json Stop
event is trusted (both record turn-end; the guard simply becomes fail-closed).

## Wiring

Run **`acc hosts-sync`** (automatic at install; re-run — or just start a
session — after installing a new agent). It appends the `[mcp_servers.acc]`
block and inserts the `notify` line ABOVE the first `[section]` header in
`~/.codex/config.toml` — only when grep finds neither marker; an existing or
half-applied acc entry is never amended (drift is reported). A
`.acc-backup-<ts>` sibling is written per changed file. The same pass renders
the substrate-contract teaching into a fenced section of `~/.codex/AGENTS.md`
(and `acc hosts-sync --project` into the project's `AGENTS.md`).
**hosts-sync owns the teaching text** — the one source is
`HOST_TEACHING_CANONICAL` in the repo's `src/hosts.rs`; there is no snippet
file to hand-copy, and tests pin every carrier verbatim.

### Manual fallback / reference (what hosts-sync converges toward)

1. **Binary.** Install acc so `acc` is on PATH (repo root README /
   `install.sh`).

2. **Config.** Append [`config.toml.snippet`](config.toml.snippet) to your
   `~/.codex/config.toml`, replacing `/ABSOLUTE/PATH/TO/acc` with this repo's
   path. Mind the snippet's note: `notify` is a top-level key and must sit
   ABOVE any `[section]` header. The `[mcp_servers.acc]` block exposes the
   two verbs to every Codex session.

3. **Contract digest.** Run `acc hosts-sync` (global `AGENTS.md`) or
   `acc hosts-sync --project` (project `AGENTS.md`) — the fenced section it
   writes IS the contract digest (retrieve first, cite `[ids]`, credit
   honestly), rendered from `HOST_TEACHING_CANONICAL` in `src/hosts.rs`.

Cross-project memory: add `"ACC_DB" = "/abs/path/acc.db"` to the
`[mcp_servers.acc]` `env` map and export the same variable in the shell Codex
runs from (the notify hook inherits it). Default resolution is the per-project
`acc.db`.

## What gets recorded

Once `hooks.json` is trusted (`/hooks`), Codex records the FULL lifecycle —
per-prompt retrieval-inject (`UserPromptSubmit`→`turn-start`), the fail-closed
substrate-binding guard (`Stop`→`turn-end`), verify-evidence capture
(`PostToolUse`→`post-tool`), and the session/compact/subagent boundaries — the
same structural binding Claude Code and OpenCode have. Before trust (and as a
permanent harmless fallback), Codex's `notify` surface fires once per completed
turn and records the `turn-end` boundary through the ONE generic hook envelope.
Either way, everything the model itself does through the two MCP verbs — solves,
retrievals, outcomes — compounds into `acc.db`, which is where the real
compounding happens. The pre-trust turn-end fallback is wired NATIVELY via
`acc hook codex-notify` (no shell script): it parses Codex's notify JSON
in-process and is strictly fail-open — junk JSON, missing fields, or a missing
`acc` binary all exit 0 silently.

## Depth limitations (honest four-link reach)

Codex reaches **full 8/8 binding parity ONCE you run `/hooks` to trust** the
`hooks.json` entries. Until then — and on any Codex build where the `hooks`
feature is unavailable — the reach is shallower than the Claude Code / OpenCode
reference depth, and the model must compensate through MCP discipline:

- **No per-prompt retrieval-inject before trust.** Codex has NO pre-prompt hook
  in the pre-trust state — only the `notify` line, which fires AFTER a turn
  completes (`turn-end`). So in the gap there is no automatic
  retrieval-inject (the top law: knowledge compounds only when retrieval is
  behaviorally binding). Once `hooks.json` is trusted, `UserPromptSubmit` →
  `turn-start` restores the per-prompt inject.
- **No fail-closed Stop guard before trust.** The `notify` line records the turn
  boundary but cannot BLOCK a turn that mutated the repo without a commitment.
  The fail-closed guard arrives only with the trusted `Stop` → `turn-end` hook.
- **Session / compact / subagent events ride the trusted hooks.json only** — the
  pre-trust `notify` fallback covers `turn-end` exclusively.

**Compensating MCP discipline (the recipe that closes the gap).** The two MCP
verbs are full-depth on Codex regardless of hook trust state, so the model
self-enforces the loop:

- **Call `acc_retrieve` at the START of every turn** (the
  `~/.codex/AGENTS.md` fence carries this contract) and **cite the `[ids]`** you
  build on — this hand-runs the inject the pre-trust state cannot.
- Route non-trivial work through `acc_act` `solve`, answer any returned
  `brain_frame` via `continue`, and **close commitments with `outcome`** — the
  Stop guard you do not get for free before trust, run by hand.

Run `/hooks` once to trust acc's SHA-keyed hooks and lift Codex to full binding
parity; the recipe above remains correct as a permanent belt-and-suspenders.

## Timeouts — landed-slow is not dead (-32001)

The acc MCP server bounds every `acc_act` call with a server-side stall deadline
(`ACC_MCP_CALL_DEADLINE_SECS`, default 45s) plus an absolute ceiling
(`ACC_MCP_CALL_CEILING_SECS`, default 240s). Progress resets the stall clock; a
silent call RETURNS a resumable checkpoint — never a hang. But if your HOST's
MCP client timeout is SHORTER than the server return point, the client reports
`-32001 Request timed out` while the work keeps running and usually LANDS
server-side. The client cannot tell landed-slow from dead.

**Fix: keep the server return points BELOW your host's client timeout** (the
snippet sets acc's stall window to 45s and Codex's tool timeout to 300s; acc's
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
