# acc — Architecture Overview

A skimmable map of the system. The thesis lives in [whitepaper.md](whitepaper.md); this page is the engineering surface, and it's IP-protected.

## What acc is

acc is a Recursive Language Model (RLM) over a late-interaction scored-token memory, implemented as a single Rust crate. A reasoner talks to one persistent substrate through two verbs, retrieve and act. The substrate learns from real outcomes: it moves the score of the individual units of memory that actually aligned with the work, and it *predicts* the path most likely to work next from a transitions ledger over past appraisals. The intelligence lives in the scored state rather than in the model, and the model is a replaceable processor. acc is a working single-host research kernel. It tries to stay honest about what is proven by reality, what is self-graded, and what is still aspirational.

## The two verbs

These two verbs are the whole reasoner interface. There is no third verb, and vision is native to `retrieve`.

- **`acc_retrieve(query | image)`** is the only read. It peeks the memory by MaxSim. Pass text or a typed image; both encode to late-interaction tokens, so a text memo can answer an image (ColPali-style cross-modal retrieval).
- **`acc_act(runtime, input)`** does anything. Built-in runtimes:
  - `solve` — RECURSE: re-enter the loop on a sub-goal. Decomposition emerges from the recursion tree; there is no `decompose` op.
  - `exec` — run sandboxed code; inside it, the code can recurse over the memory.
  - `register` — store reusable named code. It becomes scored tokens, with no privileged lane.
  - `outcome` — close a commitment with a real-world verdict; credit flows to the cited memory.
  - `<name>` — run any registered runtime, with `input` bound to a standard input variable.

Writing to memory and crediting are not verbs. The loop does them automatically on every call.

## Late-interaction scored-token memory (commodity layer + acc's form)

Each entity (knowledge, runtime, owner fact, goal, image) is stored as an ordered set of per-token vectors. There is no single-vector dense form; the token is the atom. Retrieval ranks by MaxSim:

$$\text{score}(q, d) = \sum_i \max_j \text{sim}(q_i, d_j)$$

For each query token, take its best-matching doc token and sum. The aligned (query→doc) pairs are the citation. This part is published commodity: ColBERT for text, ColPali for vision.

acc extends this. Each document token carries a Bayesian Beta(α, β) posterior (Thompson 1933), with mean $\pi_j = \alpha_j/(\alpha_j+\beta_j)$ (how often its alignments led to good outcomes) and a confidence that grows with the evidence count $\alpha_j+\beta_j$. That posterior reweights the token's contribution:

$$\text{score}(q, d) = \sum_i \max_j \big[\, \text{sim}(q_i, d_j) \cdot g(\pi_j) \,\big]$$

where $g$ is a monotonic confidence weighting, so a token reality has repeatedly confirmed pulls harder than a fresh one. (The exact form of `g` and its calibration are proprietary.)

## Reality-gated credit (the discipline + general form)

When an outcome closes, credit flows only to the tokens that aligned during retrieval, and their Beta posteriors update Bayesian-style. Three properties shape that update. It is surprise-gated: a confirming outcome moves a token little, a surprising one moves it more (free-energy minimization). It is reality-gated by provenance: a self-graded close credits at a deliberately weak prior, and full weight requires reality, meaning the owner confirmed, the world replied, a sandboxed run exited cleanly, or a test passed. And it is bounded, so a heavily-credited token stays correctable rather than pinned at certainty. In general form the update for an aligned token scales as

$$\Delta \;\propto\; \text{surprise} \cdot \text{provenance weight}$$

The system cannot compound from its own belief. (The exact surprise function, the provenance weights, the bound, and the calibration coefficients are intentionally omitted as proprietary.)

## Prediction (transitions ledger / JEPA)

Retrieval answers *what is relevant*; it does not, on its own, say *what to do next*. acc adds a forward model over the same scored state. Every loop step is logged to a **transitions ledger** as a transition in an appraisal space — a typed read of the situation (coverage, holes, how the last action landed) paired with the action taken and the outcome. To pick the next action, acc does **k-nearest-neighbor retrieval in that appraisal space** and ranks the actions that improved things from similar past situations — energy descent over predicted outcomes. The predictor watches its own error: when realized outcomes diverge from expected ones (a cadence stops landing, a reliable client goes quiet), the surprise both moves credit (above) and flags that the model of this situation has drifted. This is the JEPA bet (LeCun 2022) — predict the next state in a representation space and learn from prediction error — applied to *work* rather than perception. The predictor is wired and running; its lift over a retrieval-only baseline is young (measured as a delta, not yet isolated by a controlled experiment). (The appraisal features, the distance metric, the neighborhood size, and the energy function are proprietary.)

