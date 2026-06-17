# acc - container install (portability path)

> **Status - binary-based path restored; Docker-host smoke pending.** The
> Dockerfile now installs the public Linux release binary from GitHub Releases
> and verifies it against `sha256sums.txt`; it no longer tries to build private
> engine source. Before this path is promoted to a registry image, run the Docker
> build/run smoke below on a host with a Docker daemon.

This is the portability path for hosts where the native installer is a poor fit:

- **Docker-first Windows/macOS workflows** - run the Linux image through Docker
  Desktop.
- **Locked-down or no-root Linux boxes** - where native dependency installation
  is not acceptable.
- **Reproducible agent wiring** - the same image, mounted substrate, and MCP
  command on every Docker host.

Prefer the native installer on a Linux box you control, especially with a GPU. It
can use the host's full native model lane without Docker GPU-passthrough friction.

## Quick start

From this repository:

```bash
scripts/acc-docker.sh status
```

That command builds `acc:local` if needed, downloads the latest public Linux
release binary during the image build, verifies the SHA-256, creates owner-owned
host directories, and runs `acc status` inside the container.

Useful modes:

```bash
scripts/acc-docker.sh mcp          # stdio MCP server, suitable for agent config
scripts/acc-docker.sh start        # detached warm container named acc
scripts/acc-docker.sh stop         # remove the detached container
scripts/acc-docker.sh doctor       # run acc doctor inside the container
scripts/acc-docker.sh shell        # interactive shell inside the image
scripts/acc-docker.sh acc frames   # pass through to acc --db /data/acc.db ...
```

Pin a specific release instead of `latest`:

```bash
ACC_VERSION=v0.1.6 scripts/acc-docker.sh status
```

## Required smoke before registry submission

Run this on a real Docker host before treating the image as fully verified:

```bash
ACC_VERSION=v0.1.6 scripts/acc-docker.sh status
ACC_VERSION=v0.1.6 ACC_NO_EMBEDDER=1 scripts/acc-docker.sh doctor
ACC_VERSION=v0.1.6 scripts/acc-docker.sh start
docker exec -i acc acc --db /data/acc.db status
scripts/acc-docker.sh stop
```

If the host has no Docker daemon, the scripts can still be syntax-checked, but
the container path is not proven until the commands above build and run.

After this repo change is pushed, the manual GitHub Actions workflow
`Docker container smoke` runs the Docker build and no-model helper smoke on
GitHub's Docker host:

```bash
gh workflow run docker-container-smoke.yml -f acc_version=v0.1.6
```

That workflow intentionally sets `ACC_NO_EMBEDDER=1`, so it verifies the image,
release-binary install, helper wiring, mounted state, and detached `docker exec`
path without downloading model weights. Run the fuller local smoke above before
promoting a registry image that should prove model warm-up too.

## Environment knobs

| Env | Default | Meaning |
|---|---|---|
| `ACC_IMAGE` | `acc:local` | local image tag |
| `ACC_VERSION` | `latest` | release to install into the image (`latest`, `v0.1.6`, or `0.1.6`) |
| `ACC_DATA_DIR` | `$PWD/.acc-data` | host substrate dir mounted at `/data` |
| `ACC_MODELS_DIR` | `$PWD/.acc-models` | host model/uv cache dir mounted at `/models` |
| `ACC_CONTAINER` | `acc` | detached container name for `start` / `stop` |
| `ACC_NO_BUILD=1` | - | skip build and use an existing local image |
| `ACC_NO_PULL=1` | - | skip `docker pull debian:bookworm-slim` before build |
| `ACC_NO_GPU=1` | - | force CPU even if `nvidia-smi` exists |
| `ACC_PIN_MODEL` / `ACC_PIN_DEVICE` | `lightonai/LateOn` / `cpu` | override the pinned model lane |
| `ACC_FORCE_PIN=1` | - | rewrite an existing container model pin |
| `ACC_NO_EMBEDDER=1` | - | do not start the background embedder in `mcp` / `start` modes |

