#!/usr/bin/env bash
# Build and run the QB64-PE headless test suite.
# Expects QB64_BIN_DIR to point at an already-installed QB64-PE tree
# (same convention as qb64build.sh).
set -euo pipefail

REPODIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [ -z "${QB64_BIN_DIR:-}" ]; then
  echo "ERROR: QB64_BIN_DIR must be set"
  exit 1
fi
QB64_DIR="$(realpath "$QB64_BIN_DIR")"
QB64="$QB64_DIR/qb64pe"

if [ ! -x "$QB64" ]; then
  echo "ERROR: $QB64 not found or not executable"
  exit 1
fi

# QB64-PE resolves $EMBED paths relative to its binary directory.
# Mirror the symlink that buildqb creates so $EMBED:'assets/...' resolves.
ln -sfn "$REPODIR/assets" "$QB64_DIR/assets"

run_test() {
  local name="$1"
  local src="$REPODIR/tests/${name}.bas"
  local bin="$REPODIR/tests/${name}"

  echo "==> Building tests/${name}.bas..."
  if command -v xvfb-run &>/dev/null; then
    xvfb-run "$QB64" -x "$src" -o "$bin"
  else
    "$QB64" -x "$src" -o "$bin"
  fi

  echo "==> Running ${name}..."
  if "$bin"; then
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
  if command -v xvfb-run &>/dev/null; then
    xvfb-run "$QB64" -x "$src" -o "$bin"
  else
    "$QB64" -x "$src" -o "$bin"
  fi

  echo "==> Starting HTTP mock server..."
  local portfile
  portfile="$(mktemp)"
  python3 "$REPODIR/tools/http_mock_server" --port 0 > "$portfile" &
  local mock_pid=$!
  local mock_port=""
  for i in $(seq 1 50); do
    mock_port="$(cat "$portfile" 2>/dev/null | tr -d '[:space:]')"
    [ -n "$mock_port" ] && break
    sleep 0.1
  done
  rm -f "$portfile"

  if [ -z "$mock_port" ]; then
    echo "ERROR: mock server failed to start"
    kill "$mock_pid" 2>/dev/null || true
    exit 1
  fi
  echo "    Mock listening on port $mock_port"

  local rc=0
  if "$bin" "http://127.0.0.1:$mock_port"; then
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
run_http_test http_queue_test

echo "==> All tests passed"
