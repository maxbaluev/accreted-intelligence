# AccInt Growth Report

READ ONLY: this report tracks promotion surfaces and owner-review material. It
does not authorize pushing, posting, commenting, submitting, paying, dispatching
workflows, using account identity, or bypassing CAPTCHA/security controls.

Last receipt refresh: 2026-06-17.

## Current launch state

- Public repo: `maxbaluev/accreted-intelligence`
- Live site: `https://accint.xyz`
- Release: `v0.1.6`
- Official MCP Registry: `io.github.maxbaluev/accint` / `0.1.6`
- Public clone state at refresh: `main` synced with `origin/main` at
  `21a635e` after the approved public growth rollout.
- Live verification: hosted GitHub Actions verifier run
  `27691022310` passed after GitHub Pages finished building.
- Controlled live install receipt: `ref=controlled-0.1.6`,
  `source_ref=ref=controlled-rollout`, captured at
  `2026-06-17T13:05:33Z` from the live `https://accint.xyz/install` path.
- Owned growth surfaces include the GitHub README (`github-readme`), public
  GitHub docs (`github-docs`), and LLM/agent discovery file (`llms-txt`) so
  README/docs/live-discovery clicks and copied installer commands can be
  attributed after push.

## Holds

- Directory PR state audit at refresh: 55 PRs checked, 42 open, 8 merged,
  5 closed/unmerged, 1 open PR with failing checks, 7 attention items.
- Glama submission was made through Google OAuth with
  `maxbaluev@outlook.com`; the direct listing and score badge now verify, but
  Glama search for `accint` still did not show AccInt at refresh.
- `punkpeye/awesome-mcp-servers#8091` now has the Glama badge row on the owned
  branch at `fe1bec64dc0dba5c2f9e20d79e7940c0034e5a91`, but the upstream PR
  remains open with GitHub merge status `UNSTABLE`. Wait for maintainer/check
  movement and do not comment merely to bump visibility.
- Hacker News still requires password-based login/registration before posting.
- Reddit r/LocalLLaMA submission was attempted under the logged-in account
  `Effective_Iron2146`, but Reddit showed a Rule 4 self-promotion warning and
  the browser stayed on the submit page with no published URL. Do not record a
  social receipt unless a public post URL exists.
- PostHog dashboard/funnel checks still require valid PostHog credentials before
  live funnel evidence can be read.
- De-dupe any further directory submission against the local queue before
  submitting or sending email; MCP.so, Insidr.ai, AISuperHub, ListedAI, Apps and
  Websites, and AI Tool Claw already have recorded submission/email outcomes.
- Do not reply to directory/listing PRs merely to bump visibility. Use generated
  notes only when a maintainer asks for clarification, a listing needs registry
  proof, or the owner approves a specific reply.

## External rollout receipts

| Date | Surface | Action | Receipt | State |
|---|---|---|---|---|
| 2026-06-17 | Public repo | `ACC_APPROVE_GROWTH_ROLLOUT=1 scripts/run-approved-growth-rollout.sh v0.1.6` | `21a635e` pushed to `origin/main` | GitHub Pages built after push. |
| 2026-06-17 | Hosted live verifier | `live-site-attribution.yml` | `https://github.com/maxbaluev/accreted-intelligence/actions/runs/27691022310` | Passed live attribution and LLM discovery checks. |
| 2026-06-17 | Controlled live install | `ACC_APPROVE_CONTROLLED_LIVE_INSTALL=1 scripts/run-approved-controlled-live-install.sh v0.1.6` | `ref=controlled-0.1.6`; `source_ref=ref=controlled-rollout`; `captured_at_utc=2026-06-17T13:05:33Z` | Passed against the live installer stop path. |
| 2026-06-17 | Glama MCP Registry | `https://glama.ai/mcp/servers/maxbaluev/accreted-intelligence` | Submitted for review via Google OAuth as `maxbaluev@outlook.com` | Direct listing and score badge verify; search still missed AccInt at refresh. |
| 2026-06-17 | punkpeye PR badge follow-up | `https://github.com/punkpeye/awesome-mcp-servers/pull/8091` | Owned branch pushed at `fe1bec64dc0dba5c2f9e20d79e7940c0034e5a91` | Glama badge row added; no PR comment posted; PR remains open. |
| 2026-06-17 | Reddit LocalLLaMA | `https://www.reddit.com/r/LocalLLaMA/submit/` | No published URL | Attempted, but not confirmed published after Rule 4 warning; no social receipt row. |

## Tracked directory/listing PRs

Rows are extracted from read-only GitHub search for AccInt / Accreted
Intelligence mentions. Status can drift; verify with:

