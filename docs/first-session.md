# First session — the 60-second golden path

The literal commands and the receipt lines, nothing else. For *why* each step matters, read [concept.md](concept.md) — this page does not re-explain the loop.

> Install first: the public release installer downloads a verified prebuilt `acc` binary on supported platforms. To install, see [install/README.md](install/README.md).

## 1. Check health and your next step

```
$ acc status
```

`acc status` reports the substrate health, the embedder daemon, and your next step honestly. If anything is off, run `acc doctor` (its output is operational health only — safe to paste into an issue).

## 2. Run the loop

```
$ acc --db acc.db act solve "draft the follow-up to last week's brief"
```

A `solve` records a [commitment](glossary.md), retrieves from memory, and returns either the artifact or a deliberation [frame](glossary.md) for the attached session to resolve. A receipt is written *as* the work happens:

```
  commitment c-7f3 created   ·   retrieved 4 prior memos   [VERIFIED]
  drafted the follow-up, held for your OK                  [HELD → your OK]
  you approved · sent · the angle that worked is kept      [CREDITED]
```

*(Illustrative receipt — the stamps are narrative labels; see [glossary.md](glossary.md) for how each maps to the actual emitted state. The live, animated version with the measured stat strip is at [accint.xyz](https://accint.xyz/?ref=github-docs&utm_source=github&utm_campaign=docs).)*

## 3. Read what it wrote

```
$ acc commitments      # the commitments recorded, with their status
$ acc frames           # any open deliberation frames waiting for you
```

That is the loop end to end: a commitment created, a receipt written as it happens, a verdict from reality, credit moved to what helped.

## The whole surface

Everything you need on day one:

| Command | What it does |
|---|---|
| `acc status` | health + your next step |
| `acc --db acc.db act solve "…"` | run the loop on a goal |
| `acc commitments` | list recorded commitments + status |
| `acc frames` | list open deliberation frames |
| `acc doctor` | diagnose; output is safe to paste |

Inside your host agent (Claude Code, Cursor, …) the same two verbs are the MCP tools `acc_retrieve` and `acc_act` — no CLI needed; you just talk to the agent.

> Not `acc task` — that command belongs to a different system and does not exist here.

Next: the expanded walkthrough in [quickstart.md](quickstart.md). See it live: [accint.xyz](https://accint.xyz/?ref=github-docs&utm_source=github&utm_campaign=docs).
