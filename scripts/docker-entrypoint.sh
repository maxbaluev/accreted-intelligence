#!/bin/sh
set -eu

: "${ACC_DB:=/data/acc.db}"
: "${XDG_CONFIG_HOME:=/data/.config}"
: "${HF_HOME:=/models/huggingface}"
: "${UV_CACHE_DIR:=/models/uv-cache}"
: "${ACC_EMBEDDER_SOCK:=/tmp/acc-embedder.sock}"
: "${HOME:=/data}"

export ACC_DB XDG_CONFIG_HOME HF_HOME UV_CACHE_DIR ACC_EMBEDDER_SOCK HOME

mkdir -p /data /models "$XDG_CONFIG_HOME/acc" "$HF_HOME" "$UV_CACHE_DIR"

pin_requested=0
if [ "${ACC_PIN_MODEL+x}" = x ] || [ "${ACC_PIN_DEVICE+x}" = x ]; then
  pin_requested=1
fi
: "${ACC_PIN_MODEL:=lightonai/LateOn}"
: "${ACC_PIN_DEVICE:=cpu}"

pin_path="$XDG_CONFIG_HOME/acc/model.json"
if [ "${ACC_FORCE_PIN:-0}" = "1" ] || [ "$pin_requested" = "1" ] || [ ! -s "$pin_path" ]; then
  acc pin "$ACC_PIN_MODEL" "$ACC_PIN_DEVICE" >/dev/null 2>&1 || true
fi

start_embedder() {
  [ "${ACC_NO_EMBEDDER:-0}" = "1" ] && return 0
  if [ -S "$ACC_EMBEDDER_SOCK" ]; then
    return 0
  fi
  acc embedder >/tmp/acc-embedder.log 2>&1 &
}

cmd="${1:-mcp}"
case "$cmd" in
  mcp)
    start_embedder
    exec acc --db "$ACC_DB" mcp
    ;;
  start)
    start_embedder
    exec tail -f /dev/null
    ;;
  status)
    exec acc --db "$ACC_DB" status
    ;;
  doctor)
    exec acc --db "$ACC_DB" doctor
    ;;
  shell|sh)
    exec /bin/sh
    ;;
  bash)
    exec /bin/bash
    ;;
  embedder)
    exec acc embedder
    ;;
  acc)
    shift
    exec acc --db "$ACC_DB" "$@"
    ;;
  *)
    exec acc --db "$ACC_DB" "$@"
    ;;
esac
