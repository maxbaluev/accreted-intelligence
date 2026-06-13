---
name: Harness / coding-agent integration
about: Request or contribute support for a new coding-agent harness
title: "[harness] "
labels: ["integration"]
assignees: []
---

acc wires into a coding agent through ONE host-agnostic lifecycle protocol: eight fixed
events (`session-start · turn-start · post-tool · turn-end · subagent-start ·
subagent-end · compact · session-end`), each a plain subprocess call into the same binary
(`acc hook <event> --host generic`), plus the two-verb MCP server (`acc_retrieve` /
`acc_act`). Adding a harness is mostly translating that harness's native signals into the
generic envelope. See [`plugins/README.md`](../../plugins/README.md) for the contract and
the per-host coverage table.

## Which harness?

Name the coding agent / harness and link to its docs (especially its hook / lifecycle and
MCP configuration docs).

## Are you requesting it, or contributing it?

- [ ] **Requesting** — I'd like this harness supported; I can help test.
- [ ] **Contributing** — I have (or want to write) the adapter and will open a PR under `plugins/`.

## What the harness offers

Help us map it onto the eight-event protocol:

- **MCP support?** Does it let you register an MCP server, and in what config file/dialect?
- **Lifecycle hooks?** Which of the eight events does it expose natively? Which are missing?
- **Blocking primitive?** Can a hook block the turn (exit-code semantics), or is it advisory only?
- **Native event JSON, or generic envelope?** Does it emit structured hook JSON, or will the
  adapter synthesize the generic `{session_id, cwd, prompt?, tool_name?, …}` envelope?

## Anything else

Quirks, version constraints, links to the harness's plugin API, or a draft of the adapter.
