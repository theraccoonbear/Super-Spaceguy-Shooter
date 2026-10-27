#!/usr/bin/env bash
# Checks the container command `tools/dev run` builds, via its SSS_DEV_DRYRUN seam.
# Guards #223: without /dev/input in the container the game sees no controller.
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

if [ "$fails" -ne 0 ]; then
    echo "tools_dev_test: $fails check(s) failed"
    exit 1
fi
echo "tools_dev_test: all checks passed"
