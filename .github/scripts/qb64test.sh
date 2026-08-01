#!/usr/bin/env bash
# Build and run the QB64-PE headless test suite.
# Expects QB64_BIN_DIR to point at an already-installed QB64-PE tree
# (same convention as qb64build.sh). Runs on Linux, macOS, and Windows
# (via Git Bash, as GitHub Actions' windows-latest runner provides).
set -euo pipefail

REPODIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [ -z "${QB64_BIN_DIR:-}" ]; then
  echo "ERROR: QB64_BIN_DIR must be set"
  exit 1
fi
QB64_DIR="$(realpath "$QB64_BIN_DIR")"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) QB64="$QB64_DIR/qb64pe.exe" ;;
  *)                    QB64="$QB64_DIR/qb64pe" ;;
esac

if [ ! -x "$QB64" ]; then
  echo "ERROR: $QB64 not found or not executable"
  exit 1
fi

# QB64-PE resolves $EMBED paths relative to its binary directory.
# Mirror the link that buildqb creates so $EMBED:'assets/...' resolves.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    WIN_LINK=$(cygpath -w "$QB64_DIR/assets")
    WIN_TARGET=$(cygpath -w "$REPODIR/assets")
    WIN_LINK="$WIN_LINK" WIN_TARGET="$WIN_TARGET" \
      powershell -Command 'if (Test-Path $env:WIN_LINK) { Remove-Item $env:WIN_LINK -Force -Recurse }; New-Item -ItemType Junction -Path $env:WIN_LINK -Target $env:WIN_TARGET' > /dev/null
    ;;
  *)
    ln -sfn "$REPODIR/assets" "$QB64_DIR/assets"
    ;;
esac

# Compile a test .bas into an executable. $1 = source path, $2 = output path
# (no extension). Sets RUN_BIN to the actual runnable path once done.
#
# Windows: QB64-PE's exit code can't be trusted after a successful -x compile
# on this platform (same issue qb64build.sh works around), so run it via
# PowerShell and verify the output file directly instead of checking $?.
build_test() {
  local src="$1" out="$2"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      local qb64_win src_win out_win
      qb64_win=$(cygpath -w "$QB64")
      src_win=$(cygpath -w "$src")
      out_win=$(cygpath -w "${out}.exe")
      QB64_WIN="$qb64_win" SRC_WIN="$src_win" OUT_WIN="$out_win" \
        powershell -Command '& $env:QB64_WIN -x $env:SRC_WIN -o $env:OUT_WIN; exit 0'
      if [ ! -f "${out}.exe" ]; then
        echo "ERROR: ${out}.exe not produced by QB64-PE"
        exit 1
      fi
      RUN_BIN="${out}.exe"
      ;;
    *)
      if command -v xvfb-run &>/dev/null; then
        xvfb-run "$QB64" -x "$src" -o "$out"
      else
        "$QB64" -x "$src" -o "$out"
      fi
      RUN_BIN="$out"
      ;;
  esac
}

run_test() {
  local name="$1"
  local src="$REPODIR/tests/${name}.bas"
  local bin="$REPODIR/tests/${name}"

  echo "==> Building tests/${name}.bas..."
  build_test "$src" "$bin"

  echo "==> Running ${name}..."
  if "$RUN_BIN"; then
    echo "==> ${name} passed"
  else
    echo "==> TESTS FAILED — ${name} — see output above"
    exit 1
  fi
}

run_http_test() {
  local name="$1"
  local src="$REPODIR/tests/${name}.bas"
  local bin="$REPODIR/tests/${name}"

  echo "==> Building tests/${name}.bas..."
  build_test "$src" "$bin"
  local run_bin="$RUN_BIN"

  echo "==> Starting HTTP mock server..."
  local portfile errfile
  portfile="$(mktemp)"
  errfile="$(mktemp)"
  python3 "$REPODIR/tools/http_mock_server" --port 0 > "$portfile" 2> "$errfile" &
  local mock_pid=$!
  local mock_port=""
  for i in $(seq 1 150); do
    mock_port="$(cat "$portfile" 2>/dev/null | tr -d '[:space:]')"
    [ -n "$mock_port" ] && break
    sleep 0.1
  done

  if [ -z "$mock_port" ]; then
    echo "ERROR: mock server failed to start"
    echo "--- stderr ---"
    cat "$errfile" 2>/dev/null || true
    rm -f "$portfile" "$errfile"
    kill "$mock_pid" 2>/dev/null || true
    exit 1
  fi
  rm -f "$portfile" "$errfile"
  echo "    Mock listening on port $mock_port"

  local rc=0
  if "$run_bin" "http://127.0.0.1:$mock_port"; then
    echo "==> ${name} passed"
  else
    rc=$?
    echo "==> TESTS FAILED — ${name} — see output above"
  fi
  kill "$mock_pid" 2>/dev/null || true
  if [ $rc -ne 0 ]; then exit 1; fi
}

run_test seq_trace_test
run_test seq_dispatch_test
run_test scene_jump_planet_test
run_test snd_init_test
run_test telem_creds_test
run_test dbg_output_test
run_http_test http_queue_test

echo "==> All tests passed"
