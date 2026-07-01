#!/usr/bin/env bash
set -euo pipefail

REPODIR="$(cd "$(dirname "$0")/../.." && pwd)"

# If QB64_BIN_DIR is set, use that existing QB64-PE installation.
# Otherwise download and compile QB64-PE from the latest release.
if [ -n "${QB64_BIN_DIR:-}" ]; then
  QB64_DIR="$(realpath "$QB64_BIN_DIR")"
  echo "==> Using QB64-PE at $QB64_DIR"
else
  WORKDIR=$(mktemp -d)
  trap "rm -rf $WORKDIR" EXIT
  QB64_DIR="$WORKDIR/qb64pe"

  echo "==> Resolving QB64-PE Linux release asset..."
  RELEASE_JSON=$(curl -fsSL https://api.github.com/repos/QB64-Phoenix-Edition/QB64pe/releases/latest)
  ASSET_URL=$(echo "$RELEASE_JSON" \
    | python3 -c "import sys,json; assets=json.load(sys.stdin)['assets']; print(next(a['browser_download_url'] for a in assets if 'lnx' in a['name'].lower()))")
  QB64_VERSION=$(echo "$RELEASE_JSON" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
  echo "    version: $QB64_VERSION"
  echo "    url:     $ASSET_URL"

  echo "==> Downloading..."
  curl -fsSL -o "$WORKDIR/qb64pe_lnx.tar.gz" "$ASSET_URL"

  echo "==> Extracting..."
  tar xzf "$WORKDIR/qb64pe_lnx.tar.gz" -C "$WORKDIR"

  echo "==> Compiling QB64-PE from source (takes a few minutes)..."
  cd "$QB64_DIR" && bash setup_lnx.sh 1 && cd "$REPODIR"
fi

QB64="$QB64_DIR/qb64pe"
if [ ! -x "$QB64" ]; then
  echo "ERROR: $QB64 not found or not executable"
  exit 1
fi

# QB64-PE resolves $EMBED paths relative to its binary directory.
# Symlink code/3d -> repo inside the QB64-PE dir so 'code/3d/assets/...' resolves correctly.
mkdir -p "$QB64_DIR/code"
ln -sfn "$REPODIR" "$QB64_DIR/code/3d"

echo "==> Building sss.bas..."
mkdir -p "$REPODIR/builds"
if command -v xvfb-run &>/dev/null; then
  xvfb-run "$QB64" -x -w -s:ExeDefaultDir="$REPODIR/builds" "$QB64_DIR/code/3d/sss.bas"
else
  "$QB64" -x -w -s:ExeDefaultDir="$REPODIR/builds" "$QB64_DIR/code/3d/sss.bas"
fi
echo "==> Build complete"
