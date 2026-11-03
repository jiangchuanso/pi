#!/usr/bin/env bash
#
# Package the macOS pi binaries into unsigned .dmg disk images.
# No Apple Developer account is available, so the image and its contents are
# NOT code-signed or notarized. Users must bypass Gatekeeper manually:
#   xattr -cr /usr/local/pi/pi
#   sudo spctl --add /usr/local/pi/pi
#
# The dmg root mirrors the tarball layout: pi (the binary) plus all runtime
# assets resolved relative to the executable, plus an install.command helper
# that installs everything to /usr/local/pi and links /usr/local/bin/pi.
#
# Usage:
#   ./scripts/package-dmg.sh <binaries-dir> <out-dir> [version]
#
# Requires: hdiutil (macOS only)
#
# Output (in <out-dir>):
#   pi-darwin-arm64.dmg
#   pi-darwin-x64.dmg

set -euo pipefail

cd "$(dirname "$0")/.."

BINARIES_DIR="${1:?usage: package-dmg.sh <binaries-dir> <out-dir> [version]}"
OUT_DIR="${2:?missing out-dir}"
VERSION="${3:-}"

mkdir -p "$OUT_DIR"

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "::error::hdiutil not found. This script must run on macOS." >&2
  exit 1
fi

for arch in darwin-arm64 darwin-x64; do
  src="$BINARIES_DIR/$arch"
  if [[ ! -d "$src" ]]; then
    echo "::error::missing platform directory $src (upstream build layout may have changed)" >&2
    exit 1
  fi
  if [[ ! -f "$src/pi" ]]; then
    echo "::error::missing $src/pi (upstream build layout may have changed)" >&2
    exit 1
  fi

  dmgroot="$(mktemp -d)/pi-dmg"
  mkdir -p "$dmgroot"

  # Mirror the tarball layout: binary + runtime assets at the dmg root.
  cp -r "$src/." "$dmgroot/"
  chmod +x "$dmgroot/pi"

  # Helper that installs to /usr/local/pi and links /usr/local/bin/pi.
  cat > "$dmgroot/install.command" <<'EOF'
#!/usr/bin/env bash
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DEST=/usr/local/pi
sudo mkdir -p "$DEST"
for item in pi photon_rs_bg.wasm theme assets export-html native docs examples package.json README.md CHANGELOG.md; do
  if [[ -e "$SRC/$item" ]]; then
    sudo cp -R "$SRC/$item" "$DEST/"
  fi
done
sudo chmod +x "$DEST/pi"
sudo ln -sf "$DEST/pi" /usr/local/bin/pi
echo "Pi installed to /usr/local/bin/pi"
/usr/local/bin/pi --version
EOF
  chmod +x "$dmgroot/install.command"

  cat > "$dmgroot/README.txt" <<EOF
Pi ${VERSION} for macOS (unsigned, not notarized)

This build was produced without an Apple Developer account, so macOS Gatekeeper
will block it on first run. Allow it once with:

  xattr -cr /usr/local/pi/pi
  sudo spctl --add /usr/local/pi/pi

Install:
  - Double-click install.command (copies pi + assets to /usr/local/pi and
    links /usr/local/bin/pi), or
  - Copy "pi" (and its sibling folders) to a directory already on your PATH.

Run:
  pi --version
EOF

  # Familiar "drag here" target for the Finder window.
  ln -s /Applications "$dmgroot/Applications"

  out="$OUT_DIR/pi-${arch}.dmg"
  echo "==> Building .dmg for $arch"
  hdiutil create -volname "Pi ${VERSION} (${arch})" -srcfolder "$dmgroot" -ov -format UDZO "$out" >/dev/null

  if [[ ! -s "$out" ]]; then
    echo "::error::expected image $out was not produced" >&2
    exit 1
  fi
  echo "==> Built $out ($(du -h "$out" | cut -f1))"
done
