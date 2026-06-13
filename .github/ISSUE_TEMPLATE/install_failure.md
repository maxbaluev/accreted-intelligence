---
name: Install / build failure
about: The installer or first build did not finish successfully
title: "[install] "
labels: ["install"]
assignees: []
---

Install failures are almost always environment-specific (a missing system library, a
sandbox/browser dependency, a model download interrupted mid-stream). The fields below let
us pin the cause fast.

> Not an install problem? Use the [bug report](./bug_report.md) instead.
> Security issue? Report it privately — see [SECURITY.md](../SECURITY.md).

## How you installed

- [ ] One-line bootstrap (`curl … | sh` / `irm … | iex`)
- [ ] `./install.sh` from a clone (the dev path)
- [ ] Container (`scripts/acc-docker.sh` / Tier-C image)
- [ ] Other (describe)

## Where it failed

Which step printed the error? (dependency install · `acc` build · embedder/model pin ·
warm daemon start · MCP wiring · `acc doctor` at the end)

## Environment

- **OS / arch:** (e.g. Ubuntu 22.04 x86_64, macOS 14 arm64, Windows 11)
- **Shell:** (bash / zsh / PowerShell)
- **First install or update?** fresh install · re-running over an existing clone

## Error output

Paste the failing command and its full error output here (in a code block). Redact
anything sensitive.

```
<paste the failing output here>
```

## Diagnostics — run `acc report` (or paste `acc doctor` output)

The fastest path: run **`acc report`**. It runs the full self-check, builds a **sanitized**
diagnostic bundle (operational health only — **no memory contents, file paths, or secrets**),
and prints a pre-filled version of this very issue plus the exact text to paste below. It
never sends anything itself — you review and submit. If the binary built far enough to run at
all, that one command gives us everything.

If you'd rather paste manually, `acc doctor` is the underlying end-to-end self-check (every
layer: substrate, embedder, sandbox, hooks, MCP wiring) and is equally safe to paste in full:

```
<paste the output of `acc doctor` here>
```

If the binary never built, `acc doctor` won't exist yet — that's fine, the build error
output above is what we need. (`acc status` is a lighter health + next-step check if
`doctor` is too verbose.)
