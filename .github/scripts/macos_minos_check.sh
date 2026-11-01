#!/usr/bin/env bash
# Fails unless the macOS binary's minimum OS version (LC_BUILD_VERSION minos, or the
# older LC_VERSION_MIN_MACOSX version) is the expected one (default 12.0) (#352).
# Usage: macos_minos_check.sh BINARY [EXPECTED]
set -euo pipefail

bin="${1:?usage: $0 BINARY [EXPECTED]}"
want="${2:-12.0}"

cmds=$(otool -l "$bin")
echo "$cmds" | grep -A6 -E "cmd LC_BUILD_VERSION|cmd LC_VERSION_MIN_MACOSX" || true

got=$(echo "$cmds" | awk '
    /cmd LC_BUILD_VERSION/ { mode = "b"; next }
    /cmd LC_VERSION_MIN_MACOSX/ { mode = "m"; next }
    /Load command/ { mode = "" }
    mode == "b" && $1 == "minos" { print $2; exit }
    mode == "m" && $1 == "version" { print $2; exit }')

[ -n "$got" ] || { echo "::error::no LC_BUILD_VERSION or LC_VERSION_MIN_MACOSX in $bin"; exit 1; }
echo "minos: $got (expected $want)"
[ "$got" = "$want" ] || { echo "::error::$bin has minos $got, expected $want"; exit 1; }
