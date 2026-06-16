# Changelog

This repo compounds through the same loop it ships — every entry below is a
commitment that passed the operator loop: built, held for approval, merged,
credited. The running readout is live at [accint.xyz](https://accint.xyz).

All notable changes to acc are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project aims at
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- **All plugins multi-OS: Cursor hooks invoke `acc` directly via a new `--host cursor`
  parser (no `/bin/sh`, `jq`, or `python3`); OpenCode plugin spawns `acc.exe` on Windows;
  Codex `hooks.json` + quoted commands already cross-OS (notify stays a Git-Bash
  fallback).** The three `CURSOR_*_HOOK` commands were `/bin/sh -c '…jq/python3… | acc
  hook <event> --host generic'` wrappers — `/bin/sh` does not exist on Windows, so Cursor
  lifecycle hooks were POSIX-only. They are now the bare `acc hook <event> --host cursor`,
  and a native in-process parser (`src/hook.rs` `cursor_map`/`cursor_envelope`) maps
  Cursor's stdin JSON `{conversation_id, workspace_roots[], prompt, file_path}` into acc's
  generic envelope (session_id ← conversation_id || "cursor", cwd ← workspace_roots[0] ||
  `$PWD`, the edit path threads `file_path` into `tool_input`), fail-open on junk stdin or
  an unresolvable cwd. The OpenCode plugin now spawns `process.platform === "win32" ?
  "acc.exe" : "acc"` (no shell). Codex's `~/.codex/hooks.json` (`--host claude-code`) is
  the binding multi-OS path on every OS; `plugins/codex/notify-acc.sh` remains a
  Git-Bash-only fallback on Windows. Cursor's hook commands and `plugins/cursor/hooks.json`
  stay pinned byte-for-byte by `tests/hosts_sync.rs`.
- **Codex hook commands quote the `acc` binary path (cross-OS paths-with-spaces).**
  The wired `~/.codex/hooks.json` command now shell-quotes the binary
  (`"<bin>" hook <event> --host claude-code`), so a Windows home with a space
  (e.g. `C:\Users\First Last\.cargo\bin\acc.exe`) no longer splits into two args
  when Codex runs the hook through a shell. One `command` covers every OS — POSIX,
  cmd, and powershell all strip the quotes — and space-free Linux/macOS paths are
  unaffected.
- **Stable `acc` binary in wired host commands (Codex hook-trust no longer
  re-prompts).** `hosts-sync` resolved the wired command (the `[mcp_servers.acc]`
  block and every Codex `hooks.json` entry) from `std::env::current_exe()`, so a
  converge run from a transient build binary — a pool-slot `target/debug/acc`, a
  `target/release/acc` — baked that path into long-lived config. Concurrent dev
  terminals each wrote a DIFFERENT path, and Codex (which content-hashes a hook for
  trust) saw the hook "change" every session and re-prompted forever. New
  `stable_acc_bin()` resolves the SAME installed `acc` for every caller
  (PATH-first; falls back to a non-build-artifact running exe, else the bare name
  `acc` resolved by `$PATH` at run time) — never a `target/`/`.worktrees/` path. The
  wired command is now byte-identical across terminals, so one Codex trust click
  sticks.

### Added

- **Codex hooks.json binding parity (8/8 lifecycle hooks).** Codex 0.139 ships a
  STABLE, default-on `hooks` feature whose JSON contract is Claude Code's hook
  protocol verbatim. `acc hosts-sync` now wires `~/.codex/hooks.json` (and a
  project's `.codex/hooks.json` under `--project`) with 7 lifecycle events —
  `SessionStart`/`UserPromptSubmit`/`PostToolUse`(Bash)/`Stop`/`PreCompact`/
  `SubagentStart`/`SubagentStop` → `acc hook <event> --host claude-code` — lifting
  Codex from advisory `notify`-only telemetry to full per-prompt retrieval-inject
  and the fail-closed Stop guard, at parity with Claude Code and OpenCode. Same
  rails as every host: add-only merge (foreign events/matchers/handlers preserved,
  existing acc entries never amended → drift-reported), atomic write,
  `.acc-backup-<ts>` sibling, and `--remove` strips only acc-owned entries. The
  `notify` line stays as the pre-trust turn-end fallback; the one manual step is
  running `/hooks` in Codex once to trust acc's SHA-keyed hooks. `[features]\nhooks
  = true` is written belt-and-suspenders (the feature is default-on). The survey
  depth line and doctor grounding ladder now report binding parity when the
  hooks.json is present, advisory when only `notify` is.

## [0.1.5] — 2026-06-16

### Added

- **Work that compounds — for real.** Browser flows and code changes now build
  on themselves: when you do something similar to before, acc reuses the
  *verified* approach instead of starting over. Identity is decided by meaning
  (late-interaction MaxSim), not brittle string-matching — so "message Rinat"
  and "reply Harkirat" reinforce one capability instead of fragmenting into
  dead ones.
- **Code compounding.** Every verified, merged change becomes a reusable,
  scored pattern future work retrieves as a hint (never a blind replay).

### Changed

- **Chat-is-authority.** The cryptographic grant layer is gone — authority is
  held when you're in an interactive session and asked in plain chat at the
  consent boundary. Simpler, no keys.
- **Smarter browser profiles** — inferred from the site/service automatically.

### Fixed

- **Fail-closed grounding.** If the memory can't be reached (busy embedder), acc
  now says "grounding faulted — retry" instead of confidently answering from
  generic priors.
- **Stop-hook loop** that could burn tokens by re-blocking itself — closed.
- Diagnostics no longer misread correctly-idle loops as broken.

## [0.1.2] — 2026-06-15

New-user install / update / download hardening, from a real fresh-machine install log
(CachyOS + RTX 4090) and a new user's `acc report`. Engine binaries are fully-static musl
(any Linux, no glibc floor); prebuilts ship for Linux x86_64 + arm64, macOS (Apple
Silicon), and Windows, with `.mcpb` MCP bundles for all four platforms.

### Fixed

- **The memory engine never warmed on a fresh machine.** The AWQ encoder pinned
  `transformers==4.57.1` (which renamed `PytorchGELUTanh` → `GELUTanh`) against
  `autoawq==0.2.9` (which still imports the old name) → hard `ImportError` → the embedder
  crash-looped → retrieval was dead and the install ended `DEGRADED`. A fresh `uv` resolve
  hit it; dev machines were masked by a warm cache. Restored the alias.
- **Silent auto-update would have bricked `acc` on the next release.** The background stager
  staged the raw release `.tar.gz` (no extraction) and the swap never set the executable bit,
  so apply-on-boot would have swapped a non-executable gzip blob over the binary. It now
  extracts the binary and `chmod +x`'s the swap; stale archive-stagings self-heal.
- **A 10-minute false "still downloading…".** A permanent encoder failure now fails fast with
  the real error instead of waiting out the clock.
- **`acc doctor` no longer false-warns** "rebuild with `cargo install`" on a prebuilt
  release install (the distribution repo has no `Cargo.toml`); the skew is reported as expected.
- **Honest install end** — a degraded install says so and leads with the one next step; the
  per-project wiring hints point to `acc hosts-sync --project .`; `acc report` (a sanitized,
  pre-filled GitHub issue) is surfaced as the escalation path.
- **`sudo` no longer prompts/hangs** in a piped `curl | sh` install (TTY-gated).
- **Browser: new-user multimodal routing is structural-first.**

### Added

- **Visible model + encoder-env downloads on release installs** — `acc prefetch <model>`
  (model weights, live progress) and `acc warm-encoder <model>` (the multi-GB torch/awq env,
  live progress) are embedded in the binary, so install phases 4 & 6 show the download with
  progress instead of hiding it inside the first embedder start.

### Changed

- **Anonymous usage telemetry is ON by default** (event names only — never your data, prompts,
  files, or memory). Opt out any time: `acc telemetry off`, or `ACC_NO_TELEMETRY=1` before
  install. `install.ps1` reaches Windows parity.
- The first-run briefing now teaches what the install set up and the explicit next action.

## [0.1.0] — 2026-06-13

First public release. `0.1.0` is the intentional baseline across all three version
surfaces, which are kept in lockstep at release:

- `Cargo.toml` (`version = "0.1.0"`) — the engine.
- `plugins/claude/.claude-plugin/plugin.json` (`"version": "0.1.0"`) — the Claude
  Code plugin (loosely coupled to the engine; it bumps independently only when the
  plugin's hook/MCP surface changes on its own).
- The git tag (`v0.1.0`) — the release marker.

### Highlights

- **Manual release path.** A clean, scripted cut to the public distribution repo
  `maxbaluev/accreted-intelligence` — the prebuilt-only public install lane plus the
  source dev lane.
- **`acc update`.** A shipped self-update subcommand: pulls and rebuilds acc in
  place (`--dry-run` to preview, `--offline` to rebuild from the working tree
  without a network fetch) — no clone or bootstrap re-run required.
- **Substrate migration ladder.** Schema migrations run automatically inside the
  binary on the first open after an update (a `PRAGMA user_version` ladder); your
  memory (`acc.db`) is preserved across versions. An older binary refuses to open a
  newer substrate for writing rather than corrupting it.
- **Cold-start onboarding.** A plain-language first-run path: the installer pins the
  best embedder for the host, warms the daemon, wires Claude Code MCP, and ends with
  the commands to try; `acc status` / `acc doctor` report the next step honestly.

[0.1.0]: https://github.com/maxbaluev/accreted-intelligence/releases/tag/v0.1.0
