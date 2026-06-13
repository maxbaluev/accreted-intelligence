# Licensing

acc ships as two layers with two different licenses. This split is deliberate: the parts
that run on your machine are open and auditable; the engine that is the project's moat is
closed.

## Open glue — Apache License 2.0

The **integration glue** is licensed under [Apache-2.0](LICENSE-APACHE-2.0.txt). You may
read, audit, fork, modify, and redistribute it. Contributions are welcome (see
[CONTRIBUTING.md](CONTRIBUTING.md)). This covers:

- the installers: `install.sh`, `install.ps1`, `bootstrap/`
- the coding-agent plugins: `plugins/**` (including `plugins/claude/**`, the reference host)

Auditing these is encouraged — they are exactly what touches your system at install time.

## Proprietary binary — EULA

The **prebuilt `acc` engine binary** (distributed via GitHub Releases) is governed by a
separate end-user license — see [EULA.md](EULA.md) (currently a **draft template** pending
legal review). The engine **source** (the scoring, calibration, and prediction internals)
is not published; it is the project's moat.

## Your memory is yours

Your substrate — `acc.db`, the memory and scores acc accumulates from your work — is
**yours**. It never leaves your machine through the binary, and no license here claims any
right to it.

## Summary

| Layer | What | License |
|---|---|---|
| Glue | install scripts, `plugins/` (incl. `plugins/claude/`) | Apache-2.0 (open) |
| Binary | the prebuilt `acc` engine | EULA (proprietary, draft) |
| Engine source | scoring / calibration / prediction internals | not published |
| Your substrate | `acc.db` | yours |