```bash
scripts/check-directory-pr-state.sh docs/ops/growth-report.md
node scripts/prepare-directory-priority-report.js --check docs/ops/growth-report.md
node scripts/prepare-directory-surface-refs.js --check docs/ops/growth-report.md
node scripts/prepare-directory-followup-kit.js --check --actionable docs/ops/growth-report.md
node scripts/prepare-glama-submission-packet.js --check v0.1.6
```

| # | List | Area | State at refresh | PR | Last update | Note |
|---|---|---|---|---|---|---|
| 1 | punkpeye/awesome-mcp-servers | MCP directory | open | https://github.com/punkpeye/awesome-mcp-servers/pull/8091 | 2026-06-17T13:36:11Z | Glama badge row pushed to owned branch; wait for checks/maintainer. |
| 2 | appcypher/wong2/TensorBlock alternatives via TensorBlock/awesome-mcp-servers | MCP directory | merged | https://github.com/TensorBlock/awesome-mcp-servers/pull/721 | 2026-06-15T21:49:38Z | Listing win; monitor only. |
| 3 | mcpHQ/awesome-mcp-servers | MCP directory | merged | https://github.com/mcpHQ/awesome-mcp-servers/pull/2 | 2026-06-15T19:43:45Z | Listing win; monitor only. |
| 4 | DhanushNehru/awesome-mcp-servers | MCP directory | merged | https://github.com/DhanushNehru/awesome-mcp-servers/pull/33 | 2026-06-15T11:18:19Z | Listing win; monitor only. |
| 5 | wundercorp/awesome-mcp | MCP directory | merged | https://github.com/wundercorp/awesome-mcp/pull/7 | 2026-06-16T18:23:52Z | Listing win; monitor only. |
| 6 | TsinghuaC3I/Awesome-Memory-for-Agents | Agent memory | merged | https://github.com/TsinghuaC3I/Awesome-Memory-for-Agents/pull/21 | 2026-06-16T02:48:45Z | Listing win; monitor only. |
| 7 | aristoapp/awesome-second-brain | Memory/watchlist | merged | https://github.com/aristoapp/awesome-second-brain/pull/23 | 2026-06-16T12:30:56Z | Listing win; monitor only. |
| 8 | sickn33/antigravity-awesome-skills | Skills directory | merged | https://github.com/sickn33/antigravity-awesome-skills/pull/687 | 2026-06-15T17:29:39Z | Skill listing win; monitor only. |
| 9 | Chat2AnyLLM/awesome-repo-configs | Skill repo config | merged | https://github.com/Chat2AnyLLM/awesome-repo-configs/pull/63 | 2026-06-15T14:16:02Z | Listing win; monitor only. |
| 10 | AI-in-Transportation-Lab/awesome-mcp | MCP directory | open | https://github.com/AI-in-Transportation-Lab/awesome-mcp/pull/22 | 2026-06-15T09:50:41Z | Follow only if asked. |
| 11 | AIAnytime/Awesome-MCP-Server | MCP directory | open | https://github.com/AIAnytime/Awesome-MCP-Server/pull/43 | 2026-06-15T09:31:26Z | Follow only if asked. |
| 12 | AlexMili/Awesome-MCP | MCP directory | open | https://github.com/AlexMili/Awesome-MCP/pull/134 | 2026-06-15T09:12:55Z | Follow only if asked. |
| 13 | MobinX/awesome-mcp-list | MCP directory | open | https://github.com/MobinX/awesome-mcp-list/pull/315 | 2026-06-15T06:47:17Z | Follow only if asked. |
| 14 | YuzeHao2023/Awesome-MCP-Servers | MCP directory | open | https://github.com/YuzeHao2023/Awesome-MCP-Servers/pull/318 | 2026-06-15T12:04:28Z | Follow only if asked. |
| 15 | mctrinh/awesome-mcp-servers | MCP directory | open | https://github.com/mctrinh/awesome-mcp-servers/pull/68 | 2026-06-15T09:37:13Z | Follow only if asked. |
| 16 | habitoai/awesome-mcp-servers | MCP directory | open | https://github.com/habitoai/awesome-mcp-servers/pull/93 | 2026-06-15T09:46:57Z | Follow only if asked. |
| 17 | lobstercare/mcp-hub | MCP hub | open | https://github.com/lobstercare/mcp-hub/pull/47 | 2026-06-15T11:59:03Z | Follow only if asked. |
| 18 | ravitemer/mcp-registry | MCP registry | open | https://github.com/ravitemer/mcp-registry/pull/31 | 2026-06-15T12:50:37Z | Official registry proof may help if maintainer asks. |
| 19 | Prat011/awesome-llm-skills | Skills directory | open | https://github.com/Prat011/awesome-llm-skills/pull/150 | 2026-06-15T10:27:23Z | Follow only if asked. |
| 20 | BehiSecc/awesome-claude-skills | Claude skills | open | https://github.com/BehiSecc/awesome-claude-skills/pull/369 | 2026-06-15T12:33:30Z | Follow only if asked. |
| 21 | ComposioHQ/awesome-claude-skills | Claude skills | open | https://github.com/ComposioHQ/awesome-claude-skills/pull/1082 | 2026-06-15T14:02:42Z | Review required / merge blocked; follow only with owner-approved clarification. |
| 22 | ComposioHQ/awesome-claude-plugins | Claude plugins | open | https://github.com/ComposioHQ/awesome-claude-plugins/pull/301 | 2026-06-15T13:48:51Z | Follow only if asked. |
| 23 | GetBindu/awesome-claude-code-and-skills | Claude Code | open | https://github.com/GetBindu/awesome-claude-code-and-skills/pull/68 | 2026-06-15T12:19:46Z | Follow only if asked. |
| 24 | rohitg00/awesome-claude-code-toolkit | Claude Code | open | https://github.com/rohitg00/awesome-claude-code-toolkit/pull/544 | 2026-06-15T07:15:16Z | Follow only if asked. |
| 25 | ccplugins/awesome-claude-code-plugins | Claude Code plugins | open | https://github.com/ccplugins/awesome-claude-code-plugins/pull/270 | 2026-06-15T07:17:41Z | Follow only if asked. |
| 26 | jqueryscript/awesome-claude-code | Claude Code | open | https://github.com/jqueryscript/awesome-claude-code/pull/399 | 2026-06-15T07:20:58Z | Follow only if asked. |
| 27 | awesome-opencode/awesome-opencode | OpenCode | open | https://github.com/awesome-opencode/awesome-opencode/pull/439 | 2026-06-15T07:41:48Z | Follow only if asked. |
| 28 | darknorth-123/Awesome-Codex-Plugins | Codex plugins | open | https://github.com/darknorth-123/Awesome-Codex-Plugins/pull/3 | 2026-06-15T11:22:27Z | Follow only if asked. |
| 29 | milisp/awesome-codex-cli | Codex CLI | open | https://github.com/milisp/awesome-codex-cli/pull/47 | 2026-06-15T12:14:37Z | Follow only if asked. |
| 30 | Switchy-AI/awesome-ai-memory | Agent memory | open | https://github.com/Switchy-AI/awesome-ai-memory/pull/1 | 2026-06-15T09:55:54Z | Follow only if asked. |
| 31 | cxxz/awesome-agent-memory | Agent memory | open | https://github.com/cxxz/awesome-agent-memory/pull/9 | 2026-06-15T10:01:17Z | Follow only if asked. |
| 32 | IAAR-Shanghai/Awesome-AI-Memory | Agent memory | open | https://github.com/IAAR-Shanghai/Awesome-AI-Memory/pull/74 | 2026-06-15T08:24:01Z | Follow only if asked. |
| 33 | XiaomingX/awesome-ai-memory | Agent memory | open | https://github.com/XiaomingX/awesome-ai-memory/pull/9 | 2026-06-15T09:07:03Z | Follow only if asked. |
| 34 | topoteretes/awesome-ai-memory | Agent memory | open | https://github.com/topoteretes/awesome-ai-memory/pull/41 | 2026-06-15T09:02:24Z | Follow only if asked. |
| 35 | Meirtz/Awesome-Context-Engineering | Context engineering | open | https://github.com/Meirtz/Awesome-Context-Engineering/pull/75 | 2026-06-15T07:01:05Z | Follow only if asked. |
| 36 | yzfly/awesome-context-engineering | Context engineering | open | https://github.com/yzfly/awesome-context-engineering/pull/10 | 2026-06-17T04:10:28Z | Recently updated; check before any reply. |
| 37 | ai-boost/awesome-harness-engineering | Harness engineering | open | https://github.com/ai-boost/awesome-harness-engineering/pull/67 | 2026-06-15T08:40:51Z | Follow only if asked. |
| 38 | nibzard/awesome-agentic-patterns | Agentic patterns | open | https://github.com/nibzard/awesome-agentic-patterns/pull/102 | 2026-06-15T10:44:08Z | Failing checks; inspect before any owner-approved fix or reply. |
| 39 | rafska/awesome-local-llm | Local LLM | open | https://github.com/rafska/awesome-local-llm/pull/106 | 2026-06-15T10:34:25Z | Follow only if asked. |
| 40 | tensorchord/Awesome-LLMOps | LLMOps | open | https://github.com/tensorchord/Awesome-LLMOps/pull/577 | 2026-06-15T06:13:09Z | Follow only if asked. |
| 41 | Danielskry/Awesome-RAG | RAG | open | https://github.com/Danielskry/Awesome-RAG/pull/104 | 2026-06-15T08:23:47Z | RAG framing is weaker; avoid over-follow-up. |
| 42 | ai-for-developers/awesome-ai-coding-tools | AI coding tools | open | https://github.com/ai-for-developers/awesome-ai-coding-tools/pull/420 | 2026-06-15T06:11:05Z | Follow only if asked. |
| 43 | jim-schwoebel/awesome_ai_agents | AI agents | open | https://github.com/jim-schwoebel/awesome_ai_agents/pull/341 | 2026-06-15T10:18:12Z | Follow only if asked. |
| 44 | caramaschiHG/awesome-ai-agents-2026 | AI agents | open | https://github.com/caramaschiHG/awesome-ai-agents-2026/pull/340 | 2026-06-15T08:02:53Z | Follow only if asked. |
| 45 | ARUNAGIRINATHAN-K/awesome-ai-agents-2026 | AI agents | open | https://github.com/ARUNAGIRINATHAN-K/awesome-ai-agents-2026/pull/94 | 2026-06-15T11:36:32Z | Follow only if asked. |
| 46 | dmgrok/agent_skills_directory | Agent skills | open | https://github.com/dmgrok/agent_skills_directory/pull/88 | 2026-06-15T14:53:56Z | Follow only if asked. |
| 47 | intellectronica/awesome-skills | Skills directory | open | https://github.com/intellectronica/awesome-skills/pull/34 | 2026-06-15T13:31:46Z | Follow only if asked. |
| 48 | ranbot-ai/awesome-skills | Skills directory | open | https://github.com/ranbot-ai/awesome-skills/pull/6 | 2026-06-15T14:43:16Z | Follow only if asked. |
| 49 | memohai/supermarket | Plugin supermarket | open | https://github.com/memohai/supermarket/pull/12 | 2026-06-15T13:13:58Z | Follow only if asked. |
| 50 | TeleAI-UAGI/Awesome-Agent-Memory | Agent memory | closed | https://github.com/TeleAI-UAGI/Awesome-Agent-Memory/pull/42 | 2026-06-15T19:12:35Z | Closed due source-boundary fit; do not retry without policy change. |
| 51 | Jenqyang/Awesome-AI-Agents | AI agents | closed | https://github.com/Jenqyang/Awesome-AI-Agents/pull/307 | 2026-06-15T08:37:23Z | Closed; do not retry without policy change. |
| 52 | jamesmurdza/awesome-ai-devtools | AI devtools | closed | https://github.com/jamesmurdza/awesome-ai-devtools/pull/666 | 2026-06-15T06:14:14Z | Superseded by #667. |
| 53 | jamesmurdza/awesome-ai-devtools | AI devtools | open | https://github.com/jamesmurdza/awesome-ai-devtools/pull/667 | 2026-06-15T06:14:34Z | Follow only if asked. |
| 54 | Chat2AnyLLM/awesome-claude-skills | Claude skills | closed | https://github.com/Chat2AnyLLM/awesome-claude-skills/pull/38 | 2026-06-15T14:16:52Z | Superseded by repo-config merge. |
| 55 | yzfly/Awesome-MCP-ZH | MCP directory | closed | https://github.com/yzfly/Awesome-MCP-ZH/pull/291 | 2026-06-15T15:04:37Z | Closed; do not retry without policy change. |

