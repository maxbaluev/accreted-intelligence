# Social launch kit

Purpose: give the owner ready-to-review launch copy for the highest-leverage
human channels without losing install attribution. This file does not authorize
posting. Do not post, submit, comment, DM, pay, or use an account identity from
this checklist unless the owner explicitly approves that exact external action.

Use this after the public growth bundle is pushed and the live site deploy
passes the attribution checks in
[`growth-rollout-checklist.md`](growth-rollout-checklist.md).

## Preflight

Before any post goes live:

```bash
bash scripts/check-growth-readiness.sh
scripts/check-growth-live-state.sh v<tag>
scripts/check-live-attribution-flow.sh https://accint.xyz
node scripts/check-growth-surfaces.js --check
node scripts/check-social-launch-kit.js --check
node scripts/prepare-social-launch-packet.js --check
```

Post only after these are true:

- `scripts/check-growth-readiness.sh` passes in the public clone.
- `scripts/check-live-attribution-flow.sh https://accint.xyz` passes against
  the deployed site.
- GitHub detects the public repo license as Apache-2.0.
- The live site serves `ACC_INSTALL_REF` and `ACC_INSTALL_SOURCE` prompt-copy
  attribution.
- The release/install path fetches a binary that contains the private
  install-attribution telemetry bridge.
- The copy below still states the source boundary: public Apache-2.0 glue,
  proprietary local engine binary, private engine source.

Do not claim:

- fully open source
- open-source engine
- public memory implementation
- cloud memory account

## Attribution refs

Use stable lowercase refs so installs can be grouped without storing post text,
prompts, files, memory, or Work Model data.

The canonical checked manifest is
[`docs/ops/growth-surfaces.json`](growth-surfaces.json). Keep launch links and
installer snippets in sync with it.

| Surface | Ref | Source |
|---|---|---|
| Show HN | `hn-show` | `ref=hn-show&utm_source=hacker_news&utm_campaign=launch` |
| X launch thread | `x-launch-thread` | `ref=x-launch-thread&utm_source=x&utm_campaign=launch` |
| Reddit LocalLLaMA | `reddit-localllama` | `ref=reddit-localllama&utm_source=reddit&utm_campaign=launch&rsub=localllama` |
| Reddit ClaudeAI | `reddit-claudeai` | `ref=reddit-claudeai&utm_source=reddit&utm_campaign=launch&rsub=claudeai` |
| Reddit ChatGPTCoding | `reddit-chatgptcoding` | `ref=reddit-chatgptcoding&utm_source=reddit&utm_campaign=launch&rsub=chatgptcoding` |

Attributed landing URLs:

| Surface | URL |
|---|---|
| Show HN | `https://accint.xyz/?ref=hn-show&utm_source=hacker_news&utm_campaign=launch` |
| X launch thread | `https://accint.xyz/?ref=x-launch-thread&utm_source=x&utm_campaign=launch` |
| Reddit LocalLLaMA | `https://accint.xyz/reddit/?ref=reddit-localllama&utm_source=reddit&utm_campaign=launch&rsub=localllama` |
| Reddit ClaudeAI | `https://accint.xyz/reddit/?ref=reddit-claudeai&utm_source=reddit&utm_campaign=launch&rsub=claudeai` |
| Reddit ChatGPTCoding | `https://accint.xyz/reddit/?ref=reddit-chatgptcoding&utm_source=reddit&utm_campaign=launch&rsub=chatgptcoding` |

Plain install link:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

Attributed POSIX snippets:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=hn-show ACC_INSTALL_SOURCE='ref=hn-show&utm_source=hacker_news&utm_campaign=launch' sh
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=x-launch-thread ACC_INSTALL_SOURCE='ref=x-launch-thread&utm_source=x&utm_campaign=launch' sh
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=reddit-localllama ACC_INSTALL_SOURCE='ref=reddit-localllama&utm_source=reddit&utm_campaign=launch&rsub=localllama' sh
```

Attributed PowerShell example:

```powershell
$env:ACC_INSTALL_REF='hn-show'; $env:ACC_INSTALL_SOURCE='ref=hn-show&utm_source=hacker_news&utm_campaign=launch'; irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

