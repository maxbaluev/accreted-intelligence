#!/usr/bin/env bash
# (run under bash — uses bash arrays + $'…' escapes. The bootstrap checks `command -v bash`
#  before exec'ing this file, so a busybox/dash-only host fails early with a clear message
#  rather than mid-parse on the first array.)
# acc installer — deterministic PHASE-MACHINE. Fresh machine → working organism, on any
# POSIX OS. Numbered, idempotent, individually re-runnable phases; resume is structural
# (each phase checks its own postcondition first — no state file). Drives a 3-model tier
# ladder from probed host facts (the same signals src/selector.rs uses: nvidia-smi VRAM,
# uname OS/arch, total RAM), so the embedder lane is chosen, not guessed.
#
# AUTO-INSTALLS every dependency (Rust, uv, python3, sandbox + browser system libs), installs
# `acc` (phase 3 fetches the sha256-VERIFIED prebuilt release binary first — no rustup
# needed when a release is reachable — and falls back to a source build otherwise),
# materializes the encoder env, pins the host-selected model, PREFETCHES the model
# weights into the HF cache with VISIBLE progress (phase 6: uv run encoders/prefetch.py
# — snapshot_download's native resume + cache reuse; a network failure skips, the daemon
# still downloads lazily on first start), brings up the warm embedder daemon AND the
# host Camoufox browser daemon, seeds the core runtimes, wires .mcp.json + hooks, and
# verifies with `acc doctor`.
#
# TIER LADDER (owner:52bd4f391a2ec9f6 / src/selector.rs — multimodal preferred, LateOn last):
#   linux x86_64 + NVIDIA, free VRAM ≥10GB → ColQwen3 8B-AWQ on cuda  (best multimodal)
#   linux x86_64 + NVIDIA, free VRAM ≥5GB  → ColQwen3 4B-AWQ on cuda
#   linux x86_64, RAM ≥24/12GB             → ColQwen3 8B/4B-AWQ on cpu (slow, multimodal)
#   darwin (Apple Silicon), RAM ≥32/16GB   → ColQwen3 8B/4B full bf16 on mps
#   linux aarch64 / Intel-mac, RAM ≥32/16GB→ ColQwen3 8B/4B full bf16 on cpu
#   any NVIDIA GPU, free VRAM ≥2GB         → LateOn text-only ON cuda (small ~0.6GB model fits a
#                                            ~4GB GPU; runs on the GPU, not a slow cpu encode)
#   anything below the floors                → LateOn text-only (cpu, or mps ≥16GB)
#   DISK FLOOR (every rung): expected model download (static sizes mirrored from
#     encoders/prefetch.py) + 2048MB headroom must fit the free disk at the HF cache
#     (HF_HOME, default ~/.cache/huggingface), else the pick degrades one rung at a
#     time (8b→4b→lateon) with the honest 'disk floor: need ~XGB, have ~YGB' reason
#     in TIER_REASON — same honesty as the VRAM floors.
#   nothing viable natively (Windows / no-root / locked-down) → the CONTAINER tier path
#     (docs/INSTALL_CONTAINER.md). Override the lane with ACC_TIER=<8b-awq|4b-awq|8b-cpu|
#     4b-cpu|8b-full|4b-full|lateon|container>.
#
# UPDATE PATH: re-running on an EXISTING install (acc on PATH and/or a substrate at the
# db path) is the update — same idempotent phases (satisfied deps skip fast), the binary
# is rebuilt/reinstalled, the model pin is re-written ONLY if the host's pick changed,
# the user's acc.db is NEVER modified or deleted (schema migrations run inside the
# binary on first open), and the run ends with `acc doctor` + "updated <old> → <new>".
#
# Usage:  ./install.sh [substrate-db-path]   (default: ./acc.db)
#         ./install.sh --dry-run             walk every phase, mutate NOTHING, report what
#                                            WOULD happen (the self-test)
#         ./install.sh --json                one JSON line per phase {phase,status,detail,
#                                            next}; final line = overall verdict + the
#                                            `acc doctor --json` handoff (Claude-as-installer)
#         ./install.sh --dry-run --json      both: machine-readable dry walk, exit 0
#         ./install.sh --persist-path        OPT-IN: append the ~/.local/bin export to your
#                                            shell rc (~/.bashrc or ~/.profile) so a NEW
#                                            terminal finds `acc`. Default is advisory-print
#                                            only — the installer NEVER edits your rc unless
#                                            you pass this flag.
#   Env: ACC_NO_BROWSER=1   skip the browser capability
#        ACC_NONINTERACTIVE=1 never prompt; skip sudo steps, just warn
#        ACC_TIER=<lane>    force the embedder lane (skip the host probe's pick)
#        ACC_INSTALL=source skip the phase-3 prebuilt-release fetch; always build from source
#        ACC_BROWSER_HOME / ACC_BROWSER_SOCK   browser env overrides
#
# Windows: native installs use install.ps1 (the same phase-machine in PowerShell). This
# POSIX script is the unix lane (unix sockets, bwrap, /tmp); the container is the fallback
# for locked-down/no-root hosts. On a host where no native tier fits, the machine prints
# the container path rather than installing a broken native lane.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$PWD"

# ── flags ───────────────────────────────────────────────────────────────────────────
DRY_RUN=0
JSON=0
PERSIST_PATH=0
ARGS=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    --json)    JSON=1 ;;
    --persist-path) PERSIST_PATH=1 ;;
    -h|--help) sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d'; exit 0 ;;
    *)         ARGS+=("$a") ;;
  esac
done
# DB default is set AFTER OS is known (below) so a release install (non-git) writes the db
# to the per-OS CANONICAL DATA DIR — the SAME path `db::canonical_db_path` resolves a bare
# `acc.db` to outside a git repo. Otherwise bare `acc report`/`acc doctor` (read-only, cannot
# create) look in the canonical dir while the installer wrote it under $PWD — the exact split
# that hard-FAILED for a real user. An explicit path arg ($ARGS[0]) still wins.
DB_ARG="${ARGS[0]:-}"

EMB_SOCK="/tmp/acc-embedder.sock"
ENCODER_SCRIPT_FULL="$REPO/encoders/li_encode.py"           # LateOn / full-bf16 lanes
ENCODER_SCRIPT_AWQ="$REPO/encoders/li_encode_colqwen.py"    # AWQ lanes (linux x86_64)
BROWSER_HOME="${ACC_BROWSER_HOME:-$HOME/.local/share/acc/browser}"
BROWSER_VENV="$BROWSER_HOME/venv"

OS="$(uname -s)"
ARCH="$(uname -m)"

# The per-OS CANONICAL DATA DIR — mirrors `crate::platform::data_dir()` (linux/other:
# ${XDG_DATA_HOME:-~/.local/share}/acc; macOS: ~/Library/Application Support/acc). The
# substrate db default lives here so the installer, the wired MCP (relative `acc.db` →
# same canonical dir off-git via db::canonical_db_path), and bare read-only `acc` commands
# all agree on ONE db. (The ACC_DATA_DIR used later for plugins recomputes the same value.)
case "$OS" in
  Darwin) CANON_DATA_DIR="$HOME/Library/Application Support/acc" ;;
  *)      CANON_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/acc" ;;
esac
DB="${DB_ARG:-$CANON_DATA_DIR/acc.db}"

# REPO_IS_CLONE — is $REPO the HIDDEN bootstrap clone (~/.local/share/acc/src, the dir the
# one-liner clones into and cd's to), rather than a real project the user works in? The
# bootstrap clones to ${ACC_SRC:-$CANON_DATA_DIR/src} and exec's this script from there, so
# $REPO == that path on the public one-liner path. When $REPO is the clone, we must NOT wire
# Claude-Code PROJECT files (.mcp.json / .claude/settings.json) INTO it — the user never opens
# Claude Code in the clone dir, so that wiring is dead. The one-Work-Model pivot makes those
# project files unnecessary anyway: phase 13 (`acc hosts-sync`) wires Claude Code GLOBALLY
# (~/.claude.json + ~/.claude/settings.json on the one global db), so acc works in every
# directory. A genuine dev clone of the repo (a real project the dev works in) is NOT under
# the data dir, so this stays false there (its own tracked project files are left as-is).
CLONE_DIR="${ACC_SRC:-$CANON_DATA_DIR/src}"
if [ "$REPO" = "$CLONE_DIR" ] || [ "$REPO" = "$CANON_DATA_DIR/src" ]; then
  REPO_IS_CLONE=1
else
  REPO_IS_CLONE=0
fi

# ── interactivity + color/Unicode gating ──────────────────────────────────────────────
# NON-INTERACTIVE = stdout is not a TTY (piped / captured by an agent's Bash tool / a
# `curl … | sh` redirect), OR the caller set ACC_NONINTERACTIVE=1. In this mode the
# installer must NEVER block on a long synchronous wait (a coding-agent shell has a command
# TIMEOUT that would kill a half-finished install) — the embedder warm-wait is skipped and
# the model warms in the background. It also drives the output surface below: an agent that
# CAPTURES stdout must receive plain ASCII, never raw ANSI escape codes or Unicode glyphs
# (they show up as literal \033[..m / mojibake and corrupt the captured guidance).
if [ "${ACC_NONINTERACTIVE:-0}" = "1" ] || ! [ -t 1 ]; then NONINTERACTIVE=1; else NONINTERACTIVE=0; fi
# USE_COLOR: only when stdout is a real TTY AND NO_COLOR is unset (https://no-color.org).
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then USE_COLOR=1; else USE_COLOR=0; fi
# Color codes + status glyphs collapse to empty / ASCII when color is off. The glyph
# fallbacks ([ok]/[!]/>) are pure ASCII so a captured stream stays clean and readable.
if [ "$USE_COLOR" = "1" ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
  G_OK=$'\033[32m✓\033[0m'; G_WARN=$'\033[33m!\033[0m'; G_STEP=$'\033[1m▸ '
else
  C_GREEN=''; C_YELLOW=''; C_BOLD=''; C_RESET=''
  G_OK='[ok]'; G_WARN='[!]'; G_STEP='> '
fi

# ── output surface ────────────────────────────────────────────────────────────────────
# Human mode → pretty status lines. JSON mode → exactly one object per phase + a final
# verdict object. Everything that would clutter the JSON stream goes to stderr in JSON mode.
# Color/glyphs are gated on USE_COLOR above so a captured (non-TTY) stream is plain ASCII.
have() { command -v "$1" >/dev/null 2>&1; }
log()  { [ "$JSON" = "1" ] && printf '%s\n' "$*" >&2 || printf '  %s\n' "$*"; }
say()  { log "$@"; }
ok()   { [ "$JSON" = "1" ] && printf '  %s %s\n' "$G_OK" "$*" >&2 || printf '  %s %s\n' "$G_OK" "$*"; }
warn() { [ "$JSON" = "1" ] && printf '  %s %s\n' "$G_WARN" "$*" >&2 || printf '  %s %s\n' "$G_WARN" "$*"; }
step() { [ "$JSON" = "1" ] && printf '\n%s%s%s\n' "$G_STEP" "$*" "$C_RESET" >&2 || printf '\n%s%s%s\n' "$G_STEP" "$*" "$C_RESET"; }

# json_phase NAME STATUS DETAIL NEXT — emit one machine-readable phase line (JSON mode only).
# STATUS ∈ ok|failed|skipped|would. DETAIL/NEXT are free text (newlines/quotes escaped).
json_str() {
  # Bootstrap-safe: phase 1 may need to install python3, so JSON output cannot depend on
  # python3 already existing. awk is part of the POSIX base lane this shell installer needs.
  printf '%s' "$1" | awk '
    BEGIN { printf "\"" }
    {
      gsub(/\\/,"\\\\")
      gsub(/"/,"\\\"")
      gsub(/\t/,"\\t")
      gsub(/\r/,"\\r")
      if (NR > 1) printf "\\n"
      printf "%s", $0
    }
    END { printf "\"" }
  '
}
json_phase() {
  [ "$JSON" = "1" ] || return 0
  local name="$1" status="$2" detail="$3" next="${4:-}"
  local jname jstatus jdetail jnext
  jname="$(json_str "$name")"
  jstatus="$(json_str "$status")"
  jdetail="$(json_str "$detail")"
  if [ -n "$next" ]; then jnext="$(json_str "$next")"; else jnext="null"; fi
  printf '{"phase":%s,"status":%s,"detail":%s,"next":%s}\n' "$jname" "$jstatus" "$jdetail" "$jnext"
}

# phase_result NAME STATUS DETAIL [NEXT] — single funnel: pretty line (human) OR json line.
phase_result() {
  local name="$1" status="$2" detail="$3" next="${4:-}"
  if [ "$JSON" = "1" ]; then
    json_phase "$name" "$status" "$detail" "$next"
  else
    case "$status" in
      ok)      ok "$detail" ;;
      would)   say "WOULD: $detail" ;;
      skipped) say "skip: $detail" ;;
      failed)  warn "$detail"; [ -n "$next" ] && warn "→ $next" ;;
    esac
  fi
}

# In a real run, mutating actions execute; in --dry-run they are reported, never run.
# act "<human description>" cmd args…   — runs cmd unless DRY_RUN; returns cmd's status.
act() {
  local desc="$1"; shift
  if [ "$DRY_RUN" = "1" ]; then
    say "WOULD: $desc"
    return 0
  fi
  "$@"
}

