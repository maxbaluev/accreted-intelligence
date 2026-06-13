# Public Repo Manifest

This file defines exactly what belongs in the **public** distribution repo
(`maxbaluev/accreted-intelligence`) versus what stays in the **private** engine repo
(`maxbaluev/accint`). It is the source of truth for the separate-clone publish (see
[RELEASE_RUNBOOK.md](RELEASE_RUNBOOK.md)).

## Trust model

The glue is open and auditable; the engine binary is closed; the ideas are public; the
constants are the moat. A new user can read every line that runs on their machine at install
time, while the engine's scoring/calibration internals stay private.

## PUBLIC — ships to `accreted-intelligence`

- **Install surface:** `install.sh`, `install.ps1`, `bootstrap/install`, `bootstrap/install.ps1`, `Dockerfile`, `docs/install/**`
- **Plugins (integration glue):** `plugins/**` (including `plugins/claude/**`, the reference host) — REQUIRED public: the installer fetches `plugins/` into `~/.local/share/acc/plugins`
- **Public docs:** `README.md`, `docs/**` — the three-layer tree: concept/glossary/quickstart/first-session (Layer 1–2), `docs/reference/whitepaper.md`, `docs/reference/architecture-overview.md`, `docs/reference/trust-model.md` (principles public, numeric constants proprietary), `CHANGELOG.md`
- **Releases:** prebuilt multi-OS binaries + `sha256sums.txt` (via GitHub Releases)
- **Community infra:** `.github/ISSUE_TEMPLATE/**`, `.github/SECURITY.md`, `CONTRIBUTING.md`, `LICENSE-APACHE-2.0.txt`, `EULA.md`, `LICENSING.md`, this manifest

## PRIVATE — stays in `accint` (the moat)

- **Engine source:** `src/**` (`src/recursion.rs`, `src/maxsim.rs`, `src/selector.rs`, `src/calibration.rs`, `src/appraisal.rs`, … — the scoring, the `g` function, surprise/provenance weights, calibration constants)
- **Build:** `Cargo.toml`, `Cargo.lock`, `build.rs`, `tests/**`, the source-dependent CI workflows
- **Substrate:** `acc.db` and all memory — never ships in any form

## Publish discipline (history-leak guard)

Push public files to `accreted-intelligence` **only from a separate clone** of that repo —
**never** `git push` from this engine checkout, and never add the public repo as a remote
here. A single push from this checkout would leak the entire private `src/` revision history.
Release binaries are published via `gh release create --repo maxbaluev/accreted-intelligence`
(assets only, no source). See [RELEASE_RUNBOOK.md](RELEASE_RUNBOOK.md).
