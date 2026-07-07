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
# Match the symlink qb64build.sh sets up so tests compile against the same assets.
mkdir -p "$QB64_DIR/code"
ln -sfn "$REPODIR" "$QB64_DIR/code/3d"

TESTBIN="$REPODIR/tests/seq_trace_test"

echo "==> Building tests/seq_trace_test.bas..."
if command -v xvfb-run &>/dev/null; then
  xvfb-run "$QB64" -x "$QB64_DIR/code/3d/tests/seq_trace_test.bas" -o "$TESTBIN"
else
  "$QB64" -x "$QB64_DIR/code/3d/tests/seq_trace_test.bas" -o "$TESTBIN"
fi

echo "==> Running seq_trace_test..."
if "$TESTBIN"; then
  echo "==> All tests passed"
else
  echo "==> TESTS FAILED — see output above"
  exit 1
fi