# ── sudo wrapper ──────────────────────────────────────────────────────────────────────
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  # Only use interactive sudo when stdin is a real TTY. A piped `curl … | sh` install has no TTY,
  # so sudo would block forever on a password prompt nobody can answer (it leaked
  # `[sudo] password for <user>:` into a brand-new user's run). No TTY → leave SUDO empty → the
  # sudo step fails fast and prints its actionable "run: sudo … " guidance instead of hanging.
  if have sudo && [ "${ACC_NONINTERACTIVE:-0}" != "1" ] && [ -t 0 ]; then SUDO="sudo"; fi
fi
maybe_sudo() {
  if [ "$DRY_RUN" = "1" ]; then say "WOULD (sudo): $*"; return 0; fi
  if [ -n "$SUDO" ]; then $SUDO "$@"; elif [ "$(id -u)" -eq 0 ]; then "$@";
  else warn "skipping (needs root, no sudo): $*"; return 1; fi
}

PKG=""
case "$OS" in
  Linux)  for m in apt-get dnf pacman zypper apk; do have "$m" && { PKG="$m"; break; }; done ;;
  Darwin) have brew && PKG="brew" ;;
esac
pkg_install() {
  local p="$1"
  case "$PKG" in
    apt-get) maybe_sudo apt-get update -qq && maybe_sudo apt-get install -y -qq "$p" ;;
    dnf)     maybe_sudo dnf install -y -q "$p" ;;
    pacman)  maybe_sudo pacman -Sy --noconfirm "$p" ;;
    zypper)  maybe_sudo zypper --non-interactive install -y "$p" ;;
    apk)     maybe_sudo apk add --no-progress "$p" ;;
    brew)    [ "$DRY_RUN" = "1" ] && { say "WOULD: brew install $p"; return 0; }; brew install "$p" ;;
    *) if [ "$OS" = "Darwin" ]; then
         warn "macOS: no Homebrew — cannot auto-install '$p'. Install Homebrew (https://brew.sh) then re-run ./install.sh, or install '$p' manually."
       else
         warn "no known package manager — install '$p' manually"
       fi
       return 1 ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 0 — probe + tier select. Mirrors src/selector.rs's signals SHELL-SIDE (no Rust
# changes): nvidia-smi free VRAM, uname OS/arch, total RAM — plus the DISK FLOOR: free
# disk at the HF cache must fit the pick's expected download + headroom, else the pick
# degrades one rung at a time. Sets TIER / MODEL_ID / DEVICE / ENCODER_SCRIPT and
# TIER_REASON. Pure read — runs identically in dry-run and real mode.
# ════════════════════════════════════════════════════════════════════════════════════════
# Selector floors (MB) — kept in lockstep with src/selector.rs.
AWQ_8B_VRAM=10000; AWQ_4B_VRAM=5000
AWQ_8B_CPU_RAM=24000; AWQ_4B_CPU_RAM=12000
FULL_8B_RAM=32000;  FULL_4B_RAM=16000
# Small-VRAM cuda floor (MB): LateOn (dim-128, ~0.6GB) runs ON cuda when a GPU is present but
# below every ColQwen floor — mirrors src/selector.rs LATEON_MIN_VRAM_MB so phase 0 and `acc
# pin` agree (a ~4GB GPU runs the small model on the GPU, not a 10–100× slower cpu encode).
LATEON_VRAM=2000

# DISK FLOOR (MB) — model weights land in the HF cache; the pick's expected download
# (static sizes mirrored from encoders/prefetch.py STATIC_EXPECTED_BYTES) + headroom
# must fit the free disk there, else the ladder degrades ONE rung at a time
# (8b→4b→lateon). Same honesty as the VRAM floors: a host with 6GB free disk must
# never select an 8.3GB tier and die mid-download.
MODEL_MB_8B_FULL=8300; MODEL_MB_4B_FULL=4200   # full bf16 (~8.3GB / ~4.2GB)
MODEL_MB_8B_AWQ=6000;  MODEL_MB_4B_AWQ=3000    # AWQ (~6GB / ~3GB)
MODEL_MB_LATEON=600                            # LateOn text-only (~0.6GB)
DISK_HEADROOM_MB=2048

hf_cache_dir() {
  # Where snapshot_download lands weights: HF_HOME wins; unix default ~/.cache/huggingface.
  if [ -n "${HF_HOME:-}" ]; then printf '%s\n' "$HF_HOME"; else printf '%s\n' "$HOME/.cache/huggingface"; fi
}

probe_disk_free_mb() {
  # Free MB on the filesystem that will hold the HF cache. The cache dir may not exist
  # yet on a fresh host — walk up to the nearest existing ancestor (terminates at /).
  local d; d="$(hf_cache_dir)"
  while [ ! -d "$d" ]; do d="$(dirname "$d")"; done
  df -Pk "$d" 2>/dev/null | awk 'NR==2 {print int($4/1024)}'
}

# expected_model_mb TIER — the static expected download for a tier's pinned model (MB).
expected_model_mb() {
  case "$1" in
    8b-awq|8b-cpu) echo "$MODEL_MB_8B_AWQ" ;;
    4b-awq|4b-cpu) echo "$MODEL_MB_4B_AWQ" ;;
    8b-full)       echo "$MODEL_MB_8B_FULL" ;;
    4b-full)       echo "$MODEL_MB_4B_FULL" ;;
    lateon)        echo "$MODEL_MB_LATEON" ;;
    *)             echo 0 ;;
  esac
}

mb_to_gb() { awk -v m="$1" 'BEGIN{printf "%.1f", m/1024}'; }

probe_vram_free_mb() {
  # Free VRAM a FRESH install would see. The real install probes BEFORE the daemon starts
  # (phase ordering), so free≈total. But on an already-installed host (re-run / dry-run) the
  # live acc embedder is HOLDING the GPU — its socket exists — so reading "free" would lie
  # low and drop the tier. When that daemon is present, the honest fresh-install figure is
  # TOTAL VRAM (the daemon would not be running during a real probe). Deterministic + honest.
  have nvidia-smi || { echo 0; return; }
  local free total
  free="$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')"
  total="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')"
  [ -z "$free" ] && free=0
  [ -z "$total" ] && total=0
  if [ -S "$EMB_SOCK" ] && [ "$total" -gt 0 ]; then echo "$total"; else echo "$free"; fi
}

read_total_ram_mb() {
  if [ -r /proc/meminfo ]; then
    awk '/^MemTotal:/ {print int($2/1024); exit}' /proc/meminfo
  elif have sysctl; then
    local b; b="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"; echo $(( b / 1024 / 1024 ))
  else echo 0; fi
}

# select_tier — walk the ladder top-down; the FIRST rung the host honestly clears wins.
# Sets TIER, MODEL_ID, DEVICE, ENCODER_SCRIPT, TIER_REASON. Honors ACC_TIER override.
select_tier() {
  local gpu=0 vram ram
  TIER_FORCED=0
  vram="$(probe_vram_free_mb)"; ram="$(read_total_ram_mb)"
  [ "$vram" -gt 0 ] && gpu=1
  local awq=0; [ "$OS" = "Linux" ] && [ "$ARCH" = "x86_64" ] && awq=1
  local mps=0; [ "$OS" = "Darwin" ] && { [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; } && mps=1

  PROBE_GPU="$gpu"; PROBE_VRAM="$vram"; PROBE_RAM="$ram"; PROBE_AWQ="$awq"; PROBE_MPS="$mps"

  # Explicit override — owner pins the lane, skip the probe's pick.
  local forced="${ACC_TIER:-}"
  if [ -n "$forced" ]; then
    case "$forced" in
      8b-awq)  TIER=8b-awq;  MODEL_ID=TomoroAI/tomoro-ai-colqwen3-embed-8b-awq; DEVICE=cuda; ENCODER_SCRIPT="$ENCODER_SCRIPT_AWQ" ;;
      4b-awq)  TIER=4b-awq;  MODEL_ID=TomoroAI/tomoro-ai-colqwen3-embed-4b-awq; DEVICE=cuda; ENCODER_SCRIPT="$ENCODER_SCRIPT_AWQ" ;;
      8b-cpu)  TIER=8b-cpu;  MODEL_ID=TomoroAI/tomoro-ai-colqwen3-embed-8b-awq; DEVICE=cpu;  ENCODER_SCRIPT="$ENCODER_SCRIPT_AWQ" ;;
      4b-cpu)  TIER=4b-cpu;  MODEL_ID=TomoroAI/tomoro-ai-colqwen3-embed-4b-awq; DEVICE=cpu;  ENCODER_SCRIPT="$ENCODER_SCRIPT_AWQ" ;;
      8b-full) TIER=8b-full; MODEL_ID=TomoroAI/tomoro-colqwen3-embed-8b; DEVICE="$([ "$mps" = 1 ] && echo mps || echo cpu)"; ENCODER_SCRIPT="$ENCODER_SCRIPT_FULL" ;;
      4b-full) TIER=4b-full; MODEL_ID=TomoroAI/tomoro-colqwen3-embed-4b; DEVICE="$([ "$mps" = 1 ] && echo mps || echo cpu)"; ENCODER_SCRIPT="$ENCODER_SCRIPT_FULL" ;;
      lateon)  TIER=lateon;  MODEL_ID=lightonai/LateOn; DEVICE="$([ "$gpu" = 1 ] && [ "$vram" -ge "$LATEON_VRAM" ] && echo cuda || { [ "$mps" = 1 ] && [ "$ram" -ge "$FULL_4B_RAM" ] && echo mps || echo cpu; })"; ENCODER_SCRIPT="$ENCODER_SCRIPT_FULL" ;;
      container) TIER=container; MODEL_ID=""; DEVICE=""; ENCODER_SCRIPT="" ;;
      *) warn "unknown ACC_TIER='$forced' — ignoring, falling back to host probe"; forced="" ;;
    esac
    if [ -n "$forced" ]; then TIER_FORCED=1; TIER_REASON="forced via ACC_TIER=$forced"; return; fi
  fi

  # 1–2: AWQ on cuda — linux x86_64 + NVIDIA; best multimodal per VRAM.
  if [ "$awq" = 1 ] && [ "$gpu" = 1 ] && [ "$vram" -ge "$AWQ_8B_VRAM" ]; then
    TIER=8b-awq; MODEL_ID=TomoroAI/tomoro-ai-colqwen3-embed-8b-awq; DEVICE=cuda; ENCODER_SCRIPT="$ENCODER_SCRIPT_AWQ"
    TIER_REASON="GPU ${vram}MB free ≥ ${AWQ_8B_VRAM} → ColQwen3-8B AWQ on cuda (best multimodal)"; return
  fi
  if [ "$awq" = 1 ] && [ "$gpu" = 1 ] && [ "$vram" -ge "$AWQ_4B_VRAM" ]; then
    TIER=4b-awq; MODEL_ID=TomoroAI/tomoro-ai-colqwen3-embed-4b-awq; DEVICE=cuda; ENCODER_SCRIPT="$ENCODER_SCRIPT_AWQ"
    TIER_REASON="GPU ${vram}MB free ≥ ${AWQ_4B_VRAM} (< ${AWQ_8B_VRAM} for 8B) → ColQwen3-4B AWQ on cuda"; return
  fi
  # 3–4: AWQ on cpu — ONLY when a cuda GPU is PRESENT but its free VRAM is under the tier floor
  # (degraded; the device recovers to cuda when VRAM frees). A host with NO GPU at all falls
  # through to LateOn (rung 9) — a light, fast first run, NOT a multi-GB ColQwen-on-cpu grind
  # (the new-user cross-OS default; multimodal-on-cpu stays one ACC_TIER=8b-cpu/4b-cpu away).
  # Mirrors src/selector.rs select_model_for_os so phase 0 and `acc pin` agree.
  if [ "$gpu" = 1 ] && [ "$awq" = 1 ] && [ "$ram" -ge "$AWQ_8B_CPU_RAM" ]; then
    TIER=8b-cpu; MODEL_ID=TomoroAI/tomoro-ai-colqwen3-embed-8b-awq; DEVICE=cpu; ENCODER_SCRIPT="$ENCODER_SCRIPT_AWQ"
    TIER_REASON="cuda present but free VRAM ${vram}MB under its tier floor, RAM ${ram}MB ≥ ${AWQ_8B_CPU_RAM} → ColQwen3-8B AWQ on cpu (degraded; recovers to cuda when VRAM frees)"; return
  fi
  if [ "$gpu" = 1 ] && [ "$awq" = 1 ] && [ "$ram" -ge "$AWQ_4B_CPU_RAM" ]; then
    TIER=4b-cpu; MODEL_ID=TomoroAI/tomoro-ai-colqwen3-embed-4b-awq; DEVICE=cpu; ENCODER_SCRIPT="$ENCODER_SCRIPT_AWQ"
    TIER_REASON="cuda present but free VRAM ${vram}MB under its tier floor, RAM ${ram}MB ≥ ${AWQ_4B_CPU_RAM} → ColQwen3-4B AWQ on cpu (degraded; recovers to cuda when VRAM frees)"; return
  fi
  # 5–6: full bf16 on mps — Apple Silicon (no AWQ wheels; plain-transformers full lane).
  if [ "$mps" = 1 ] && [ "$ram" -ge "$FULL_8B_RAM" ]; then
    TIER=8b-full; MODEL_ID=TomoroAI/tomoro-colqwen3-embed-8b; DEVICE=mps; ENCODER_SCRIPT="$ENCODER_SCRIPT_FULL"
    TIER_REASON="Apple Silicon, unified memory ${ram}MB ≥ ${FULL_8B_RAM} → ColQwen3-8B full bf16 on mps"; return
  fi
  if [ "$mps" = 1 ] && [ "$ram" -ge "$FULL_4B_RAM" ]; then
    TIER=4b-full; MODEL_ID=TomoroAI/tomoro-colqwen3-embed-4b; DEVICE=mps; ENCODER_SCRIPT="$ENCODER_SCRIPT_FULL"
    TIER_REASON="Apple Silicon, unified memory ${ram}MB ≥ ${FULL_4B_RAM} → ColQwen3-4B full bf16 on mps"; return
  fi
  # 7–8: full bf16 on cpu — ONLY when a GPU is PRESENT on a non-AWQ platform but under its VRAM
  # floor (degraded; keeps the ColQwen model). A host with NO GPU falls through to LateOn — the
  # light cross-OS default, never a multi-GB full-bf16 download grinding on cpu by default.
  if [ "$gpu" = 1 ] && [ "$awq" = 0 ] && [ "$ram" -ge "$FULL_8B_RAM" ]; then
    TIER=8b-full; MODEL_ID=TomoroAI/tomoro-colqwen3-embed-8b; DEVICE=cpu; ENCODER_SCRIPT="$ENCODER_SCRIPT_FULL"
    TIER_REASON="GPU present but no AWQ lane / under VRAM floor, RAM ${ram}MB ≥ ${FULL_8B_RAM} → ColQwen3-8B full bf16 on cpu (degraded)"; return
  fi
  if [ "$gpu" = 1 ] && [ "$awq" = 0 ] && [ "$ram" -ge "$FULL_4B_RAM" ]; then
    TIER=4b-full; MODEL_ID=TomoroAI/tomoro-colqwen3-embed-4b; DEVICE=cpu; ENCODER_SCRIPT="$ENCODER_SCRIPT_FULL"
    TIER_REASON="GPU present but no AWQ lane / under VRAM floor, RAM ${ram}MB ≥ ${FULL_4B_RAM} → ColQwen3-4B full bf16 on cpu (degraded)"; return
  fi
  # 8.5: small-VRAM cuda — a cuda GPU is PRESENT but every ColQwen rung's VRAM/RAM floor was
  # missed (e.g. a ~4GB GPU on a low-RAM box). Run LateOn (dim-128, ~0.6GB) ON cuda rather than
  # dropping a present GPU to a 10–100× slower cpu encode. LateOn loads through plain transformers
  # on cuda (no AWQ/triton dep), so this rung does NOT require awq. Mirrors src/selector.rs.
  if [ "$gpu" = 1 ] && [ "$vram" -ge "$LATEON_VRAM" ]; then
    TIER=lateon; MODEL_ID=lightonai/LateOn; DEVICE=cuda; ENCODER_SCRIPT="$ENCODER_SCRIPT_FULL"
    TIER_REASON="cuda present, free VRAM ${vram}MB ≥ ${LATEON_VRAM} but under every ColQwen floor → LateOn (text-only) on cuda — small model fits the GPU"; return
  fi
  # 9: LateOn — the light text-only tier, and now the DEFAULT for any host with NO usable
  # accelerator (no cuda GPU, no mps): a new user's first run is fast + small (~0.6GB) on ANY OS
  # instead of a multi-GB ColQwen-on-cpu grind. Multimodal is auto-preferred when a cuda/mps
  # accelerator is present and stays one ACC_TIER=… away on cpu.
  if [ "$ram" -ge 2000 ]; then
    TIER=lateon; MODEL_ID=lightonai/LateOn; ENCODER_SCRIPT="$ENCODER_SCRIPT_FULL"
    DEVICE="$([ "$mps" = 1 ] && [ "$ram" -ge "$FULL_4B_RAM" ] && echo mps || echo cpu)"
    TIER_REASON="no accelerator (cuda/mps) present (RAM ${ram}MB, free VRAM ${vram}MB) → LateOn (light text-only default; multimodal via a GPU or ACC_TIER) on $DEVICE"; return
  fi
  # 10: nothing viable natively → the container tier path.
  TIER=container; MODEL_ID=""; DEVICE=""; ENCODER_SCRIPT=""
  TIER_REASON="no native tier viable (RAM ${ram}MB, OS $OS/$ARCH) → use the CONTAINER tier (docs/INSTALL_CONTAINER.md)"
}

