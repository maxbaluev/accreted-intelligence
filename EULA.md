# acc Binary — End User License (DRAFT TEMPLATE)

> ⚠️ **DRAFT TEMPLATE — NOT YET BINDING.** This is a starting point for the license that
> will govern the prebuilt `acc` binary. It has **not** been reviewed by legal counsel.
> Review, edit, and ratify it with a lawyer before publishing or distributing any binary.
> Until then, no terms here are in force.

This template covers the **prebuilt `acc` engine binary** distributed via the public
`accreted-intelligence` releases. It does **not** cover the open integration glue (the
install scripts and `plugins/`), which is licensed permissively — see
[LICENSING.md](LICENSING.md) and [LICENSE-APACHE-2.0.txt](LICENSE-APACHE-2.0.txt).

## Intended terms (to be finalized with counsel)

- **Grant.** A non-exclusive, non-transferable license to install and run the `acc` binary
  on machines you control, for personal or internal business use.
- **Your data is yours.** Your substrate (`acc.db`) — your memory, scores, and content — is
  owned by you. It is never transmitted by the binary; the publisher claims no rights to it.
- **No reverse engineering.** Do not decompile, disassemble, or attempt to derive the engine
  source from the binary, except where that restriction is unenforceable by law.
- **No redistribution of the binary** without written permission. (The open glue may be
  forked and redistributed under its Apache-2.0 license.)
- **No warranty / limitation of liability.** The binary is provided "as is," without warranty
  of any kind; the publisher's liability is limited to the extent permitted by law.
- **Integrity, not authenticity (today).** Releases are verified by SHA-256 checksums.
  Cryptographic signing is on the roadmap (see [.github/SECURITY.md](.github/SECURITY.md)).
- **Termination** on breach of these terms.

## Owner action

Replace this template with counsel-ratified terms, set the publisher/jurisdiction details,
and place the finalized text as the binary license in the public repo before the first
release. Track this as a release blocker for the binary (the glue can ship under Apache-2.0
independently).
