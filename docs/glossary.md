# Glossary

One screen, one source of truth for the terms and stamps used across this repo and [accint.xyz](https://accint.xyz/?ref=github-docs&utm_source=github&utm_campaign=docs). Other docs link here rather than redefine.

## The loop

| Term | What it means |
|---|---|
| **Work Model** | What `acc` builds: a scored record of what worked in your world — judgment, not just memory. It predicts the better path, is checked against your own results, lives on your machine, and is the asset you keep when you swap the reasoning model. |
| **commitment** | A unit of work `acc` records before acting — intent plus the memory it retrieved. The thing reality later settles. In the CLI a commitment row carries a status of `pending` or `good`. |
| **retrieval** | Peeking the scored memory by relevance (MaxSim) before acting. The only read. The verb is `acc_retrieve`; citing what you used is the credit edge. |
| **prediction** (transitions ledger) | The part recall can't do: ranking the action most likely to improve things next — k-nearest-neighbor in the space of past appraisals — and watching its own error, so when your world shifts it notices. |
| **outcome** | Closing a commitment with a verdict from reality. The verb is `acc_act(outcome, …)`. Credit flows to exactly the memory that aligned. |
| **runtime** | A path that held — a script, a browser flow, a tool integration — saved and scored exactly like a memo, so it can replay instead of re-reasoning. |
| **runtime ledger** | The record of capability earning its score the same way memory does: write → drive → replay → debit. A flow that worked replays cheaply; one that broke is docked and not trusted blind. The browser is just another scored runtime — no privileged lane. |
| **frame** (`brain_frame`) | A deliberation handed back to the attached session when memory can't answer. Resolved by `acc_act(continue, …)`. Frame states in the CLI: `waiting:brain`, `checkpointed`. |
| **substrate** | The scored memory itself — one file (`acc.db`) on a machine you control. Your Work Model is what lives in it. |
| **authority gate** | The hard check at the owner/external boundary: anything that sends, publishes, deploys, transfers, deletes, or uses your credentials waits for your OK. Not advisory. |

## The two verbs

| Verb | What it does |
|---|---|
| **`acc_retrieve`** | The only read — peek the scored memory by MaxSim. Natively multimodal (it can look at an image). |
| **`acc_act`** | The only do. `solve` recurses on a sub-goal · `exec` runs sandboxed code · `register` stores a reusable runtime · `outcome` closes a commitment against reality · `continue` resolves a frame. |

## The stamps

The stamps are the brand's **narrative labels** for what the loop is doing at a glance. They are presentation — they read on the site and in receipts — and most are **not** verbatim CLI tokens. Here is the honest map to what the product actually emits:

| Stamp (narrative) | What it marks | Maps to (actual emitted state) |
|---|---|---|
| **VERIFIED** | a step reality confirmed | commitment `good`; outcome provenance `external` / `runtime` |
| **HELD → your OK** | a step waiting at the authority gate | presentation-only — the held-for-consent boundary, not a single CLI token |
| **DECIDED** | you approved it — your name on the call | presentation-only — the owner-validated close; provenance tier `owner` |
| **REFUSED** | a boundary the gate would not cross | presentation-only |
| **FLOOR** | a standing consent floor held (e.g. "named people only, never a list") | presentation-only — the authority floor, not a single CLI token |
| **CREDITED** | credit moved to the memory that helped | outcome closed; provenance tier records who validated (`owner` / `external` / `runtime` / `self_graded`) |
| **REPLAYED** | a verified path ran again instead of re-reasoning | runtime replay |
| **KNOWN** | recalled from memory rather than re-derived | a retrieval hit |
| **NOT TRUSTED** | a runtime that broke — score docked, not retried blind | runtime credit debited (β increases; the row drops in rank) |

Provenance tiers, verbatim, are `self_graded` · `owner` · `external` · `runtime`. A close defaults to `self_graded` — a deliberately weak prior; full weight requires reality. Belief never counts as reality.

> Note: `acc task` is **not** part of this product — it belongs to a different system. The real CLI surface is `acc status`, `acc commitments`, `acc frames`, `acc doctor`, and `acc --db acc.db act solve "…"`, plus the two MCP verbs `acc_retrieve` / `acc_act`. See [first-session.md](first-session.md).

See it live: [accint.xyz](https://accint.xyz/?ref=github-docs&utm_source=github&utm_campaign=docs).
