#!/usr/bin/env bash
# Smoke-tests a release build of sss (#275): the plain version, a --help without
# the dev-only flags, and every dev-only flag rejected as an unknown option.
#
# Usage: tests/release_build_test.sh [binary]   (default builds/sss)
# Build the binary first with `tools/buildqb --release sss.bas`, or run
# `tools/dev build --release`, which builds it and runs this.
set -uo pipefail

echo "=== release_build_test ==="

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$REPO/builds/sss}"

RUN=()
if [ "$(uname -s)" = Linux ] && command -v xvfb-run > /dev/null 2>&1; then
    RUN=(xvfb-run -a)
fi

DEV_FLAGS=(--scene --crawls --god --nerf --credits --ships --shields --input-script
           --frames --seed --screenshot-at --leaderboard-file --debug)

fails=0
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

out=$(${RUN[@]+"${RUN[@]}"} "$BIN" --version 2>&1 | tr -d '\r')
echo "$out"
tag="$(git -C "$REPO" describe --tags --exact-match --match 'v[0-9]*' HEAD 2> /dev/null || true)"
want="${tag:-v$(tr -d '[:space:]' < "$REPO/VERSION")}"
want="Super Spaceguy Shooter ${want#v}"
if [ "$out" = "$want" ]; then echo "ok:   --version prints '$want'"; else fail "--version: expected '$want'"; fi

help=$(${RUN[@]+"${RUN[@]}"} "$BIN" --help 2>&1 | tr -d '\r')
status=$?
echo "$help"
[ "$status" -eq 0 ] || fail "--help exited $status"
grep -q -- "--no-telem" <<< "$help" && echo "ok:   --help lists --no-telem" || fail "--help doesn't list --no-telem"
for flag in "${DEV_FLAGS[@]}" "Scene names"; do
    if grep -q -- "$flag" <<< "$help"; then fail "--help lists '$flag'"; else echo "ok:   --help omits '$flag'"; fi
done

for flag in "${DEV_FLAGS[@]}"; do
    [ "$flag" = --debug ] && continue
    out=$(${RUN[@]+"${RUN[@]}"} "$BIN" "$flag" 1 2>&1 | tr -d '\r')
    status=$?
    if [ "$status" -ne 0 ] && grep -q -- "unknown option '$flag'" <<< "$out"; then
        echo "ok:   $flag rejected as unknown"
    else
        fail "$flag not rejected (exit $status): $(head -n 1 <<< "$out")"
    fi
done

if [ "$fails" -ne 0 ]; then
    echo "release_build_test: $fails check(s) failed"
    exit 1
fi
echo "release_build_test: all checks passed"
