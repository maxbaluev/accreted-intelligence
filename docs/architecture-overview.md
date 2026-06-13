# Accreted Intelligence (AccInt) — Architecture Overview

*A skimmable map of the system. The thesis lives in [whitepaper.md](whitepaper.md); this is the engineering surface, IP-protected.*

## What acc is

**acc** is a Recursive Language Model (RLM) over a late-interaction scored-token memory, implemented as a single Rust crate. A reasoner interacts with one persistent substrate through exactly **two verbs** — retrieve and act — and the substrate *learns from real outcomes* by moving the score of the individual units of memory that actually aligned with the work. Intelligence lives in the scored state, not in the model; the model is a replaceable processor. acc is a working single-host research kernel, honest about what is proven by reality versus self-graded versus aspirational.

## The two verbs

The entire reasoner interface. There is no third verb; vision is native to `retrieve`.

- **`acc_retrieve(query | image)`** — the *only* read. Peek the memory by MaxSim. Pass text or a typed image; both encode to late-interaction tokens, so a text memo can answer an image (ColPali-style cross-modal retrieval).
- **`acc_act(runtime, input)`** — *do* anything. Built-in runtimes:
  - `solve` — RECURSE: re-enter the loop on a sub-goal. Decomposition emerges from the recursion tree; there is no `decompose` op.
  - `exec` — run sandboxed code; inside it, the code can recurse over the memory.
  - `register` — store reusable named code (it becomes scored tokens, no privileged lane).
  - `outcome` — close a commitment with a real-world verdict; credit flows to the cited memory.
  - `<name>` — run any registered runtime, with `input` bound to a standard input variable.

Writing to memory and crediting are *not* verbs — the loop does them automatically on every call.

## Late-interaction scored-token memory (commodity layer + acc's form)

Each entity (knowledge, runtime, owner fact, goal, image) is stored as an ordered set of per-token vectors — no single-vector dense form, the token is the atom. Retrieval ranks by **MaxSim**:

$$\text{score}(q, d) = \sum_i \max_j \text{sim}(q_i, d_j)$$

For each query token, take its best-matching doc token and sum. The aligned (query→doc) pairs *are* the citation. This is published commodity (ColBERT for text, ColPali for vision).

acc extends this: each document token carries a Bayesian **Beta(α, β) posterior** (Thompson 1933) — mean $\pi_j = \alpha_j/(\alpha_j+\beta_j)$ (how often its alignments led to good outcomes) and a confidence that grows with the evidence count $\alpha_j+\beta_j$. That posterior reweights the token's contribution:

$$\text{score}(q, d) = \sum_i \max_j \big[\, \text{sim}(q_i, d_j) \cdot g(\pi_j) \,\big]$$

where $g$ is a monotonic confidence weighting — a token reality has repeatedly confirmed pulls harder than a fresh one. *(The exact form of `g` and its calibration are proprietary.)*

## Reality-gated credit (the discipline + general form)

When an outcome closes, credit flows only to the tokens that aligned during retrieval; their Beta posteriors update Bayesian-style. The update is **surprise-gated** (a confirming outcome moves a token little, a surprising one moves it more — free-energy minimization), **reality-gated** by provenance (a self-graded close credits at a deliberately weak prior; full weight requires reality — the owner confirmed, the world replied, a sandboxed run exited cleanly, or a test passed), and **bounded** so a heavily-credited token stays correctable rather than pinned at certainty. In general form the update for an aligned token scales as

$$\Delta \;\propto\; \text{surprise} \cdot \text{provenance weight}$$

The system cannot compound from its own belief. *(The exact surprise function, the provenance weights, the bound, and the calibration coefficients are intentionally omitted — proprietary.)*

## Recursion as the primitive (RLM)

acc is an instance of the Recursive Language Model idea: the model is a step inside a recursive program over an external store, not a single long-context forward pass. `acc_act(solve)` re-enters the loop on a sub-goal; the tree of solves *is* the decomposition. Long context is avoided by MaxSim late interaction (the model never holds the substrate in its window) and by an in-sandbox loop where `exec` code maps the whole memory programmatically.

## Prediction — the transitions ledger (the world-model layer, JEPA-shaped)

Retrieval is perception; the substrate also **predicts**. Every settled act appends one **transition** — `(state, action, state′)` where state is the typed appraisal of the work — to a bounded ledger. A **nonparametric k-NN** over those transitions predicts which action most reduces the remaining typed residue (**predicted-energy descent**), entering action selection as a scored term, never as authority (a candidate whose only predicted gain is in the owner-authority dimension never auto-fires). Three properties make it a Joint-Embedding Predictive Architecture in the practical sense (LeCun 2022):