# apply_disk_floor — the tier ladder's DISK leg: the pick's expected download + 2048MB
# headroom must fit the free disk at the HF cache, else degrade ONE RUNG AT A TIME
# (8b→4b→lateon), noting 'disk floor: need ~XGB, have ~YGB' in TIER_REASON. A forced
# ACC_TIER is the owner's pick — never degraded, but an unfittable pick is warned
# honestly. Unknown free disk (no df) skips the floor with an explicit note.
apply_disk_floor() {
  [ -n "$MODEL_ID" ] || return 0                       # container tier: nothing to download
  local need
  need=$(( $(expected_model_mb "$TIER") + DISK_HEADROOM_MB ))
  if [ "$DISK_FREE_MB" -le 0 ]; then
    TIER_REASON="$TIER_REASON · disk floor not applied (free disk unknown at $HF_CACHE)"
    return 0
  fi
  if [ "$TIER_FORCED" = 1 ]; then
    [ "$need" -gt "$DISK_FREE_MB" ] && warn "forced tier $TIER needs ~$(mb_to_gb "$need")GB free disk (model + 2GB headroom) but only ~$(mb_to_gb "$DISK_FREE_MB")GB is free at $HF_CACHE — the download may fail"
    return 0
  fi
  local needg haveg
  while [ "$need" -gt "$DISK_FREE_MB" ]; do
    needg="$(mb_to_gb "$need")"; haveg="$(mb_to_gb "$DISK_FREE_MB")"
    if [ "$TIER" = "lateon" ]; then
      TIER_REASON="$TIER_REASON · disk floor UNMET even for LateOn: need ~${needg}GB, have ~${haveg}GB — the download may fail"
      break
    fi
    case "$TIER" in
      8b-awq)  TIER=4b-awq;  MODEL_ID=TomoroAI/tomoro-ai-colqwen3-embed-4b-awq ;;  # device/script unchanged
      8b-cpu)  TIER=4b-cpu;  MODEL_ID=TomoroAI/tomoro-ai-colqwen3-embed-4b-awq ;;
      8b-full) TIER=4b-full; MODEL_ID=TomoroAI/tomoro-colqwen3-embed-4b ;;
      *)       TIER=lateon;  MODEL_ID=lightonai/LateOn; ENCODER_SCRIPT="$ENCODER_SCRIPT_FULL"
               DEVICE="$([ "$PROBE_MPS" = 1 ] && [ "$PROBE_RAM" -ge "$FULL_4B_RAM" ] && echo mps || echo cpu)" ;;
    esac
    TIER_REASON="$TIER_REASON · disk floor: need ~${needg}GB, have ~${haveg}GB → degraded to $TIER"
    need=$(( $(expected_model_mb "$TIER") + DISK_HEADROOM_MB ))
  done
}

# ── phase 0 banner + selection ────────────────────────────────────────────────────────
step "phase 0 — probe host + select embedder tier"
[ "$DRY_RUN" = "1" ] && say "(dry-run: walking every phase, mutating NOTHING)"
say "Accreted Intelligence (AccInt) — acc is a Work Model + tool loop for Claude Code: retrieve from your scored Work Model, run sandboxed actions, learn from real outcomes."
say "host: $OS/$ARCH · substrate: $DB"
[ "$OS" = "Linux" ] || [ "$OS" = "Darwin" ] || warn "untested OS '$OS' — proceeding best-effort (Windows: use install.ps1; container as fallback)"

# ── update-mode detection ───────────────────────────────────────────────────────────
# An EXISTING install (an acc binary on PATH and/or an existing substrate at $DB) flips
# this run into UPDATE mode: the same idempotent phase-machine runs (satisfied deps skip
# fast — every phase checks its postcondition first), but the model pin is re-written
# ONLY when the host's pick CHANGED, the prefetch is skipped while the pin holds, and the
# run ends with a one-line "updated <old> → <new>" summary. The substrate at $DB is NEVER
# modified or deleted by the installer in either mode — schema migrations live in the
# binary (the PRAGMA user_version ladder in src/db.rs) and run automatically on the first
# writable open after the update; `acc doctor` reports substrate-vs-binary versions.
UPDATE_MODE=0
OLD_ACC_ID=""
if have acc; then
  OLD_ACC_ID="$(acc --version 2>/dev/null | awk 'NR==1{print $2}' || echo '')"
fi
if [ -n "$OLD_ACC_ID" ] || [ -f "$DB" ]; then
  UPDATE_MODE=1
  say "existing install detected (binary: ${OLD_ACC_ID:-none} · substrate: $([ -f "$DB" ] && echo present || echo none)) — UPDATE mode: your Work Model at $DB is never touched"
fi
select_tier
HF_CACHE="$(hf_cache_dir)"
DISK_FREE_MB="$(probe_disk_free_mb)"
case "$DISK_FREE_MB" in ''|*[!0-9]*) DISK_FREE_MB=0 ;; esac
apply_disk_floor
say "probe: gpu=$PROBE_GPU vram_free=${PROBE_VRAM}MB ram=${PROBE_RAM}MB awq_lane=$PROBE_AWQ mps=$PROBE_MPS disk_free=${DISK_FREE_MB}MB (hf cache: $HF_CACHE)"
if [ "$TIER" = "container" ]; then
  # Container is a TERMINAL verdict — no native lane fits this host, so the native phases
  # don't apply. Report the container path as the verdict and stop, in BOTH dry-run and real
  # mode (dry-run's "what would happen" on a container-only host IS "use the container").
  phase_result "probe_tier" "ok" "$TIER_REASON → tier=container" "no native lane fits — follow docs/INSTALL_CONTAINER.md (Docker image carries deps + CPU floor)"
  warn "No native embedder tier fits this host. The container tier is the portability floor."
  warn "→ docs/INSTALL_CONTAINER.md  (scripts/acc-docker.sh)"
  [ "$JSON" = "1" ] && json_phase "verdict" "skipped" "native install not viable; container tier required ($TIER_REASON)" "docs/INSTALL_CONTAINER.md  ·  scripts/acc-docker.sh"
  exit 0
fi
phase_result "probe_tier" "ok" "tier=$TIER model=$MODEL_ID device=$DEVICE · $TIER_REASON" "phase 1: prereqs (rust/uv/python)"

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 1 — prereqs: rust (cargo), uv, python3. Idempotent: present → skip.
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 1 — prereqs (rust · uv · python)"
# rust
if have cargo; then
  phase_result "prereq_rust" "ok" "cargo present ($(cargo --version 2>/dev/null | cut -d' ' -f2))"
else
  if act "install rustup (non-interactive)" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path >/dev/null'; then
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env" || true
    phase_result "prereq_rust" "$([ "$DRY_RUN" = 1 ] && echo would || echo ok)" "rust toolchain installed" "phase 1: uv"
  else
    phase_result "prereq_rust" "failed" "rustup install failed" "install rust manually: https://rustup.rs"; exit 1
  fi
fi
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env" || true
# uv
if have uv; then
  phase_result "prereq_uv" "ok" "uv present ($(uv --version 2>/dev/null | cut -d' ' -f2))"
else
  if act "install uv (Python env manager — drives the encoder env)" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null'; then
    export PATH="$HOME/.local/bin:$PATH"
    phase_result "prereq_uv" "$([ "$DRY_RUN" = 1 ] && echo would || echo ok)" "uv installed" "phase 1: python"
  else
    phase_result "prereq_uv" "failed" "uv install failed" "install uv manually: https://astral.sh/uv"; exit 1
  fi
fi
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
# python3 (used by the encoder, warm-probes, JSON helpers after phase 1, and .mcp.json writer)
if have python3; then
  phase_result "prereq_python" "ok" "python3 present ($(python3 --version 2>/dev/null | cut -d' ' -f2))"
else
  case "$PKG" in
    pacman|brew) PY_PKG=python ;;
    *)           PY_PKG=python3 ;;
  esac
  if act "install $PY_PKG (provides python3 for installer helpers + encoder runtime)" pkg_install "$PY_PKG"; then
    if [ "$DRY_RUN" = "1" ]; then
      phase_result "prereq_python" "would" "python3 installed" "phase 2: system deps"
    elif have python3; then
      phase_result "prereq_python" "ok" "python3 installed ($(python3 --version 2>/dev/null | cut -d' ' -f2))" "phase 2: system deps"
    else
      phase_result "prereq_python" "failed" "python3 install completed but python3 is still not on PATH" "add python3 to PATH, then re-run ./install.sh"; exit 1
    fi
  else
    phase_result "prereq_python" "failed" "python3 install failed" "install python3 via your OS package manager (or use the container)"; exit 1
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 2 — system deps: sandbox (bwrap, Linux) + a C linker for cargo. Idempotent.
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 2 — system deps (sandbox + build)"
if [ "$OS" = "Linux" ]; then
  if have bwrap; then
    phase_result "sysdeps_sandbox" "ok" "bubblewrap present — runtimes get read-only system + writable workdir; HOST network stays reachable by design (substrate socket included)"
  else
    if act "install bubblewrap (sandbox)" pkg_install bubblewrap; then
      have bwrap && phase_result "sysdeps_sandbox" "$([ "$DRY_RUN" = 1 ] && echo would || echo ok)" "bubblewrap installed" \
        || { warn "bwrap not installed — exec runtimes REFUSE to run unsandboxed (acc returns an error, never runs unsandboxed code); retrieve/solve/outcome still work. Install bubblewrap to enable exec, or use the container."; \
             phase_result "sysdeps_sandbox" "skipped" "bwrap not installed — exec runtimes refuse unsandboxed code; install bubblewrap to enable exec (retrieve/solve/outcome still work)" "install bubblewrap manually or use the container"; }
    else
      phase_result "sysdeps_sandbox" "skipped" "could not install bwrap — exec will refuse to run unsandboxed" "apt install bubblewrap (or use the container)"
    fi
  fi
  have cc || have gcc || act "install gcc (cargo needs a C linker)" pkg_install gcc || true
  # System SQLite dev lib — rusqlite links it (no bundled amalgamation compile).
  case "$PKG" in
    apt-get) SQLITE_DEV=libsqlite3-dev ;;
    dnf|zypper) SQLITE_DEV=sqlite-devel ;;
    pacman) SQLITE_DEV=sqlite ;;
    apk) SQLITE_DEV=sqlite-dev ;;
    *) SQLITE_DEV="" ;;
  esac
  [ -n "$SQLITE_DEV" ] && { [ -f /usr/include/sqlite3.h ] || act "install $SQLITE_DEV (system sqlite for rusqlite)" pkg_install "$SQLITE_DEV" || true; }
