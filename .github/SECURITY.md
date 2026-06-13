# Security Policy

Thank you for helping keep acc and its users safe. Because acc installs by downloading and
running a prebuilt binary, the integrity of that supply chain is something we take seriously.

## Reporting a vulnerability — privately

**Please do not open a public issue for a security vulnerability.** Public disclosure before
a fix is available puts every user at risk.

Report privately through one of:

1. **GitHub private security advisory** (preferred) — go to the **Security** tab of
   [`maxbaluev/accreted-intelligence`](https://github.com/maxbaluev/accreted-intelligence)
   and choose **Report a vulnerability**. This opens a private advisory visible only to you
   and the maintainers, with a built-in space to collaborate on the fix and a coordinated
   disclosure timeline.
2. **Direct contact** — if you cannot use the advisory flow, open a minimal placeholder issue
   titled "security contact request" (no details) at
   <https://github.com/maxbaluev/accreted-intelligence/issues> and a maintainer will reach out
   to move the conversation to a private channel. Never put exploit details in the public
   issue.

Please include, as far as you can: the affected component and version, a description of the
issue, reproduction steps or a proof of concept, and the impact you foresee. We aim to
acknowledge a report promptly and will keep you updated as we triage and fix.

We will credit reporters who want credit once a fix ships, and we ask for coordinated
disclosure: give us a reasonable window to release a fix before any public write-up.

## The download-and-execute trust model

acc is distributed as a **prebuilt binary**. The installer downloads a release artifact and
then runs it. That is a privileged step, and you should understand exactly what protects it
today and what does not yet.

### Integrity today: sha256

Every release publishes a `sha256sums.txt` alongside the artifacts. The installer verifies the
downloaded artifact's SHA-256 against that manifest **before it ever executes the binary**. If
the bytes don't match, the install aborts. This protects against a corrupted or truncated
download and against a tampered artifact *given a trustworthy checksum manifest*.

### The integrity-vs-authenticity caveat (read this)

sha256 proves **integrity** — "these are the bytes the checksum describes." It does **not**
prove **authenticity** — "these bytes were produced and published by the acc maintainers."
The checksum manifest is fetched over the same channel as the artifact; an attacker who can
substitute the artifact can, in principle, also substitute the manifest. TLS and GitHub's
release infrastructure are what currently stand between you and that substitution — not a
cryptographic signature you can independently verify. **Until signing lands (below), the trust
root is GitHub + TLS, not an offline-verifiable key.** If your threat model requires
authenticity guarantees, prefer building from source (available to licensees of the engine)
or pin and review the installer before running it.

### Roadmap: cryptographic signing

Cryptographic signing of release artifacts (cosign keyless / Sigstore) is a tracked follow-on,
not yet shipped. When it lands, releases will carry verifiable signatures, the installer will
verify the signature in addition to the checksum, and this document will be updated with the
verification steps. Until then, sha256 + TLS is the documented integrity floor — stated plainly
so you can make an informed decision.

## Scope

In scope for security reports:

- **The installer** — `install.sh`, `install.ps1`, and the `bootstrap/` one-liner: download
  integrity, checksum verification, privilege escalation, command injection, and anything that
  could let a malicious actor get code executed during install.
- **The prebuilt `acc` binary** — the distributed engine: sandbox escapes, memory-safety
  issues with security impact, mishandling of the substrate/credentials, or anything that
  compromises the host or the user's data.

Out of scope (report as a normal [bug](./ISSUE_TEMPLATE/bug_report.md) instead): functional
bugs without a security impact, missing hardening that is already on the documented roadmap
(e.g. signing, before it ships), and issues in third-party dependencies that are better
reported upstream (tell us anyway if acc's usage makes the impact materially worse).

The deliberate, documented design choice that the sandbox uses the **host network** (so
sandboxed runtimes can reach APIs and the embedder socket) is a known trade, not a
vulnerability — see the architecture docs. A report that turns that trade into an unintended
escalation *is* in scope.
