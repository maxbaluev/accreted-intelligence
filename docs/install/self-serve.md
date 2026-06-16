# Self-serve install — the plain installer path

You run the one-liner yourself, on a box you control. This is the same install the [conversational path](with-agent.md) drives — just without your agent narrating each step.

> **Early access.** The public `bootstrap/install` currently hits a source gate and does not yet produce a working binary for an outside reader — it is the path that opens once you have an invite. Join the list at [accint.xyz/#access](https://accint.xyz/#access). Never read the one-liner as "installs today."

## The one line

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

```powershell
# Windows (PowerShell 5.1+)
irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

Prefer to read before you run? The installer is Apache-2.0 and auditable — `bootstrap/install`, `bootstrap/install.ps1`, and `install.sh` / `install.ps1` are exactly what touches your system. Read them, then run.

## What it does, in order

1. **Probes your hardware** and picks the embedder tier it can honestly run (cuda / mps / cpu). It never pretends your machine is bigger than it is.
2. **Builds `acc`** (a pure-Rust binary) and places it on your PATH.
3. **Starts a warm local embedder daemon** so retrieval is fast from the first call.
4. **Wires Claude Code** — adds `acc` to `.mcp.json` (add-only; your existing config is never rewritten).
5. **Runs `acc hosts-sync`** to wire any other installed agents (OpenCode, Codex, Cursor) — add-only and idempotent. See [../hosts/README.md](../hosts/README.md).

**First run may download the embedder model (several GB) and take minutes.** The installer reports the wait honestly.

## Verify it worked

```
$ acc status            # health + your next step
$ acc doctor --json     # machine-readable health contract
```

`acc doctor` output is operational health only — safe to paste into a [GitHub issue](https://github.com/maxbaluev/accreted-intelligence/issues) if something is off.

## If native doesn't fit

Windows, locked-down, no-root, or "must just work"? Use the [container](container.md) — it runs anywhere Docker does, substrate on a volume you own.

---

Then run your [first session](../first-session.md). See it live: [accint.xyz](https://accint.xyz).