The helper runs the container as your host UID/GID and bind-mounts both state
directories, so `acc.db`, the model pin, and downloaded model caches remain
owner-owned files outside the image layer.

## The substrate survives rebuilds

The container declares two mounted state areas:

- **`/data`** - the substrate (`acc.db`) plus config (`XDG_CONFIG_HOME=/data/.config`).
- **`/models`** - HuggingFace model cache (`HF_HOME`) and uv cache.

Rebuild the image as often as needed. The live Work Model is the mounted
`acc.db`, not a layer inside the image.

One rule matters: one substrate belongs to one encoder vector space. Switching
from LateOn to a ColQwen lane changes the embedder, so an existing substrate
must be re-encoded before MaxSim retrieval is meaningful again.

## CPU default and optional GPU lane

The default pin is `lightonai/LateOn` on `cpu`. That is the broad compatibility
floor and avoids pulling a large multimodal GPU model on an ordinary Docker host.

The CPU floor is text-only. Sight / image retrieval requires a ColQwen lane.

For NVIDIA GPU passthrough:

1. Install the host `nvidia-container-toolkit`.
2. Confirm `nvidia-smi` works on the host.
3. Run with a GPU pin:

   ```bash
   ACC_PIN_MODEL=<colqwen-variant> ACC_PIN_DEVICE=cuda scripts/acc-docker.sh status
   ```

The helper only adds `--gpus all` after a quick Docker passthrough probe succeeds.
On macOS there is no NVIDIA passthrough; use the native installer for Apple
Silicon/MPS or stay on the container CPU floor.

## Wiring it into Claude Code

The MCP server speaks JSON-RPC over stdio. The simplest project wiring is to
have Claude Code launch the helper directly:

```json
{
  "mcpServers": {
    "acc-container": {
      "command": "/absolute/path/to/accreted-intelligence/scripts/acc-docker.sh",
      "args": ["mcp"]
    }
  }
}
```

That starts an ephemeral container process for the MCP session while preserving
state through the host bind mounts.

If you prefer a long-lived container:

```bash
scripts/acc-docker.sh start
```

Then wire Claude Code through `docker exec`:

```json
{
  "mcpServers": {
    "acc-container": {
      "command": "docker",
      "args": ["exec", "-i", "acc", "acc", "--db", "/data/acc.db", "mcp"]
    }
  }
}
```

Do not overwrite a native `.mcp.json` entry if you also run acc natively. Use a
separate server name, such as `acc-container`.

## Manual Docker commands

The helper is just a wrapper around these primitives:

```bash
docker build --build-arg ACC_VERSION=v0.1.6 -t acc:local .
mkdir -p .acc-data .acc-models
docker run --rm -it \
  -v "$PWD/.acc-data:/data" \
  -v "$PWD/.acc-models:/models" \
  acc:local status
```

For MCP over stdio:

```bash
docker run --rm -i \
  -v "$PWD/.acc-data:/data" \
  -v "$PWD/.acc-models:/models" \
  acc:local mcp
```

## Honest limitations

- **Docker-host verification is still required.** The repo path is binary-based
  now, but publish it as a registry image only after the smoke commands above
  pass on a Docker daemon.
- **First run may download large model and Python dependencies.** The `/models`
  bind mount caches that work after the first run.
- **CPU model is text-only.** Multimodal image retrieval needs a ColQwen lane.
- **GPU passthrough is host-dependent.** Docker needs the NVIDIA runtime/toolkit
  and a compatible host driver.
- **Sandboxing depends on Docker/userns settings.** `act exec` uses `bubblewrap`;
  if the host runtime blocks unprivileged user namespaces, sandbox diagnostics
  will report that honestly.
- **No brain credential exists.** The brain is the interactive MCP-attached
  session. Headless non-reflex `solve` work checkpoints until an interactive
  session drains the frame.