- **Latent world-state sketch.** Each transition carries an FDE sketch of the pre-act context, so the k-NN matches in a *learned joint-embedding space* (grid distance first, world-sketch distance as the tie-break), not on surface features. The encoder is frozen — prediction-over-representations without online training; collapse is precluded by bounded Beta evidence, not an EMA teacher.
- **Self vs. world.** Transitions are tagged controlled (`Self_`, our settled acts) vs exogenous (`World`, a `world:*` ingest). The self-prediction k-NN conditions on `Self_`, so exogenous change never contaminates action-outcome prediction; drift is attributed — *we changed* vs *the world changed* — by counting exogenous arrivals against per-region Brier.
- **Hierarchy, one memory.** Prediction runs at three timescales over the same substrate: token-level MaxSim (perception), act-level transition k-NN (above), and goal/region-level (region-localized routing posteriors + per-region Brier, learned from commitment outcomes). No second model, no separate planner.

The predictor stays nonparametric on purpose: a learned forward head is **gated** behind a measured trigger (k-NN abstention or Brier stagnation), not built speculatively. *(The exact energy weighting, sketch projection, drift thresholds, and calibration constants are proprietary.)*

## Scored runtimes + sandbox

`register` ingests code as scored tokens — retrievable by MaxSim, creditable by outcome, improvable by re-registering. **No privileged lane**: a runtime is just another scored row plus a sandboxed executor. Every run goes through an OS sandbox where available (read-only system, ephemeral writable workdir, process isolation, a hard deadline). The network is deliberately reachable so sandboxed code can call real APIs; the substrate is available read-only for in-sandbox recall. A browser is *one runtime-capability* over the same substrate, not a separate stack.

## The four links + structural enforcement (the discipline made hard)

Every non-trivial call closes four links: **owner intent → retrieval (citation = credit edge) → act → outcome**. The links are made *binding* by structural enforcement hooks in the runtime — their content is late-interaction (substrate-derived, it compounds); their enforcement is hard. Retrieval fires on the owner's prompt and is bound into the working context (the top law: *retrieval must be behaviorally binding*), and an exit guard fails closed when a turn mutated the workspace but recorded no qualifying commitment. The governing principle: *advisory gates are fake — make them hard.* The specific hook set and its internals are intentionally omitted.

## Trust-kernel: credit honesty + owner-authority floor

- **Credit honesty.** A self-graded close credits at a weak prior, so the substrate stops compounding from self-belief. Full weight requires reality (owner confirmed, world replied, a sandboxed run or passing test). Prediction is not a result.
- **Owner-authority floor.** Anything that sends, publishes, deploys, transfers, deletes important data, or uses owner credentials requires verified owner authority — a cryptographic check the gate cannot be tricked into skipping. The second reasoner is never owner consent. Prediction is not permission.

## Processor independence

The scored substrate is read and extended by two different model families through the identical two-verb interface; neither owns the judgment — it lives in the state. The reasoning processor is swappable, and demonstrably swapped. The claim is bounded: the *encoder* is part of the substrate's identity (one substrate, one pinned encoder; changing it requires a full re-encode), and the operating contract shapes behavior. The *reasoning* processor is a free variable; the encoder and contract are not.

## Worktree concurrency ("ants on one anthill")

Many terminals share what compounds — the substrate, the warm encoder daemon, the git object store — but **never a git working tree**. Every code mutation runs in its **own worktree**; the main checkout is the runtime home (live db, daemons, hooks, MCP) and is read/run-only. The coordinator delegates implementation to a worktree worker and reconciles by **commit + merge** — merge is the only write to main.

## What's proven vs. in-flight

| Proven (live, running) | In-flight / not yet proven |
|---|---|
| MaxSim retrieval + per-unit scored memory | Substrate-on-vs-off lift (no counterfactual harness yet) |
| Surprise-gated, bounded outcome credit | Cost-compression instrumentation (partial) |
| Two reasoners over one substrate (two verbs) | Model-swap resilience as a measured delta |
| RLM recursion (`solve` re-enters the loop) | Dependable runtime *replay* (partial) |
| Sandboxed, scored runtimes | Reality-gated / idempotent side-effecting execution |
| Structural enforcement of the four links | Scaling MaxSim memory well past a single host |
| Owner-authority floor; weak self-graded prior | Hardening the reachable-network / send boundary |
| Transition ledger + k-NN energy-descent predictor | Predicted-energy lift over a no-predictor baseline (mechanism-level only) |
| Latent world-state sketches (JEPA-shaped); self/world drift split | Learned forward head (gated on k-NN abstention / Brier stagnation) |

The mechanisms in the left column are running today. The right column is honest open work — the largest claims (substrate lift, scale, replay, and whether the predictor measurably beats a no-predictor baseline) are *not* yet validated by controlled experiment.

---

Questions, issues, and discussion: the project channel at
[github.com/maxbaluev/accreted-intelligence/issues](https://github.com/maxbaluev/accreted-intelligence/issues).