If a channel dislikes long install commands, link to that surface's attributed
landing URL instead and let the deployed copy buttons carry the attribution
into prompt copies. The post body can still use the plain install command when
clarity matters more than source precision.

## Owner-reviewed launch packet

Before any owner-approved post, generate the local review packet:

```bash
node scripts/prepare-social-launch-packet.js --check
node scripts/prepare-social-launch-packet.js --markdown
```

The packet reads only this Markdown file and
[`docs/ops/growth-surfaces.json`](growth-surfaces.json). It does not open
posting URLs, post, submit, comment, DM, pay, or use account identity. It
prints per-surface copy, attributed landing URLs, install snippets, and channel
fit checks so the owner can approve an exact target without reassembling the
launch by hand.

## Show HN

Title:

```text
Show HN: AccInt - local-first memory so coding agents learn what worked
```

Body:

```text
Most AI forgets the moment it answers. You keep paying - time and tokens - to rediscover what already worked last week. AccInt is a bet that this is temporary: move learning out of model weights into scored external state that compounds from contact with reality.

It slots under the agents you already run (Claude Code, Codex, OpenCode, Cursor) as an MCP server plus host plugins. Two verbs over one memory: retrieve (MaxSim over a late-interaction, ColBERT/ColPali-style scored-token memory) and act (recurse / run / register). Every run records a commitment, predicts the path most likely to work from what worked before, acts with a receipt, holds anything that leaves your machine for your OK, and lets reality settle it - a passing test, a real reply. Credit defaults to a weak prior; only reality earns full weight. The Work Model stays on your machine: swap the model, keep the judgment.

The public Apache-2.0 glue (installer and plugins) lets you read the integration code that runs on your machine; the local engine binary is proprietary and the engine source is private. One-line install, no account, no API key - the installer probes your hardware and tells you honestly which embedder tier it can run.

It is young and I will say what is proven vs unproven. Repo and one-liner:
https://github.com/maxbaluev/accreted-intelligence
Live ledger: https://accint.xyz/?ref=hn-show&utm_source=hacker_news&utm_campaign=launch

Happy to go deep on the MaxSim credit assignment (which retrieved tokens actually earned their keep) and the reality-gated scoring in the comments.
```

Optional install line for a first comment:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=hn-show ACC_INSTALL_SOURCE='ref=hn-show&utm_source=hacker_news&utm_campaign=launch' sh
```

## X / Twitter thread

1. Most AI forgets the moment it answers. You re-pay - time + tokens - to rediscover what already worked. AccInt is a local-first Work Model that slots under Claude Code / Codex / OpenCode / Cursor and learns what held up.

2. It is two verbs over one memory. `retrieve` = MaxSim over a late-interaction scored-token memory (ColBERT/ColPali-style). `act` = recurse / run / register. Decomposition emerges from recursion, not a hardcoded agent graph.

3. The part that matters: credit. Every run is graded by reality - a passing test, a real reply, owner approval - not the model's own word. Credit defaults to a weak prior; only reality earns full weight. Retrieved tokens that actually aligned get the credit.

4. It predicts the better path before the next run starts, then replays verified steps instead of re-reasoning. Same kind of job gets cheaper and lands better every run.

5. Local-first. You own it. Open install glue + plugins (Apache-2.0) so you can audit the integration code; the local engine binary is proprietary. No account, no API key.

6. It is young. The live commitments ledger settles in real time at https://accint.xyz/?ref=x-launch-thread&utm_source=x&utm_campaign=launch - proven vs young, stated honestly. Repo: https://github.com/maxbaluev/accreted-intelligence

Attributed install reply if useful:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=x-launch-thread ACC_INSTALL_SOURCE='ref=x-launch-thread&utm_source=x&utm_campaign=launch' sh
```

