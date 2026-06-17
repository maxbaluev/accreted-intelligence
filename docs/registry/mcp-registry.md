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
- [`../../server.json`](../../server.json) — current registry metadata for the
  latest published MCPB assets.
- [`../../registry/server.template.json`](../../registry/server.template.json) —
  template for the registry `server.json`.

The generated bundle filename intentionally contains `mcp`. The official
registry requires MCPB package URLs to contain that string, either in the file
extension/name or in the repository path.

## Build MCPB assets

After the normal release assets exist on GitHub:

```bash
scripts/package-mcpb.sh v0.1.5 all
```

This creates:

```text
dist/acc-mcp-v0.1.5-aarch64-apple-darwin.mcpb
dist/acc-mcp-v0.1.5-aarch64-apple-darwin.sha256
dist/acc-mcp-v0.1.5-aarch64-unknown-linux-musl.mcpb
dist/acc-mcp-v0.1.5-aarch64-unknown-linux-musl.sha256
dist/acc-mcp-v0.1.5-x86_64-unknown-linux-musl.mcpb
dist/acc-mcp-v0.1.5-x86_64-unknown-linux-musl.sha256
dist/acc-mcp-v0.1.5-x86_64-pc-windows-msvc.mcpb
dist/acc-mcp-v0.1.5-x86_64-pc-windows-msvc.sha256
dist/server.<target>.json
dist/server.mcpb-all.json
```

Attach the `.mcpb` files and their `.sha256` sidecars to the same GitHub
Release. Do not commit `dist/`; release artifacts belong on GitHub Releases.

After the upload, verify the release and generated metadata before copying the
metadata into the root:

```bash
scripts/check-mcpb-release-assets.sh v0.1.5 dist/server.mcpb-all.json
```

The check must pass before `server.json` is advanced to the new version. A
`server.json` that points at assets which are not attached to the GitHub Release
will fail registry validation and downstream discovery.

## Publish

For the current release, the root [`../../server.json`](../../server.json) is
already the publishable metadata file.

For a new release, regenerate it from the generated multi-package file:

```bash
scripts/check-mcpb-release-assets.sh v0.1.5 dist/server.mcpb-all.json
cp dist/server.mcpb-all.json server.json
scripts/check-release-alignment.sh v0.1.5 server.json
```

The official registry validates every package entry in `packages[]`. Keeping all
four MCPB assets in one `server.json` lets the registry metadata point at each
platform bundle while preserving one MCP server name.

Publish with the official `mcp-publisher`:

```bash
curl -L "https://github.com/modelcontextprotocol/registry/releases/latest/download/mcp-publisher_$(uname -s | tr '[:upper:]' '[:lower:]')_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" | tar xz mcp-publisher
./mcp-publisher login github
./mcp-publisher publish
```

For unattended publishing from GitHub Actions, use the tracked
[`../../.github/workflows/publish-mcp.yml`](../../.github/workflows/publish-mcp.yml)
workflow. It authenticates with GitHub OIDC instead of the device-code login:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: actions/checkout@v5
  - name: Verify MCPB release assets
    env:
      GH_TOKEN: ${{ github.token }}
    run: |
      version="$(python3 -c 'import json; print(json.load(open("server.json"))["version"])')"
      bash scripts/check-mcpb-release-assets.sh "v${version}" server.json
  - name: Verify latest release alignment
    env:
      GH_TOKEN: ${{ github.token }}
    run: bash scripts/check-release-alignment.sh
  - name: Install mcp-publisher
    run: |
      curl -L "https://github.com/modelcontextprotocol/registry/releases/latest/download/mcp-publisher_$(uname -s | tr '[:upper:]' '[:lower:]')_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" | tar xz mcp-publisher
  - name: Authenticate to MCP Registry
    run: ./mcp-publisher login github-oidc
  - name: Publish server
    run: ./mcp-publisher publish
```

Keep this workflow on manual dispatch until the release pipeline attaches MCPB
assets and updates `server.json` with real `fileSha256` values for each release.
The workflow verifies those assets and latest-release alignment before it
authenticates or publishes.
