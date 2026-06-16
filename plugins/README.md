# plugins/ — host consumers of the accreted substrate

**Hosts consume and feed the substrate; reasoning stays MaxSim-first in the
interactive session.** Each adapter here gives another agent harness (OpenCode,
Codex CLI, Cursor) the same two things the reference host has: two-verb MCP
access to the scored memory (`acc_retrieve` / `acc_act`) and lifecycle
recording through `acc hook <event> --host generic`. No adapter adds a second
mind — the substrate perceives and predicts; the session reasons.

## The generic envelope (the ONE cross-host contract)

Every host translates its native signals into a single flat JSON object on
stdin of `acc hook <event> --host generic`:

```json
{
  "session_id": "…",        // required
  "cwd": "…",               // required — the host project dir; authoritative
                            //   (the hook chdirs there; state + db resolve under it)
  "prompt": "…",            // optional — consumed by turn-start
  "tool_name": "…",         // optional — post-tool ("Bash" feeds verify capture)
  "tool_input": { },        // optional — post-tool (e.g. {"command": "cargo test"})
  "tool_response": { },     // optional — post-tool (e.g. {"exit_code": 0})
  "agent_id": "…"           // optional — subagent-start / subagent-end
}
```

Unknown fields are ignored. The eight events are the same lifecycle every
harness has: `session-start · turn-start · post-tool · turn-end ·
subagent-start · subagent-end · compact · session-end`. Rails: junk stdin or a
missing `session_id`/`cwd` exits 0 (fail-open, before any guard); exit 2 only
ever means a confirmed structural violation on `turn-end`; stdout is
coach/context text the host may surface back into the session.

## Per-host wiring

| Host | Adapter | MCP (two verbs) | Lifecycle recording |
|---|---|---|---|
| Claude Code | [`../claude-plugin/`](../claude-plugin/) (reference host) | `.mcp.json` | all eight events, wired natively (`--host claude-code`) |
| OpenCode | [`opencode/`](opencode/) | `opencode.json` `mcp` block | plugin (`acc.ts`): session/turn/tool/subagent/compact/end |
| Codex CLI | [`codex/`](codex/) | `config.toml` `[mcp_servers.acc]` | `notify` hook → `turn-end` per completed turn |
| Cursor | [`cursor/`](cursor/) | `.cursor/mcp.json` | agent hooks: `beforeSubmitPrompt` → `turn-start`, `stop` → `turn-end`, `afterFileEdit` → `post-tool` (authored against docs, not live-tested here) |

## Automatic wiring — `acc hosts-sync`

Run **`acc hosts-sync`** (automatic at install — install.sh runs it as a phase;
re-run it, or just start a session, after installing a new agent). It detects
which hosts are present (stat/PATH only — no host binary is ever executed) and
converges each global config **add-only**:

- missing acc entries are merged in; an EXISTING acc entry is **never
  rewritten** — a conflicting or half-applied one is reported as `drifted(…)`
  and left byte-untouched;
- every actually-changed file gets ONE `.acc-backup-<unix-ts>` sibling
  (no change → no write, no backup);
- `acc hosts-sync --dry-run` prints a unified-diff preview and writes nothing;
- `ACC_HOSTS_SYNC=off` disables the converger entirely.

Output is one line per host: `wired | already-wired | drifted(detail) | absent
| created-config`. `acc doctor` carries the same per-host status on its
`hosts` line.

Each host directory keeps its README with the exact manual config snippets —
they remain the documented fallback/reference (and are precisely what
`hosts-sync` converges toward). The TEACHING text (the substrate-contract
digest every instruction surface carries) has ONE source: **hosts-sync owns
it** as `HOST_TEACHING_CANONICAL` in `src/hosts.rs`, rendered verbatim into
the AGENTS.md fenced sections (opencode + codex, global and project), the
Cursor rules body, and the MCP server instructions. The per-host
`AGENTS-snippet.md` hand copies are gone — tests pin every carrier, so the
copies can never diverge again.

## Cross-project memory

One substrate can serve every project and every host: export
`ACC_DB=/abs/path/acc.db` in the environment the host starts from. The
spawned hooks and the MCP server both honor it; without it, resolution is the
per-project `<cwd>/acc.db`.

## Coexistence with your existing setup

acc extends a lived-in environment; it never replaces or edits what you already
have. The contract, per surface:

**Your hooks.** Hosts run ALL hooks registered for an event — yours and acc's
compose; acc never asks you to remove anything. Per event: acc's
SessionStart/UserPromptSubmit/PostToolUse/PreCompact/SubagentStop legs are
fail-open (any fault → silent no-op; they can slow a turn at worst, never break
it). The one HARD leg is Stop: acc blocks a stop only on a confirmed
unrecorded-work violation, and every block prints a DIAGNOSIS line naming
exactly what it saw. **Composition note:** if you have your own exit-2 Stop
hook, Stop hooks compose OR-blocking — either may block a stop. If a stop
blocks unexpectedly, read both hooks' output; acc's names itself.

**Your MCP servers.** acc adds exactly one server with two verbs
(`acc_retrieve`, `acc_act`) and never touches other entries —
`acc hosts-sync --survey` shows your servers counted and untouched.

**Your memory.** acc writes ONLY `acc.db`. Your CLAUDE.md, auto-memory,
notes, and any other RAG store are never read as authority, never edited.
acc's grounding arrives as bounded runtime hook injection — additive context
in the turn, not edits to your files.

**Your skills.** acc ships none and never will by default — the whole
interface is the two MCP verbs.

**Leaving.** `acc hosts-sync --remove` unwires exactly what sync added
(foreign or hand-modified entries stay untouched, backups taken first), and
disabling the Claude Code plugin is host-native. One command in, one command
out.
