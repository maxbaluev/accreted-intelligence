# Accreted Intelligence (AccInt)

acc is a memory + tool loop for Claude Code: it retrieves scored memory and runs
sandboxed actions, then learns from real outcomes. The primary interface is Claude
Code through MCP; the CLI is for setup, observation, and lifecycle.

## Documentation

- [Accreted Intelligence — whitepaper](docs/whitepaper.md) — the thesis, the
  architecture, and an honest empirical snapshot.
- [Architecture overview](docs/architecture-overview.md) — a skimmable tour of the
  two verbs, the scored-token memory, the hooks, and the trust-kernel.

## Running in 60 seconds

### Supported systems

- **Linux x86_64** — full (bwrap sandbox; embedder on cuda or cpu)
- **macOS** — functional (no bwrap; embedder on mps or cpu)
- **Linux aarch64** — functional (embedder on cpu)
- **Windows** — native via `install.ps1` (engine windows-clean: zero `std::os::unix` outside the platform boundary, daemon IPC = TCP loopback; container as fallback)

### Install

One line — fetches the source and hands off to the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

Windows (PowerShell 5.1+):

```powershell
irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

Already have a clone (the dev path)? Run the installer directly:

```bash
./install.sh
```

The installer auto-installs deps (Rust, uv, sandbox + browser libs), builds `acc`,
pins the best embedder for this machine, starts the warm daemon, configures Claude
Code MCP in `.mcp.json`, and ends with the commands to try. **First run may download
the model (several GB) and take minutes — the installer reports the wait honestly.**

### Updating

**Dev path (you have a clone):**

```bash
git pull && ./install.sh
```

**Public path (you bootstrapped with the one-liner):** re-run the exact same
bootstrap command — it fetches the latest source and hands off to the installer in
update mode. **Your memory (`acc.db`) is preserved** — the bootstrap and installer
never touch it.

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

```powershell
irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

**Self-update:** `acc update` checks for a newer release and prints the command to
adopt it; `acc update --dry-run` reports what it would fetch with no network call or
filesystem change.

Either way `install.sh` auto-detects an existing install (the `acc` binary and/or
your substrate) and runs in update mode: satisfied deps skip fast, the binary is
rebuilt/reinstalled, the model pin is re-written only if the host's pick changed,
and the run ends with `acc doctor` plus a one-line `updated <old> → <new>` summary.
**Your memory (`acc.db`) is never touched by the installer.** Schema migrations run
automatically inside the binary on the first open after an update (`PRAGMA
user_version` ladder — your data is preserved). The reverse is refused: an OLD
binary that meets a NEWER memory declines to open it for writing and tells you to
update (`git pull && ./install.sh`); `acc doctor` reports substrate-vs-binary
schema versions with the fix.

### Run anywhere (container)

No native deps, Windows, or a locked-down box? Run the **Tier-C container** — a
reproducible Linux image that runs anywhere Docker runs, with your substrate on an
owner-owned mounted volume. One command: `scripts/acc-docker.sh`. It defaults to
the universal CPU floor (LateOn, text-only); the GPU/ColQwen lane is opt-in. See
[docs/INSTALL_CONTAINER.md](docs/INSTALL_CONTAINER.md).

### Try it now

```bash
acc status                                                   # health + next step
acc --db acc.db ingest hello "acc memory retrieval works"  # create one memory
acc --db acc.db retrieve "memory retrieval"                 # get it back, ranked
```

### Use from Claude Code

Open this directory in Claude Code — `install.sh` wrote the project-local `.mcp.json`:

```json
{
  "mcpServers": {
    "acc": { "command": "acc", "args": ["--db", "acc.db", "mcp"] }
  }
}
```

The relative `acc.db` is intentional: Claude Code resolves it from this project
directory, so the file is clone-portable. Two verbs are exposed: `acc_retrieve`
(the only read) and `acc_act` (do anything: solve/continue/exec/register/named
runtimes — `solve` returns a final answer or a `brain_frame` the session resolves
via `continue`).

## Daily commands