else
  warn "macOS: no bwrap — exec runtimes REFUSE to run unsandboxed (acc returns an error, never runs unsandboxed code); retrieve/solve/outcome still work. For sandboxed exec on macOS, use the container (docs/INSTALL_CONTAINER.md)."
  phase_result "sysdeps_sandbox" "skipped" "macOS: no bwrap — exec runtimes refuse unsandboxed code (retrieve/solve/outcome still work); use the container for sandboxed exec. Camoufox still keeps the browser host-side."
  if ! have cc; then
    act "install Xcode CLT (C linker)" xcode-select --install || true
    # xcode-select --install opens an ASYNC GUI dialog and returns immediately — `cc` does
    # NOT exist until the user finishes that dialog. Proceeding into phase 3 now starts the
    # cargo build before the linker exists → a cryptic compiler/linker error. HARD-STOP here
    # (real runs only — dry-run never mutates and must walk every phase to exit 0).
    if [ "$DRY_RUN" != "1" ] && ! have cc; then
      phase_result "sysdeps_clt" "failed" "Xcode Command Line Tools not yet installed — a system dialog just opened to install them (the C linker 'cc' is required for the Intel/source build)" "FINISH the Command Line Tools install dialog, then re-run ./install.sh"
      exit 1
    fi
  fi
  # macOS ships system libsqlite3 (the Xcode CLT provides the sqlite3.h header) —
  # rusqlite links it, no bundled amalgamation compile. No action needed here.
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 3 — binary: PREBUILT FETCH → SOURCE BUILD. Idempotent postcondition = `acc`
# resolves AND its identity (token 2 of `acc --version`: `<ver>+<sha>`) matches the
# checkout's crate version + git short HEAD (no .git → version-only compare, noted).
# Branch order: (a) postcondition match → keep installed; (b) prebuilt fetch (unless
# ACC_INSTALL=source) — download the release artifact + sha256sums.txt, VERIFY the
# sha256 (an unverified binary is NEVER installed), unpack to the user bin dir — no
# rustup needed; (c) source build fallback — the previous behavior verbatim — when the
# fetch fails for ANY reason (a fetch failure never fails the install while this
# fallback exists). --locked: a fresh resolve can pick a newer patch that breaks the build.
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 3 — install acc (prebuilt fetch → source build)"
SRC_VER="$(grep -m1 '^version' "$REPO/Cargo.toml" 2>/dev/null | cut -d'"' -f2 || echo '')"
HEAD_SHA="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '')"

# Latest-release-tag version resolver (mirrors src/update.rs release_url/tag_name, ~lines
# 312/501): GET the releases/latest API, extract `.tag_name` (e.g. "v0.1.0"), strip the
# leading "v" → the version. This is the ONLY version source on the public binary-only path
# (no Cargo.toml → the grep above yields empty). On the source-clone path Cargo.toml wins and
# this is never called. curl-only, fail-soft: any failure (offline / rate-limit / non-2xx /
# no published release yet — the v0.1.0 release may still be a DRAFT, so /latest can 404)
# echoes empty, and the prebuilt lane then refuses honestly + falls back to source.
RELEASE_API="https://api.github.com/repos/maxbaluev/accreted-intelligence/releases/latest"
resolve_latest_version() {
  have curl || { echo ""; return; }
  local body tag
  body="$(curl -fsSL --connect-timeout 15 --retry 2 --max-time 30 \
            -H 'Accept: application/vnd.github+json' -H 'User-Agent: acc-install' \
            "$RELEASE_API" 2>/dev/null)" || { echo ""; return; }
  # Extract the first "tag_name": "vX.Y.Z" value, then strip the leading v.
  tag="$(printf '%s' "$body" \
          | grep -m1 '"tag_name"' \
          | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  case "$tag" in v[0-9]*) tag="${tag#v}" ;; esac
  echo "$tag"
}
# Public binary-only path: no Cargo.toml → resolve the version from the latest release tag so
# the ARTIFACT name (acc-v<ver>-<target>) is correct instead of the broken empty "acc-v-".
if [ -z "$SRC_VER" ]; then
  SRC_VER="$(resolve_latest_version)"
  [ -n "$SRC_VER" ] && say "resolved acc v$SRC_VER from the latest published release tag (no Cargo.toml — binary-only install)"
fi

# Version probe — token 2 of the identity line `acc <ver>+<sha> (<target>)`. (The old
# last-word parse yielded `(<target>)` and could never match — tests/build_identity.rs (c).)
INSTALLED_ID=""
have acc && INSTALLED_ID="$(acc --version 2>/dev/null | awk 'NR==1{print $2}' || echo '')"
INSTALLED_VER="${INSTALLED_ID%%+*}"
INSTALLED_SHA=""
case "$INSTALLED_ID" in *+*) INSTALLED_SHA="${INSTALLED_ID#*+}" ;; esac
ID_MATCH=0; ID_NOTE=""
if [ -n "$SRC_VER" ] && [ "$INSTALLED_VER" = "$SRC_VER" ]; then
  if [ -n "$HEAD_SHA" ]; then
    [ "$INSTALLED_SHA" = "$HEAD_SHA" ] && ID_MATCH=1
  else
    ID_MATCH=1; ID_NOTE=" — no .git: sha not compared, crate version only"
  fi
fi

# Prebuilt lane facts — release.yml naming contract: acc-<version>-<target>.tar.gz +
# sha256sums.txt, where <version> = the pushed tag (vX.Y.Z) on tag-push releases.
PREBUILT_TARGET=""
case "$OS/$ARCH" in
  Linux/x86_64)                PREBUILT_TARGET="x86_64-unknown-linux-musl" ;;   # static musl — runs on ANY linux (no glibc floor)
  Linux/aarch64|Linux/arm64)   PREBUILT_TARGET="aarch64-unknown-linux-musl" ;; # static musl — runs on ANY linux (no glibc floor)
  Darwin/arm64|Darwin/aarch64) PREBUILT_TARGET="aarch64-apple-darwin" ;;
  # Intel Mac (Darwin/x86_64): no prebuilt — the release defers the 10x-billed Intel macos-13
  # runner for now, so PREBUILT_TARGET stays empty and the fetch below source-builds (no 404).
esac
RELEASE_BASE="https://github.com/maxbaluev/accreted-intelligence/releases"
ARTIFACT="acc-v${SRC_VER}-${PREBUILT_TARGET}.tar.gz"
BIN_DIR="$HOME/.local/bin"   # already exported on PATH above (phase 1)
PREBUILT_ID=""; PREBUILT_SRC=""

sha256_of() {
  if have sha256sum; then sha256sum "$1" | awk '{print $1}'
  elif have shasum; then shasum -a 256 "$1" | awk '{print $1}'
  else echo ""; fi
}

# prebuilt_fetch — 0 = a sha256-VERIFIED release binary now lives at $BIN_DIR/acc
# (PREBUILT_ID/PREBUILT_SRC set); non-zero on ANY failure → caller falls back to source.
# Tries the version-tagged URL (v$SRC_VER) first, then /latest/. Refusal rules: missing
# manifest entry, missing sha tool, or a hash MISMATCH all REFUSE the binary — it is
# deleted with the tmp dir and never reaches the bin dir.
prebuilt_fetch() {
  [ -n "$SRC_VER" ] || { say "acc version unresolved (no Cargo.toml and no published release tag) — building from source"; return 1; }
  [ -n "$PREBUILT_TARGET" ] || { say "no prebuilt release target for $OS/$ARCH — building from source"; return 1; }
  have curl || { say "curl not available — building from source"; return 1; }
  have tar  || { say "tar not available — building from source"; return 1; }
  local tmp fetched=0 base src=""
  tmp="$(mktemp -d 2>/dev/null)" || { say "mktemp failed — building from source"; return 1; }
  for base in "$RELEASE_BASE/download/v$SRC_VER" "$RELEASE_BASE/latest/download"; do
    say "trying prebuilt: $base/$ARTIFACT"
    if curl -fsSL --connect-timeout 15 --retry 2 --max-time 180 -o "$tmp/$ARTIFACT" "$base/$ARTIFACT" 2>/dev/null \
       && curl -fsSL --connect-timeout 15 --retry 2 --max-time 60 -o "$tmp/sha256sums.txt" "$base/sha256sums.txt" 2>/dev/null; then
      fetched=1; src="$base"; break
    fi
  done
  if [ "$fetched" != 1 ]; then
    rm -rf "$tmp"; say "no prebuilt release reachable — building from source"; return 1
  fi
  # VERIFY — sha256sum -c semantics: manifest line for THIS artifact must match exactly.
  local want got
  want="$(awk -v a="$ARTIFACT" '$2==a || $2=="*"a {print $1; exit}' "$tmp/sha256sums.txt" | tr 'A-F' 'a-f')"
  if [ -z "$want" ]; then
    rm -rf "$tmp"; warn "sha256sums.txt has no entry for $ARTIFACT — REFUSING the unverified binary; building from source"; return 1
  fi
  got="$(sha256_of "$tmp/$ARTIFACT" | tr 'A-F' 'a-f')"
  if [ -z "$got" ]; then
    rm -rf "$tmp"; warn "no sha256 tool (sha256sum/shasum) — REFUSING the unverified binary; building from source"; return 1
  fi
  if [ "$got" != "$want" ]; then
    rm -rf "$tmp"
    warn "sha256 MISMATCH for $ARTIFACT (expected $want, got $got) — REFUSING the unverified binary; building from source"
    return 1
  fi
  ok "sha256 verified: $ARTIFACT matches sha256sums.txt"
  # Unpack + re-probe in tmp BEFORE installing — a wrong-version binary never lands.
  tar -xzf "$tmp/$ARTIFACT" -C "$tmp" acc 2>/dev/null || { rm -rf "$tmp"; warn "unpack failed for $ARTIFACT — building from source"; return 1; }
  chmod +x "$tmp/acc" 2>/dev/null || true
  local newid
  newid="$("$tmp/acc" --version 2>/dev/null | awk 'NR==1{print $2}' || echo '')"
  case "$newid" in
    "$SRC_VER"+*) ;;
    *) rm -rf "$tmp"; warn "prebuilt binary reports '$newid' (wanted $SRC_VER+<sha>) — building from source"; return 1 ;;
  esac
  mkdir -p "$BIN_DIR" || { rm -rf "$tmp"; warn "cannot create $BIN_DIR — building from source"; return 1; }
  mv -f "$tmp/acc" "$BIN_DIR/acc" || { rm -rf "$tmp"; warn "cannot install to $BIN_DIR — building from source"; return 1; }
  # FREE macOS trust (no paid Apple Developer cert): a curl-fetched binary normally carries NO
  # com.apple.quarantine xattr (Gatekeeper only quarantines browser/DMG downloads), so it runs
  # unblocked. Strip it DEFENSIVELY anyway in case a wrapper added it — `xattr` is idempotent and
  # fail-soft. (Apple Silicon binaries are auto ad-hoc-signed by the toolchain, which is all arm64
  # needs to EXECUTE.) Integrity is already covered: the sha256 verify above REFUSES a tampered binary.
  [ "$OS" = "Darwin" ] && xattr -dr com.apple.quarantine "$BIN_DIR/acc" 2>/dev/null || true
  rm -rf "$tmp"
  hash -r 2>/dev/null || true
  PREBUILT_ID="$newid"; PREBUILT_SRC="$src"
  return 0
}

if [ "$ID_MATCH" = 1 ]; then
  ACC_BIN="$(command -v acc)"
  phase_result "binary" "ok" "acc $INSTALLED_ID already installed at $ACC_BIN (matches checkout$ID_NOTE)"
elif [ "$DRY_RUN" = 1 ] && [ "${ACC_INSTALL:-}" != "source" ] && [ -n "$PREBUILT_TARGET" ] && [ -n "$SRC_VER" ]; then
  # Dry-run honesty: report the would-fetch artifact + would-verify line, NO network.
  say "WOULD: fetch $ARTIFACT (try $RELEASE_BASE/download/v$SRC_VER first, then $RELEASE_BASE/latest/download)"
  say "WOULD: verify sha256 of $ARTIFACT against sha256sums.txt — refuse on mismatch, an unverified binary is never installed"
  say "WOULD: unpack acc to $BIN_DIR, hash -r, re-probe \`acc --version\` (token 2: <ver>+<sha>)"
  say "WOULD: fall back to the source build (cargo build --release --locked) if no release is reachable"
  phase_result "binary" "would" "prebuilt $ARTIFACT fetched + sha256-verified into $BIN_DIR (source build is the fallback)" "phase 4: encoder env"
