#!/usr/bin/env bash
# Build MCPB archives from the existing public GitHub release binaries.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

usage() {
  cat <<'EOF'
usage: scripts/package-mcpb.sh <tag> <target|all>

Examples:
  scripts/package-mcpb.sh v0.1.1 x86_64-unknown-linux-musl
  scripts/package-mcpb.sh v0.1.1 all

Outputs:
  dist/acc-mcp-<tag>-<target>.mcpb
  dist/acc-mcp-<tag>-<target>.sha256
  dist/server.<target>.json
  dist/server.mcpb-all.json (when target is all)
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

tag="${1:-}"
target="${2:-}"

if [ -z "$tag" ] || [ -z "$target" ]; then
  usage >&2
  exit 2
fi

case "$tag" in
  v*) version="${tag#v}" ;;
  *) version="$tag" ;;
esac

targets=(
  "aarch64-apple-darwin"
  "aarch64-unknown-linux-musl"
  "x86_64-unknown-linux-musl"
  "x86_64-pc-windows-msvc"
)

platform_for_target() {
  case "$1" in
    *-apple-darwin) printf 'darwin' ;;
    *-unknown-linux-musl) printf 'linux' ;;
    *-pc-windows-msvc) printf 'win32' ;;
    *) printf 'unknown' ;;
  esac
}

asset_ext_for_target() {
  case "$1" in
    *-pc-windows-msvc) printf 'zip' ;;
    *) printf 'tar.gz' ;;
  esac
}

build_one() {
  local build_target="$1"
  local platform asset_ext asset asset_url tmp extract_dir bundle_dir binary dest_name out sha

  platform="$(platform_for_target "$build_target")"
  if [ "$platform" = "unknown" ]; then
    printf 'unknown target: %s\n' "$build_target" >&2
    exit 2
  fi

  asset_ext="$(asset_ext_for_target "$build_target")"
  asset="acc-${tag}-${build_target}.${asset_ext}"
  asset_url="https://github.com/maxbaluev/accreted-intelligence/releases/download/${tag}/${asset}"
  tmp="$(mktemp -d)"
  extract_dir="$tmp/extract"
  bundle_dir="$tmp/bundle"

  cleanup() {
    rm -rf "$tmp"
  }
  trap cleanup RETURN

  mkdir -p "$extract_dir" "$bundle_dir/server" dist

  printf 'downloading %s\n' "$asset_url"
  curl -fsSL "$asset_url" -o "$tmp/$asset"

  case "$asset_ext" in
    zip) unzip -q "$tmp/$asset" -d "$extract_dir" ;;
    tar.gz) tar -xzf "$tmp/$asset" -C "$extract_dir" ;;
  esac

  if [ "$platform" = "win32" ]; then
    binary="$(find "$extract_dir" -type f -name 'acc.exe' -print -quit)"
    dest_name="acc.exe"
  else
    binary="$(find "$extract_dir" -type f -name 'acc' -print -quit)"
    dest_name="acc"
  fi

  if [ -z "$binary" ]; then
    printf 'could not find acc binary in %s\n' "$asset" >&2
    exit 1
  fi

  cp mcpb/manifest.json "$bundle_dir/manifest.json"
  cp "$binary" "$bundle_dir/server/$dest_name"
  chmod 0755 "$bundle_dir/server/$dest_name"

  python3 - "$bundle_dir/manifest.json" "$version" "$build_target" "$platform" "$dest_name" <<'PY'
import json
import sys
from pathlib import Path

manifest_path, version, target, platform, dest_name = sys.argv[1:]
path = Path(manifest_path)
data = json.loads(path.read_text())

data["version"] = version
data["compatibility"] = {"platforms": [platform]}
server = data["server"]
server["entry_point"] = f"server/{dest_name}"
server["mcp_config"]["command"] = "${__dirname}/" + f"server/{dest_name}"
server["mcp_config"].pop("platform_overrides", None)
data.setdefault("_meta", {})["io.github.maxbaluev.accreted-intelligence"] = {
    "releaseTarget": target
}

path.write_text(json.dumps(data, indent=2, sort_keys=False) + "\n")
PY

  out="dist/acc-mcp-${tag}-${build_target}.mcpb"
  python3 - "$bundle_dir" "$out" <<'PY'
import stat
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
out = Path(sys.argv[2])

with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as zf:
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        rel = path.relative_to(root).as_posix()
        info = zipfile.ZipInfo(rel)
        mode = path.stat().st_mode
        info.external_attr = (mode & 0xFFFF) << 16
        if mode & stat.S_IXUSR:
            info.external_attr |= 0o111 << 16
        with path.open("rb") as handle:
            zf.writestr(info, handle.read())
PY

  sha="$(sha256sum "$out" | awk '{print $1}')"
  printf '%s  %s\n' "$sha" "$out" | tee "dist/acc-mcp-${tag}-${build_target}.sha256"

  python3 - registry/server.template.json "dist/server.${build_target}.json" "$tag" "$version" "$build_target" "$sha" <<'PY'
import json
import sys
from pathlib import Path

template, output, tag, version, target, sha = sys.argv[1:]
data = json.loads(Path(template).read_text())
data["version"] = version
pkg = data["packages"][0]
pkg["identifier"] = (
    "https://github.com/maxbaluev/accreted-intelligence/releases/download/"
    f"{tag}/acc-mcp-{tag}-{target}.mcpb"
)
pkg["fileSha256"] = sha
data["_meta"]["io.modelcontextprotocol.registry/publisher-provided"] = {
    "packager": "scripts/package-mcpb.sh",
    "releaseTarget": target
}
Path(output).write_text(json.dumps(data, indent=2) + "\n")
PY
}

write_all_server_json() {
  python3 - registry/server.template.json dist/server.mcpb-all.json "$version" "${targets[@]}" <<'PY'
import json
import sys
from pathlib import Path

template, output, version, *targets = sys.argv[1:]
data = json.loads(Path(template).read_text())
data["version"] = version
packages = []

for target in targets:
    generated = Path(f"dist/server.{target}.json")
    if not generated.exists():
        raise SystemExit(f"missing generated server file: {generated}")
    package = json.loads(generated.read_text())["packages"][0]
    packages.append(package)

data["packages"] = packages
data["_meta"]["io.modelcontextprotocol.registry/publisher-provided"] = {
    "packager": "scripts/package-mcpb.sh",
    "releaseTargets": targets,
}
Path(output).write_text(json.dumps(data, indent=2) + "\n")
PY
  printf 'wrote %s\n' "dist/server.mcpb-all.json"
}

if [ "$target" = "all" ]; then
  for one in "${targets[@]}"; do
    build_one "$one"
  done
  write_all_server_json
else
  build_one "$target"
fi