```bash
acc status                              # substrate, embedder, lanes, NEXT STEP
acc doctor                              # end-to-end self-check (every layer, with fixes)
acc --db acc.db retrieve "topic"       # search the memory (read-only)
acc --db acc.db ingest <id> <text>     # add memory (creates the db if needed)
acc --db acc.db act solve "goal"       # run the retrieve → reason → act loop
acc --db acc.db act exec "echo hi"     # run sandboxed code
acc --db acc.db commitments            # read-only due/stale sweep over open promises
acc --db acc.db trace <episode>        # read one solve's step trace (--profile for durations)
acc --db acc.db frames                 # the deliberation queue (open/waiting brain frames)
acc --db acc.db appraise "a prompt"    # one-line typed-coverage read (holes + recommendation)
acc --db acc.db cognition --gaps       # learning priorities from prediction failures
acc hosts-sync                          # wire acc into every coding agent installed here (add-only)
acc --db acc.db mcp                    # MCP server for Claude Code
```

`acc telemetry on|off|status` is opt-in product telemetry (PostHog) — **off by
default**; enabling requires your own `--key`, and events are names + coarse
classes only, never content. `acc telemetry off` disables it and purges the local
queue.

## Integration: the lifecycle protocol + Claude plugin

Host integration is ONE host-agnostic lifecycle protocol — eight fixed events, each
a plain subprocess call into the same binary:

```
acc hook <event> --host <claude-code|opencode|generic>

session-start · turn-start · post-tool · turn-end ·
subagent-start · subagent-end · compact · session-end
```

- **stdin** — the host's event JSON verbatim (`--host` names the parser; envelope
  normalization lives in the binary, never in adapter glue). Hosts with no native
  hook JSON use the generic envelope: `{"session_id","cwd","prompt"?,"tool_name"?,
  "tool_input"?,"tool_response"?,"agent_id"?}` (session_id/cwd required, unknown
  fields ignored, junk stdin exits 0).
- **exit code** — `0` pass; `2` block, only on a CONFIRMED violation (every internal
  error fails open — a hook never wedges a session on its own bug).
- **stdout** — coach/context text; hosts that support injection surface it (Claude
  Code: `hookSpecificOutput.additionalContext`).

**Claude Code (the reference host).** This repo wires hooks directly in
`.claude/settings.json`. For OTHER projects the distribution artifact is the
versioned plugin folder [`claude-plugin/`](claude-plugin/): the manifest, the eight
hook mappings, the MCP server (`alwaysLoad: true`), and three thin skills (`solve`,
`commitments`, `frames` — pure routing sugar over the two verbs). Use
`claude --plugin-dir <this-repo>/claude-plugin`, or copy `claude-plugin/skills/*`
into a project's `.claude/skills/`. `install.sh` validates the plugin manifests but
never rewires this repo's own settings.

**Other hosts (OpenCode · Codex CLI · Cursor).** The same substrate is consumed and
fed from other agent harnesses through [`plugins/`](plugins/): each adapter registers
the two-verb MCP server in that host's dialect and translates the host's lifecycle
signals into the generic envelope above (`acc hook <event> --host generic`). Hosts
consume and feed the substrate; reasoning stays MaxSim-first in the interactive
session. Wiring steps, the envelope spec, and the per-host coverage table live in
[`plugins/README.md`](plugins/README.md); cross-project memory rides `ACC_DB`.

**The one-substrate rule.** A hook's CONTENT is substrate-derived (retrieval memos,
typed-coverage appraisals — it compounds); its ENFORCEMENT is hard wherever the host
offers a blocking primitive. Where a host cannot block, the guard degrades to
advisory and the binary records a ledger gap event — the substrate remembers that
the gate could not be hard instead of pretending it was.

## Troubleshooting

**`retrieve` says no substrate exists** → run `./install.sh`, or create it manually:
`acc --db acc.db ingest hello "hello from acc"`.

**`retrieve` errors with "embedder is not ready"** → first run may still be
downloading/warming the model. Run `acc status`; it shows daemon state and the next
step. Start the daemon manually with `acc embedder`.

**A headless solve says it checkpointed `waiting:brain`** → that is the design, not a
fault: with no interactive session attached, non-reflex work persists a continuation
frame; open Claude Code (or run `acc frames`) and drain it. No credential is ever
needed — the interactive session is the only brain.

