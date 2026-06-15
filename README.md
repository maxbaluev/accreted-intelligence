# Accreted Intelligence

[![Stars](https://img.shields.io/github/stars/maxbaluev/accreted-intelligence?style=flat&logo=github&color=f5c518)](https://github.com/maxbaluev/accreted-intelligence/stargazers)
[![License](https://img.shields.io/badge/license-Apache--2.0%20(glue)-blue)](LICENSE-APACHE-2.0.txt)
[![MCP](https://img.shields.io/badge/MCP-server-1f6feb)](https://modelcontextprotocol.io)
[![Works with](https://img.shields.io/badge/works%20with-Claude%20Code%20·%20OpenCode%20·%20Codex%20·%20Cursor-7c3aed)](#install)
[![Platform](https://img.shields.io/badge/platform-Linux%20·%20macOS%20·%20Windows-555)](#install)
[![Live](https://img.shields.io/badge/live-accint.xyz-3fb950)](https://accint.xyz)

> Make your AI work compound. Offload the task. Never the learning.

AI agents are powerful but amnesiac: every run burns your tokens on real work, ships an output, then forgets. You **rent** capability — you never build it. `acc` changes the unit from a task that evaporates to an **investment that compounds**. Hand work to the agents you already run (Claude Code, Codex, OpenCode, Cursor), and **two things** compound into one owned asset — a **Work Model** of your business: your **intellect** (what you decide, what good looks like, what you'll never allow) and your **agents' tokens** (every verified path distilled into a runtime that replays instead of re-reasoning). It learns what actually worked, checked against your own results, and **predicts the better path before the next run starts**. It acts in your real accounts with a receipt for every step, holds anything that leaves your machine for your OK, and lets reality settle it. So the same job gets cheaper, faster, and genuinely better every time it runs. The learning is yours: **swap the model, keep the company veteran.** Your work turns into capital you own, on a machine you control.

```
predict the better path  →  act in your accounts, receipted  →  reality settles it  →  the Work Model sharpens
```

> **See it live: [accint.xyz](https://accint.xyz).** The commitments ledger settles in real time there, alongside the full story and a measured readout that updates as the system runs. The engine source is private; the binary installs in one line (below) and the building blocks are open. We say what's proven and what's young.

---

## Why this exists

A model that scores 90% on a benchmark today scores 90% tomorrow. It doesn't learn from deployment, doesn't track which of its outputs led to good outcomes, and doesn't remember last week's mistake. It generates intelligence and throws it away. You keep paying — in time and tokens — to rediscover what already worked.

Accreted Intelligence is a bet that this is temporary. The idea is to move learning out of model weights and into scored external state, where judgment compounds from contact with reality and the model becomes a replaceable processor rather than the place intelligence lives. **The reasoning engine is the part you can swap; the judgment it earned in your world is the part you keep.**

There's a gap in how the existing tools are positioned, and it's where `acc` sits. Memory remembers context. Observability shows traces. Automation runs playbooks. `acc` closes the learning loop: commitment, action, approval, outcome, reusable path — scored by results, audited on a ledger, and running fully on your hardware. And it does the one thing memory can't: it **predicts** the path most likely to work from everything that worked in your world before, then watches its own error.

`acc` is a working kernel for that thesis. It's a Recursive Language Model over a late-interaction scored-token memory: two verbs over one memory. Credit defaults to a weak prior, and only reality earns full weight.

---

## One universal workflow for everything

There is no separate mode for technical and non-technical work. The loop is identical whether you're shipping code or chasing invoices. Only the content of what's retrieved and acted on differs. You talk to your agent in plain words, and the domain lives in the content rather than the architecture.

| Job | Run 1 | What `acc` now predicts and replays |
|---|---|---|
| Ship a feature | reasons every step, runs the tests | the test that catches this class of bug, the path that passed |
| Source candidates | reads your ATS, ranks, drafts first-touches | the sourcing angle that got replies |
| Chase invoices | reads the ledger, drafts the nudge | which reminder cadence actually moves receivables |
| Monday client briefs | gathers, drafts, files | the brief shape each client reads |

*(Illustrative. The measured counts live at [accint.xyz](https://accint.xyz). These rows show the shape, not a benchmark.)*

Four different jobs, one set of primitives: **commitment → action → `HELD → your OK` → outcome → credited lesson.** The authority gate (`HELD → your OK`) is structural in every flow that touches the outside world. That gate is what makes the same loop safe for consequential work and not only for code.

Run it again next week and verified steps replay instead of re-reasoning. Most AI re-reasons every task from scratch, so you pay full price forever. `acc` predicts the path that worked and replays the verified steps, so the same job costs less every run and keeps dropping as it learns.

---

## Install

`acc` installs in one line. It runs the installer for your OS, which sets `acc` up on your machine:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

Windows (PowerShell 5.1+):

```powershell
irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

The installer probes your hardware, picks the embedder tier it can honestly run, builds `acc`, starts a warm local daemon, and wires Claude Code's `.mcp.json`. The first run may download the embedder model (several GB) and take minutes. The installer reports the wait honestly and never pretends your hardware is bigger than it is.

> **Prefer to be walked through it?** If you use Claude Code, just ask it. Paste a link to this repo and say *"install acc for my OS, then run `acc doctor --json` and walk me through it."* Claude installs with you, explaining each step, pausing for consent at the boundary, and verifying against a machine-readable contract instead of guessing. See **[docs/install/with-claude.md](docs/install/with-claude.md)**.

---

## What the loop looks like

Once installed, you watch the loop work end to end. This is what first contact looks like: a commitment created, the better path predicted from what worked before, a receipt written as the work happens, and a score that moves.

```
$ acc status                                  # health + your next step
$ acc --db acc.db act solve "draft the follow-up to last week's brief"

  commitment c-7f3 created   ·   predicted from 4 prior memos   [VERIFIED]
  drafted the follow-up, held for your OK                       [HELD → your OK]
  you approved · sent · the angle that worked is kept           [CREDITED]
```

A `solve` records a commitment, retrieves and predicts the path most likely to work, and returns either the artifact or a deliberation frame for the attached session to resolve. Every step is written down as it happens. It's a receipt, not a transcript reconstructed after the fact. Read what it wrote with `acc commitments` and `acc status`.

*(The same loop, animated, with the stat strip that updates as the system runs: [accint.xyz](https://accint.xyz).)*

---

## How it learns

Your brain lights up what it has seen before, predicts what happens next in the space of meaning, acts, and learns most from whatever surprised it. `acc` runs the same loop, with the difference that every prediction is checked against reality, shaped by how you decide, and held in a memory that stays on your machine.

- **Memory is late interaction.** Each entity is stored as per-token multi-vectors with a learned Beta posterior per token. Retrieval is MaxSim, `score(q,d) = Σᵢ maxⱼ sim(qᵢ, dⱼ)`, and outcome credit moves the posteriors of the tokens that actually aligned. No dense bottleneck, no cloud for retrieval.
- **It predicts, not just recalls.** A transitions ledger ranks which action is most likely to improve things next — k-nearest-neighbor in the space of past appraisals — and watches its own prediction error. When your world shifts, it notices. This is the part memory cannot do: recall returns what was said; prediction proposes the better path before you act. (JEPA-style predictive modeling, applied to work rather than pixels.)
- **Two verbs are the whole interface.** `acc_retrieve` peeks the memory by MaxSim. It's the only read, and it's natively multimodal, so it can look at an image. `acc_act` does anything: `solve` (recurse on a sub-goal), `exec` (run sandboxed code), `register` (store a reusable runtime), `outcome` (close a commitment with a real-world verdict).
- **Recursion is the primitive, and decomposition is a side effect.** There is no `decompose` operation. When the reasoner can't answer directly, it solves a sub-question, and the tree those solves grow *is* the decomposition. No planner, no task graph.
- **Two things compound, not one — what worked *and* how to do it.** When a path holds, whether a browser flow, a script, or a tool integration, it's saved as a runtime and scored by reality exactly like a memo. No privileged lane: the browser is just another scored runtime. A flow that worked replays cheaply; one that broke loses its score and isn't trusted again. This is how "the same job replays instead of re-reasoning" is mechanically true.
- **Belief never counts as reality.** Closing a commitment defaults to `self_graded`, a deliberately weak prior. Full weight requires reality: the owner confirmed, the world replied, a test passed, or a runtime exited clean. The system cannot compound from its own confidence.

Read the depth:
- **[Whitepaper →](docs/reference/whitepaper.md)** covers the problem (credit assignment plus retrieval-to-action binding), the thesis, the architecture *with the math* — retrieval, scored credit, and prediction — and an honest account of what's proven versus open.
- **[Architecture overview →](docs/reference/architecture-overview.md)** is the skimmable tour: two verbs, late-interaction memory, reality-gated credit, the transitions-ledger predictor, and the trust-kernel.

---

## You own it

`acc` runs on a computer you control: one small program and one data file (a pure-Rust binary and a SQLite file). There is no cloud control plane in the loop and no API key to leak, neither for memory nor for the reasoner. The reasoner is the interactive session itself; when memory can't answer, `acc` hands the attached agent a frame to deliberate over. There is no external LLM lane, ever.

- **Your data stays put.** The substrate (`acc.db`) is a plain file on your disk, owned by you. Retrieval, scoring, prediction, and the sandbox all run on your machine. Telemetry is off by default and requires your own key.
- **Swap the model, keep the company veteran.** What `acc` learned lives in the Work Model, so a replaceable reasoner reads it through the same two verbs. Two reasoning engines have been driven against one substrate. Change the generalist model and the judgment it earned in your world stays — the encoder and the operating contract are part of the substrate's identity, so one substrate is pinned to one encoder.
- **Consent at the boundary.** Owner authority is required before anything that sends, publishes, deploys, transfers, deletes important data, or uses your credentials. The gate is hard rather than advisory. A held decision is named and timestamped, and nothing leaves without it.

---

## It keeps receipts — same record, two readers

Most AI work leaves no trail: no record of what it expected, who approved it, or whether it actually worked. `acc` writes every step down as it happens. When someone asks *"why did it do that?"*, it's already written — the receipt your team can show management, and the lesson your Work Model inherits from the same row.

- **What did it do** → the `VERIFIED` rows, written as they happened.
- **Who said yes** → a held decision, named and timestamped (`HELD → your OK`).
- **What did we learn** → the lesson, credited and kept.

Nothing happens without a trace, and nothing you decided is lost.

---

## FAQ: Work Model vs memory

### Is this just agent memory?

No. Memory recalls context. A Work Model records whether that context helped real work land — and predicts the better path before the next run starts.

`acc` stores remembered facts, but it also stores commitments, actions, approval gates, outcomes, failures, and reusable runtimes. The important question is not only "what should the agent remember?" It is "which remembered thing earned trust after reality answered — and what does that predict for the next job?"

### Does it predict, or just remember?

It predicts. A transitions ledger ranks the path most likely to work from everything that worked in your world before, then watches its own error. That is the part recall can't do. When your world shifts — a client goes quiet, a cadence stops landing — the predictor's error rises and it adapts.

### How is this different from a vector database, Mem0, Supermemory, Hermes, or markdown memory files?

Those tools are useful when the problem is recall or shared context. `acc` sits one layer lower in the work loop:

```text
memory          -> what might be relevant?
trace           -> what happened?
eval            -> did the output look good?
acc Work Model  -> what was attempted, who approved it, what happened in reality,
                  which path deserves reuse, and what to try next time?
```

The distinction is outcome credit plus prediction. A retrieved memory, script, browser recipe, or runtime becomes more trusted only when the resulting work is confirmed by reality: a passing test, an owner approval, a delivered action, a reply, or another grounded outcome.

### Does anything leave my machine?

The Work Model does not require a cloud memory account. The substrate is a local SQLite file, retrieval and prediction run locally, and the embedder runs as a local daemon. External actions are gated: sends, publishes, deploys, transfers, deletes, or credentialed actions require owner authority and leave a receipt.

### What counts as reality?

Not model confidence. Reality means something outside the model confirmed the result: a test passed, the owner approved, the browser observed delivery, the world replied, or a runtime produced a grounded result. Self-graded work is kept as weak evidence, not promoted to full truth.

### What is open and what is private?

The installer, host adapters, docs, and public building blocks are open. The engine source for the late-interaction memory, appraisal/prediction layers, and credit math is private for now. The public repo says which claims are proven, which are young, and which parts are not open.

---

## Works with the tools you already run

Keep your agent. Keep your computer. `acc` works underneath the AI tools you already run, quietly turning what they do into a Work Model you own, with nothing new to open and nothing to migrate. One binary, one lifecycle protocol, and one substrate shared across every host and project.

| Host | Status | Wiring |
|---|---|---|
| **Claude Code** | live (reference host) | `.mcp.json` + native hooks ([`plugins/claude/`](plugins/claude/)) |
| **OpenCode** | live | `opencode.json` mcp block + plugin ([`plugins/opencode/`](plugins/opencode/)) |
| **Codex CLI** | live | `config.toml` mcp server + `notify` hook ([`plugins/codex/`](plugins/codex/)) |
| **Cursor** | wired — authored against docs, not live-tested | `.cursor/mcp.json` + agent hooks ([`plugins/cursor/`](plugins/cursor/)) |

`plugins/claude/` is the reference host, with native lifecycle wiring plus skills; the other three translate their host's signals into the one generic envelope. Same substrate, same two verbs, different richness of wiring. Run `acc hosts-sync` to wire `acc` into every agent installed here. It is add-only and idempotent, and it never touches your existing config. The install runs it for you.

**Supported systems:**

- **Linux x86_64:** full (`bwrap` sandbox; embedder on cuda or cpu)
- **macOS:** functional (no `bwrap`; embedder on mps or cpu)
- **Linux aarch64:** functional (embedder on cpu)
- **Windows:** native via `install.ps1` (engine windows-clean; container as fallback)
- **Locked-down / no-root / "must just work":** the **[container](docs/install/container.md)** runs anywhere Docker does, substrate on a volume you own.

---

## Where it goes — one Work Model today, a collective one tomorrow

`acc` is a working single-host research kernel, a running system rather than a roadmap. We're honest about the line. These numbers are measured rather than promised. The live readout is at **[accint.xyz](https://accint.xyz)** and updates as the system runs.

| Stage | What it is |
|---|---|
| **Now · live** | **Your Work Model** — a working Work Model of your operation, on your machine, scored by real outcomes today, with your OK required before anything leaves. The readout at [accint.xyz](https://accint.xyz) is it, running. |
| **Next** | **Your team's Work Model** — many operators, one shared Work Model, per-person authority, one audit plane, so your team's experience compounds together instead of in scattered chats. |
| **Horizon** | **Collective accreted intelligence** — Work Models that compound peer-to-peer in vector space, each node re-verifying against its own reality, so the network gets smarter with no central brain to trust. |

What's running today, what's young, and what's open:

| State | What it covers |
|---|---|
| **Running today** | MaxSim retrieval + per-unit scored memory · reality-gated bounded credit · two reasoners over one substrate · recursive `solve` · sandboxed scored runtimes · structural four-link enforcement · the owner-authority floor · the weak self-graded prior |
| **Young but wired** | the transition ledger + k-NN energy-descent predictor · dependable runtime replay · cost-compression instrumentation · model-swap resilience as a measured delta |
| **Known open** | substrate-on-vs-off lift (no counterfactual harness yet) · scaling MaxSim past a single host · hardening the reachable-network / send boundary |
| **Not started** | a public binary release · the team and collective Work-Model stages above |

The live wedge is concrete: a single-host Work Model, scored by real outcomes today, with the readout above as the running proof. Several coding-agent terminals, one local Work Model, one owner, and approval before external action. The broader product is a learning substrate for any agent-run job, and the proof starts where agents already do real work.

---

## The primitives, in the open

The engine is private: the late-interaction memory, the appraisal and prediction layers, and the credit math. That's the moat, and it stays closed. The integration glue (`install.sh`, `install.ps1`, `bootstrap/`, `plugins/`) is **Apache-2.0** and developed in the open. The prebuilt binary ships under a draft [EULA](EULA.md). See **[LICENSING.md](LICENSING.md)** for the full split.

The building blocks are public too, each shippable on its own:

- **[maxsim-rs](https://github.com/maxbaluev/maxsim-rs)** is late-interaction MaxSim, in clean Rust.
- **[colpali-retrieve](https://github.com/maxbaluev/colpali-retrieve)** is multimodal late interaction (text to document images).
- **[scored-rerank](https://github.com/maxbaluev/scored-rerank)** is ranking that learns from outcomes (Beta posteriors plus Thompson sampling).
- **[mcp-retrieve](https://github.com/maxbaluev/mcp-retrieve)** is late-interaction retrieval as an MCP tool.

---

## Community

- **[CONTRIBUTING.md](CONTRIBUTING.md)** covers what's open, how to add or fix a host adapter, and how to report a problem. Start with `acc doctor`; its output is operational health only, and it's safe to paste.
- **Found a bug or want a new host wired?** Open an [issue](.github/ISSUE_TEMPLATE/). A good *idea* for the engine is welcome as a feature request, even though engine internals can't be PR'd here.
- **Security issues:** never file publicly. See **[SECURITY.md](.github/SECURITY.md)** to report privately.
- **Install:** one line on macOS, Linux, or Windows — see [Install](#install). The live readout runs at **[accint.xyz](https://accint.xyz)**.

---

*Already running AI agents? Turn their work into expertise you own.* · See it live: [accint.xyz](https://accint.xyz)

Questions, bugs, or a host you want wired? Open a [GitHub issue](https://github.com/maxbaluev/accreted-intelligence/issues). · [accint.xyz](https://accint.xyz)
