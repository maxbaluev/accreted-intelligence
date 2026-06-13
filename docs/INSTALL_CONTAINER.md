# acc — Tier-C container install (runs anywhere Docker runs)

This is the **pragmatic cross-OS answer**: a reproducible Linux x86_64 image you
can run on any host with Docker. Use it when the native `./install.sh` path is a
poor fit:

- **Windows** — native installs use `install.ps1` (the PowerShell phase-machine);
  the container is the alternative when Docker Desktop is already your workflow.
- **Locked-down / no-root boxes** — where you can't `apt-get install bubblewrap`,
  fetch system libs, or modify the host toolchain. The image carries its deps.
- **"It must just work" reproducibility** — one image, one pinned toolchain
  (Rust 1.96), the same sandbox + encoder env on every host.

The native install (`./install.sh`) is still preferred on a Linux box you control
with a GPU — it gives you the full multimodal ColQwen lane natively without
container GPU-passthrough overhead. The container is the **portability floor**.

> The native phase-machine **routes you here itself**: its `probe_tier` phase walks
> the 3-model tier ladder, and on a host where no native tier fits (no GPU, RAM below
> the LateOn floor, an unsupported OS/arch) it prints this container path as a
> terminal verdict instead of installing a broken native lane. You can also force it
> with `ACC_TIER=container ./install.sh`. The tier ladder is documented in
> [docs/INSTALL_WITH_CLAUDE.md](INSTALL_WITH_CLAUDE.md).

