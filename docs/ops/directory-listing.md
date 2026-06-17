# Directory listing factsheet

Purpose: keep AccInt submissions factual, repeatable, and easy to review. Use
this when submitting to awesome lists, MCP directories, plugin catalogs, or
agent-memory catalogs. It is a maintainer aid, not a mandate to submit anywhere.

## Canonical facts

| Field | Value |
|---|---|
| Name | AccInt |
| Repository | `https://github.com/maxbaluev/accreted-intelligence` |
| Website | `https://accint.xyz` |
| Package form | local MCP server / CLI binary plus host plugins |
| Primary category | agent memory / Work Model / MCP server |
| Secondary categories | Claude Code plugin, Codex plugin, OpenCode plugin, Cursor integration, local-first AI tooling |
| Public repo license | Apache-2.0 for tracked public repo contents |
| Binary license | proprietary draft EULA for prebuilt `acc` engine binary |
| Source boundary | installer, docs, plugins, registry metadata, Dockerfile, and packaging scripts are public; engine source is private |
| Data posture | local substrate; no cloud memory account; anonymous event-name telemetry is opt-out and excludes prompts, files, memory, and Work Model data |

## Short descriptions

Use the shortest version that fits the target list's style.

### MCP server

AccInt is a local-first MCP Work Model for coding agents: it retrieves scored
memory, records commitments, and credits outcomes from tests, reviews, replies,
or owner approval.

### Agent memory

AccInt gives Claude Code, Codex, OpenCode, and Cursor a shared local Work Model
that learns which prior context and actions actually helped work land.

### Claude/Codex/OpenCode plugin

AccInt wires Claude Code, Codex, OpenCode, and Cursor into one local memory and
commitment ledger, so verified agent work can be reused across tools.

### Pattern / research catalog

AccInt is an implementation example of commitment-ledger learning: retrieved
context earns credit only after an externally checkable outcome settles.

## One-line entries

Prefer one of these when a catalog wants a single row.

- AccInt - local-first MCP Work Model for coding agents that retrieves scored
  memory, records commitments, and credits real outcomes.
- AccInt - shared local memory and commitment ledger for Claude Code, Codex,
  OpenCode, and Cursor, with outcome-gated learning.
- AccInt - Apache-2.0 public integration glue plus a proprietary local engine
  binary for scored agent memory and reality-gated credit.

## Tags

Recommended tags:

- `mcp`
- `mcp-server`
- `agent-memory`
- `ai-agents`
- `developer-tools`
- `claude-code`
- `codex`
- `opencode`
- `cursor`
- `local-first`
- `retrieval`
- `outcome-feedback`

## Boundary wording

Use this when a catalog cares about source availability:

> AccInt's public repository contains the Apache-2.0 installer, host plugins,
> docs, registry metadata, Dockerfile, and packaging scripts. The distributed
> `acc` engine binary is proprietary under a draft EULA, and the engine source
> is private.

Use this when a catalog has separate open-source and closed-source sections:

> If the catalog requires the core memory engine source to be public, list AccInt
> as closed-source or partial-code. If the catalog accepts open integration glue
> around a proprietary local binary, list it as an MCP/server/plugin tool with
> the boundary stated.

Avoid:

- "fully open source"
- "open-source engine"
- "public memory implementation"
- claims that the private engine source is available

## Install links

Use the GitHub repo as the primary link for catalogs. Use the website when the
catalog accepts homepages or wants a landing page.

Plain installer:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

Attributed POSIX installer for a directory/listing:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=gh-<surface> ACC_INSTALL_SOURCE='ref=gh-<surface>' sh
```

Attributed PowerShell installer:

```powershell
$env:ACC_INSTALL_REF = 'gh-<surface>'; $env:ACC_INSTALL_SOURCE = 'ref=gh-<surface>'; irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

Use lowercase ASCII labels for `<surface>`, for example:

- `gh-awesome-mcp`
- `gh-awesome-claude-skills`
- `gh-agent-memory`
- `gh-mcp-registry`

`ACC_INSTALL_REF` writes the local installer receipt ref. `ACC_INSTALL_SOURCE`
adds coarse source context (`ref=...`, UTM, or referrer category) to the same
local receipt. Neither value is sent by the installer itself; app telemetry can
later use the ref as the anonymous `distinct_id` only if telemetry is enabled.

## Reviewer caveats

- For OSS-first lists, mention the public/private split up front.
- For MCP lists, prefer "local stdio MCP server" or "local MCP server" unless
  the catalog has a stricter schema.
- For agent-memory lists, do not call it only "RAG"; the differentiator is
  outcome credit plus prediction over a local Work Model.
- For plugin lists, mention the host plugins only when the target list accepts
  integration glue or MCP-backed plugins.
- Do not add Glama score badges unless Glama has a real AccInt listing and badge
  URL. A speculative badge will fail review.

## Validation before a submission

1. `bash scripts/check-integrity.sh` passes in this repo.
2. The target list accepts the relevant artifact type: MCP server, plugin,
   agent-memory tool, or pattern.
3. The entry states the license/source boundary if the list classifies open vs
   closed source.
4. New links resolve: GitHub repo, website, and any skill/plugin path used.
5. The submission uses exactly one entry in the most specific matching section.

## Follow-up audit

After submissions are open, use the read-only PR state checker to find merges,
closures, failing checks, or maintainer action without posting anything:

```bash
scripts/check-directory-pr-state.sh path/to/report.md
```

For a Markdown table or ad hoc list, pipe only the relevant rows:

```bash
sed -n '/^| # | List |/,/^$/p' path/to/report.md | scripts/check-directory-pr-state.sh -
```

The checker prints current open/merged/closed counts, check status summaries,
and attention items. It is advisory by default; set
`ACC_DIRECTORY_PR_STRICT=1` only when a nonzero exit on attention items is
useful.

## Owner-reviewed follow-up kit

When the official registry/MCPB proof or install attribution should be included
in a maintainer reply, generate a local review packet first:

```bash
node scripts/prepare-directory-followup-kit.js --check path/to/report.md
node scripts/prepare-directory-followup-kit.js --markdown path/to/report.md
```

The kit reads local Markdown or stdin only. It does not query GitHub, post
comments, submit forms, push branches, or edit PRs. For each tracked PR it
prints:

- the stable `gh-...` attribution ref and landing URL
- the current Official MCP Registry endpoint derived from `server.json`
- MCPB package count/version context
- the Apache-2.0 public glue / proprietary local engine boundary
- a maintainer-note draft that can be reviewed before any owner-approved reply

Use the output only when a maintainer asks for clarification, a listing needs a
registry/discovery link, or the owner explicitly approves a follow-up for that
exact target. Do not reply merely to bump visibility.

## Surface attribution refs

When a report or PR table contains GitHub PR URLs, generate stable per-directory
install refs before any owner-approved follow-up:

```bash
node scripts/prepare-directory-surface-refs.js --check path/to/report.md
node scripts/prepare-directory-surface-refs.js --markdown path/to/report.md
```

The generator reads local Markdown or stdin only. It does not query GitHub,
comment, submit, push, or edit PRs. For each PR URL it emits:

- `ACC_INSTALL_REF=gh-<owner>-<repo>`
- `ACC_INSTALL_SOURCE='ref=...&utm_source=github&utm_campaign=directory_pr&entry=pr-<number>'`
- an attributed `https://accint.xyz/?...` landing URL
- POSIX and PowerShell installer snippets

Use these refs only in owner-approved maintainer replies, listing updates, or
future directory submissions where install examples are welcome. If a catalog
only allows a plain project URL, prefer the attributed landing URL over a long
installer command.
