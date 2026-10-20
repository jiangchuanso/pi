#!/usr/bin/env bash
#
# Package the Linux pi binaries into .deb packages.
# Layout: /opt/pi holds pi + all runtime assets (resolved relative to the
# executable by pi), and /usr/bin/pi symlinks to it so `pi` is on PATH.
#
# Usage:
#   ./scripts/package-deb.sh <binaries-dir> <out-dir> [version]
#
# Requires: dpkg-deb (installed on any Debian/Ubuntu CI runner)
#
# Output (in <out-dir>):
#   pi-linux-x64.deb
#   pi-linux-arm64.deb

set -euo pipefail

cd "$(dirname "$0")/.."

BINARIES_DIR="${1:?usage: package-deb.sh <binaries-dir> <out-dir> [version]}"
OUT_DIR="${2:?missing out-dir}"
VERSION="${3:-}"

mkdir -p "$OUT_DIR"

if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "::error::dpkg-deb not found. Install it with: apt-get install -y dpkg-dev" >&2
  exit 1
fi

# linux arch -> Debian architecture
declare -A DEBARCH=( [linux-x64]=amd64 [linux-arm64]=arm64 )

for arch in linux-x64 linux-arm64; do
  src="$BINARIES_DIR/$arch"
  if [[ ! -d "$src" ]]; then
    echo "::error::missing platform directory $src (upstream build layout may have changed)" >&2
    exit 1
  fi
  if [[ ! -f "$src/pi" ]]; then
    echo "::error::missing $src/pi (upstream build layout may have changed)" >&2
    exit 1
  fi

  debarch="${DEBARCH[$arch]}"
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT

  # Install tree
  mkdir -p "$stage/opt/pi" "$stage/usr/bin" "$stage/DEBIAN"

  # Copy the entire platform tree (binary + runtime assets) into /opt/pi.
  cp -r "$src/." "$stage/opt/pi/"
  chmod 755 "$stage/opt/pi/pi"
  ln -s /opt/pi/pi "$stage/usr/bin/pi"

  # Control file
  cat > "$stage/DEBIAN/control" <<EOF
Package: pi
Version: ${VERSION}
Section: devel
Priority: optional
Architecture: ${debarch}
Depends: libc6
Maintainer: Pi <noreply@pi.dev>
Description: Pi coding agent
 Minimal, extensible agent harness that you can make your own.
EOF

  out="$OUT_DIR/pi-${arch}.deb"
  echo "==> Building .deb for $arch ($debarch)"
  dpkg-deb --build --root-owner-group "$stage" "$out" >/dev/null

  if [[ ! -s "$out" ]]; then
    echo "::error::expected package $out was not produced" >&2
    exit 1
  fi
  echo "==> Built $out ($(du -h "$out" | cut -f1))"
done
