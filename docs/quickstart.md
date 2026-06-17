# Quickstart — zero to your first real session

The practitioner's path: install, run the loop, read what it wrote. For the *why* behind each step, read [concept.md](concept.md); for the bare command list, [first-session.md](first-session.md). This page is the expanded walkthrough.

> **Public binary available.** The one-liner below fetches the public release installer, which downloads a signed-by-hash prebuilt `acc` binary for supported platforms and falls back only where a source checkout is available. We still say what's proven and what's young.

## 1. Install

Pick your path from [install/README.md](install/README.md). The common cases:

```bash
# macOS / Linux — fetches the public installer and selected release binary
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

```powershell
# Windows (PowerShell 5.1+)
irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

If your host or marketplace installs from the Official MCP Registry, use the
`io.github.maxbaluev/accint` MCPB entry instead. The one-liner remains the
most complete path for local host wiring because it runs `acc hosts-sync`.

For attribution from a directory listing or PR, put `ACC_INSTALL_REF=<surface>`
on the installer process. `ACC_INSTALL_SOURCE='ref=<surface>'` can carry coarse
source context in the same local receipt:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=gh-awesome-list ACC_INSTALL_SOURCE='ref=gh-awesome-list' sh
```

The installer writes those labels to a local receipt only; it does not send the
ref or source anywhere by itself.

For installs that start from these GitHub docs, preserve the docs attribution
receipt:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=github-docs ACC_INSTALL_SOURCE='ref=github-docs&utm_source=github&utm_campaign=docs' sh
```

```powershell
$env:ACC_INSTALL_REF='github-docs'; $env:ACC_INSTALL_SOURCE='ref=github-docs&utm_source=github&utm_campaign=docs'; irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

The installer probes your hardware, picks an embedder tier it can honestly run, installs `acc`, starts a warm local daemon, and wires your agent's `.mcp.json`. First run may download the embedder model (several GB) and take minutes — the installer reports the wait honestly. Locked-down or no-root box? The [container](install/container.md) page tracks that portability path separately. Want your agent (Claude Code, Codex, Cursor, OpenCode) to drive the install and verify it for you? Paste one prompt — see [install/with-agent.md](install/with-agent.md).

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

Next: [concept.md](concept.md) for the full picture · [hosts/README.md](hosts/README.md) to wire another agent · [reference/whitepaper.md](reference/whitepaper.md) for the science. See it live: [accint.xyz](https://accint.xyz/?ref=github-docs&utm_source=github&utm_campaign=docs).
