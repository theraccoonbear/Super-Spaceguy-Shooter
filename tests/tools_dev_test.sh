#!/usr/bin/env bash
# Checks the container command `tools/dev run` builds, via its SSS_DEV_DRYRUN seam.
# Guards #223: without /dev/input in the container the game sees no controller.
# Also checks `tools/dev record` (#321): its options, its defaults, and that it plays
# its own binary, built with assets/.env masked.
set -euo pipefail

echo "=== tools_dev_test ==="

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE=localhost/sss-dev:test

cmdline="$(SSS_DEV_DRYRUN=1 SSS_ENGINE=podman SSS_IMAGE="$IMAGE" DISPLAY=:0 \
    "$REPO/tools/dev" run --version)"
echo "$cmdline"

fails=0
expect() {
    if [[ " $cmdline " == *" $1 "* ]]; then
        echo "ok:   $1"
    else
        echo "FAIL: missing '$1'"
        fails=$((fails + 1))
    fi
}

expect "-e DISPLAY"
expect "-v /tmp/.X11-unix:/tmp/.X11-unix"
if [ -e /dev/dri ]; then
    expect "--device /dev/dri"
fi
if [ -d /dev/input ]; then
    expect "-v /dev/input:/dev/input"
else
    echo "skip: no /dev/input on this machine"
fi
expect "$IMAGE builds/sss --version"

# `tools/dev record` (#321): defaults, overrides, bad values, and the DB_URL refusal.
dev() { (cd "$1" && shift && SSS_DEV_DRYRUN=1 SSS_ENGINE=podman SSS_IMAGE="$IMAGE" ./tools/dev "$@" 2>&1); }
cmdline_ends() {
    if [[ "$cmdline" == *"$1 " ]]; then
        echo "ok:   ends with '$1'"
    else
        echo "FAIL: expected the command to end with '$1'"
        fails=$((fails + 1))
    fi
}
refused() {   # refused <message part> <args...>
    local want="$1" out
    shift
    if out="$(dev "$REPO" record "$@")"; then
        echo "FAIL: record $* was accepted"
        fails=$((fails + 1))
    elif [[ "$out" == *"$want"* ]]; then
        echo "ok:   record $* refused: $want"
    else
        echo "FAIL: record $* refused without '$want': $out"
        fails=$((fails + 1))
    fi
}

cmdline="$(dev "$REPO" record)"
cmdline_ends " 2 453 --god --nerf --realtime --seed 1 --frames 20000 --input-script $REPO/tests/playthrough/playthrough.txt"
cmdline="$(dev "$REPO" record --scale 3 --frames 600 --seed 7 --timeout 99 \
    --script tests/input/boss-hold-left.txt --out /tmp/x.mp4 --scene boss3 --god)"
cmdline_ends " 3 99 --scene boss3 --god --realtime --seed 7 --frames 600 --input-script $REPO/tests/input/boss-hold-left.txt"
cmdline="$(dev "$REPO" record --frames 120 -- --scene title --god)"
cmdline_ends " 2 122 --scene title --god --realtime --seed 1 --frames 120 --input-script $REPO/tests/playthrough/playthrough.txt"
refused "--frames needs a whole number" --frames abc
refused "--scale needs a whole number 1 or more" --scale 0
refused "--out needs a value" --out
refused "no input script" --script tests/no-such-script.txt
refused "must be inside the repo" --script /etc/hostname

# record plays its own binary, built with an empty file over assets/.env, so telemetry
# credentials there never reach it; the user's assets/.env and builds/sss stay as they are.
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
mkdir -p "$fake/tools" "$fake/assets" "$fake/builds" "$fake/tests/playthrough"
cp "$REPO/tools/dev" "$fake/tools/dev"
: > "$fake/tests/playthrough/playthrough.txt"
has() {   # has <what> <text>: the record dry run's output contains <text>
    if [[ "$out" == *"$2"* ]]; then
        echo "ok:   $1"
    else
        echo "FAIL: $1: missing '$2'"
        fails=$((fails + 1))
    fi
}
echo "DB_URL=https://example.invalid" > "$fake/assets/.env"
echo "user build" > "$fake/builds/sss"
before="$(cat "$fake/assets/.env" "$fake/builds/sss")"
if out="$(dev "$fake" record)"; then
    has "record build writes builds/record/sss" "-e SSS_BUILD_OUT=builds/record/sss "
    has "record build masks assets/.env" "-v $fake/builds/record/env-empty:$fake/assets/.env:Z "
    has "record build runs buildqb" "$IMAGE ./tools/buildqb sss.bas"
    has "record plays builds/record/sss" "$IMAGE tools/container/in/record.sh $fake/builds/record/sss $fake/builds/.record-"
    if [[ "$out" == *"$fake/builds/sss "* ]]; then
        echo "FAIL: record uses the user's builds/sss: $out"
        fails=$((fails + 1))
    fi
else
    echo "FAIL: record with DB_URL set in assets/.env failed: $out"
    fails=$((fails + 1))
fi
if [ "$(cat "$fake/assets/.env" "$fake/builds/sss")" = "$before" ] && [ ! -e "$fake/builds/record" ]; then
    echo "ok:   assets/.env and builds/sss untouched"
else
    echo "FAIL: the dry run changed assets/.env, builds/sss or builds/record"
    fails=$((fails + 1))
fi
rm "$fake/assets/.env"
if out="$(dev "$fake" record)" && [[ "$out" != *"assets/.env"* ]]; then
    echo "ok:   no assets/.env: nothing to mask"
else
    echo "FAIL: record without assets/.env: $out"
    fails=$((fails + 1))
fi


if [ "$fails" -ne 0 ]; then
    echo "tools_dev_test: $fails check(s) failed"
    exit 1
fi
echo "tools_dev_test: all checks passed"