> **Verification status: PARTIAL (2026-06-06) — build infra-blocked, not verified.**
> A real `docker build -t acc:verify .` was attempted on a Docker 29.5.2 host
> (Docker Desktop / WSL2). Findings, in order:
>
> 1. **Source compiles.** The crate builds clean natively (`cargo check` → exit 0),
>    so the Dockerfile's `cargo build --release --locked` step (stage 1) is correct.
> 2. **Credential-helper prerequisite (real failure, fixed).** The first build died
>    at the base-image metadata step with `error getting credentials - err: exit
>    status 1` — the host's `credsStore: desktop.exe` helper (Docker Desktop on
>    WSL2) was failing even for the public `rust`/`debian` bases, which need no
>    auth. **Fix:** pre-pull the bases so BuildKit skips the registry-auth path:
>    `docker pull rust:1.96-bookworm && docker pull debian:bookworm-slim`. After
>    that the build advanced cleanly past credentials into the cargo compile.
> 3. **`.dockerignore` is missing (hygiene gap).** With no `.dockerignore` at the
>    repo root, a build run from a tree that has a `target/` dir ships it as build
>    context (observed: `Sending build context to Docker daemon 407.1MB`). The
>    committed tree is clean (1.2 MB), so this only bites after a local `cargo`
>    run. **Recommended:** add a repo-root `.dockerignore` with `target/`, `.git/`,
>    `.acc-data/`, `.worktrees/`, `**/__pycache__/`, `*.pyc`. (Not added here —
>    outside this change's file scope.) Or build from a freshly-checked-out tree.
> 4. **Build did NOT complete on this host.** Both BuildKit and the legacy builder
>    (`DOCKER_BUILDKIT=0`) wedged inside the `cargo build --release` stage: the
>    build container was killed mid-compile while the WSL2 kernel logged repeated
>    `rcu_tasks ... grace period stuck` stalls (and even `docker rm`/`prune`
>    started being reaped). That is a host-kernel fault, not a Dockerfile defect —
>    re-run on a healthy host or in CI to get the final image + size + build time
>    and promote this to **VERIFIED**.

## The one-liner

From the repo root:

```bash
scripts/acc-docker.sh
```

That builds the image (idempotent — Docker layer-caches), creates an owner-owned
substrate dir at `./.acc-data`, mounts a persistent model cache, detects a GPU
(passing `--gpus all` only if passthrough actually works), and serves the MCP
server. Other entry modes:

```bash
scripts/acc-docker.sh status        # print acc status (the doctor-equivalent) and exit
scripts/acc-docker.sh shell         # interactive shell inside the container
scripts/acc-docker.sh retrieve "memory retrieval"   # any acc command, passed through
```

Useful env knobs (all optional):

| Env | Default | Meaning |
|---|---|---|
| `ACC_IMAGE` | `acc:local` | image tag |
| `ACC_DATA_DIR` | `$PWD/.acc-data` | host substrate dir (owner-owned) |
| `ACC_MODELS_VOL` | `acc-models` | named volume for the model cache |
| `ACC_NO_BUILD=1` | — | skip build, use an existing/pulled image |
| `ACC_NO_PULL=1` | — | skip the base-image pre-pull (offline host, bases cached) |
| `ACC_NO_GPU=1` | — | force the CPU floor even if a GPU is present |
| `ACC_PIN_MODEL` / `ACC_PIN_DEVICE` | `lightonai/LateOn` / `cpu` | override the pinned model lane |

## The substrate is owner-owned and survives rebuilds

`acc.db` is the live scored-token memory — it must outlive any image rebuild and
stay owned by you, not baked into a container layer. The container declares two
volumes:

- **`/data`** — the substrate (`acc.db`) **plus** the model pin (`XDG_CONFIG_HOME`
  → `/data/.config`). `scripts/acc-docker.sh` bind-mounts your host dir
  (`$PWD/.acc-data`) over it, so the db file is a real file on your disk, owned by
  you. Rebuild the image as often as you like — the memory is untouched. (The
  devcontainer uses a named `acc-data` volume instead; same persistence, managed
  by Docker.)
- **`/models`** — the HuggingFace cache (`HF_HOME`) + the uv cache (`UV_CACHE_DIR`).
  The several-GB model download lands here once and is reused across rebuilds.

Because the substrate is just a file on a mount, you can back it up, move it, or
point a native acc at the same db — provided you use the **same embedder** (one
vector space per db; never mix encoders).

## CPU default (LateOn) vs GPU (ColQwen) — the tradeoff

The image **defaults to the universal CPU floor: LateOn**, a text-only,
broad-compat late-interaction model (dim-128). This is the deliberate default so
the image works on **any** Docker host with **no GPU** — Windows laptops, CI
runners, locked-down servers. The entrypoint pins `lightonai/LateOn` on `cpu` on
first run, so the embedder never tries to pull a multi-GB GPU model on a CPU host.

**The CPU floor is text-only.** Sight (`acc_retrieve` with an `image` input, the
multimodal ColQwen cross-modal property) requires the ColQwen lane — it is **not**
available on the CPU floor.

The optional **GPU / ColQwen lane** (linux-x86_64 + NVIDIA only):

1. The host needs an NVIDIA GPU **and** the `nvidia-container-toolkit` installed
   (that's a host concern — the image can't provide GPU passthrough itself).
2. Run with the GPU exposed and pin a ColQwen variant:

   ```bash
   ACC_PIN_MODEL=<colqwen-variant> ACC_PIN_DEVICE=cuda scripts/acc-docker.sh status
   ```

   `acc-docker.sh` auto-adds `--gpus all` when it detects a working GPU; force it
   off with `ACC_NO_GPU=1`. The ColQwen AWQ encoder deps
   (`encoders/li_encode_colqwen.py`) are PEP-508-marked to linux/x86_64, so they
   only resolve on that lane and CPU hosts stay clean.

> **One vector space per db.** Switching lanes (LateOn ↔ ColQwen) changes the
> embedder and therefore the vector space — MaxSim across two spaces is 0. Switching
> the model lane on an existing substrate requires a full re-encode. Pick the lane
> before you accumulate memory.

## Wiring it into Claude Code (`.mcp.json`)

The MCP server speaks JSON-RPC over **stdio** (not a TCP port). To point Claude
Code at the acc running inside the container, run a long-lived container and have
Claude Code launch the MCP client via `docker exec -i` against it.

1. Start the container detached, with the substrate mounted:

   ```bash
   docker run -d --name acc \
     -v "$PWD/.acc-data:/data" \
     -v acc-models:/models \
     acc:local
   ```

   (The default CMD serves MCP; for the `docker exec` wiring below you mainly need
   the embedder daemon warm inside the container, which the default entry starts.)

2. Add an MCP server to your project `.mcp.json` that execs into the container:

   ```json
   {
     "mcpServers": {
       "acc": {
         "command": "docker",
         "args": ["exec", "-i", "acc", "acc", "--db", "/data/acc.db", "mcp"]
       }
     }
   }
   ```

   `docker exec -i` keeps stdio open, which is exactly what the MCP transport
   needs. Reload MCP in Claude Code and the two verbs (`acc_retrieve`,
   `acc_act`) appear.

> The repo's own `.mcp.json` is the **native** wiring (`command: "acc"`). Do not
> overwrite it if you also run acc natively — use a separate project or a distinct
> server name for the containerized wiring.

## Honest limitations

- **Image size.** A Rust release build + Debian slim + uv + (on first run) the
  Python encoder env and the model download is **not small**. The model and uv
  caches live on the `/models` volume (paid once), but the base image itself is a
  few hundred MB before any model.
- **CPU model is text-only.** The default LateOn lane cannot do sight / multimodal.
  That needs the GPU/ColQwen lane.
- **GPU passthrough varies.** `--gpus all` needs the host `nvidia-container-toolkit`
  and a working NVIDIA driver. On Windows it needs WSL2 + the CUDA-on-WSL stack; on
  macOS there is **no** NVIDIA GPU passthrough at all (Apple Silicon → CPU floor in
  a container, or use the native installer for the mps lane).
- **Sandbox depends on the host.** `act exec` uses `bubblewrap`; unprivileged user
  namespaces must be permitted by the host/Docker runtime. If a runtime reports
  `sandboxed: false`, the host's userns or seccomp settings are the cause. The
  image does **not** run `--privileged` (that would weaken isolation).
- **No brain credential — nothing to mount.** The brain is the interactive session
  itself: when memory can't answer, `solve` returns a continuation frame that the
  MCP-attached session (Claude Code) deliberates and submits back via `continue`. No
  credential, OAuth token, or API key exists, in or out of the container. Headless
  (no session attached), a non-reflex solve checkpoints `waiting:brain` and is
  drained at the next interactive session (`acc frames`).
