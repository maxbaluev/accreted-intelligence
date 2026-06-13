# Accreted Intelligence

> *Most AI forgets. This is the learning substrate for AI that remembers what worked — and gets wiser.*

**The learning substrate for agent work.** `acc` is a local Work Model that makes the AI tools you already run — Claude Code, Codex, OpenCode, Cursor — remember what actually worked. Hand work to your agent. `acc` learns what held up, checked against reality and shaped by how you decide, and starts the next run from the better path. The same job gets faster, safer, and genuinely better each time. All on a machine you control.

```
the agent acts  →  you see a receipt  →  reality settles it  →  next run starts from what worked
```

> **See it live — [accint.xyz](https://accint.xyz)** — the commitments ledger settling in real time, with the full story and the measured readout that updates as the system runs. Currently **early access**: the engine source is private, the integration glue is open, and there is no public binary release yet. We say what's proven and what's young.

---

## Why this exists

A model that scores 90% on a benchmark today scores 90% tomorrow. It doesn't learn from deployment, doesn't track which of its outputs led to good outcomes, doesn't remember last week's mistake. It generates intelligence and throws it away.

**Accreted Intelligence** is the bet that this is temporary: move learning out of model weights and into *scored external state* — where judgment compounds from contact with reality, and the model is a **replaceable processor** rather than the locus of intelligence.

There's a gap in the landscape, and it's where `acc` sits:

> Memory remembers context. Observability shows traces. Automation runs playbooks. **`acc` closes the learning loop** — commitment → action → approval → outcome → reusable path — scored by results, audited on a ledger, running fully on your hardware.

`acc` is a working kernel for that thesis: a Recursive Language Model over a late-interaction scored-token memory. Two verbs over one memory. Credit defaults to a weak prior; only reality earns full weight.

---

## One universal workflow for everything

There is no separate mode for technical and non-technical work. The loop is identical whether you're shipping code or chasing invoices — only the content of what's retrieved and acted on differs. You talk to your agent in plain words; the domain lives in the content, never the architecture.

| Job | Run 1 | What `acc` now knows |
|---|---|---|
| Ship a feature | reasons every step, runs the tests | the test that catches this class of bug, the path that passed |
| Source candidates | reads your ATS, ranks, drafts first-touches | the sourcing angle that got replies |
| Chase invoices | reads the ledger, drafts the nudge | which reminder cadence actually moves receivables |
| Monday client briefs | gathers, drafts, files | the brief shape each client reads |

*(Illustrative — the measured counts live at [accint.xyz](https://accint.xyz). These rows show the shape, not a benchmark.)*

Four different jobs, one set of primitives: **commitment → action → `HELD → your OK` → outcome → credited lesson.** The authority gate (`HELD → your OK`) is structural in every flow that touches the outside world — it's what makes the same loop safe for consequential work, not just code.

Run it again next week and verified steps **replay instead of re-reasoning**. The same job costs less and lands better every run.

---

## Early access — what install looks like

`acc` is in **early access**. There is no public binary yet, so the one-liner below does not install a working binary for an outside reader today — it is the path that opens once you have an invite.

**Join the list: [accint.xyz/#access](https://accint.xyz/#access).** Invites go in order — teams already putting agents near real work first.

When you have an invite, install is one line. It fetches the source and hands off to the installer for your OS:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

Windows (PowerShell 5.1+):

```powershell
irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

The installer probes your hardware, picks the embedder tier it can honestly run, builds `acc`, starts a warm local daemon, and wires Claude Code's `.mcp.json`. **First run may download the embedder model (several GB) and take minutes — the installer reports the wait honestly, and never pretends your hardware is bigger than it is.**

> **Prefer to be walked through it?** If you use Claude Code, just ask it: paste a link to this repo and say *"install acc for my OS, then run `acc doctor --json` and walk me through it."* Claude installs *with* you — explaining each step, pausing for consent at the boundary, and verifying against a machine-readable contract instead of guessing. See **[docs/install/with-claude.md](docs/install/with-claude.md)**.

---

## What the loop looks like

Once installed, you watch the loop work, end to end. This is what first contact looks like — a commitment created, a receipt written as the work happens, a score that moves:

```
$ acc status                                  # health + your next step
$ acc --db acc.db act solve "draft the follow-up to last week's brief"

  commitment c-7f3 created   ·   retrieved 4 prior memos  [VERIFIED]
  drafted the follow-up, held for your OK    [HELD → your OK]
  you approved · sent · the angle that worked is kept     [CREDITED]
```

A `solve` records a **commitment**, answers from memory when it can, and returns either the artifact or a deliberation frame for the attached session to resolve. Every step is written down as it happens — a receipt, not a transcript after the fact. Read what it wrote with `acc commitments` and `acc status`.

*(The same loop, animated, with the stat strip that updates as the system runs: [accint.xyz](https://accint.xyz).)*

---

## How it learns

Your brain lights up what it has seen before, predicts what happens next in the space of meaning, acts, and learns most from whatever surprised it. `acc` runs the same loop — except every prediction is checked against reality, shaped by how you decide, and the whole memory stays on your machine.

- **Memory is late interaction.** Each entity is stored as per-token multi-vectors with a learned Beta posterior per token. Retrieval is MaxSim — `score(q,d) = Σᵢ maxⱼ sim(qᵢ, dⱼ)` — and outcome credit moves the posteriors of the tokens that actually aligned. No dense bottleneck, no cloud for retrieval.
- **Two verbs are the whole interface.** `acc_retrieve` peeks the memory by MaxSim (the only read; natively multimodal — it can look at an image). `acc_act` does anything: `solve` (recurse on a sub-goal), `exec` (run sandboxed code), `register` (store a reusable runtime), `outcome` (close a commitment with a real-world verdict).
- **Recursion is the primitive; decomposition is a side effect.** There is no `decompose` operation. When the reasoner can't answer directly, it solves a sub-question — and the tree those solves grow *is* the decomposition. No planner, no task graph.
- **Runtimes compound too.** When a path holds — a browser flow, a script, a tool integration — it's saved as a runtime and scored by reality exactly like a memo. No privileged lane. This is how "the same job replays instead of re-reasoning" is mechanically true.
- **Belief never counts as reality.** Closing a commitment defaults to `self_graded` — a deliberately weak prior. Full weight requires reality: the owner confirmed, the world replied, a test passed, a runtime exited clean. The system cannot compound from its own confidence.

Read the depth:
- **[Whitepaper →](docs/reference/whitepaper.md)** — the problem (credit assignment + retrieval-to-action binding), the thesis, the architecture *with the math*, and an honest account of what's proven vs. open.
- **[Architecture overview →](docs/reference/architecture-overview.md)** — the skimmable tour: two verbs, late-interaction memory, reality-gated credit, the trust-kernel.

---

## You own it

`acc` runs on a computer you control: one small program and one data file (a pure-Rust binary and a SQLite file). There is no cloud control plane in the loop and **no API key to leak** — not for memory, and not for the reasoner. The reasoner is the interactive session itself; when memory can't answer, `acc` hands the attached agent a frame to deliberate over. There is no external LLM lane, ever.

- **Your data stays put.** The substrate (`acc.db`) is a plain file on your disk, owned by you. Retrieval, scoring, and the sandbox all run on your machine. Telemetry is off by default and requires your own key.
- **The reasoner is replaceable at the interface; the memory is not.** What `acc` learned lives in the Work Model, so a replaceable reasoner reads it through the same two verbs — two reasoning engines have been driven against one substrate. The encoder and the operating contract are part of the substrate's identity, not free variables: one substrate is pinned to one encoder.
- **Consent at the boundary.** Owner authority is required before anything that sends, publishes, deploys, transfers, deletes important data, or uses your credentials. The gate is hard, not advisory — a held decision is named and timestamped, and nothing leaves without it.

---

## Works with the tools you already run

Keep your agent. Keep your computer. `acc` works underneath the AI tools you already run, quietly learning what worked — nothing new to open, nothing to migrate. One binary, one lifecycle protocol, one substrate shared across every host and project.

| Host | Status | Wiring |
|---|---|---|
| **Claude Code** | live (reference host) | `.mcp.json` + native hooks ([`plugins/claude/`](plugins/claude/)) |
| **OpenCode** | live | `opencode.json` mcp block + plugin ([`plugins/opencode/`](plugins/opencode/)) |
| **Codex CLI** | live | `config.toml` mcp server + `notify` hook ([`plugins/codex/`](plugins/codex/)) |
| **Cursor** | wired — authored against docs, not live-tested | `.cursor/mcp.json` + agent hooks ([`plugins/cursor/`](plugins/cursor/)) |

`plugins/claude/` is the reference host — native lifecycle wiring plus skills; the other three translate their host's signals into the one generic envelope. Same substrate, same two verbs, different richness of wiring. Run `acc hosts-sync` to wire `acc` into every agent installed here — add-only, idempotent, and it never touches your existing config. The install runs it for you.

**Supported systems:**

- **Linux x86_64** — full (`bwrap` sandbox; embedder on cuda or cpu)
- **macOS** — functional (no `bwrap`; embedder on mps or cpu)
- **Linux aarch64** — functional (embedder on cpu)
- **Windows** — native via `install.ps1` (engine windows-clean; container as fallback)
- **Locked-down / no-root / "must just work"** — the **[container](docs/install/container.md)** runs anywhere Docker does, substrate on a volume you own.

---

## What's proven, and what's young

`acc` is a working single-host research kernel — a running system, not a roadmap. We're honest about the line. These numbers are measured, not promised — the live readout is at **[accint.xyz](https://accint.xyz)** and updates as the system runs.

| State | What it covers |
|---|---|
| **Running today** | MaxSim retrieval + per-unit scored memory · reality-gated bounded credit · two reasoners over one substrate · recursive `solve` · sandboxed scored runtimes · structural four-link enforcement · the owner-authority floor · the weak self-graded prior |
| **Young but wired** | dependable runtime replay · cost-compression instrumentation · model-swap resilience as a measured delta · the transition ledger + k-NN energy-descent predictor |
| **Known open** | substrate-on-vs-off lift (no counterfactual harness yet) · scaling MaxSim past a single host · hardening the reachable-network / send boundary |
| **Not started** | a public binary release · the team and collective world-model stages (see [accint.xyz](https://accint.xyz) #roadmap) |

The live wedge is concrete: a single-host world model, scored by real outcomes today, with the readout above as the running proof — several coding-agent terminals, one local Work Model, one owner, approval before external action. The broader product is a learning substrate for any agent-run job — the proof starts where agents already do real work.

---

## The primitives, in the open

The engine is private — the late-interaction memory, the appraisal and prediction layers, the credit math. That's the moat, and it stays closed. The integration glue (`install.sh`, `install.ps1`, `bootstrap/`, `plugins/`) is **Apache-2.0** and developed in the open. The prebuilt binary ships under a draft [EULA](EULA.md). See **[LICENSING.md](LICENSING.md)** for the full split.

The building blocks are public too — each shippable on its own:

- **[maxsim-rs](https://github.com/maxbaluev/maxsim-rs)** — late-interaction MaxSim, in clean Rust.
- **[colpali-retrieve](https://github.com/maxbaluev/colpali-retrieve)** — multimodal late interaction (text → document images).
- **[scored-rerank](https://github.com/maxbaluev/scored-rerank)** — ranking that learns from outcomes (Beta posteriors + Thompson sampling).
- **[mcp-retrieve](https://github.com/maxbaluev/mcp-retrieve)** — late-interaction retrieval as an MCP tool.

---

## Community

- **[CONTRIBUTING.md](CONTRIBUTING.md)** — what's open, how to add or fix a host adapter, and how to report a problem (start with `acc doctor` — its output is operational health only, safe to paste).
- **Found a bug or want a new host wired?** Open an [issue](.github/ISSUE_TEMPLATE/). A great *idea* for the engine is welcome as a feature request, even though engine internals can't be PR'd here.
- **Security issues** — never file publicly. See **[SECURITY.md](.github/SECURITY.md)** to report privately.
- **Early access** — join the waitlist at **[accint.xyz](https://accint.xyz)**. Invites go in order: teams already putting agents near real work first.

---

*Already running AI agents? Make them compound.* · See it live: [accint.xyz](https://accint.xyz)

Questions, bugs, or a host you want wired? Open a [GitHub issue](https://github.com/maxbaluev/accreted-intelligence/issues). · [accint.xyz](https://accint.xyz)
