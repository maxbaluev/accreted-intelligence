# Release runbook (public, redacted)

The maintainer procedure for cutting a public release of `acc` to
`maxbaluev/accreted-intelligence`. This is the redacted public copy — the
private engine repo holds the full version with internal CI detail. Pairs with
[PUBLIC_REPO_MANIFEST.md](PUBLIC_REPO_MANIFEST.md) (what ships) and
[../CHANGELOG.md](../CHANGELOG.md) (the ledger of what shipped).

## The discipline (read first)

Publish public files to `accreted-intelligence` **only from a separate clone** of
that repo — **never** `git push` from the private engine checkout, and never add
the public repo as a remote there. A single push from the engine checkout would
leak the entire private `src/` history. Release binaries are published via
`gh release create --repo maxbaluev/accreted-intelligence` (assets only, no
source).

## Version surfaces (kept in lockstep at release)

- `Cargo.toml` (`version = "…"`) — the engine.
- `plugins/claude/.claude-plugin/plugin.json` (`"version": "…"`) — the Claude Code
  plugin (loosely coupled; bumps independently when its own hook/MCP surface
  changes).
- the git tag (`vX.Y.Z`) — the release marker.

## Cut steps (outline)

1. **Land the changes** in the public clone on `main`; confirm the working tree is
   clean and the [manifest](PUBLIC_REPO_MANIFEST.md) split still holds (no engine
   internals leaked into a public path).
2. **Bump the version surfaces** above in lockstep; update
   [../CHANGELOG.md](../CHANGELOG.md) (move `[Unreleased]` into a dated section).
3. **Verify the install surface** — `bash -n install.sh`, `bash -n bootstrap/install`,
   and a smoke run of the bootstrap path on each supported OS tier.
4. **Tag and release** — `git tag vX.Y.Z`, push the tag, and
   `gh release create vX.Y.Z --repo maxbaluev/accreted-intelligence` with the
   prebuilt binaries + `sha256sums.txt` as assets (no source in the release).
5. **Confirm the live site** — the [accint.xyz](https://accint.xyz) deploy serves
   from `index.html` + `CNAME` at repo root; confirm the deep-doc links resolve on
   the published default branch.

> Engine-side CI, signing, and the exact build matrix are maintained privately and
> intentionally omitted here.