elif [ "$DRY_RUN" != 1 ] && [ "${ACC_INSTALL:-}" != "source" ] && prebuilt_fetch; then
  ACC_BIN="$BIN_DIR/acc"
  SKEW=""
  [ -n "$HEAD_SHA" ] && [ "$PREBUILT_ID" != "$SRC_VER+$HEAD_SHA" ] && SKEW=" (binary sha differs from checkout HEAD $HEAD_SHA — built from the release tag)"
  phase_result "binary" "ok" "prebuilt acc $PREBUILT_ID installed at $ACC_BIN — sha256-verified from $PREBUILT_SRC, no rustup/toolchain needed$SKEW" "phase 4: encoder env"
else
  [ "${ACC_INSTALL:-}" = "source" ] && say "ACC_INSTALL=source — prebuilt lane skipped, building from source"
  if act "cargo build --release --locked" cargo build --release --locked \
     && act "cargo install --path . --locked --force" bash -c 'cargo install --path "'"$REPO"'" --locked --force >/dev/null'; then
    ACC_BIN="$(command -v acc || echo "$REPO/target/release/acc")"
    phase_result "binary" "$([ "$DRY_RUN" = 1 ] && echo would || echo ok)" "acc built + installed at $ACC_BIN" "phase 4: encoder env"
  else
    phase_result "binary" "failed" "cargo build/install failed" "fix the build error above, then re-run ./install.sh"; exit 1
  fi
fi
[ "$DRY_RUN" = "1" ] && ACC_BIN="${ACC_BIN:-$REPO/target/release/acc}"

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 3b — plugins on disk (solved:a78f0ba601287cad: U-PLUGINS-ON-DISK). A binary-only
# PUBLIC release ships ONLY the bare `acc` binary — NO `plugins/` tree. Without this step
# `hosts.rs detect_repo_root` would fall to the build-host `CARGO_MANIFEST_DIR` (the CI
# runner's checkout path), and the OpenCode/Codex convergers would write that DEAD path as a
# plugin/notify entry into the user's configs (silently breaking OpenCode plugin-load +
# Codex notify on EVERY OS).
# Fix: provision `plugins/` into the per-user DATA DIR — the SAME dir the binary's
# `platform::data_dir()` resolves to (linux/other: ${XDG_DATA_HOME:-~/.local/share}/acc;
# macOS: ~/Library/Application Support/acc) — so `detect_repo_root` probe (iv) finds it.
# Source: copy the local `plugins/` when present (dev / install-from-clone); else FETCH the
# tree from the public repo raw URLs (mirrors the prebuilt_fetch idiom). Idempotent.
# `ACC_REPO_ROOT` is exported to the DATA DIR so the hosts-sync phase's convergers wire the
# REAL on-disk path regardless of any per-OS data-dir subtlety (probe (ii)).
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 3b — provision plugins/ to the per-user data dir"
case "$OS" in
  Darwin) ACC_DATA_DIR="$HOME/Library/Application Support/acc" ;;
  *)      ACC_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/acc" ;;
esac
PLUGINS_DEST="$ACC_DATA_DIR/plugins"
# The plugin files the convergers + probes reference (kept in sync with plugins/ tree;
# the marker probe is plugins/opencode/acc.ts — it MUST be among these).
PLUGINS_FILES="opencode/acc.ts opencode/opencode.json.snippet opencode/README.md \
codex/hooks.json codex/config.toml.snippet codex/README.md \
cursor/rules-acc.mdc cursor/hooks.json cursor/mcp.json cursor/README.md README.md"
PLUGINS_RAW_BASE="https://raw.githubusercontent.com/maxbaluev/accreted-intelligence/main/plugins"

provision_plugins() {
  # Already provisioned (idempotent postcondition = the marker exists under the data dir).
  if [ -f "$PLUGINS_DEST/opencode/acc.ts" ] && [ -f "$PLUGINS_DEST/codex/hooks.json" ]; then
    say "plugins already provisioned at $PLUGINS_DEST"
    return 0
  fi
  mkdir -p "$PLUGINS_DEST" || { warn "cannot create $PLUGINS_DEST"; return 1; }
  # (a) install-from-clone / dev: copy the local plugins/ tree verbatim.
  if [ -d "$REPO/plugins" ] && [ -f "$REPO/plugins/opencode/acc.ts" ]; then
    cp -R "$REPO/plugins/." "$PLUGINS_DEST/" || { warn "copy from $REPO/plugins failed"; return 1; }
    ok "plugins copied from $REPO/plugins → $PLUGINS_DEST"
    return 0
  fi
  # (b) bare-binary public path: FETCH the tree from the public repo raw URLs (mirrors the
  # prebuilt binary fetch). curl required; a fetch failure is fail-soft (hosts-sync then
  # skips the plugin/notify field rather than writing a dead path).
  have curl || { warn "no local plugins/ and curl unavailable — plugin/notify wiring will be skipped (no dead path written)"; return 1; }
  local f got=0
  for f in $PLUGINS_FILES; do
    mkdir -p "$PLUGINS_DEST/$(dirname "$f")"
    if curl -fsSL --retry 2 --max-time 60 -o "$PLUGINS_DEST/$f" "$PLUGINS_RAW_BASE/$f" 2>/dev/null; then
      got=$((got + 1))
    fi
  done
  if [ -f "$PLUGINS_DEST/opencode/acc.ts" ] && [ -f "$PLUGINS_DEST/codex/hooks.json" ]; then
    ok "plugins fetched ($got files) from $PLUGINS_RAW_BASE → $PLUGINS_DEST"
    return 0
  fi
  warn "plugins fetch incomplete (markers missing) — hosts-sync will skip plugin/notify wiring (no dead path)"
  return 1
}

if [ "$DRY_RUN" = "1" ]; then
  if [ -d "$REPO/plugins" ] && [ -f "$REPO/plugins/opencode/acc.ts" ]; then
    say "WOULD: copy $REPO/plugins → $PLUGINS_DEST (local tree present)"
  else
    say "WOULD: fetch plugins/ from $PLUGINS_RAW_BASE → $PLUGINS_DEST (no local tree — bare-binary path)"
  fi
  phase_result "plugins" "would" "provision plugins/ into $PLUGINS_DEST (probed by detect_repo_root; convergers wire the REAL path)" "phase 4: encoder env"
elif provision_plugins; then
  export ACC_REPO_ROOT="$ACC_DATA_DIR"
  phase_result "plugins" "ok" "plugins/ provisioned at $PLUGINS_DEST — convergers wire the real on-disk path (ACC_REPO_ROOT=$ACC_DATA_DIR)" "phase 4: encoder env"
else
  phase_result "plugins" "skipped" "no plugins/ on disk (fail-soft) — hosts-sync skips plugin/notify wiring rather than writing a dead path" "re-run with a clone present, or after publishing plugins to the release"
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 4 — encoder env: materialize the chosen tier's Python deps with `uv sync --script`
# (PEP-723 inline deps). This pays the resolve/download cost ONCE, BEFORE the daemon's first
# encode, so the model load isn't also resolving the env. Idempotent (uv caches the env).
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 4 — encoder env (uv sync of the tier's script deps)"
# Resolve the encoder-env-warm command. A DEV checkout ships encoders/li_encode*.py on disk →
# `uv sync --script <file>`. A binary-only RELEASE install ships no encoders/ dir → the encoder
# scripts are embedded in the binary and reachable as `acc warm-encoder <model>` (probe with
# --help), which materializes the tier's encoder and `uv sync --script`s it with VISIBLE uv
# progress and WITHOUT loading the model. Either path resolves+caches the (multi-GB)
# torch/transformers/awq/flash-attn env once, BEFORE the daemon's first encode, so the model
# load isn't also hiding the wheel download. No model / no path → skipped (deps resolve lazily).
if [ -n "$ENCODER_SCRIPT" ] && [ -f "$ENCODER_SCRIPT" ]; then
  if act "uv sync --script $(basename "$ENCODER_SCRIPT") (resolve+cache the $TIER encoder deps)" \
       uv sync --script "$ENCODER_SCRIPT" >/dev/null 2>&1; then
    phase_result "encoder_env" "$([ "$DRY_RUN" = 1 ] && echo would || echo ok)" \
      "encoder env ready for $TIER ($(basename "$ENCODER_SCRIPT") deps resolved/cached)" "phase 5: model pin"
  else
    phase_result "encoder_env" "skipped" "uv sync --script reported an issue (deps resolve lazily on first encode)" "re-run; or check: uv sync --script $ENCODER_SCRIPT"
  fi
elif [ -n "$MODEL_ID" ] && "$ACC_BIN" warm-encoder --help >/dev/null 2>&1; then
  # Binary-only release install: on-disk encoders/ absent but the binary carries the embedded
  # encoder scripts. Warm the env via the binary so the wheel download is VISIBLE here instead
  # of hidden inside the first embedder start (mirror of the phase-6 prefetch binary fallback).
  if [ "$DRY_RUN" = "1" ]; then
    say "WOULD: acc warm-encoder $MODEL_ID (uv sync --script the tier's embedded encoder env, live progress, no model load)"
    phase_result "encoder_env" "would" "warm the encoder env for $TIER via acc warm-encoder $MODEL_ID (torch/transformers/... — several GB, one time)" "phase 5: model pin"
  else
    say "resolving the encoder env (torch/transformers/... — several GB, one time)…"
    if act "acc warm-encoder $MODEL_ID (resolve+cache the $TIER encoder env, visible progress, no model load)" \
         "$ACC_BIN" warm-encoder "$MODEL_ID"; then
      phase_result "encoder_env" "ok" "encoder env ready for $TIER (acc warm-encoder $MODEL_ID — torch/transformers/... resolved/cached)" "phase 5: model pin"
    else
      phase_result "encoder_env" "skipped" "acc warm-encoder reported an issue (deps resolve lazily on first encode)" "re-run; or let the daemon resolve the env lazily on first start"
    fi
  fi
else
  phase_result "encoder_env" "skipped" "no encoder env to warm for tier=$TIER (on-disk $ENCODER_SCRIPT absent and the binary has no warm-encoder subcommand, or no model pinned)" "tier mis-selected — check phase 0"
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 5 — model pin: record the install-time (model, device) to the pin
# ($XDG_CONFIG_HOME/acc/model.json) BEFORE VRAM is taken. `acc pin` re-runs the SAME
# selector.rs ladder host-side, so the pin matches phase 0's tier on a real host. Idempotent.
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 5 — pin the embedder model (install-time, before VRAM is taken)"
PIN_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/acc/model.json"
# UPDATE-MODE PIN GUARD: a stored pin that already matches the host's pick is left
# byte-untouched — re-pinning ONLY when the selection changed (one substrate = one pinned
# model; an unchanged pin must never be churned on every update). Pure read, dry-run safe.
PIN_CURRENT=""
[ -r "$PIN_PATH" ] && PIN_CURRENT="$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("model_id","?"),"on",d.get("device","?"))' "$PIN_PATH" 2>/dev/null || echo '')"
PIN_UNCHANGED=0
[ -n "$PIN_CURRENT" ] && [ "$PIN_CURRENT" = "$MODEL_ID on $DEVICE" ] && PIN_UNCHANGED=1
if [ "$UPDATE_MODE" = "1" ] && [ "$PIN_UNCHANGED" = "1" ]; then
  phase_result "model_pin" "ok" "pin unchanged ($PIN_CURRENT) — left as-is (update mode re-pins only on a changed selection)" "phase 6: model prefetch"
elif [ "$DRY_RUN" = "1" ]; then
  phase_result "model_pin" "would" "pin $MODEL_ID on $DEVICE → $PIN_PATH" "phase 6: model prefetch"
elif {
       # FORCED-TIER PIN (the ACC_TIER-ignored bug): bare `acc pin` bootstraps from a fresh
       # host probe, and with an existing pin it only PRINTS status (never rewrites). When the
       # owner forced ACC_TIER, write the pin EXPLICITLY (`acc pin <model> <device>` always
       # writes) so phase 0's forced lane is the lane actually pinned — even in update mode,
       # even if a stale auto-probed pin disagrees. Non-forced installs keep the host-probe pin.
       if [ "$TIER_FORCED" = "1" ]; then
         act "acc pin $MODEL_ID $DEVICE (explicit — owner forced ACC_TIER=$TIER, always writes)" "$ACC_BIN" pin "$MODEL_ID" "$DEVICE" >/dev/null 2>&1
       else
         act "acc pin (records the host-selected model/device)" "$ACC_BIN" pin >/dev/null 2>&1
       fi
     }; then
  PINNED="$([ -r "$PIN_PATH" ] && python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("model_id","?"),"on",d.get("device","?"))' "$PIN_PATH" 2>/dev/null || echo "$MODEL_ID on $DEVICE")"
  phase_result "model_pin" "ok" "pinned $PINNED → $PIN_PATH" "phase 6: model prefetch"
else
  phase_result "model_pin" "skipped" "pin failed — clients fall back to a live probe" "re-run, or: acc pin"
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 6 — model prefetch: pull the pinned model into the HF cache NOW, with VISIBLE
# progress (uv run encoders/prefetch.py — snapshot_download's native resume + cache
# reuse), instead of hiding an up-to-8.3GB download inside the daemon-warm phase.
# Idempotent: a cache hit returns instantly. Prefetch is UX, not a dependency — a
# network failure is 'skipped' and the daemon still downloads lazily on first start.
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 6 — model prefetch (weights into the HF cache, visible progress)"
PREFETCH_SCRIPT="$REPO/encoders/prefetch.py"
EXP_MB="$(expected_model_mb "$TIER")"
NEED_MB=$((EXP_MB + DISK_HEADROOM_MB))
# Resolve the prefetch command. Dev checkouts ship encoders/prefetch.py → run it via uv.
# A binary-only RELEASE install ships no encoders/ dir → the script is embedded in the binary
# and reachable as `acc prefetch` (probe with --help). Either way the weights download with
# huggingface_hub's live progress. No command → the prefetch is skipped (daemon downloads lazily).
PREFETCH_CMD=()
if [ -f "$PREFETCH_SCRIPT" ]; then
  PREFETCH_CMD=(uv run "$PREFETCH_SCRIPT")
  PREFETCH_DISPLAY="uv run encoders/prefetch.py"
elif "$ACC_BIN" prefetch --help >/dev/null 2>&1; then
  PREFETCH_CMD=("$ACC_BIN" prefetch)
  PREFETCH_DISPLAY="acc prefetch"
fi
if [ -z "$MODEL_ID" ] || [ "${#PREFETCH_CMD[@]}" -eq 0 ]; then
  phase_result "model_prefetch" "skipped" "no model to prefetch for tier=$TIER (or no prefetch path: on-disk $PREFETCH_SCRIPT absent and the binary has no prefetch subcommand)" "phase 7: substrate"
elif [ "$UPDATE_MODE" = "1" ] && [ "$PIN_UNCHANGED" = "1" ]; then
  # Update mode + unchanged pin: the weights were already fetched by the original install;
  # skip the prefetch walk entirely (the daemon still downloads lazily if anything is missing).
  phase_result "model_prefetch" "skipped" "pin unchanged — weights already cached by the original install (the daemon downloads lazily if anything is missing)" "phase 7: substrate"
elif [ "$DRY_RUN" = "1" ]; then
  # Dry-run honesty: expected size (static, NO network) + the free-disk verdict only.
  if [ "$DISK_FREE_MB" -gt 0 ]; then
    if [ "$NEED_MB" -le "$DISK_FREE_MB" ]; then DISK_VERDICT="fits"; else DISK_VERDICT="SHORT — the disk floor would have degraded the tier in phase 0"; fi
    say "disk verdict: need ~$(mb_to_gb "$NEED_MB")GB (model ~$(mb_to_gb "$EXP_MB")GB + 2GB headroom), have ~$(mb_to_gb "$DISK_FREE_MB")GB free at $HF_CACHE → $DISK_VERDICT"
  else
    say "disk verdict: free disk unknown at $HF_CACHE (df unreachable) — floor not applied"
  fi
  say "WOULD: $PREFETCH_DISPLAY $MODEL_ID (snapshot_download: resume + cache reuse, live progress on stderr; ~$(mb_to_gb "$EXP_MB")GB expected — static approximation, no network in dry-run)"
  phase_result "model_prefetch" "would" "prefetch $MODEL_ID (~$(mb_to_gb "$EXP_MB")GB) into the HF cache with live progress" "phase 7: substrate"
else
  say "prefetching $MODEL_ID (~$(mb_to_gb "$EXP_MB")GB expected; resume + cache reuse — a cache hit is instant)…"
  # stdout (the final JSON line) is captured; stderr (live progress) streams through.
  if PREFETCH_JSON="$("${PREFETCH_CMD[@]}" "$MODEL_ID")"; then
    PREFETCH_NOTE="$(printf '%s\n' "$PREFETCH_JSON" | tail -n1 | python3 -c 'import json,sys
d = json.loads(sys.stdin.read() or "{}")
print("%.1fGB cached at %s" % (d.get("cached_bytes", 0) / 1e9, d.get("path", "?")))' 2>/dev/null || echo "cached (size unreadable)")"
    phase_result "model_prefetch" "ok" "model $MODEL_ID prefetched — $PREFETCH_NOTE" "phase 7: substrate"
  else
    phase_result "model_prefetch" "skipped" "prefetch failed (network unreachable, or the model is gated) — the daemon still downloads lazily on first start" "re-run, or let the daemon download lazily on first start"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 7 — substrate: ensure the db exists (idempotent). A fresh db is created by the first
# write; we touch it via `acc status` (read-only path also opens/creates the file).
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 7 — substrate init"
# WSL FOREIGN-FS HAZARD (the Windows+WSL new-user landmine): a substrate on a Windows-drive mount
# (9p in WSL2 / drvfs in WSL1, i.e. under /mnt/c) breaks SQLite's WAL + flock locking →
# 'database is locked' / corruption. Warn (non-fatal) and name the fix; a native Linux fs is silent.
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  DB_FSTYPE="$(df -PT "$(dirname "$DB")" 2>/dev/null | awk 'NR==2{print $2}')"
  case "$DB_FSTYPE" in
    9p|drvfs|drv_fs)
      warn "substrate $DB is on a Windows drive mounted in WSL (fstype $DB_FSTYPE) — SQLite locking is UNRELIABLE there (database-is-locked / corruption). Keep it on the WSL Linux filesystem: re-run as ./install.sh \$HOME/.local/share/acc/acc.db, or install off /mnt/*." ;;
  esac
