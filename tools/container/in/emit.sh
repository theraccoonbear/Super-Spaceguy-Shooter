#!/usr/bin/env bash
# tools/container/in/emit.sh -- `tools/dev emit`, inside the dev container.
#
# Usage (from the repo root, in the container): tools/container/in/emit.sh
# npm install in math/, then regenerate the spline math with tools/emit-spline.js.
set -euo pipefail

(cd math && npm install)
node tools/emit-spline.js
