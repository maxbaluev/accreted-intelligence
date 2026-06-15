# One universal workflow

*The plain-words version. No math. No code required to follow it.*

Your agent is brilliant once and amnesiac forever. It solves your problem today, then forgets how — so next week you pay, in time and tokens, to rediscover yesterday. Accreted Intelligence fixes the forgetting: the same work gets faster, safer, and genuinely better every run, because what worked is kept — checked against reality, owned by you. **Offload the task. Never the learning.** The reasoning engine is the part you can swap; the judgment it earned in your world is the part you keep.

## The loop, in plain words

```
it predicts the better path  →  the agent acts, receipted  →  reality settles it  →  the Work Model sharpens
```

Named without jargon, it is four links:

1. **You say what you want**, in plain words — to the agent you already use.
2. **`acc` predicts the better path** from everything that worked in your world before, and shapes the move from it. This is more than [retrieval](glossary.md): it recalls what's relevant, *and* ranks the path most likely to work — then watches its own error, so when your world shifts it notices.
3. **The agent acts and writes a receipt _as_ it goes**, not after, in your real accounts. That receipt is a [commitment](glossary.md): the intent plus the memory it leaned on, recorded the moment work begins.
4. **Reality settles it** — a reply lands, a test passes, you say yes or no — and credit moves to exactly what helped. This is [outcome credit](glossary.md). Belief never counts as reality: a result you only graded yourself carries a deliberately weak weight; a real reply, a passing test, or your own OK carries full weight. The verdict updates your **Work Model**, so the next run starts from what already worked, not from zero.

And one guardrail wraps all four: **anything that leaves your machine waits for your OK first.** That is the [authority gate](glossary.md) — `HELD → your OK`. It is hard, not advisory.

## The same loop, twice

The whole point is that this loop does not change shape between jobs. Only the content does.

**Chasing invoices** — no code anywhere. You tell your agent, in plain words: *"Get the overdue invoices moving."*

- finds the overdue list — `VERIFIED`
- drafts 6 nudges, none templated — `HELD → your OK`
- sends the 6 you approved — `VERIFIED`
- two get paid; the angle that worked is kept — `CREDITED`
- won't blast all 40 — the consent floor holds — `REFUSED`

**Shipping code.** You tell your agent: *"Wire the retry logic through the client."*

- recalls the pattern that passed last time — `KNOWN`
- edits, runs the suite — `VERIFIED`
- the fix that held is kept as a reusable path — `CREDITED`
- won't push to main without your OK — `HELD`

Same four links. Same stamps. The notable thing about both rows: **the entry shape is identical** — *you say X to your agent.* The non-technical surface is conversational, through the host agent you already run (Claude Code, Cursor, and friends). There is no separate "business mode" and no "technical mode," and for the non-coder there is no CLI to learn — it is one loop, learning from all of them into one memory.

*(Illustrative — the stamps show the shape, not a benchmark. The only measured numbers live at [accint.xyz](https://accint.xyz).)*

## Two things compound, not one

Most tools that "remember" keep *what was said*. `acc` keeps two things, and scores both by reality:

- **What worked** — the angle, the cadence, the test, the path that landed. Your judgment about your world: your voice, your standards, what a good outcome looks like, what you will never allow.
- **How to do it** — when a path holds (a browser flow, a script, a tool integration), it's saved as a runtime and scored exactly like a memo. A flow that worked replays cheaply next time; one that broke loses its score and isn't trusted again. No privileged lane — the browser is just another scored runtime.

What builds up is capital you own: your team's judgment, made replayable on your machine, kept out of someone else's model.

## It keeps receipts — same record, two readers

Every step is written down as it happens: what it expected, who approved it, what came back. When someone asks *"why did it do that?"*, it's already written — the receipt your team can show management, and the lesson your Work Model inherits from the same row. Nothing happens without a trace, and nothing you decided is lost.

## Why it compounds

Run 1 reasons every step from scratch. By later runs, the steps reality already verified **replay instead of re-reasoning** — near-instant. So the same job costs less and lands better each time, instead of costing the same forever. The invoice nudge that got two clients to pay, the test that caught a class of bug — those are predicted, kept, and reused, not rediscovered.

## Where it runs

On a machine you control. One small program and one data file, sitting underneath the agent you already run. No cloud brain in the loop, no API key to leak — not for the memory, and not for the reasoner. Your Work Model stays yours. (The honest mechanics: [reference/trust-model.md](reference/trust-model.md).)

## Honest bounds

`acc` is early access and a working single-host kernel — a running system, not a finished platform. The universal claim above is proven by *shape* — the architecture genuinely is identical across jobs — but not yet by scale. We say what's young, with evidence. The depth, with the math and the proven-vs-open line, is in [reference/whitepaper.md](reference/whitepaper.md).

Ready to run it? → [first-session.md](first-session.md). See it live → [accint.xyz](https://accint.xyz).
