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

run_test seq_trace_test
run_test snd_init_test

echo "==> All tests passed"