## Recursion as the primitive (RLM)

acc is an instance of the Recursive Language Model idea. The model is a step inside a recursive program over an external store, not a single long-context forward pass. `acc_act(solve)` re-enters the loop on a sub-goal, and the tree of solves is the decomposition. Long context is avoided two ways: by MaxSim late interaction (the model never holds the substrate in its window) and by an in-sandbox loop where `exec` code maps the whole memory programmatically.

## Scored runtimes + sandbox

`register` ingests code as scored tokens. From there it is retrievable by MaxSim, creditable by outcome, and improvable by re-registering. There is no privileged lane: a runtime is just another scored row plus a sandboxed executor. Every run goes through an OS sandbox where available, with a read-only system, an ephemeral writable workdir, process isolation, and a hard deadline. The network is deliberately reachable so sandboxed code can call real APIs, and the substrate is available read-only for in-sandbox recall. A browser is one runtime-capability over the same substrate, not a separate stack.

## The four links + structural enforcement (the discipline made hard)

Every non-trivial call closes four links: **owner intent → retrieval (citation = credit edge) → act → outcome**. Structural enforcement hooks in the runtime make those links binding. Their content is late-interaction (substrate-derived, so it compounds), while their enforcement is hard. Retrieval fires on the owner's prompt and is bound into the working context, which is the top law here: retrieval must be behaviorally binding. An exit guard fails closed when a turn mutated the workspace but recorded no qualifying commitment. The governing principle is that advisory gates are fake, so the gates are made hard. The specific hook set and its internals are intentionally omitted.

## Trust-kernel: credit honesty + owner-authority floor

- **Credit honesty.** A self-graded close credits at a weak prior, so the substrate stops compounding from self-belief. Full weight requires reality: the owner confirmed, the world replied, or a sandboxed run or passing test settled it. A prediction is not a result.
- **Owner-authority floor.** Anything that sends, publishes, deploys, transfers, deletes important data, or uses owner credentials requires verified owner authority. That is a cryptographic check the gate cannot be tricked into skipping. The second reasoner is never owner consent. A prediction is not permission.

## Processor independence

Two different model families read and extend the scored substrate through the identical two-verb interface. Neither owns the judgment; it lives in the state. The reasoning processor is swappable, and we have swapped it. The claim is bounded. The encoder is part of the substrate's identity: one substrate, one pinned encoder, and changing it requires a full re-encode. The operating contract shapes behavior. So the reasoning processor is a free variable, while the encoder and contract are fixed.

## Worktree concurrency ("ants on one anthill")

Many terminals share what compounds: the substrate, the warm encoder daemon, and the git object store. They never share a git working tree. Every code mutation runs in its own worktree. The main checkout is the runtime home (live db, daemons, hooks, MCP) and is read/run-only. The coordinator delegates implementation to a worktree worker and reconciles by commit plus merge. Merge is the only write to main.

## What's proven vs. in-flight

| Proven (live, running) | In-flight / not yet proven |
|---|---|
| MaxSim retrieval + per-unit scored memory | Substrate-on-vs-off lift (no counterfactual harness yet) |
| Surprise-gated, bounded outcome credit | Cost-compression instrumentation (partial) |
| Two reasoners over one substrate (two verbs) | Model-swap resilience as a measured delta |
| RLM recursion (`solve` re-enters the loop) | Dependable runtime *replay* (partial) |
| Sandboxed, scored runtimes | Reality-gated / idempotent side-effecting execution |
| Structural enforcement of the four links | Scaling MaxSim memory well past a single host |
| Transitions-ledger predictor (k-NN energy descent), wired and running | Predictor lift over retrieval-only (measured delta, not isolated) |
| Owner-authority floor; weak self-graded prior | Hardening the reachable-network / send boundary |

The mechanisms in the left column are running today. The right column is honest open work. The largest claims (substrate lift, scale, replay) are not yet validated by controlled experiment. This is the live system rather than a demo, and the measured readout runs at [accint.xyz](https://accint.xyz).
