#!/usr/bin/env bash
# Smoke-tests a release build of sss (#275): the plain version, a --help without
# the dev-only flags, and every dev-only flag rejected as an unknown option.
#
# Usage: tests/release_build_test.sh [binary]   (default builds/sss)
# Build the binary first with `tools/buildqb --release sss.bas`, or run
# `tools/dev build --release`, which builds it and runs this.
#
# A dev build accepts the dev flags and would start the game, so the script refuses a
# dev binary before the flag checks, and every run is time-limited with no stdin.
set -uo pipefail

echo "=== release_build_test ==="

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$REPO/builds/sss}"
LIMIT=10

command -v timeout > /dev/null 2>&1 || { echo "release_build_test: needs timeout(1)"; exit 2; }

RUN=()
if [ "$(uname -s)" = Linux ] && command -v xvfb-run > /dev/null 2>&1; then
    RUN=(xvfb-run -a)
fi

# timeout runs inside xvfb-run so it signals sss itself; 124/137 = still running at the limit
run_bin() {
    ${RUN[@]+"${RUN[@]}"} timeout -k 2 "$LIMIT" "$BIN" "$@" < /dev/null 2>&1 | tr -d '\r'
    return "${PIPESTATUS[0]}"
}
timed_out() { [ "$1" -eq 124 ] || [ "$1" -eq 137 ]; }

DEV_FLAGS=(--scene --crawls --god --nerf --difficulty --credits --ships --shields --fuel --pup --input-script
           --script-override --frames --realtime --seed --screenshot-at --leaderboard-file --debug)

fails=0
fail() { echo "FAIL: $1"; fails=$((fails + 1)); }

out=$(run_bin --version)
status=$?
echo "$out"
if timed_out "$status"; then
    echo "FAIL: --version still running after ${LIMIT}s; skipping the remaining checks"
    exit 1
fi

help=$(run_bin --help)
help_status=$?
echo "$help"
if timed_out "$help_status"; then
    echo "FAIL: --help still running after ${LIMIT}s; skipping the remaining checks"
    exit 1
fi

if grep -q -- '-dev+' <<< "$out" || grep -q -- '--scene' <<< "$help"; then
    echo "FAIL: $BIN is a dev build (it accepts the dev flags); build it with --release. Skipping the remaining checks"
    exit 1
fi

tag="$(git -C "$REPO" describe --tags --exact-match --match 'v[0-9]*' HEAD 2> /dev/null || true)"
want="${tag:-v$(tr -d '[:space:]' < "$REPO/VERSION")}"
want="Super Spaceguy Shooter ${want#v}"
if [ "$out" = "$want" ]; then echo "ok:   --version prints '$want'"; else fail "--version: expected '$want'"; fi

[ "$help_status" -eq 0 ] || fail "--help exited $help_status"
grep -q -- "--no-telem" <<< "$help" && echo "ok:   --help lists --no-telem" || fail "--help doesn't list --no-telem"
for flag in "${DEV_FLAGS[@]}" "Scene names"; do
    if grep -q -- "$flag" <<< "$help"; then fail "--help lists '$flag'"; else echo "ok:   --help omits '$flag'"; fi
done

for flag in "${DEV_FLAGS[@]}"; do
    [ "$flag" = --debug ] && continue
    out=$(run_bin "$flag" 1)
    status=$?
    if timed_out "$status"; then
        fail "$flag: binary accepted the dev flag and started (killed after ${LIMIT}s)"
    elif [ "$status" -ne 0 ] && grep -q -- "unknown option '$flag'" <<< "$out"; then
        echo "ok:   $flag rejected as unknown"
    else
        fail "$flag not rejected (exit $status): $(head -n 1 <<< "$out")"
    fi
done

# A libcurl symbol version (Debian's CURL_OPENSSL_4) makes Fedora's loader warn on every launch (#303)
if [ "$(uname -s)" = Linux ]; then
    if readelf -V "$BIN" | grep -q 'File: libcurl'; then
        fail "binary requires libcurl symbol versions: $(readelf -V "$BIN" | grep -A1 'File: libcurl' | tail -n 1 | xargs)"
    else
        echo "ok:   no libcurl symbol versions required"
    fi
fi

# Release builds link libstdc++ and libgcc statically (#352), so the player needs no matching runtime
if [ "$(uname -s)" = Linux ]; then
    if readelf -d "$BIN" | grep NEEDED | grep -Eq 'libstdc\+\+|libgcc_s'; then
        fail "binary needs libstdc++ or libgcc_s at run time"
    else
        echo "ok:   libstdc++ and libgcc_s not needed"
    fi
fi

if [ "$fails" -ne 0 ]; then
    echo "release_build_test: $fails check(s) failed"
    exit 1
fi
echo "release_build_test: all checks passed"
