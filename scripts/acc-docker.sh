#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

IMAGE="${ACC_IMAGE:-acc:local}"
VERSION="${ACC_VERSION:-latest}"
DATA_DIR="${ACC_DATA_DIR:-$PWD/.acc-data}"
MODELS_DIR="${ACC_MODELS_DIR:-$PWD/.acc-models}"
CONTAINER="${ACC_CONTAINER:-acc}"

have() { command -v "$1" >/dev/null 2>&1; }

if ! have docker; then
  echo "acc-docker: docker not found; install Docker or use ./install.sh for the native path" >&2
  exit 1
fi

mkdir -p "$DATA_DIR" "$MODELS_DIR"

if [ "${ACC_NO_BUILD:-0}" != "1" ]; then
  if [ "${ACC_NO_PULL:-0}" != "1" ]; then
    docker pull debian:bookworm-slim >/dev/null || true
  fi
  docker build --build-arg "ACC_VERSION=$VERSION" -t "$IMAGE" .
fi

gpu_args=()
if [ "${ACC_NO_GPU:-0}" != "1" ] && have nvidia-smi; then
  if docker run --rm --gpus all --entrypoint true "$IMAGE" >/dev/null 2>&1; then
    gpu_args=(--gpus all)
  else
    echo "acc-docker: NVIDIA detected but Docker GPU passthrough is unavailable; using CPU" >&2
  fi
fi

uidgid="$(id -u):$(id -g)"
common_args=(
  -e ACC_DB=/data/acc.db
  -e XDG_CONFIG_HOME=/data/.config
  -e HF_HOME=/models/huggingface
  -e UV_CACHE_DIR=/models/uv-cache
  -e ACC_EMBEDDER_SOCK=/tmp/acc-embedder.sock
  -v "$DATA_DIR:/data"
  -v "$MODELS_DIR:/models"
  --user "$uidgid"
)

for env_name in ACC_PIN_MODEL ACC_PIN_DEVICE ACC_FORCE_PIN ACC_NO_EMBEDDER; do
  if [ -n "${!env_name+x}" ]; then
    common_args+=(-e "$env_name=${!env_name}")
  fi
done

mode="${1:-mcp}"
case "$mode" in
  start)
    shift || true
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    exec docker run -d --name "$CONTAINER" "${gpu_args[@]}" "${common_args[@]}" "$IMAGE" start "$@"
    ;;
  stop)
    exec docker rm -f "$CONTAINER"
    ;;
  shell|bash|sh)
    shift || true
    exec docker run --rm -it "${gpu_args[@]}" "${common_args[@]}" "$IMAGE" "$mode" "$@"
    ;;
  mcp)
    shift || true
    exec docker run --rm -i "${gpu_args[@]}" "${common_args[@]}" "$IMAGE" mcp "$@"
    ;;
  *)
    shift || true
    exec docker run --rm "${gpu_args[@]}" "${common_args[@]}" "$IMAGE" "$mode" "$@"
    ;;
esac
