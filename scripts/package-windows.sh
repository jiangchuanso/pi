#!/usr/bin/env bash
#
# Package the Windows pi binaries into NSIS installers (.exe).
# Mirrors the layout produced by scripts/build-binaries.sh: each platform
# directory (e.g. binaries-out/windows-x64) contains pi.exe plus all runtime
# assets (photon_rs_bg.wasm, theme/, assets/, native/, ...) which pi resolves
# relative to the executable. We preserve that exact tree under $INSTDIR.
#
# Usage:
#   ./scripts/package-windows.sh <binaries-dir> <out-dir> [version]
#
# Requires: makensis (apt-get install -y nsis on Linux CI runners)
#
# Output (in <out-dir>):
#   pi-setup-windows-x64.exe
#   pi-setup-windows-arm64.exe

set -euo pipefail

cd "$(dirname "$0")/.."

BINARIES_DIR="${1:?usage: package-windows.sh <binaries-dir> <out-dir> [version]}"
OUT_DIR="${2:?missing out-dir}"
VERSION="${3:-}"

mkdir -p "$OUT_DIR"

if ! command -v makensis >/dev/null 2>&1; then
  echo "::error::makensis not found. Install it with: apt-get install -y nsis" >&2
  exit 1
fi

# Emit NSIS File/SetOutPath lines that reproduce <src> under $INSTDIR,
# grouped by directory to minimize SetOutPath switches.
emit_files() {
  local src="$1" prev=""
  ( cd "$src" && find . -type f | sort ) | while IFS= read -r f; do
    local rel="${f#./}"
    local dir
    dir="$(dirname "$rel")"
    if [[ "$dir" != "$prev" ]]; then
      if [[ "$dir" == "." ]]; then
        printf '  SetOutPath "$INSTDIR"\n'
      else
        printf '  SetOutPath "$INSTDIR/%s"\n' "$dir"
      fi
      prev="$dir"
    fi
    printf '  File "%s"\n' "$src/$rel"
  done
}

for arch in windows-x64 windows-arm64; do
  src="$BINARIES_DIR/$arch"
  if [[ ! -d "$src" ]]; then
    echo "::error::missing platform directory $src (upstream build layout may have changed)" >&2
    exit 1
  fi
  if [[ ! -f "$src/pi.exe" ]]; then
    echo "::error::missing $src/pi.exe (upstream build layout may have changed)" >&2
    exit 1
  fi

  out="$OUT_DIR/pi-setup-${arch}.exe"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # Fill @OUT@ / @VERSION@; the ;@FILES@ marker is left for the split below.
  sed -e "s|@OUT@|$out|g" -e "s|@VERSION@|${VERSION}|g" scripts/pi.nsi.template > "$tmp/pi.nsi"

  # Split template at the ;@FILES@ marker and inject the generated file list.
  awk '/;@FILES@/{f=1} !f{print}' "$tmp/pi.nsi" > "$tmp/final.nsi"
  emit_files "$src" >> "$tmp/final.nsi"
  awk 'f && !/;@FILES@/{print} /;@FILES@/{f=1}' "$tmp/pi.nsi" >> "$tmp/final.nsi"

  echo "==> Building NSIS installer for $arch"
  makensis "$tmp/final.nsi"

  if [[ ! -f "$out" ]]; then
    echo "::error::expected installer $out was not produced" >&2
    exit 1
  fi
  echo "==> Built $out ($(du -h "$out" | cut -f1))"
done
