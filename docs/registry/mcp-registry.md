# MCP Registry Packaging

AccInt is a local MCP server exposed by the `acc` binary. The public release
already ships prebuilt binaries, so the lowest-friction official MCP Registry
path is **MCPB**: a GitHub Release asset that contains `manifest.json` plus the
platform binary.

This page is maintainer-facing. It prepares the registry submission, but does
not submit anything by itself.

## Current path

- Registry name: `io.github.maxbaluev/accint`
- Package type: `mcpb`
- Transport: `stdio`
- MCP server command inside the bundle: `acc --db <acc.db> mcp`
- Tools: `acc_retrieve`, `acc_act`

The bundle must not include `acc.db`. The user chooses the local substrate path
during MCPB install, and that file stays on the user's machine.

## Why MCPB, not Cargo

The registry supports Cargo packages, but that route depends on crates.io and
requires a visible `mcp-name: io.github.maxbaluev/accint` token in the package
README because crates.io strips HTML comments. The engine crate is not published
to crates.io from this public repo.

MCPB fits the current release model: the public repo owns GitHub Release assets,
and the registry metadata points to those assets with a SHA-256 hash.

## Files

- [`../../mcpb/manifest.json`](../../mcpb/manifest.json) — template manifest
  copied into each bundle.
- [`../../scripts/package-mcpb.sh`](../../scripts/package-mcpb.sh) — builds
  `dist/acc-mcp-<tag>-<target>.mcpb` from a published GitHub Release binary.
- [`../../registry/server.template.json`](../../registry/server.template.json) —
  template for the registry `server.json`.

The generated bundle filename intentionally contains `mcp`. The official
registry requires MCPB package URLs to contain that string, either in the file
extension/name or in the repository path.

## Build MCPB assets

After the normal release assets exist on GitHub:

```bash
scripts/package-mcpb.sh v0.1.1 all
```

This creates:

```text
dist/acc-mcp-v0.1.1-aarch64-apple-darwin.mcpb
dist/acc-mcp-v0.1.1-aarch64-unknown-linux-musl.mcpb
dist/acc-mcp-v0.1.1-x86_64-unknown-linux-musl.mcpb
dist/acc-mcp-v0.1.1-x86_64-pc-windows-msvc.mcpb
dist/server.<target>.json
```

Attach the `.mcpb` files and their `.sha256` sidecars to the same GitHub
Release. Do not commit `dist/`; release artifacts belong on GitHub Releases.

## Publish

Pick one generated `dist/server.<target>.json`, copy it to `server.json`, and
publish with the official `mcp-publisher`:

```bash
curl -L "https://github.com/modelcontextprotocol/registry/releases/latest/download/mcp-publisher_$(uname -s | tr '[:upper:]' '[:lower:]')_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" | tar xz mcp-publisher
./mcp-publisher login github
./mcp-publisher publish
```

For unattended publishing from GitHub Actions, use GitHub OIDC instead of the
device-code login:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: actions/checkout@v5
  - name: Install mcp-publisher
    run: |
      curl -L "https://github.com/modelcontextprotocol/registry/releases/latest/download/mcp-publisher_$(uname -s | tr '[:upper:]' '[:lower:]')_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" | tar xz mcp-publisher
  - name: Authenticate to MCP Registry
    run: ./mcp-publisher login github-oidc
  - name: Publish server
    run: ./mcp-publisher publish
```

Keep this as a manual maintainer step until the release pipeline attaches MCPB
assets and produces a real `server.json` with a real `fileSha256`.
