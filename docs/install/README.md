# Install — pick your path

`acc` installs as one binary plus one local daemon. Three honest paths, by how much control you have over the box.

> **Public binary available.** The native paths download a public release binary when one exists for your OS/architecture, verify it by SHA-256, and then wire the local Work Model. No invite is required for the public release path.

## Pick your path

| Your situation | Path | Doc |
|---|---|---|
| You'd rather be walked through it (any agent — Claude Code, Codex, Cursor, OpenCode) | paste one prompt into your agent | [with-agent.md](with-agent.md) |
| macOS / Linux you control | the one manual line | [self-serve.md](self-serve.md) |
| Windows you control | PowerShell installer | [self-serve.md](self-serve.md) |
| Locked-down, no-root, or container-only hosts | container portability path | [container.md](container.md) |

The universal path is the simplest: paste **one prompt** into whatever agent you already
use and it installs acc *with* you, pausing for your consent at the boundary and verifying
the result against a machine-readable contract — see [with-agent.md](with-agent.md). The
prompt is the same one on [accint.xyz](https://accint.xyz); the other two paths are the
same install underneath, by hand.

## The one-liner (self-serve)

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install | sh
```

```powershell
# Windows (PowerShell 5.1+)
irm https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/bootstrap/install.ps1 | iex
```

For install attribution from a directory listing or PR, set
`ACC_INSTALL_REF=<surface>` on the installer process. Add
`ACC_INSTALL_SOURCE='ref=<surface>'` when you want coarse source context in the
same receipt. The installer writes those labels locally only; it does not send
the ref or source anywhere by itself. See [self-serve.md](self-serve.md) for
exact shell and PowerShell examples.
Maintainers can measure the ref chain with the
[attribution dashboard runbook](../ops/attribution-dashboard.md).

It fetches the public installer and hands off to the installer for your OS. The installer probes your hardware, picks the embedder tier it can honestly run, downloads and verifies the release binary when available, starts a warm local daemon, and wires your agent's `.mcp.json`. **First run may download the embedder model (several GB) and take minutes** — the installer reports the wait honestly and never pretends your hardware is bigger than it is. Full detail: [self-serve.md](self-serve.md).

## The OS / tier ladder (honest native-vs-container)

| System | Native support | Notes |
|---|---|---|
| **Linux x86_64** | full | `bwrap` sandbox; embedder on cuda or cpu |
| **macOS** | functional | no `bwrap`; embedder on mps or cpu |
| **Linux aarch64** | functional | embedder on cpu |
| **Windows** | native via `install.ps1` | engine windows-clean; [container](container.md) as fallback |
| **Locked-down / no-root** | use the container | image carries its deps; CPU floor works with no GPU |

The native path is preferred on a Linux box you control (it gives the full multimodal lane natively). The [container](container.md) is the pragmatic cross-OS answer for Docker-first hosts; it now installs the public release binary, with Docker-host smoke still tracked before registry promotion.

## After install

```
$ acc status     # health + your next step
$ acc doctor     # diagnose; output is safe to paste
```

Then run your [first session](../first-session.md). To wire another agent (OpenCode, Codex, Cursor), run `acc hosts-sync` — see [../hosts/README.md](../hosts/README.md).

See it live: [accint.xyz](https://accint.xyz).
