#!/usr/bin/env bash
# tools/container/in/headless.sh -- `tools/dev headless`, inside the dev container.
#
# Usage (from the repo root, in the container): tools/container/in/headless.sh [sss args...]
# Runs builds/sss on an off-screen X server (Xvfb, 1280x720). The container has no
# sound card, so ALSA's complaints about it are dropped from the output.
set -euo pipefail

xvfb-run -a -s "-screen 0 1280x720x24" builds/sss "$@" 2>&1 | { grep -v "^ALSA lib" || true; }
