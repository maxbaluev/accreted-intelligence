# Self-serve install — the plain installer path

You run the one-liner yourself, on a box you control. This is the same install the [conversational path](with-agent.md) drives — just without your agent narrating each step.

> **Public release path.** The public `bootstrap/install` clones the open installer/glue repo, then `install.sh` downloads and SHA-256 verifies the latest matching prebuilt `acc` binary. A source build is only the fallback for development checkouts that contain engine source.

## The one line

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

```powershell
# Windows (PowerShell 5.1+)
irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

Optional local attribution for docs, directory listings, or PR links:

```bash
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | ACC_INSTALL_REF=gh-awesome-list ACC_INSTALL_SOURCE='ref=gh-awesome-list' sh
```

```powershell
$env:ACC_INSTALL_REF = 'gh-awesome-list'; $env:ACC_INSTALL_SOURCE = 'ref=gh-awesome-list'; irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

`ACC_INSTALL_REF` and optional `ACC_INSTALL_SOURCE` are written only to a local
receipt at `install-attribution.env` under the acc data directory. The installer
does not send that ref or source anywhere by itself. Web prompt copies set both:
a content-free correlation nonce in `ACC_INSTALL_REF`, plus a coarse source
envelope such as `ref=...` / `utm_source=...` in `ACC_INSTALL_SOURCE`.
Maintainers can measure the ref chain with the
[attribution dashboard runbook](../ops/attribution-dashboard.md).

Prefer to read before you run? The installer is Apache-2.0 and auditable — `bootstrap/install`, `bootstrap/install.ps1`, and `install.sh` / `install.ps1` are exactly what touches your system. Read them, then run.

## What it does, in order

1. **Probes your hardware** and picks the embedder tier it can honestly run (cuda / mps / cpu). It never pretends your machine is bigger than it is.
2. **Installs `acc`** by fetching a verified prebuilt release binary when available, then places it on your PATH. Development checkouts with engine source can still build from source.
3. **Starts a warm local embedder daemon** so retrieval is fast from the first call.
4. **Wires Claude Code** — adds `acc` to `.mcp.json` (add-only; your existing config is never rewritten).
5. **Runs `acc hosts-sync`** to wire any other installed agents (OpenCode, Codex, Cursor) — add-only and idempotent. See [../hosts/README.md](../hosts/README.md).

**First run may download the embedder model (several GB) and take minutes.** The installer reports the wait honestly.

The public installer enables anonymous event-name telemetry by default so the
maintainer can see real install failures and usage health. It never sends your
prompts, files, memory, or Work Model data. Set `ACC_NO_TELEMETRY=1` before
install, or run `acc telemetry off` after install, to opt out.

## Verify it worked

```
$ acc status            # health + your next step
$ acc doctor --json     # machine-readable health contract
```

`acc doctor` output is operational health only — safe to paste into a [GitHub issue](https://github.com/maxbaluev/accreted-intelligence/issues) if something is off.

## If native doesn't fit

Windows? Use the PowerShell one-liner above. Locked-down, no-root, or container-only host? See the [container](container.md) portability path; it uses the public release binary and documents the remaining Docker-host smoke before registry promotion.

---

Then run your [first session](../first-session.md). See it live: [accint.xyz](https://accint.xyz).