## Next owner-review packets

Generate these locally before any follow-up:

```bash
node scripts/prepare-growth-owner-handoff.js --markdown v0.1.6
node scripts/prepare-growth-decision-queue.js --markdown v0.1.6
node scripts/prepare-growth-approval-brief.js --markdown v0.1.6
scripts/check-directory-pr-state.sh docs/ops/growth-report.md
node scripts/prepare-directory-priority-report.js --markdown docs/ops/growth-report.md
node scripts/prepare-directory-surface-refs.js --markdown docs/ops/growth-report.md
node scripts/prepare-directory-followup-kit.js --markdown --actionable docs/ops/growth-report.md
node scripts/prepare-glama-submission-packet.js --form-packet v0.1.6
```

Start with the owner handoff for the current approval ask, then use the
decision queue and approval brief when more detail is needed. The priority
report ranks open directory/listing PRs by live PR state, repository reach,
checks, and known blockers so owner-approved follow-up goes to the
highest-upside surfaces first. The generated notes are not posting
authorization. They are review packets for exact owner-approved maintainer
replies or listing updates. Use the Glama form packet before the
punkpeye badge follow-up because that PR is blocked on Glama's listing and
score badge.

## Social launch receipts

Append rows here only after an owner-approved public post exists. Generate the
row locally from the checked launch packet so the surface ref, published URL,
attributed landing URL, and follow-up boundary stay together:

```bash
node scripts/prepare-social-launch-packet.js --receipt-packet hn-show <published-url>
```

| Date | Surface ref | Published URL | Attributed landing URL | Follow-up boundary |
|---|---|---|---|---|
