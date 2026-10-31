#!/usr/bin/env bash
# tools/container/in/build.sh -- `tools/dev build`, inside the dev container.
#
# Usage (from the repo root, in the container): tools/container/in/build.sh [--release]
#   (none)     tools/buildqb sss.bas, then the builds/sss --version smoke test
#   --release  a release build, then tests/release_build_test.sh
set -euo pipefail

if [ "${1:-}" = --release ]; then
    ./tools/buildqb --release sss.bas
    bash tests/release_build_test.sh
    exit
fi

./tools/buildqb sss.bas
out=$(xvfb-run -a builds/sss --version)
[[ "$out" != *$'\r'* ]] || { echo "Error: --version output contains a carriage return (#252)" >&2; exit 1; }
echo "$out"
base=$(tr -d "[:space:]" < VERSION)
grep -qE "Super Spaceguy Shooter ${base}(-dev\+[0-9a-f]+(-dirty)?)?$" <<< "$out" || {
    echo "Error: --version smoke test failed: expected a version starting with ${base}" >&2
    exit 1
}
echo ">>> smoke test passed"
