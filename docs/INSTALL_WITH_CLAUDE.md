# Install acc by pasting a link into Claude

This is the **conversational install path**: you give Claude (Claude Code) a link to
this repo, and Claude installs acc *with* you — explaining each step, asking before
anything irreversible, running the installer, and then **verifying the result against a
machine-readable contract** (`acc doctor --json`) instead of guessing. No manual JSON
pasting, no "did it work?" — Claude reads the doctor report and tells you the truth.

If you would rather run it yourself, the README's `./install.sh` and the
[container path](INSTALL_CONTAINER.md) are the same install underneath. This doc is for
when you want Claude to drive.

## The one paste

Open Claude Code in an empty directory and paste a single line:

```
Install acc from https://github.com/<owner>/<repo> — clone it, run the installer for my
OS, then run `acc doctor --json` and walk me through the result.
```

That's the whole trigger. Everything below is the **contract** Claude follows once you
send it — written so you know exactly what Claude will (and will not) do on your machine.

## The installer ↔ Claude contract

When you paste that line, Claude is expected to do these steps, in order, **pausing for
your consent at the boundary** (the clone/install/daemon steps touch your machine):

1. **Explain before touching anything.** Claude states what acc is (a local memory +
   tool loop), what the installer will change (Rust toolchain, `uv`, a sandbox lib, a
   warm embedder daemon, a project-local `.mcp.json`), and roughly how long it takes —
   then asks for your go-ahead. **First run may download the embedder model (several GB)
   and take minutes**; Claude tells you that up front, not after you're waiting.

