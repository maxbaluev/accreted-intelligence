# acc — TIER C universal container (runs anywhere Docker runs)
# =============================================================================
# The pragmatic cross-OS answer: a reproducible Linux x86_64 image you can run on
# any host with Docker (incl. Windows / macOS via Docker Desktop, and locked-down
# boxes where the native install.sh can't fetch system deps). The owner SUBSTRATE
# (acc.db) lives on a MOUNTED VOLUME at /data — owner-owned, survives rebuilds.
#
# DEFAULT MODEL LANE: the universal CPU floor — LateOn (text-only, dim-128). This
#   is the broad-compat lane: it works on ANY Docker host with NO GPU. The image
#   pins LateOn/cpu on first run (see entrypoint), so the embedder never tries to
#   pull a multi-GB GPU model on a CPU-only host.
#
# OPTIONAL GPU / ColQwen lane (linux-x86_64 + NVIDIA only): run the image with
#   `--gpus all` AND set `ACC_PIN_MODEL`/`ACC_PIN_DEVICE` (or run `acc pin`
#   inside the container against the GPU). The ColQwen AWQ encoder deps in
#   encoders/li_encode_colqwen.py are PEP-508-marked to linux/x86_64, so they
#   only resolve on that lane; CPU hosts stay on LateOn. NVIDIA passthrough
#   additionally needs the host nvidia-container-toolkit installed — that is a
#   host concern, not something this image can provide.
#
# Two named volumes the owner controls:
#   /data        — the substrate (acc.db) + the model pin (XDG_CONFIG_HOME). OWNER-OWNED.
#   /models      — the HuggingFace model cache (HF_HOME). Survives rebuilds so the
#                  several-GB first-run download is paid once.
#
# NOTE: this image needs a real `docker build` (CI / owner) to fully verify — it
#   cannot be built in the authoring sandbox (no network / no daemon).
# =============================================================================

# ---------------------------------------------------------------------------
# STAGE 1 — build: compile the acc binary with the pinned toolchain (1.96).
# On unix rusqlite LINKS the prebuilt system libsqlite3 (libsqlite3-dev below),
# skipping the bundled SQLite-C amalgamation compile (~96s); the encoders/ dir is
# include_str!'d into the binary at compile time, so it must be present in the build
# context.
# ---------------------------------------------------------------------------
FROM rust:1.96-bookworm AS build
WORKDIR /app

# Copy the crate. Cargo.lock is committed → a reproducible, locked resolve.
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY encoders ./encoders

# System SQLite dev lib (header + .so) — rusqlite links it instead of compiling the
# bundled amalgamation. pkg-config lets libsqlite3-sys discover it.
RUN apt-get update \
 && apt-get install -y --no-install-recommends pkg-config libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/*

# Release build (LTO + codegen-units=1 per Cargo.toml [profile.release]).
# --locked: never let a fresh resolve drift from the committed Cargo.lock.
RUN cargo build --release --locked

# ---------------------------------------------------------------------------
# STAGE 2 — runtime: slim Debian + the runtime deps the binary needs.
#   bubblewrap     — the sandbox for `act exec` runtimes (network-isolated, RO).
#   ca-certificates — TLS for the brain client + HuggingFace model download.
#   curl           — fetches the astral `uv` installer (drives the encoder env).
#   python3        — the encoder subprocess interpreter (uv manages its env).
# The encoder Python deps themselves are NOT baked in: `uv` resolves them on the
# first embedder run (PEP-723 inline metadata in encoders/*.py), cached into the
# /models + uv cache volumes so the cost is paid once.
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bubblewrap \
      ca-certificates \
      curl \
      python3 \
      python3-venv \
      libsqlite3-0 \
 && rm -rf /var/lib/apt/lists/*
# libsqlite3-0 — the runtime SQLite shared lib the binary now dynamically links
# (unix links system libsqlite3 instead of bundling the amalgamation).

# Install uv (astral) system-wide so any user can drive the encoder env.
# UV_INSTALL_DIR puts it on a stable PATH location.
ENV UV_INSTALL_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# The acc binary (the only build artifact we need).
COPY --from=build /app/target/release/acc /usr/local/bin/acc
# encoders/ is compiled INTO the binary; we still copy it for reference/parity
# and so an operator can inspect the PEP-723 headers inside the container.
COPY --from=build /app/encoders /opt/acc/encoders

# The container entry (sets up the substrate + pin, then serves MCP / status / shell).
COPY scripts/docker-entrypoint.sh /usr/local/bin/acc-entrypoint
RUN chmod +x /usr/local/bin/acc-entrypoint

# -- Owner-owned, rebuild-surviving state ------------------------------------
# /data:   the substrate db + the model pin (XDG_CONFIG_HOME → /data/.config).
# /models: the HuggingFace cache (HF_HOME) — the model download lives here.
# Declared as VOLUMEs so they persist outside the container layer; the owner
# bind-mounts host dirs over them (scripts/acc-docker.sh does -v $PWD/.acc-data:/data).
ENV ACC_DB=/data/acc.db \
    XDG_CONFIG_HOME=/data/.config \
    HF_HOME=/models/huggingface \
    UV_CACHE_DIR=/models/uv-cache \
    ACC_EMBEDDER_SOCK=/tmp/acc-embedder.sock
RUN mkdir -p /data /models
VOLUME ["/data", "/models"]

WORKDIR /data

# Health: a substrate round-trip. `acc status` is the doctor-equivalent — it
# reports substrate, embedder daemon state, the session brain lane, and the next
# step, and exits non-zero only on a hard substrate fault.
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD acc --db "$ACC_DB" status >/dev/null 2>&1 || exit 1

# DEFAULT: print status (the doctor-equivalent) then serve the MCP server on
# stdio. Pass `status`, `shell`, `embedder`, or any acc args to override (see
# scripts/docker-entrypoint.sh). MCP is stdio JSON-RPC — wire Claude Code to it
# with `docker exec -i <container> acc --db /data/acc.db mcp` (see the install doc).
ENTRYPOINT ["acc-entrypoint"]
CMD ["mcp"]
