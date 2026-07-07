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

TESTBIN="$REPODIR/tests/seq_trace_test"

echo "==> Building tests/seq_trace_test.bas..."
if command -v xvfb-run &>/dev/null; then
  xvfb-run "$QB64" -x "$REPODIR/tests/seq_trace_test.bas" -o "$TESTBIN"
else
  "$QB64" -x "$REPODIR/tests/seq_trace_test.bas" -o "$TESTBIN"
fi

echo "==> Running seq_trace_test..."
if "$TESTBIN"; then
  echo "==> All tests passed"
else
  echo "==> TESTS FAILED — see output above"
  exit 1
fi
