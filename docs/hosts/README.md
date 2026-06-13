# Hosts — one protocol, many agents

`acc` works underneath the coding agents you already run. Keep your agent, keep your computer — `acc` learns what worked quietly underneath, nothing new to open. **One binary, one lifecycle protocol, one substrate shared across every host and project.**

This page is the narrative tour. The exact, copy-pasteable per-host config snippets live beside the code under [`../../plugins/`](../../plugins/) — that is the source of truth and what `acc hosts-sync` converges toward.

## The generic envelope (the one cross-host contract)

Every host translates its native signals into a single flat JSON object on the stdin of `acc hook <event> --host generic`. The eight lifecycle events are the same everywhere: `session-start · turn-start · post-tool · turn-end · subagent-start · subagent-end · compact · session-end`. No adapter adds a second mind — the substrate perceives and predicts; the session reasons. Full envelope spec: [`../../plugins/README.md`](../../plugins/README.md).

## Supported hosts

| Host | Status | Wiring | Config |
|---|---|---|---|
| **Claude Code** | live (reference host) | `.mcp.json` + native hooks | [`../../plugins/claude/`](../../plugins/claude/) |
| **OpenCode** | live | `opencode.json` mcp block + plugin | [`../../plugins/opencode/`](../../plugins/opencode/) |
| **Codex CLI** | live | `config.toml` mcp server + `notify` hook | [`../../plugins/codex/`](../../plugins/codex/) |
| **Cursor** | wired — authored against docs, not live-tested | `.cursor/mcp.json` + agent hooks | [`../../plugins/cursor/`](../../plugins/cursor/) |

`plugins/claude/` is the reference host — native lifecycle wiring plus skills; the other three translate their host's signals into the one generic envelope. Same substrate, same two verbs, different richness of wiring.

## Automatic wiring — `acc hosts-sync`

Run **`acc hosts-sync`** (the installer runs it for you). It detects which hosts are present and converges each config **add-only**: missing `acc` entries are merged in, an existing one is never rewritten (drift is reported, not overwritten), every changed file gets one `.acc-backup-<ts>` sibling, and `acc hosts-sync --dry-run` shows the diff first. It never touches your existing config beyond adding `acc`.

## One substrate across projects

Export `ACC_DB=/abs/path/acc.db` to share one memory across every project and host; without it, resolution is the per-project `<cwd>/acc.db`.

## Wiring a new host

A great way to contribute: add or fix a host adapter. See [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md) and the existing adapters under [`../../plugins/`](../../plugins/) as the template. For the lifecycle the adapter maps onto, read [reference/architecture-overview.md](../reference/architecture-overview.md).

---

See it live: [accint.xyz](https://accint.xyz).