fi
if [ "$DRY_RUN" = "1" ] && [ -f "$DB" ]; then
  phase_result "substrate" "would" "validate the existing substrate at $DB opens with this binary" "phase 8: embedder daemon"
elif [ -f "$DB" ]; then
  # Existence is not validity: a db from a different schema epoch (e.g. created by a stale
  # cached binary) must fail HERE with guidance, not poison every later phase. `status`
  # alone is too weak a probe (it opened a pre-ablation db cleanly on CI); `commitments`
  # SELECTs the full commitment shape and trips on any old schema.
  if "$ACC_BIN" --db "$DB" status >/dev/null 2>&1 && "$ACC_BIN" --db "$DB" commitments >/dev/null 2>&1; then
    phase_result "substrate" "ok" "substrate exists at $DB (opens clean — preserved, never clobbered)"
  else
    phase_result "substrate" "failed" "substrate at $DB does not open with this binary (schema from a different epoch?)" "update acc to the latest release; your Work Model is preserved (never modify, move, or delete the db)"; exit 1
  fi
elif [ "$DRY_RUN" = "1" ]; then
  phase_result "substrate" "would" "create a fresh substrate at $DB" "phase 8: embedder daemon"
elif act "initialize substrate at $DB" "$ACC_BIN" --db "$DB" status >/dev/null 2>&1; then
  phase_result "substrate" "ok" "substrate initialized at $DB"