## Reddit

### r/LocalLLaMA

Title:

```text
AccInt: a local-first Work Model that makes your coding agent learn what worked (MaxSim / late-interaction memory, no cloud)
```

Body:

```text
Most coding-agent memory is recall: keep context, retrieve context, hope it helps. AccInt is trying a different layer: a local Work Model that stores commitments, actions, approvals, outcomes, failures, and reusable paths, then scores what actually held up.

It runs under Claude Code, Codex, OpenCode, and Cursor as a local MCP server plus host wiring. The memory stays on your machine. The API is intentionally small: retrieve scored memory; act with a commitment and a receipt. Anything that leaves your machine is supposed to stop at your approval gate.

The technical bet is late-interaction retrieval plus reality-gated credit. Retrieval uses MaxSim over scored tokens, inspired by ColBERT/ColPali-style retrieval. A memory, script, or runtime only earns strong credit when reality answers: a passing test, a real reply, or owner approval. Self-graded results are weak evidence, not truth.

Boundary: the public repo is Apache-2.0 installer/docs/plugins/registry glue; the local engine binary is proprietary and the engine source is private. There is no cloud memory account. Anonymous event-name telemetry is opt-out and excludes prompts, files, memory, and Work Model data.

Repo: https://github.com/maxbaluev/accreted-intelligence
Live ledger/readout: https://accint.xyz/reddit/?ref=reddit-localllama&utm_source=reddit&utm_campaign=launch&rsub=localllama
Install:
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=reddit-localllama ACC_INSTALL_SOURCE='ref=reddit-localllama&utm_source=reddit&utm_campaign=launch&rsub=localllama' sh

I would especially value critique of the scoring approach: what should count as reality, and how should a local agent memory avoid rewarding accidental success?
```

### r/ClaudeAI

Use this only in a relevant thread or with owner approval for a standalone post:

```text
I built AccInt as a local Work Model under Claude Code (and Codex/OpenCode/Cursor): it records commitments, retrieves scored memory, and only gives strong credit to what survived reality - tests, owner approval, or real replies. It is local-first: public Apache-2.0 install/plugin glue, proprietary local engine binary, private engine source, no cloud memory account.

Repo: https://github.com/maxbaluev/accreted-intelligence
Live readout: https://accint.xyz/reddit/?ref=reddit-claudeai&utm_source=reddit&utm_campaign=launch&rsub=claudeai
```

Attributed install snippet for a comment if requested:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=reddit-claudeai ACC_INSTALL_SOURCE='ref=reddit-claudeai&utm_source=reddit&utm_campaign=launch&rsub=claudeai' sh
```

### r/ChatGPTCoding

Use this only in a relevant thread or with owner approval for a standalone post:

```text
AccInt is a local Work Model for coding agents, including Codex. It gives agents a shared local commitment ledger: retrieve prior scored memory, act with a receipt, and credit the result only after tests, owner approval, or real-world feedback. The point is to keep what worked across model/tool swaps.

Repo: https://github.com/maxbaluev/accreted-intelligence
Live readout: https://accint.xyz/reddit/?ref=reddit-chatgptcoding&utm_source=reddit&utm_campaign=launch&rsub=chatgptcoding
```

Attributed install snippet for a comment if requested:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=reddit-chatgptcoding ACC_INSTALL_SOURCE='ref=reddit-chatgptcoding&utm_source=reddit&utm_campaign=launch&rsub=chatgptcoding' sh
```

## After posting

After an owner-approved post goes live, record the URL and surface ref in the
growth report, then monitor without spamming:

```bash
scripts/check-directory-pr-state.sh path/to/report.md
scripts/check-growth-live-state.sh v<tag>
```

Do not reply just to bump visibility. Reply only when there is a concrete
question, a correction, or useful technical detail.
