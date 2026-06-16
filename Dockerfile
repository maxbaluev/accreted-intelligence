# acc - binary-release container
#
# This public repo does not ship engine source. The image therefore installs the
# verified Linux release binary from GitHub Releases instead of trying to build
# from Cargo.toml/src.
FROM debian:bookworm-slim

ARG ACC_VERSION=latest
ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      bubblewrap \
      ca-certificates \
      curl \
      python3 \
      python3-venv \
      tar \
 && rm -rf /var/lib/apt/lists/*

ENV UV_INSTALL_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN set -eu; \
    arch="${TARGETARCH:-$(uname -m)}"; \
    case "$arch" in \
      amd64|x86_64) release_target="x86_64-unknown-linux-musl" ;; \
      arm64|aarch64) release_target="aarch64-unknown-linux-musl" ;; \
      *) echo "unsupported Docker target arch: $arch" >&2; exit 1 ;; \
    esac; \
    if [ "$ACC_VERSION" = "latest" ]; then \
      tag="$(curl -fsSL --connect-timeout 15 --retry 2 --max-time 30 \
        -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: acc-docker-build' \
        https://api.github.com/repos/maxbaluev/accreted-intelligence/releases/latest \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n 1)"; \
    else \
      tag="v${ACC_VERSION#v}"; \
    fi; \
    case "$tag" in v[0-9]*) : ;; *) echo "could not resolve acc release tag" >&2; exit 1 ;; esac; \
    version="${tag#v}"; \
    artifact="acc-v${version}-${release_target}.tar.gz"; \
    base="https://github.com/maxbaluev/accreted-intelligence/releases/download/${tag}"; \
    tmp="$(mktemp -d)"; \
    curl -fsSL --connect-timeout 15 --retry 2 --max-time 180 -o "$tmp/$artifact" "$base/$artifact"; \
    curl -fsSL --connect-timeout 15 --retry 2 --max-time 60 -o "$tmp/sha256sums.txt" "$base/sha256sums.txt"; \
    awk -v a="$artifact" '$2 == a {print; found=1} END {exit found ? 0 : 1}' "$tmp/sha256sums.txt" > "$tmp/sha256-one.txt"; \
    (cd "$tmp" && sha256sum -c sha256-one.txt); \
    tar -xzf "$tmp/$artifact" -C "$tmp" acc; \
    install -m 0755 "$tmp/acc" /usr/local/bin/acc; \
    /usr/local/bin/acc --version; \
    rm -rf "$tmp"

COPY scripts/docker-entrypoint.sh /usr/local/bin/acc-entrypoint
RUN chmod +x /usr/local/bin/acc-entrypoint \
 && mkdir -p /data /models \
 && chmod 1777 /data /models

ENV ACC_DB=/data/acc.db \
    XDG_CONFIG_HOME=/data/.config \
    HF_HOME=/models/huggingface \
    UV_CACHE_DIR=/models/uv-cache \
    ACC_EMBEDDER_SOCK=/tmp/acc-embedder.sock \
    HOME=/data

VOLUME ["/data", "/models"]
WORKDIR /data

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD acc --db "$ACC_DB" status >/dev/null 2>&1 || exit 1

ENTRYPOINT ["acc-entrypoint"]
CMD ["mcp"]