**Claude Code can't see acc** → check `.mcp.json` matches the block above, then
reload MCP.

**Moving your memory to another machine** → `acc.db` is portable, but its `-wal` and
`-shm` sidecars can hold uncheckpointed writes. Copy `acc.db` **together with**
`acc.db-wal` and `acc.db-shm`, or run `acc doctor` first (it checkpoints the WAL into
`acc.db`) and then copy `acc.db` alone.

## What acc is underneath

- **Memory = late interaction.** Each entity is stored as per-token multi-vectors
  with a learned Beta posterior per token. Retrieval is MaxSim
  (`score(q,d) = Σ_i max_j sim(q_i, d_j)`); outcome credit moves the posteriors of
  the tokens that actually aligned. No dense bottleneck, no OpenAI for retrieval.
- **TWO verbs.** A reasoner has exactly two primitives over that memory:
  - **`retrieve`** — peek the memory by MaxSim (the only *read*).
  - **`act`** — *do* anything. Runtimes: `solve` (RECURSE — re-enter the loop on a
    sub-question), `exec` (run sandboxed code), `register` (store reusable named
    code), or any registered runtime by name.
- **Recursion is the primitive; decomposition is a side effect.** There is no
  `decompose` operation. When the reasoner can't answer directly it `act`s with
  runtime `solve` on a sub-question; the tree those recursive solves grow *is* the
  decomposition.
- **Runtimes are scored code.** Registering a runtime just ingests its code as
  scored tokens (retrievable, creditable, improvable). No privileged lane — a
  runtime is just-another-row plus a sandboxed executor.
- **The RLM REPL.** Inside an `act exec` command the code can recurse over the
  memory programmatically: `acc --db /tmp/acc.db retrieve "<query>"` prints ranked
  hits, so the reasoner can write *programs* that peek/map the memory in loops —
  Ω(|memory|) work with the memory never loaded into the model's context window.
- **Sandbox.** Every runtime runs under bubblewrap (`bwrap`) when available:
  read-only system, writable workdir + ephemeral `/tmp`, PID isolation, plus acc's
  built-in Rust-side deadline. **Network is the HOST network — deliberately NOT
  isolated** (sandboxed code can call APIs, fetch data, reach services — including
  the embedder socket; see `src/sandbox.rs` for the accepted trade). The substrate
  is bind-mounted **read-only** at `/tmp/acc.db` for the recall callback — so
  networked sandbox code can read and transmit it; the authority boundary for
  owner-credential sends lives upstream. Without bwrap (e.g. macOS), `exec` runtimes
  **refuse** to run — acc returns an error rather than running unsandboxed code;
  `retrieve` / `solve` / `outcome` still work. Install bubblewrap to enable `exec`, or
  run acc in the container (`docs/INSTALL_CONTAINER.md`) for sandboxed exec on those
  hosts. (Windows runs `exec` under the deadline lane with `sandboxed: false` by design.)
- **One substrate, one reasoner.** The substrate perceives and predicts; it contains no
  second mind. The one reasoner is the interactive session: `acc_act(solve)` is
  memory-first and returns either a final answer or a **continuation frame**
  (`brain_frame`) typed by what is missing — the session deliberates and submits via the
  reserved `continue` runtime. Authority holes never open a frame (they go to the owner);
  headless runs are reflex-only and checkpoint `waiting:brain`, drained at the next
  session (`acc frames`). There is no external LLM lane — no credential, OAuth, or
  API key, ever; the loop needs nothing beyond the session itself.
- **The percept.** Retrieval returns more than scores: per-query-token alignment profiles
  (sim/winner/margin) read as typed coverage — injectivity, order-preservation, winner
  scatter — from which the appraisal layer derives typed HOLES (missing knowledge,
  synthesis hole, missing procedure, medium blindness, missing authority). Routing is
  gated on the typed residue, not a scalar; `acc appraise <text>` prints the one-line
  read for any prompt.
