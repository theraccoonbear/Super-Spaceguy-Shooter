#!/usr/bin/env bash
set -euo pipefail

REPODIR="$(cd "$(dirname "$0")/../.." && pwd)"

# OS-specific settings
case "$(uname -s)" in
  Darwin*)
    QB64_ASSET_FILTER="osx"
    QB64_SETUP_SCRIPT="setup_osx.command"
    QB64_BIN_NAME="qb64pe"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    QB64_ASSET_FILTER="win-x64"
    QB64_SETUP_SCRIPT="setup_win.bat"
    QB64_BIN_NAME="qb64pe.exe"
    ;;
  *)
    QB64_ASSET_FILTER="lnx"
    QB64_SETUP_SCRIPT="setup_lnx.sh"
    QB64_BIN_NAME="qb64pe"
    ;;
esac

# If QB64_BIN_DIR is set, use that existing QB64-PE installation.
# Otherwise download and compile QB64-PE from the latest release.
if [ -n "${QB64_BIN_DIR:-}" ]; then
  QB64_DIR="$(realpath "$QB64_BIN_DIR")"
  echo "==> Using QB64-PE at $QB64_DIR"
else
  WORKDIR=$(mktemp -d)
  trap "rm -rf $WORKDIR" EXIT
  QB64_DIR="$WORKDIR/qb64pe"

  echo "==> Resolving QB64-PE release asset..."
  RELEASE_JSON=$(curl -fsSL https://api.github.com/repos/QB64-Phoenix-Edition/QB64pe/releases/latest)
  ASSET_URL=$(echo "$RELEASE_JSON" \
    | python3 -c "import sys,json; f='${QB64_ASSET_FILTER}'; assets=json.load(sys.stdin)['assets']; print(next(a['browser_download_url'] for a in assets if f in a['name'].lower()))")
  QB64_VERSION=$(echo "$RELEASE_JSON" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
  echo "    version: $QB64_VERSION"
  echo "    url:     $ASSET_URL"

  echo "==> Downloading..."
  curl -fsSL -o "$WORKDIR/qb64pe_pkg" "$ASSET_URL"

  echo "==> Extracting..."
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      powershell -Command "Expand-Archive -Path '$(cygpath -w "$WORKDIR/qb64pe_pkg")' -DestinationPath '$(cygpath -w "$WORKDIR")'"
      ;;
    *)
      tar xzf "$WORKDIR/qb64pe_pkg" -C "$WORKDIR"
      ;;
  esac

  echo "==> Compiling QB64-PE from source (takes a few minutes)..."
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      cd "$QB64_DIR" && cmd //c "$QB64_SETUP_SCRIPT 1" && cd "$REPODIR"
      ;;
    *)
      cd "$QB64_DIR" && bash "$QB64_SETUP_SCRIPT" 1 && cd "$REPODIR"
      ;;
  esac
fi

QB64="$QB64_DIR/$QB64_BIN_NAME"
if [ ! -x "$QB64" ]; then
  echo "ERROR: $QB64 not found or not executable"
  exit 1
fi

# QB64-PE resolves $EMBED paths relative to its binary directory.
# Create assets -> repo/assets in the QB64-PE dir so '$EMBED:assets/...'
# finds the right files regardless of where the repo lives on disk.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    WIN_LINK=$(cygpath -w "$QB64_DIR/assets")
    WIN_TARGET=$(cygpath -w "$REPODIR/assets")
    WIN_LINK="$WIN_LINK" WIN_TARGET="$WIN_TARGET" \
      powershell -Command 'if (Test-Path $env:WIN_LINK) { Remove-Item $env:WIN_LINK -Force -Recurse }; New-Item -ItemType Junction -Path $env:WIN_LINK -Target $env:WIN_TARGET'
    ;;
  *)
    ln -sfn "$REPODIR/assets" "$QB64_DIR/assets"
    ;;
esac

# Ubuntu stores libcurl at /usr/lib/x86_64-linux-gnu/ which is not in QB64-PE's search
# path list.  Symlink it to /usr/lib/libcurl.so (a path QB64-PE does check) so the
# compiler finds it and bakes an absolute system path into the binary.
# On user machines with libcurl installed, that same path exists.  On machines without
# it, the graceful ON ERROR GOTO in http.bas catches error 260 and disables telemetry.
if [ "$(uname -s)" = "Linux" ] && [ ! -e /usr/lib/libcurl.so ]; then
    CURL_SO=$(find /usr/lib -name 'libcurl.so' 2>/dev/null | head -1)
    if [ -n "$CURL_SO" ]; then
        sudo ln -sf "$CURL_SO" /usr/lib/libcurl.so
    fi
fi

# Write .env from CI secrets for $EMBED. Empty values disable network telemetry.
cat > "$REPODIR/assets/.env" <<EOF
TELEM_NET_URL=${TELEM_NET_URL:-}
TELEM_NET_KEY=${TELEM_NET_KEY:-}
EOF

echo "==> Building sss.bas..."
mkdir -p "$REPODIR/builds"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    QB64_WIN=$(cygpath -w "$QB64")
    SRC_WIN=$(cygpath -w "$REPODIR/sss.bas")
    OUT_WIN=$(cygpath -w "$REPODIR/builds")
    # QB64-PE exits 1 on Windows even after a successful -x compile; verify output instead
    QB64_WIN="$QB64_WIN" SRC_WIN="$SRC_WIN" OUT_WIN="$OUT_WIN" \
      powershell -Command '& $env:QB64_WIN -x -w "-s:ExeDefaultDir=$env:OUT_WIN" $env:SRC_WIN; exit 0'
    if [ ! -f "$REPODIR/builds/sss.exe" ]; then
      echo "ERROR: sss.exe not produced by QB64-PE"
      exit 1
    fi
    ;;
  *)
    if command -v xvfb-run &>/dev/null; then
      xvfb-run "$QB64" -x -w "-s:ExeDefaultDir=$REPODIR/builds" "$REPODIR/sss.bas"
    else
      "$QB64" -x -w "-s:ExeDefaultDir=$REPODIR/builds" "$REPODIR/sss.bas"
    fi
    ;;
esac
echo "==> Build complete"