2. **Scoped consent, then the one-liner.** With your "go", Claude's first move is handing
   you (or running) the bootstrap one-liner for your host. It fetches the source and hands
   off to the same installer underneath — zero install logic of its own:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
   ```

   ```powershell
   irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
   ```

   The install lane that one-liner lands in is picked for your host:
   - **Linux x86_64 / aarch64 / macOS** → the native `./install.sh`. It is a
     **deterministic phase-machine**: it probes your host, selects the embedder tier (the
     3-model ladder, below), auto-installs deps, builds `acc`, materializes the encoder
     env, pins the host-selected model, starts the warm daemon, writes `.mcp.json`, and
     seeds the core runtimes. Idempotent — each phase checks its own postcondition first,
     so re-running is safe and resumes from where it left off. Claude drives it with
     `./install.sh --json` (one machine-readable line per phase — see the installer
     contract below) so it can react phase-by-phase rather than parsing prose.
   - **Windows** → the native `install.ps1`, the same deterministic phase-machine in
     PowerShell: same `-DryRun`/`-Json` contract, the Windows tier ladder (full-bf16
     lanes only — AWQ/triton has no Windows wheels), and the same `acc doctor --json`
     handoff. The engine is Windows-native (zero `std::os::unix` outside the platform
     boundary; daemon IPC = TCP loopback + owner token); the container below remains
     the fallback for locked-down hosts.
   - **A locked-down/no-root box, or "it must just work"** → the **Tier-C
     container** (`scripts/acc-docker.sh`), a reproducible Linux image that runs
     anywhere Docker runs, with your substrate on an owner-owned mounted volume. Full
     details and the GPU/CPU-floor tradeoff live in
     [docs/INSTALL_CONTAINER.md](INSTALL_CONTAINER.md). The native installer **detects
     this case itself**: on a host where no native tier fits, `./install.sh` prints the
     container path as a terminal verdict instead of installing a broken native lane.

   Claude does **not** silently `sudo`, install global packages, or modify your shell
   profile beyond what the installer itself does — and it names those side effects before
   running. Before any real install, Claude can run `./install.sh --dry-run` (walks every
   phase, mutates nothing, reports what *would* happen and which tier it would pick) as a
   no-side-effect preview.

### The installer's `--json` contract (`acc.install.v1`)

`./install.sh --json` emits **one JSON object per phase** on stdout (all human chatter
goes to stderr), so Claude can drive the install programmatically and react to each phase
as it completes. Each line is:

```json
{ "phase": "binary", "status": "ok", "detail": "acc v0.0.1 …", "next": "phase 4: encoder env" }
```

| field | meaning |
|---|---|
| `phase` | the phase id (stable; the canonical set is below) |
| `status` | `ok` (done/already-satisfied) · `would` (dry-run preview) · `skipped` (non-fatal, with a `next` fix) · `failed` (fatal — install stops) |
| `detail` | human-readable result of the phase |
| `next` | the exact next command/phase to run when action is needed (or `null`) |

**The canonical phases, in order:**

| phase id | does |
|---|---|
| `probe_tier` | probes host (VRAM/RAM/OS/arch) + selects the embedder tier (the ladder below). On a container-only host this is the terminal verdict. |
| `prereq_rust` / `prereq_uv` / `prereq_python` | ensures the toolchain (cargo, uv, python3) — idempotent |
| `sysdeps_sandbox` | bubblewrap (Linux sandbox) + a C linker |
| `binary` | `cargo build --release` + `cargo install` — skipped when the installed version already matches source |
| `encoder_env` | `uv sync --script` of the selected tier's encoder deps (pays the resolve cost once, before the daemon's first encode) |
| `model_pin` | `acc pin` — records the host-selected `(model, device)` before VRAM is taken |
| `substrate` | ensures `acc.db` exists (**never clobbers** an existing one) |
| `embedder_daemon` | starts the warm embedder daemon (first run downloads the model) |
| `browser` | optional Camoufox host-side browser env (`ACC_NO_BROWSER=1` to skip) |
| `seed` | waits for the embedder, then converges the browser daemon + seeds `runtime:browser` |
| `mcp_wiring` | writes/merges the project-local `.mcp.json` (idempotent) |
| `verify` | runs `acc doctor` |
| `verdict` | final line — overall outcome + the `acc doctor --json` handoff (the verification contract below) |

The final `verdict` line's `next` is always the `acc doctor --json` command — the
installer's machine-readable stream **hands off** to the doctor's machine-readable report
(schema `acc.doctor.v1`, below) for the load-bearing verification step.

### The 3-model tier ladder (host-selected)

`probe_tier` walks a ladder top-down and picks the **first** rung your host honestly
clears — multimodal ColQwen3 is preferred at every rung; LateOn (text-only) is the last
resort. It mirrors `src/selector.rs`'s signals shell-side (`nvidia-smi` free VRAM, `uname`
OS/arch, total RAM):

| your host | tier | model · device |
|---|---|---|
| linux x86_64 + NVIDIA, free VRAM ≥ 10 GB | `8b-awq` | ColQwen3-8B AWQ · cuda (best multimodal) |
| linux x86_64 + NVIDIA, free VRAM ≥ 5 GB | `4b-awq` | ColQwen3-4B AWQ · cuda |
| linux x86_64, RAM ≥ 24 / 12 GB | `8b-cpu` / `4b-cpu` | ColQwen3-8B/4B AWQ · cpu (slow, multimodal) |
| Apple Silicon, RAM ≥ 32 / 16 GB | `8b-full` / `4b-full` | ColQwen3-8B/4B full bf16 · mps |
| linux aarch64 / Intel-mac, RAM ≥ 32 / 16 GB | `8b-full` / `4b-full` | ColQwen3-8B/4B full bf16 · cpu |
| below the floors | `lateon` | LateOn text-only · cpu (or mps ≥ 16 GB) |
| nothing viable natively | `container` | → [docs/INSTALL_CONTAINER.md](INSTALL_CONTAINER.md) |

Override the auto-pick with `ACC_TIER=<8b-awq|4b-awq|8b-cpu|4b-cpu|8b-full|4b-full|lateon|container>`.

3. **Verify against `acc doctor --json` — the verification contract.** This is the
   load-bearing step. Instead of trusting install output, Claude runs:

   ```bash
   acc doctor --json
   ```

   and reads the structured report (schema **`acc.doctor.v1`**). It is one JSON object:

   ```json
   {
     "schema": "acc.doctor.v1",
     "status": "ok | warn | fail",
     "summary": "6 ok, 2 warn",
     "checks": [
       { "name": "binary",    "status": "ok",   "detail": "...", "fix": null },
       { "name": "substrate", "status": "ok",   "detail": "...", "fix": null },
       { "name": "embedder",  "status": "warn", "detail": "...", "fix": "run `acc embedder` …" },
       { "name": "model_pin", "status": "skip", "detail": "...", "fix": null },
       { "name": "sandbox",   "status": "ok",   "detail": "...", "fix": null },
       { "name": "mcp",       "status": "ok",   "detail": "...", "fix": null },
       { "name": "hooks",     "status": "ok",   "detail": "...", "fix": null },
       { "name": "brain/session", "status": "ok", "detail": "live via the MCP continuation-frame lane — the interactive session is the reasoner (no credential needed)", "fix": null }
     ]
   }
   ```

   **The eight checks (always in this order), each a layer of the organism:**

   | check | proves | typical fix when not `ok` |
   |---|---|---|
   | `binary` | the `acc` binary built/installed (with its version) | — (fails only if the build broke) |
   | `substrate` | the `acc.db` opens; entity count + pinned model | run `./install.sh`, or ingest one memory to create it |
   | `embedder` | the warm daemon answers a real encode round-trip | `acc embedder` (first run downloads the model — minutes) |
   | `model_pin` | the encoder's vector dim matches the substrate's | re-pin / re-ingest under one model (never mix embedders) |
   | `sandbox` | `bwrap` is available so `act exec` runs isolated | install bubblewrap, or use the container ([here](INSTALL_CONTAINER.md)) |
   | `mcp` | `.mcp.json` registers the `acc` server for Claude Code | re-run `./install.sh` (writes the wiring) |
   | `hooks` | the three four-link hooks are present under `.claude/hooks/` | re-run `./install.sh` to restore them |
   | `brain/session` | the continuation-frame lane is live — the interactive session is the reasoner | — (always ok; no credential, ever — see the no-credential note below) |

   **How Claude reads the verdict:**
   - `status: "ok"` overall → every layer healthy; proceed to the first useful turn.
   - `status: "warn"` → degraded but usable for what it covers. Claude reads each
     `warn` check's `detail` + `fix` and tells you which capabilities are affected (e.g.
     a `warn` on `embedder` means retrieval isn't ready *yet*).
   - `status: "fail"` → a layer is broken; Claude surfaces the failing check's `fix`
     and works it with you before calling the install done.

   `acc doctor` (no `--json`) prints the same report as a human-readable ✓/⚠/✗ list
   with the same fixes — useful if you want to read it yourself. The exit code is `0`
   only when everything is `ok`/`skip`; any `warn` or `fail` is non-zero, so the
   installer treats "embedder still warming" as not-yet-done.

4. **Interpret and fix conversationally.** Claude doesn't dump the JSON at you — it
   translates: which layers are green, which need a moment (the model is still
   downloading), which need a decision from you (install bubblewrap vs. switch to the
   container). It re-runs `acc doctor` after a fix to confirm the layer flipped to `ok`.

5. **Optional, consent-gated grounding.** Once doctor is green, Claude *offers* to seed a
   little starter context — a memory or two about you / your project so the first
   retrieval has something real to find. This is **opt-in**: nothing about you is stored
   unless you say yes, and it stays in your local `acc.db`.

6. **First useful turn.** With the substrate live, Claude shows the loop working end to
   end — usually a tiny `acc_retrieve` then a real task — so your first interaction
   produces something, not just a green checklist.

## The no-credential note (the brain is the session)

acc needs **no API key and no login at all** — not for memory, and not for the brain.
`acc_retrieve` and the scored-token substrate are entirely local, and the brain is the
**interactive session itself**: when memory can't answer, `acc_act(solve)` returns a
continuation frame that the attached session (Claude Code) deliberates over and submits
back via the reserved `continue` runtime. There is no external LLM lane — no credential,
OAuth, or API key, ever.

Headless runs (no interactive session attached) are reflex-only: work that needs
deliberation checkpoints `waiting:brain` as a persisted frame and is drained at the next
interactive session — open Claude Code or run `acc frames` to see the queue. That
checkpoint is the design, not a fault.

## Honest consent & privacy

- **Local-only by default.** The substrate (`acc.db`) is a plain file on your disk,
  owned by you. Retrieval, scoring, and the sandbox all run on your machine. Nothing is
  sent anywhere for memory or retrieval.
- **The model never leaves the host.** The embedder daemon loads the model host-side and
  serves it over a unix socket; the GPU never enters the sandbox.
- **No secrets to hold.** acc keeps no credential at all — there is no brain token, no
  OAuth store, no API key. The reasoning step is the interactive session itself, so there
  is nothing to leak, log, or store in the substrate.
- **Consent at the boundary.** Claude installs with your go-ahead, asks before the
  optional grounding step, and never sends/publishes/deploys anything during install. The
  install path touches only your machine.
- **The brain is never your consent.** A brain suggestion is a prediction, not your
  approval — Claude keeps "what acc knows" separate from "what you said".

## Failure → fix, straight from `acc doctor`

Every failure has a fix line *in the doctor report itself* — Claude reads it and acts on
it. The common ones:

- **`sandbox` warn — "no sandbox available" (`bwrap` missing).** `act exec` refuses to
  run unsandboxed by design. Fix: install bubblewrap (`apt install bubblewrap` on Linux),
  or run acc in the **container** ([docs/INSTALL_CONTAINER.md](INSTALL_CONTAINER.md)),
  which carries its own sandbox. On macOS there's no `bwrap`; runtimes run under acc's
  built-in deadline (or use the container).
- **`embedder` warn — daemon down / "still warming".** The first run downloads the model
  (several GB). Fix: `acc embedder`, then wait and re-run `acc doctor` — it flips to
  `ok` once a real encode round-trip succeeds. (A bound-but-cold daemon is reported
  honestly as still warming, not as ready.)
- **`substrate` warn — "MIXED EMBEDDERS".** The db has vectors from more than one model.
  One vector space per db: re-ingest under a single embedder (MaxSim across two spaces
  scores 0).
- **`model_pin` warn — encoder dim ≠ substrate dim.** The daemon's model differs from the
  substrate's. Re-pin or re-ingest under one model.
- **`mcp` warn — no/incomplete `.mcp.json`.** Re-run `./install.sh` (it writes the
  project-local wiring), then reload MCP in Claude Code so the two verbs appear.
- **`hooks` warn — a hook is missing.** Re-run `./install.sh` to restore
  `.claude/hooks/*` (these bind the four-link discipline).
- **`brain/session`.** Always `ok` — the interactive session is the reasoner, nothing to
  configure. A headless solve that says `waiting:brain` is a checkpoint, not a fault:
  drain it at the next interactive session (`acc frames`).

## Tier guidance — which install lane

| Your host | Lane | Why |
|---|---|---|
| Linux x86_64 with a GPU you control | native `./install.sh` | full multimodal ColQwen lane, no container overhead |
| Linux x86_64/aarch64 or macOS, root-ish | native `./install.sh` | functional; embedder on cpu/mps |
| Windows | native `install.ps1` | same phase-machine in PowerShell; the **container** ([here](INSTALL_CONTAINER.md)) is the fallback for locked-down hosts |
| Locked-down / no-root / "must just work" | **container** ([here](INSTALL_CONTAINER.md)) | the image carries its deps; CPU floor works with no GPU |

The container defaults to the universal CPU floor (LateOn, text-only); the GPU/ColQwen
lane (and cross-modal sight via `acc_retrieve` with an `image` input) is opt-in. See
[docs/INSTALL_CONTAINER.md](INSTALL_CONTAINER.md) for the full tradeoff and the
`docker exec -i` MCP wiring.

## The two machine-readable contracts (install → verify)

Claude drives the whole install on **two** machine-readable streams, end to end:

1. **`./install.sh --json`** (schema `acc.install.v1`, above) — the deterministic
   phase-machine. The `probe_tier` phase carries the explicit tier-selector recommendation
   (which of the 3 models, on which device, and why), so the lane choice is itself a
   machine-readable line rather than Claude's host inspection. Each phase's `status` +
   `next` tell Claude exactly what to do.
2. **`acc doctor --json`** (schema `acc.doctor.v1`, above) — the verification contract
   the installer's final `verdict` line hands off to.

Together they are the full install-then-verify contract — no prose parsing, no "did it
work?" guessing. `./install.sh --dry-run --json` previews the same phase stream (every
phase `status: "would"`) with zero side effects, so Claude can show you the plan and the
selected tier before touching your machine.