- **Transitions + energy.** Every settled solve appends an appraisal-state transition
  (state, action, state′) to a bounded ledger; a k-NN over it predicts which action most
  reduces typed residue (predicted-energy descent) and per-region drift/Brier stats watch
  the predictions — rising error fires a `drift_alarm` (the world changed).
  `acc cognition --gaps` ranks the worst-predicted regions as learning priorities.

## The embedder daemon (the system embedder)

The embedder is a neural late-interaction model served warm by a daemon so it loads
only once:

```bash
acc embedder      # loads the pinned model, serves /tmp/acc-embedder.sock
acc host          # host probe + the model the ladder picked for this machine
```

The model follows a 3-family ladder chosen by host configuration at install time
(`acc pin`): the multimodal **TomoroAI family** (8B or 4B, ColQwen3 architecture upstream;
AWQ 4-bit on linux-x86_64+cuda, full bf16 on mps/cpu) whenever the host can honestly run it, **LateOn** (text-only)
as last resort. One substrate = one pinned model; changing the pin requires a full
re-encode.

Every other caller — the loop, the MCP server, the hooks, and the **in-sandbox
recall** — encodes by RPC over that socket. The model runs host-side, so the GPU
never enters the sandbox.

`--offline` swaps in a deterministic hash encoder for tests and dev with no daemon
and no dependencies. Don't mix: a memory ingested by one embedder must be queried by
the same one.

## Development

```bash
cargo build --release          # builds target/release/acc (rusqlite links system libsqlite3 on unix — install libsqlite3-dev)
cargo install --path .         # puts `acc` on PATH (~/.cargo/bin/acc)
cargo test --no-default-features  # the FAST offline lane: deterministic hash encoder, no daemon, no model download
cargo test                        # the full suite (the daemon/MCP features compiled in)
```

The offline lane (`--no-default-features`) is the verify path — it swaps in the
deterministic hash encoder so the suite runs with no embedder daemon and no network.

Multi-OS CI (`.github/workflows/multi-os.yml`) runs the suite on linux-x86_64,
linux-arm64 (QEMU), and real Apple Silicon (macos-14) on every push to main.

## Layout

```
src/token.rs       scored tokens: vectors + Beta posteriors, encode/decode
src/maxsim.rs      MaxSim, alignment profiles (the percept), surprisal-gated credit
src/appraisal.rs   typed residue over (percepts × posteriors × ledger): holes, routing, trajectory views
src/db.rs          SQLite substrate: entities, representations, event ledger, frames, transitions
src/encoder.rs     Encoder trait + offline HashEncoder
src/selector.rs    host probe → model ladder (TomoroAI-8B/4B multimodal → LateOn; cuda/mps/cpu)
src/subproc_encoder.rs  neural LI model over a uv/Python subprocess (loaded by the daemon)
src/embedder.rs    the warm embedder daemon + socket client (the system embedder)
src/brain.rs       the brain FACADE: the one Brain seam + lane-generic substrate
src/brain/session.rs    the ONE lane: continuation frames (final | brain_frame + `continue`)
src/runtime.rs     sandboxed runtimes (bwrap) + the in-sandbox recall bind
src/recursion.rs   THE loop: solve, the two verbs, automatic four-link credit
src/mcp.rs         JSON-RPC stdio MCP server: acc_retrieve, acc_act
src/doctor.rs      end-to-end self-check: layers + lanes + frames/reflex/drift
src/main.rs        CLI (explicit args + ACC_* env knobs — see below)
```

## Operator knobs (env vars)

The CLI takes explicit args plus ~50 `ACC_*` env knobs. Tuning values live in the
scored substrate, not prose — only the operator-safety knobs are listed here:

| Knob | What it does |
|---|---|
| `ACC_GUARD` | `off` bypasses the Stop substrate-binding guard (emergency only) |
| `ACC_SOLVE_DEADLINE_SECS` | wall-clock deadline for a `solve` run |
| `ACC_EMBED_TIMEOUT_SECS` | embedder socket timeout per encode call |
| `ACC_HOOK_RETRIEVE_BUDGET_MS` | hook-path retrieval budget (default 2000) — past it the prompt proceeds ungrounded with a one-line note (reactivity under embedder contention) |
| `ACC_BROWSER_TIMEOUT_SECS` | browser socket deadline (default 180s; 0 disables) |
