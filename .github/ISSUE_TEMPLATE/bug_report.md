---
name: Bug report
about: Something behaves incorrectly once acc is installed and running
title: "[bug] "
labels: ["bug"]
assignees: []
---

Thanks for taking the time to file this. Clear, reproducible reports are the fastest path
to a fix — and they make the next person's report easier too.

> If this is a **security** issue, do **not** file it here. Report it privately — see
> [SECURITY.md](../SECURITY.md).
>
> If this is an **install / build** failure, the
> [install failure template](./install_failure.md) collects the diagnostics we need.

## What happened

A clear, one-paragraph description of the bug.

## Steps to reproduce

1. ...
2. ...
3. ...

## Expected behavior

What you expected acc to do.

## Actual behavior

What acc actually did. Paste the exact error text or the surprising output (in a code
block). Redact anything sensitive.

## Environment

- **OS / arch:** (e.g. Linux x86_64, macOS arm64, Windows 11)
- **Install path:** one-line bootstrap · `./install.sh` from a clone · container
- **Coding-agent harness:** (e.g. Claude Code, OpenCode, Codex CLI, Cursor, generic) and its version
- **acc version:** the version line from `acc status`

## Diagnostics (optional but very helpful)

The `acc doctor` end-to-end self-check reports the state of every layer with suggested
fixes. Its output is operational health only — **no memory contents, no file paths, no
secrets**. Pasting it (in a code block) usually tells us exactly where the break is:

```
<paste the output of `acc doctor` here>
```

## Anything else

Screenshots, related issues, or context you think is relevant.
