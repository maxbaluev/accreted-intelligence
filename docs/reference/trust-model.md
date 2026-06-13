# Trust model — what's open, what's closed, and why

This is the repo's *you own it* page: what runs on your machine, what stays private and why, where the authority boundary sits, and where your data lives. The mechanics of the split are in [../PUBLIC_REPO_MANIFEST.md](../PUBLIC_REPO_MANIFEST.md) and [../../LICENSING.md](../../LICENSING.md); this page is the *why*.

## The split, in one line

**The glue is open and auditable; the engine binary is closed; the ideas are public; the constants are the moat.** You can read every line that touches your system at install time, while the engine's scoring and calibration internals stay private.

## What's open — Apache-2.0

The integration glue is [Apache-2.0](../../LICENSE-APACHE-2.0.txt) and developed in the open, because it is exactly what runs on your machine when you install:

- the installers — `install.sh`, `install.ps1`, `bootstrap/`
- the host plugins — `plugins/**`, including the Claude Code reference host at `plugins/claude/`

Audit them. They never touch your existing config except add-only, and `acc hosts-sync --dry-run` shows you the diff before anything is written.

The building blocks are public too, each shippable on its own: [maxsim-rs](https://github.com/maxbaluev/maxsim-rs), [colpali-retrieve](https://github.com/maxbaluev/colpali-retrieve), [scored-rerank](https://github.com/maxbaluev/scored-rerank), [mcp-retrieve](https://github.com/maxbaluev/mcp-retrieve).

## What's closed — and why

The engine **source** — the late-interaction memory, the appraisal and prediction layers, the credit math — is private. That is the moat, and it stays closed. The prebuilt `acc` binary ships under a draft [EULA](../../EULA.md).

The principles are public (see [whitepaper.md](whitepaper.md) and [architecture-overview.md](architecture-overview.md)); the **exact numeric constants are not** — the surprise function, the provenance weights, the self-graded discount, the calibration coefficients. The whitepaper states the general form and marks the coefficients *intentionally omitted — proprietary*. A good *idea* for the engine is welcome as a feature request even though engine internals can't be PR'd here.

This is the honest version of "open core": ideas and glue in the open, the calibrated engine closed.

## The authority floor (hard, not advisory)

Owner authority is required before anything that **sends, publishes, deploys, transfers, deletes important data, exposes secrets, or uses your credentials.** The gate is structural — a held decision is named and timestamped, and nothing leaves without it. It cannot be tricked into skipping. This is what makes the same loop safe for recruiting, sales, and finance, not only code. Deliberation is never consent; prediction is never permission.

## Data residency — your data stays put

- The substrate (`acc.db`) is a plain file on your disk, owned by you. Retrieval, scoring, and the sandbox all run on your machine.
- There is **no cloud control plane in the loop** and **no API key to leak** — not for memory, and not for the reasoner. The reasoner is the interactive session itself; when memory can't answer, `acc` hands the attached agent a frame to deliberate over. There is no external LLM lane, ever.
- Telemetry is off by default and requires your own key.
- No license here claims any right to your substrate. It is yours.

## Credit honesty

Closing a commitment defaults to `self_graded` — a deliberately weak prior — so the system cannot compound from its own confidence. Full weight requires reality: the owner confirmed, the world replied, a test passed, a sandboxed run exited clean. Belief never counts as reality.

---

The live readout — checked-against-reality vs. self-graded, updating as the system runs — is at [accint.xyz](https://accint.xyz): measured, not promised.
