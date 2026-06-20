# acc × OpenCode

OpenCode sessions **consume and feed** the accreted scored memory (`acc.db`):
two-verb MCP access (`acc_retrieve` / `acc_act`) plus a lifecycle plugin that
records session/turn/tool boundaries through the ONE generic hook envelope
(`acc hook <event> --host generic`). Reasoning stays MaxSim-first in the
interactive session — the substrate is memory, not a second mind.

## Wiring

Run **`acc hosts-sync`** (automatic at install; re-run — or just start a
session — after installing a new agent). It adds the plugin registration (by
absolute path), the `/goal` command, and the `mcp.acc` block to
`~/.config/opencode/opencode.json` add-only, with a `.acc-backup-<ts>` sibling
per changed file; an existing acc entry is never rewritten (drift is reported).
The same pass renders the
substrate-contract teaching into a fenced section of
`~/.config/opencode/AGENTS.md` (and `acc hosts-sync --project` into the
project's `AGENTS.md`). **hosts-sync owns the teaching text** — the one
source is `HOST_TEACHING_CANONICAL` in the repo's `src/hosts.rs`; there is no
snippet file to hand-copy, and tests pin every carrier verbatim.

### Manual fallback / reference (what hosts-sync converges toward)

1. **Binary.** Install acc so `acc` is on PATH (see the repo root README /
   `install.sh`), and have the embedder daemon available (`acc embedder`).

2. **Plugin + command + MCP.** EITHER copy [`acc.ts`](acc.ts) into your project's
    `.opencode/plugin/` (auto-discovered — also works globally from
    `~/.config/opencode/plugin/`), OR register it by absolute path via the
    `plugin` array as in [`opencode.json.snippet`](opencode.json.snippet),
    replacing `/ABSOLUTE/PATH/TO/acc` with this repo's path — not both (it would
    load twice; `hosts-sync` skips the registration when it sees the
    globally-copied file). Merge the snippet's `command.goal` and `mcp.acc`
    blocks into your `opencode.json` either way; `/goal <text>` then starts the
    acc solve/continue loop, and `mcp.acc` exposes the two verbs.

3. **Contract digest.** Run `acc hosts-sync` (global `AGENTS.md`) or
   `acc hosts-sync --project` (project `AGENTS.md`) — the fenced section it
   writes IS the contract digest (retrieve first, cite `[ids]`, credit
   honestly), rendered from `HOST_TEACHING_CANONICAL` in `src/hosts.rs`.

Cross-project memory: export `ACC_DB=/abs/path/acc.db` in the environment
OpenCode starts from (the plugin's spawned hooks and the MCP server both
inherit it). Default is `<project>/acc.db`.

## What the plugin records

| OpenCode signal | acc hook event |
|---|---|
| `session.created` (root) | `session-start` |
| `session.created` (child, `parentID` set) | `subagent-start` |
| `chat.message` (user prompt) | `turn-start` — the hook's stdout (the binding retrieval memo) is pushed back into the message parts so the model sees it |
| `tool.execute.after` | `post-tool` (`bash` is normalized to `Bash` so cargo verify runs feed the outcome link) |
| `session.idle` (root) | `turn-end` |
| `session.idle` (child) | `subagent-end` |
| `session.compacted` | `compact` |
| `session.deleted` (root) | `session-end` (OpenCode emits no event on plain process exit) |

Every handler is wrapped: a missing `acc` binary is a permanent silent no-op,
a hung hook is killed after 15s, and the plugin can never crash or block the
host.

## Verify the load (no model call)

```
opencode debug config --print-logs 2>&1 | grep "acc.ts loading plugin"
```

`opencode debug config` boots the instance, loads config + plugins, and exits
without prompting any model.

## Timeouts — landed-slow is not dead (-32001)

The acc MCP server bounds every `acc_act` call with a server-side stall deadline
(`ACC_MCP_CALL_DEADLINE_SECS`, default 45s) plus an absolute ceiling
(`ACC_MCP_CALL_CEILING_SECS`, default 240s). Progress resets the stall clock; a
silent call RETURNS a resumable checkpoint — never a hang. But if your HOST's
MCP client timeout is SHORTER than the server return point, the client reports
`-32001 Request timed out` while the work keeps running and usually LANDS
server-side. The client cannot tell landed-slow from dead.

**Fix: keep the server return points BELOW your host's client timeout** (the
snippet sets acc's stall window to 45s and OpenCode's client timeout to 300s;
acc's built-in ceiling is 240s), so slow calls return an honest checkpoint
payload the model can act on instead of an opaque client error.

Recovery recipes when a timeout still happens:
- `continue` (frame submission) is IDEMPOTENT — resubmit the exact same
  `{frame_id, submit_token, proposal_text}`; a landed submit replays its cached
  result instantly.
- For a long solve/browser act, the checkpoint payload names the resume handle;
  `acc frames` lists what is waiting.
- Never assume a timed-out external action did NOT happen — verify state first
  (the send may have landed).