else
  phase_result "substrate" "skipped" "could not init substrate (created on first ingest)" "acc --db $DB ingest hello \"hi\""
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 8 — warm embedder daemon. A connect-check LIES about warmth (the daemon binds its
# socket BEFORE the model loads) — truth = one real encode round-trip with a short timeout.
# The model itself was prefetched in phase 6, so the first warm-up no longer hides a
# multi-GB download (a skipped prefetch still downloads lazily here).
# ════════════════════════════════════════════════════════════════════════════════════════
emb_warm() {
  python3 - "$EMB_SOCK" <<'PY' 2>/dev/null
import socket, json, sys
s = socket.socket(socket.AF_UNIX); s.settimeout(3)
try:
    s.connect(sys.argv[1]); s.sendall(b'{"text":"warm?","q":true}\n')
    sys.exit(0 if json.loads(s.makefile().readline()).get("vectors") else 1)
except Exception:
    sys.exit(1)
PY
}
step "phase 8 — warm embedder daemon"
if emb_warm; then
  phase_result "embedder_daemon" "ok" "embedder already warm on $EMB_SOCK"
elif [ "$DRY_RUN" = "1" ]; then
  phase_result "embedder_daemon" "would" "start the embedder daemon (model $MODEL_ID on $DEVICE; weights prefetched in phase 6 — a skipped prefetch downloads lazily here)" "phase 9: browser"
else
  act "start the embedder daemon (model loads in background)" bash -c 'nohup "'"$ACC_BIN"'" embedder >/tmp/acc-embedder.log 2>&1 &'
  phase_result "embedder_daemon" "ok" "embedder starting — model loads in background (first run downloads it). Log: /tmp/acc-embedder.log" "phase 9: browser"
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 9 — browser capability (Camoufox, host-side). Optional (ACC_NO_BROWSER=1).
# install.sh installs the Python env + browser (first-run accelerator); the binary
# (src/converge.rs) OWNS broker.py restore + daemon spawn + runtime:browser seed.
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 9 — browser capability (Camoufox, host-side)"
if [ "${ACC_NO_BROWSER:-0}" = "1" ]; then
  phase_result "browser" "skipped" "ACC_NO_BROWSER=1 — browser capability skipped"
elif [ -x "$BROWSER_VENV/bin/camoufox" ] && [ -x "$BROWSER_VENV/bin/python" ]; then
  phase_result "browser" "ok" "browser venv already provisioned at $BROWSER_VENV"
elif [ "$DRY_RUN" = "1" ]; then
  phase_result "browser" "would" "create browser venv at $BROWSER_VENV; install camoufox+playwright; fetch Camoufox" "phase 10: seed"
else
  act "create browser dirs" mkdir -p "$BROWSER_HOME/profiles"
  [ -x "$BROWSER_VENV/bin/python" ] || act "create browser venv" uv venv "$BROWSER_VENV" >/dev/null
  act "install camoufox + playwright" uv pip install --python "$BROWSER_VENV/bin/python" -q camoufox playwright
  if [ "$OS" = "Linux" ]; then
    maybe_sudo "$BROWSER_VENV/bin/playwright" install-deps firefox >/dev/null 2>&1 \
      && ok "browser system libs installed" \
      || warn "could not auto-install browser system libs — if the browser fails, run: sudo $BROWSER_VENV/bin/playwright install-deps firefox"
  fi
  act "fetch Camoufox browser (idempotent)" "$BROWSER_VENV/bin/camoufox" fetch >/dev/null 2>&1 \
    && phase_result "browser" "ok" "Camoufox browser installed — runtime:browser seeds in phase 10 once the embedder is warm" "phase 10: seed" \
    || phase_result "browser" "skipped" "camoufox fetch reported an issue" "re-run; or: $BROWSER_VENV/bin/camoufox fetch"
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 10 — seed core runtimes (waits for the embedder to warm). Seeding encodes with the
# REAL embedder, so it must be warm first. Convergence (broker.py restore + daemon spawn +
# runtime:browser seed) lives in the BINARY (src/converge.rs); `browser start` triggers it.
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 10 — seed core runtimes (waits for the embedder)"
if [ "$DRY_RUN" = "1" ]; then
  phase_result "seed" "would" "wait for the embedder to warm, then converge the browser daemon + seed runtime:browser" "phase 11: wiring"
elif [ "$NONINTERACTIVE" = "1" ]; then
  # NON-INTERACTIVE (piped / captured / agent shell / ACC_NONINTERACTIVE=1): the blocking
  # 600s warm-wait below would hide the multi-GB first-run model download inside a synchronous
  # loop — an agent's Bash-tool TIMEOUT kills the install mid-wait, leaving a half-state and
  # never printing the next-step guidance. The critical path (binary, .mcp.json, hooks) is
  # complete or runs in the phases AFTER this one; the embedder warms in the BACKGROUND on its
  # own. So SKIP the wait entirely, name the background warm + how to check it, and let the
  # remaining phases (wiring, verify) run so the script EXITS PROMPTLY. (warm stays 0 → the
  # final verdict prints the honest "warming in background" path, not happy-path try-these.)
  warm=0; emb_died=0
  phase_result "seed" "skipped" "non-interactive install: not blocking on the embedder warm-up (your Work Model warms up in the background — downloading the model, several GB on first run). Check progress in a few minutes with: acc --db $DB doctor" "acc --db $DB browser start (after the model finishes loading)"
else
  say "waiting for the embedder (first run may download the model — several GB, takes minutes)…"
  warm=0; emb_died=0
  for i in $(seq 0 599); do
    if emb_warm; then warm=1; break; fi
    # LIVENESS CHECK: a crash-on-start (CUDA OOM, missing driver, import error) would otherwise
    # burn the full 600s printing 'not ready' lines then a bare timeout. The daemon records its
    # pid in $EMB_SOCK.pid ({"daemon_pid":N,…}); if that process is gone, the daemon EXITED — stop
    # waiting now and surface the log instead of sleeping out the clock.
    emb_pid="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("daemon_pid",""))
except Exception:
    pass' "${EMB_SOCK}.pid" 2>/dev/null || echo '')"
    if [ -n "$emb_pid" ] && ! kill -0 "$emb_pid" 2>/dev/null; then
      emb_died=1
      say "[embedder] daemon process exited — see /tmp/acc-embedder.log"
      break
    fi
    [ $((i % 10)) -eq 0 ] && [ "$i" -gt 0 ] && say "[embedder wait ${i}s/600s] model loading into memory/VRAM (weights were pre-fetched in phase 6; first load takes a moment) (log: /tmp/acc-embedder.log)"
    # PERMANENT-FAILURE SCAN (install-side never-silent invariant, cf. solved:e60ca6342725ecf0):
    # the daemon is a SUPERVISOR that respawns a crash-looping worker, so the pid check above
    # never fires on a hard ImportError / bad-model load — the worker dies, the daemon lives, and
    # the loop burns the full 600s printing "still downloading". Scan the embedder log for a
    # TERMINAL signature (none of these are transient-download messages) and bail NOW with the
    # real error, routed through the emb_died branch (which prints the actionable fix).
    if [ "$i" -ge 3 ] && [ -f /tmp/acc-embedder.log ] \
       && grep -Eq 'ImportError|cannot import name|WARMUP FAILED|WORKER CRASH-LOOP|refusing respawn|serve failed' /tmp/acc-embedder.log 2>/dev/null; then
      emb_died=1
      say "[embedder] hard failure detected in /tmp/acc-embedder.log — not waiting out the 10-min clock"
      break
    fi
    sleep 1
  done
  if [ "$warm" = "1" ]; then
    [ "${i:-0}" -gt 0 ] && say "embedder ready after ~${i}s"
    if [ "${ACC_NO_BROWSER:-0}" != "1" ]; then
      "$ACC_BIN" --db "$DB" browser start >/dev/null 2>&1 \
        && phase_result "seed" "ok" "converged browser daemon + seeded runtime:browser" "phase 11: wiring" \
        || phase_result "seed" "skipped" "browser convergence reported an issue (see /tmp/acc-browser.log)" "acc --db $DB browser start"
    else
      phase_result "seed" "ok" "embedder warm (browser skipped)" "phase 11: wiring"
    fi
  else
    # On EITHER an early exit (the daemon crashed) OR the 600s timeout, tail the embedder log so
    # CUDA/driver/import errors surface instead of a bare 'did not warm' — guarded so a missing log
    # never errors the phase.
    if [ -f /tmp/acc-embedder.log ]; then
      say "── last lines of /tmp/acc-embedder.log ──"
      tail -n 20 /tmp/acc-embedder.log 2>/dev/null | while IFS= read -r line; do say "  $line"; done
      say "──────────────────────────────────────────"
    fi
    if [ "$emb_died" = "1" ]; then
      phase_result "seed" "skipped" "embedder daemon exited before warming (see the log tail above + /tmp/acc-embedder.log — likely CUDA/driver/import error)" "fix the error above, then: acc embedder &  ·  acc --db $DB browser start"
    else
      phase_result "seed" "skipped" "embedder did not warm within 10min (see the log tail above + /tmp/acc-embedder.log)" "seed later: acc --db $DB browser start (after the model finishes loading)"
    fi
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 11 — wiring: register acc as an MCP server (project-local .mcp.json). Relative
# "acc.db" on purpose — Claude Code launches MCP servers from the project dir, so the file
# stays clone-portable. "alwaysLoad": true skips MCP tool-search deferral (the two verbs are
# the kernel interface — they must never be lazy-loaded). Idempotent: a complete acc entry
# is left unchanged; a pre-alwaysLoad entry is upgraded IN PLACE (key added, rest preserved).
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 11 — register acc as an MCP server (.mcp.json)"
if [ "$REPO_IS_CLONE" = "1" ]; then
  # The clone dir is NOT a project the user works in — wiring .mcp.json there is dead config
  # (Claude Code launches MCP servers from the dir the user OPENS, never the hidden clone).
  # The one-Work-Model pivot: Claude Code is now wired GLOBALLY in phase 13 (`acc hosts-sync`
  # registers the user-scope ~/.claude.json mcpServers.acc on the ONE global db), so NO
  # per-project step is needed — acc works in every directory the moment phase 13 runs. We
  # record the honest skip here; phase 13 does the real global wiring.
  phase_result "mcp_wiring" "skipped" "global install — not wiring .mcp.json into the hidden clone dir ($REPO). Claude Code is wired GLOBALLY in phase 13 (acc hosts-sync → ~/.claude.json, one global Work Model) — no per-project step needed." "phase 13 wires Claude Code globally (acc hosts-sync)"
elif [ "$DRY_RUN" = "1" ]; then
  if [ -f "$REPO/.mcp.json" ] && python3 -c 'import json,sys;e=json.load(open(sys.argv[1])).get("mcpServers",{}).get("acc");sys.exit(0 if isinstance(e,dict) and e.get("alwaysLoad") is True else 1)' "$REPO/.mcp.json" 2>/dev/null; then
    phase_result "mcp_wiring" "ok" ".mcp.json already registers the acc server with alwaysLoad (would leave unchanged)"
  else
    phase_result "mcp_wiring" "would" "write project-local .mcp.json (server: acc · db: acc.db, relative · alwaysLoad: true)" "phase 11b: hooks wiring"
  fi
else
  MCP_RESULT="$(python3 - <<'PY'
import json, pathlib
path = pathlib.Path(".mcp.json")
acc = {"command": "acc", "args": ["--db", "acc.db", "mcp"], "alwaysLoad": True}
if path.exists():
    try:
        data = json.loads(path.read_text())
    except Exception:
        print("FAIL .mcp.json exists but is not valid JSON — fix it or paste manually"); raise SystemExit
else:
    data = {}
servers = data.setdefault("mcpServers", {})
entry = servers.get("acc")
if isinstance(entry, dict):
    if entry.get("alwaysLoad") is True:
        print("KEPT .mcp.json already has a complete acc entry — left unchanged")
    else:
        entry["alwaysLoad"] = True  # upgrade in place: add the key, preserve the rest
        path.write_text(json.dumps(data, indent=2) + "\n")
        print("UPGRADED .mcp.json acc entry in place — added alwaysLoad: true (rest preserved)")
else:
    servers["acc"] = acc
    path.write_text(json.dumps(data, indent=2) + "\n")
    print("WROTE project-local .mcp.json (server: acc · db: acc.db, relative on purpose · alwaysLoad: true)")
PY
)"
  case "$MCP_RESULT" in
    WROTE*|KEPT*|UPGRADED*) phase_result "mcp_wiring" "ok" "${MCP_RESULT#* }" "phase 11b: hooks wiring" ;;
    *)                      phase_result "mcp_wiring" "skipped" "${MCP_RESULT#* }" "edit .mcp.json by hand or re-run" ;;
  esac
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 11b — wiring: register acc's Claude Code hooks (`acc hooks-wire` →
# .claude/settings.json). A binary-only public install ships NO tracked .claude/settings.json,
# so without this NONE of acc's hooks register — the cold-start briefing, prompt grounding,
# and the Stop substrate-binding guard silently never fire. The subcommand carries the
# eight-event registrations COMPILED-IN (no runtime hooks.json dependency), merges them
# ADD-ONLY (any pre-existing non-acc hook is preserved), is IDEMPOTENT, and is DEV-CLONE-AWARE
# (a git-tracked settings.json — this repo — is left UNCHANGED so the install creates no
# spurious diffs). Mirrors the .mcp.json phase: dry-run-aware, honest phase_result line.
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 11b — register acc's Claude Code hooks (.claude/settings.json)"
HOOKS_BIN="$ACC_BIN"
[ -x "$HOOKS_BIN" ] || HOOKS_BIN="$(command -v acc || true)"
if [ "$REPO_IS_CLONE" = "1" ]; then
  # Same as phase 11: the hidden clone is not a project the user opens, so wiring its
  # .claude/settings.json is dead. The one-Work-Model pivot: phase 13 (`acc hosts-sync`) now
  # writes acc's hooks GLOBALLY into ~/.claude/settings.json (the user settings), so the hooks
  # fire in every directory — no per-project step. Record the honest skip; phase 13 does it.
  phase_result "hooks_wiring" "skipped" "global install — not wiring .claude/settings.json into the hidden clone dir ($REPO). Claude Code hooks are wired GLOBALLY in phase 13 (acc hosts-sync → ~/.claude/settings.json) — no per-project step needed." "phase 13 wires Claude Code globally (acc hosts-sync)"
elif [ -z "$HOOKS_BIN" ] || [ ! -x "$HOOKS_BIN" ]; then
  phase_result "hooks_wiring" "skipped" "acc binary not available yet (dry-run on a fresh host) — run \`acc hooks-wire\` after the real install" "acc hooks-wire"
elif [ "$DRY_RUN" = "1" ]; then
  # Dry-run: report the verdict WITHOUT writing. On the dev clone (tracked settings.json) the
  # subcommand itself is a no-op, but the installer must not invoke a mutating path in dry-run;
  # describe the would-action. A tracked settings.json reports KEPT honestly via the probe below.
  if [ -f "$REPO/.claude/settings.json" ] && git -C "$REPO" ls-files --error-unmatch .claude/settings.json >/dev/null 2>&1; then
    phase_result "hooks_wiring" "ok" ".claude/settings.json is git-tracked (dev clone) — would leave unchanged (the clone ships the wiring; rewriting it would create spurious diffs)" "phase 12: claude plugin"
  elif [ -f "$REPO/.claude/settings.json" ] && grep -q 'acc hook ' "$REPO/.claude/settings.json" 2>/dev/null; then
    phase_result "hooks_wiring" "ok" ".claude/settings.json already registers acc's hooks (would leave unchanged)" "phase 12: claude plugin"
  else
    phase_result "hooks_wiring" "would" "register acc's eight-event hook lifecycle into .claude/settings.json (add-only; cold-start briefing · prompt grounding · Stop guard)" "phase 12: claude plugin"
  fi
else
  if HOOKS_OUT="$("$HOOKS_BIN" hooks-wire "$REPO" 2>&1)"; then
    case "$HOOKS_OUT" in
      WROTE*|MERGED*|KEPT*) phase_result "hooks_wiring" "ok" "$HOOKS_OUT" "phase 12: claude plugin" ;;
      *)                    phase_result "hooks_wiring" "skipped" "$HOOKS_OUT" "acc hooks-wire" ;;
    esac
  else
    phase_result "hooks_wiring" "skipped" "acc hooks-wire reported an issue: $HOOKS_OUT (fail-soft — re-run \`acc hooks-wire\`)" "acc hooks-wire"
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 12 — claude plugin (the DISTRIBUTION artifact). Validates the versioned plugin
# folder's manifests (claude-plugin/) with python3 json.load and prints how to use the
# plugin in OTHER projects. This phase deliberately does NOT rewire this repo's own
# .claude/settings.json — the repo keeps direct hook wiring; the plugin folder exists so
# other projects can consume the same eight-event lifecycle + the two MCP verbs. Pure
# read (idempotent, fail-soft): a broken manifest warns and the install continues.
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 12 — claude plugin manifests (distribution artifact)"
PLUGIN_DIR="$REPO/claude-plugin"
PLUGIN_BAD=""
for m in .claude-plugin/plugin.json hooks/hooks.json .mcp.json; do
  if [ ! -f "$PLUGIN_DIR/$m" ]; then
    PLUGIN_BAD="$PLUGIN_BAD $m(missing)"
  elif ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$PLUGIN_DIR/$m" >/dev/null 2>&1; then
    PLUGIN_BAD="$PLUGIN_BAD $m(invalid-json)"
  fi
done
if [ -n "$PLUGIN_BAD" ]; then
  phase_result "claude_plugin" "failed" "claude-plugin/ manifest check:$PLUGIN_BAD" "fix the manifest(s) under claude-plugin/ — fail-soft, install continues (this repo's .claude/settings.json is untouched either way)"
else
  say "this repo keeps DIRECT hook wiring in .claude/settings.json — nothing here is rewired; the plugin folder is the distribution artifact for OTHER projects"
  say "use it elsewhere:   claude --plugin-dir $PLUGIN_DIR"
  say "or copy the skills: cp -r $PLUGIN_DIR/skills/* <project>/.claude/skills/"
  phase_result "claude_plugin" "ok" "claude-plugin/ manifests valid (plugin.json · hooks/hooks.json · .mcp.json) — distribution artifact only; this repo's own wiring untouched" "phase 13: hosts-sync"
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 13 — host wiring: `acc hosts-sync` converges EVERY coding agent installed on this
# machine onto the ONE global substrate — the one-Work-Model pivot. ALL FOUR agents wire
# GLOBALLY here: Claude Code (user-scope ~/.claude.json mcpServers.acc + ~/.claude/settings.json
# hooks, on the canonical global db), OpenCode, Codex CLI, Cursor — each two-verb MCP +
# lifecycle recording, ADD-ONLY (an existing acc entry is never rewritten; drift is reported),
# one .acc-backup-<ts> sibling per actually-changed file. So a fresh install leaves all agents
# working on one compounding memory with NO per-project step. Fail-soft: wiring an agent is
# convenience — it never fails the install. Honors --dry-run (unified-diff preview, nothing
# written) and ACC_HOSTS_SYNC=off (no-op inside the binary). Idempotent + re-runnable: install
# a new agent later and just re-run `acc hosts-sync` (or start a session — the fingerprint
# trigger re-converges). The OPTIONAL isolation override is `acc hosts-sync --project .`
# (a separate per-project .mcp.json + db for confidential/separated work).
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 13 — wire installed coding agents globally (acc hosts-sync)"
HOSTS_BIN="$ACC_BIN"
[ -x "$HOSTS_BIN" ] || HOSTS_BIN="$(command -v acc || true)"
if [ -z "$HOSTS_BIN" ] || [ ! -x "$HOSTS_BIN" ]; then
  phase_result "hosts_sync" "skipped" "acc binary not available yet (dry-run on a fresh host) — run \`acc hosts-sync\` after the real install" "acc hosts-sync"
elif [ "$DRY_RUN" = "1" ]; then
  HOSTS_OUT="$("$HOSTS_BIN" hosts-sync --dry-run 2>&1)" || true
  printf '%s\n' "$HOSTS_OUT" | while IFS= read -r line; do [ -n "$line" ] || continue; say "$line"; done
  phase_result "hosts_sync" "would" "converge installed coding agents (preview above — add-only; nothing written in dry-run)" "phase 14: verify"
