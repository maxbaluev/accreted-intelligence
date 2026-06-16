# Quickstart — zero to your first real session

The practitioner's path: install, run the loop, read what it wrote. For the *why* behind each step, read [concept.md](concept.md); for the bare command list, [first-session.md](first-session.md). This page is the expanded walkthrough.

> **Early access.** There is no public binary yet — the one-liner below installs a working binary only once you have an invite. Join the list at [accint.xyz/#access](https://accint.xyz/#access). We say what's proven and what's young.

## 1. Install

Pick your path from [install/README.md](install/README.md). The common cases:

```bash
# macOS / Linux — fetches source, hands off to the installer for your OS
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

```powershell
# Windows (PowerShell 5.1+)
irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

The installer probes your hardware, picks an embedder tier it can honestly run, builds `acc`, starts a warm local daemon, and wires your agent's `.mcp.json`. First run may download the embedder model (several GB) and take minutes — the installer reports the wait honestly. Locked-down or no-root box? Use the [container](install/container.md). Want your agent (Claude Code, Codex, Cursor, OpenCode) to drive the install and verify it for you? Paste one prompt — see [install/with-agent.md](install/with-agent.md).

## 2. Confirm health

```
$ acc status     # health + your next step
$ acc doctor     # diagnose; output is operational health only, safe to paste
```

## 3. Run the loop

```
$ acc --db acc.db act solve "draft the follow-up to last week's brief"
```

A `solve` records a [commitment](glossary.md), retrieves from memory, and returns the artifact or a deliberation [frame](glossary.md). A receipt is written *as* the work happens — not a transcript after the fact. The full literal receipt lines are in [first-session.md](first-session.md).

Inside your host agent (Claude Code, Cursor, …), you don't type CLI at all — the same two verbs are the MCP tools `acc_retrieve` and `acc_act`. You just talk to the agent.

## 4. Read what it wrote

```
$ acc commitments     # the commitments recorded, with status
$ acc frames          # open deliberation frames waiting for you
```

## 5. Watch it compound

Run the same kind of job again next week. Steps reality already verified **replay instead of re-reasoning** — the same job costs less and lands better each run. Anything that leaves your machine still waits for your OK at the [authority gate](glossary.md).

---

Next: [concept.md](concept.md) for the full picture · [hosts/README.md](hosts/README.md) to wire another agent · [reference/whitepaper.md](reference/whitepaper.md) for the science. See it live: [accint.xyz](https://accint.xyz).
