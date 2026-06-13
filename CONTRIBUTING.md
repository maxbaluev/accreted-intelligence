# Contributing to acc

Welcome — and thank you for wanting to make acc better. This repo is the **public
distribution and community hub** for acc: the place you install from, report problems,
request integrations, and contribute the glue that wires acc into more coding agents.

Before anything else: be kind. We want acc's community to be a genuinely good place to
spend time. Assume good faith, keep it constructive, and help the next person.

## What's open, and what isn't

acc has two layers, and they're licensed differently — on purpose.

- **The engine source is private.** The late-interaction scored-token memory, the appraisal /
  prediction layers, the credit math — the parts that make acc *work* — live in a private
  repository and ship to you as a **prebuilt binary** under an end-user license
  ([EULA.md](EULA.md), currently a draft). That's the moat, and it stays closed.

- **The integration glue is open and welcomes PRs.** The install scripts (`install.sh`,
  `install.ps1`, `bootstrap/`) and the host adapters in [`plugins/`](plugins/) are
  **Apache-2.0 licensed** ([LICENSE-APACHE-2.0.txt](LICENSE-APACHE-2.0.txt)) and developed in
  the open. This is the surface you can read, fork, fix, and extend.

See [LICENSING.md](LICENSING.md) for the full split. The short version: **glue = Apache-2.0,
binary = EULA, engine source = private.**

So: a pull request that improves the installer, hardens a sandbox setup step, fixes a host
adapter, or adds support for a new coding agent is exactly the kind of contribution this repo
is built to receive. A change to the engine internals isn't something you can PR here — but a
great *idea* for one absolutely is, as a [feature request](.github/ISSUE_TEMPLATE/feature_request.md).

## How to add or fix a harness plugin

acc integrates with a coding agent through ONE host-agnostic lifecycle protocol — eight
fixed events, each a subprocess call into the binary:

```
acc hook <event> --host <claude-code|opencode|generic>

session-start · turn-start · post-tool · turn-end ·
subagent-start · subagent-end · compact · session-end
```

Each adapter under [`plugins/`](plugins/) does two things: (1) registers the two-verb MCP
server (`acc_retrieve` / `acc_act`) in that host's config dialect, and (2) translates the
host's native lifecycle signals into the **generic envelope** on stdin of
`acc hook <event> --host generic`:

```json
{ "session_id": "…", "cwd": "…", "prompt": "…", "tool_name": "…", "tool_input": {}, "tool_response": {}, "agent_id": "…" }
```

`session_id` and `cwd` are required; unknown fields are ignored; junk stdin exits 0
(fail-open). The full envelope spec and the per-host coverage table live in
[`plugins/README.md`](plugins/README.md) — start there.

**To fix an existing adapter:** find it under `plugins/<host>/`, make the change, and verify
the events still translate correctly against that host. Open a PR describing the host version
you tested against.

**To add a new harness:** copy the closest existing adapter (`plugins/opencode/`,
`plugins/codex/`, or `plugins/cursor/`) as a starting point, map the host's signals onto the
eight events, and register the MCP server in the host's dialect. Filing a
[harness integration issue](.github/ISSUE_TEMPLATE/harness_integration.md) first is a great way
to get pointers before you write code.

The integration is **add-only and idempotent** by design — `acc hosts-sync` converges a host's
config without clobbering what's already there. Keep that property in any adapter you write.

## Reporting a problem

The fastest, lowest-friction path:

1. Run **`acc doctor`** — the end-to-end self-check. It walks every layer and prints what's
   healthy, what's broken, and the suggested fix. Its output is operational health only —
   **no memory contents, no paths, no secrets** — so it's safe to paste into an issue.
2. Open an issue with the template that fits — [bug](.github/ISSUE_TEMPLATE/bug_report.md),
   [install failure](.github/ISSUE_TEMPLATE/install_failure.md),
   [feature](.github/ISSUE_TEMPLATE/feature_request.md), or
   [harness integration](.github/ISSUE_TEMPLATE/harness_integration.md) — and paste the
   `acc doctor` output where the template asks for it.

The install-failure template in particular is built around that paste: a pre-filled issue with
your `acc doctor` output usually tells us exactly where the break is.

**Security issues are different** — never file them publicly. See
[SECURITY.md](.github/SECURITY.md) to report privately.

## Pull requests

- Keep PRs focused — one logical change per PR.
- For glue changes, make sure the install / plugin path still works on the platform you touched.
- Describe what you changed and how you verified it.
- By contributing to the open glue, you agree your contribution is licensed under Apache-2.0
  (matching [LICENSE-APACHE-2.0.txt](LICENSE-APACHE-2.0.txt)).

Thanks again — every honest bug report and every adapter you contribute makes acc work for
more people on more tools.