else
  if HOSTS_OUT="$("$HOSTS_BIN" hosts-sync 2>&1)"; then
    printf '%s\n' "$HOSTS_OUT" | while IFS= read -r line; do [ -n "$line" ] || continue; say "$line"; done
    phase_result "hosts_sync" "ok" "installed coding agents converged (per-host lines above; re-run \`acc hosts-sync\` after installing a new agent)" "phase 14: verify"
  else
    printf '%s\n' "$HOSTS_OUT" | while IFS= read -r line; do [ -n "$line" ] || continue; say "$line"; done
    phase_result "hosts_sync" "skipped" "acc hosts-sync reported an issue (fail-soft — host wiring never blocks an install)" "acc hosts-sync"
  fi
fi

# The RESPECT REPORT (read-only; G1, solved:f35b42f4a6700656): name what the user's
# environment already contains — their MCP servers, hooks, skills, memory files — and
# state acc's exact additive footprint. An installer that shows what it did NOT touch
# earns trust. Fail-soft: a survey fault never blocks an install.
if [ -n "$HOSTS_BIN" ] && [ -x "$HOSTS_BIN" ] && [ "$DRY_RUN" != "1" ]; then
  SURVEY_OUT="$("$HOSTS_BIN" hosts-sync --survey 2>&1)" || true
  printf '%s\n' "$SURVEY_OUT" | while IFS= read -r line; do [ -n "$line" ] || continue; say "$line"; done
fi

# Consented environment understanding (P2): notice who the user is from PUBLIC signals
# only (git identity, locale, timezone, OS/arch, project name), seed user_profile:current
# ONLY-IF-ABSENT per field, and DISCLOSE every stored fact + its source (the "noticed: …"
# line surfaced below) — so the very first session greets them by name in their language.
# Local-only: facts live in acc.db, never sent anywhere; view: `acc profile show`,
# remove: `acc profile clear`. Fail-soft: a seed fault never blocks an install. The seed
# is non-interactive by design (it never prompts), so ACC_NONINTERACTIVE needs no
# special-casing here.
if [ "$DRY_RUN" = "1" ]; then
  say "WOULD: seed profile from environment (git identity, locale, timezone — disclosed, local-only)"
elif [ -n "$HOSTS_BIN" ] && [ -x "$HOSTS_BIN" ]; then
  SEED_OUT="$("$HOSTS_BIN" --db "$DB" profile seed 2>&1)" || true
  printf '%s\n' "$SEED_OUT" | while IFS= read -r line; do [ -n "$line" ] || continue; say "$line"; done
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 14 — verify: `acc doctor` (the end-to-end self-check). In --json mode the final
# stream line is the verdict + the `acc doctor --json` handoff for Claude-as-installer.
# In dry-run nothing was mutated, so doctor would report the CURRENT (pre-install) state.
# ════════════════════════════════════════════════════════════════════════════════════════
step "phase 14 — verify (acc doctor)"
if [ "$DRY_RUN" = "1" ]; then
  phase_result "verify" "would" "run: acc --db $DB doctor (proves binary/substrate/embedder/model_pin/sandbox/mcp/hooks/brain)" "acc --db $DB doctor --json"
else
  if [ "$JSON" = "1" ]; then
    DOC_JSON="$("$ACC_BIN" --db "$DB" doctor --json 2>/dev/null || echo '{"schema":"acc.doctor.v1","status":"unknown"}')"
    DOC_STATUS="$(printf '%s' "$DOC_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("status","unknown"))' 2>/dev/null || echo unknown)"
    case "$DOC_STATUS" in
      ok)   json_phase "verify" "ok" "acc doctor: $DOC_STATUS" "acc --db $DB doctor --json" ;;
      *)    json_phase "verify" "ok" "acc doctor: $DOC_STATUS (degraded layers are normal on a fresh install — see the doctor report)" "acc --db $DB doctor --json" ;;
    esac
  else
    "$ACC_BIN" --db "$DB" doctor || true
  fi
fi

# ════════════════════════════════════════════════════════════════════════════════════════
# PHASE 15 — telemetry (anonymous usage events, ON by default). The key below is the project's
# WRITE-ONLY PostHog token — public-safe by design (it can only append events, never read).
# Events are NAMES ONLY — never owner data, prompts, files, or memory. On by default so the
# maintainer can see what breaks for real users; opt out any time with `acc telemetry off`, or
# set ACC_NO_TELEMETRY=1 before install to never enable it. Fail-soft: a CLI error never fails
# the install.
# ════════════════════════════════════════════════════════════════════════════════════════
TELEMETRY_KEY="phc_A5xgn9QqiSCKXivifKGEBPrpSZDwvFyxm5op974q3ekC"
TELEMETRY_LATER="enable later: acc telemetry on --key <your key> --host us (works with any PostHog project)"
TELEMETRY_OPTOUT="opt out any time: acc telemetry off  (or set ACC_NO_TELEMETRY=1 before install)"

step "phase 15 — telemetry (anonymous usage events, on by default)"
if [ "$DRY_RUN" = "1" ]; then
  phase_result "telemetry" "would" "enable anonymous usage telemetry by default (event names only — never your data, prompts, files, or Work Model; opt-out: acc telemetry off)"
elif [ "${ACC_NO_TELEMETRY:-0}" = "1" ]; then
  phase_result "telemetry" "skipped" "ACC_NO_TELEMETRY=1 — telemetry stays off" "$TELEMETRY_LATER"
elif "$ACC_BIN" telemetry on --key "$TELEMETRY_KEY" --host us >/dev/null 2>&1; then
  # One real event: `telemetry status` runs the app_opened instrumentation, queued through the
  # normal pipeline (no custom capture path here).
  "$ACC_BIN" telemetry status >/dev/null 2>&1 || true
  phase_result "telemetry" "ok" "anonymous usage telemetry ON (event names only — never your data, prompts, files, or Work Model). $TELEMETRY_OPTOUT"
else
  phase_result "telemetry" "skipped" "could not enable telemetry (non-fatal) — $TELEMETRY_LATER"
fi

# ── final verdict ─────────────────────────────────────────────────────────────────────
# Update-mode one-line summary: old → new binary identity (token 2 of `acc --version`).
NEW_ACC_ID=""
[ "$DRY_RUN" != "1" ] && [ -n "${ACC_BIN:-}" ] && [ -x "$ACC_BIN" ] && NEW_ACC_ID="$("$ACC_BIN" --version 2>/dev/null | awk 'NR==1{print $2}' || echo '')"
if [ "$JSON" = "1" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    json_phase "verdict" "would" "dry-run complete: all phases walked, nothing mutated; tier=$TIER ($MODEL_ID on $DEVICE)" "run ./install.sh (no --dry-run) to install"
  elif [ "$UPDATE_MODE" = "1" ]; then
    json_phase "verdict" "ok" "updated ${OLD_ACC_ID:-<none>} → ${NEW_ACC_ID:-?}; tier=$TIER ($MODEL_ID on $DEVICE); Work Model at $DB untouched (schema migrates automatically on first open). Verify with the doctor handoff." "acc --db $DB doctor --json"
  else
    json_phase "verdict" "ok" "install complete; tier=$TIER ($MODEL_ID on $DEVICE). Verify with the doctor handoff." "acc --db $DB doctor --json"
  fi
  exit 0
fi

step "done"
if [ "$DRY_RUN" = "1" ]; then
  ok "dry-run complete — all phases walked, NOTHING mutated."
  say "Selected tier: $TIER · $MODEL_ID on $DEVICE"
  say "Run ./install.sh (no --dry-run) to install for real."
  exit 0
fi
# NEXT-STEP guidance. The one-Work-Model pivot: phase 13 wired ALL your agents (Claude Code,
# OpenCode, Codex, Cursor) GLOBALLY onto ONE compounding memory — they work in EVERY directory
# now, with no per-project step. So the next step is simply: open Claude Code anywhere and talk.
# The OPTIONAL isolation override (`acc hosts-sync --project .`) carves a project onto its own db.
cc_next_lines() {
  cat <<CCNEXT
Next — acc is wired into all your agents (Claude Code, OpenCode, Codex, Cursor) GLOBALLY on ONE
Work Model that compounds across every task and project. Open Claude Code in ANY directory and just
say what you want done in plain words ("research X", "draft an email to Y"). On first open it
shows what is set up and starts learning how you work; nothing leaves your machine without your OK.
(The two verbs acc_retrieve + acc_act appear after a restart / reload MCP if Claude Code is open.)
Optional — isolate a project on its OWN separate Work Model (confidential / separated work):
  cd <your-project> && acc hosts-sync --project .
The CLI lane works right now with no restart: acc --db $DB retrieve "…"  ·  acc --db $DB ingest …
CCNEXT
}

if [ "$UPDATE_MODE" = "1" ]; then
  ok "updated ${OLD_ACC_ID:-<none>} → ${NEW_ACC_ID:-?} — Work Model at $DB untouched (schema migrates automatically on first open)"
  printf '\nClaude Code: if it is open, reload MCP to pick up the new binary.\n'
elif [ "$NONINTERACTIVE" = "1" ] && [ "${warm:-0}" != "1" ]; then
  # NON-INTERACTIVE path: we deliberately SKIPPED the blocking warm-wait (phase 10), so the
  # embedder is warming in the BACKGROUND — this is NOT a failure. Print a clear line and exit
  # 0 promptly (an agent's captured stdout shows the next step without ever hitting its timeout).
  ok "acc installed. Your Work Model is warming up — downloading the model in the background (several GB on first run)."
  cat <<BGWARM

Check progress in a few minutes:
  acc --db $DB doctor        (expect: embedder OK once the model finishes loading)

Once the embedder is warm, retrieval is live. The CLI works immediately:
  acc --db $DB ingest hello "acc is live — the Work Model is recording"
  acc --db $DB retrieve "what acc is"   (works once the embedder reports OK above)

BGWARM
  cc_next_lines
elif [ "${warm:-0}" != "1" ]; then
  # DEGRADED honesty (interactive run, embedder really failed to warm): retrieve/ingest CANNOT
  # work yet — do NOT claim "complete" or print happy-path try-these that would just fail. Lead
  # with the ONE manual step the user must take next. (install is stage 0 of onboarding — name
  # the next action explicitly whenever manual recovery is required.)
  warn "acc installed, but the embedder (the encoder daemon) did NOT come up — retrieval + ingest won't work yet."
  cat <<DEGRADED

Fix this FIRST (then acc is fully live):
  1. See why it failed:   tail -n 30 /tmp/acc-embedder.log
  2. Start the embedder:  acc embedder            (first run downloads the model — several GB, minutes)
  3. Re-check health:     acc --db $DB doctor     (expect: embedder OK, verdict OK)
  4. Still stuck?         acc report              (builds a SANITIZED report — no Work Model data, no secrets, just
                          structural health — and prints a pre-filled GitHub issue link to file at
                          github.com/maxbaluev/accreted-intelligence/issues)

DEGRADED
  cc_next_lines
else
  ok "acc install complete — embedder warm, all systems live."
  cat <<TRY

Try these now:
  1. Check health:        acc --db $DB doctor
  2. Add one entry:       acc --db $DB ingest hello "acc is live — the Work Model is recording"
  3. Retrieve it:         acc --db $DB retrieve "what acc is"

TRY
  cc_next_lines
fi

# PATH-PERSIST ADVISORY (prebuilt lane): the binary lands in ~/.local/bin and this run exported
# it onto PATH, but only for THIS installer process — a NEW terminal that has ~/.local/bin missing
# from its shell rc gets 'acc: command not found'. We do NOT silently edit the user's shell rc;
# instead, when ~/.local/bin is absent from BOTH ~/.bashrc and ~/.profile, print the exact line to
# add + a 'new terminal' note so the user makes the change knowingly.
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
if [ -x "$BIN_DIR/acc" ]; then
  in_rc=0
  for rc in "$HOME/.bashrc" "$HOME/.profile"; do
    [ -f "$rc" ] && grep -qF "$BIN_DIR" "$rc" 2>/dev/null && { in_rc=1; break; }
  done
  if [ "$in_rc" = "0" ]; then
    EXPORT_LINE="export PATH=\"$BIN_DIR:\$PATH\""
    if [ "$PERSIST_PATH" = "1" ]; then
      # OPT-IN persist: the user explicitly asked us to edit their rc. Append the export to
      # ~/.bashrc when it exists, else ~/.profile; print exactly what we changed. We NEVER
      # reach this branch without --persist-path — the default stays advisory-print only.
      RC_TARGET="$HOME/.bashrc"; [ -f "$RC_TARGET" ] || RC_TARGET="$HOME/.profile"
      if [ "$DRY_RUN" = "1" ]; then
        say "WOULD append to $RC_TARGET: $EXPORT_LINE"
      else
        {
          printf '\n# added by acc install.sh --persist-path\n'
          printf '%s\n' "$EXPORT_LINE"
        } >> "$RC_TARGET"
        printf '\n%sPATH persisted%s\n' "$G_STEP" "$C_RESET"
        printf '  Appended to %s:\n' "$RC_TARGET"
        printf '      %s%s%s\n' "$C_BOLD" "$EXPORT_LINE" "$C_RESET"
        printf '  Start a new terminal (or `source %s`) to pick it up.\n' "$RC_TARGET"
      fi
    else
      printf '\n%sPATH note%s\n' "$G_STEP" "$C_RESET"
      printf '  acc is installed at %s, but that dir is not on your shell PATH for NEW terminals.\n' "$BIN_DIR"
      printf '  Add this line to your ~/.bashrc (or ~/.profile), then start a new terminal:\n'
      printf '      %s%s%s\n' "$C_BOLD" "$EXPORT_LINE" "$C_RESET"
      printf '  Or re-run with %s--persist-path%s to have the installer append it for you.\n' "$C_BOLD" "$C_RESET"
    fi
  fi
fi
