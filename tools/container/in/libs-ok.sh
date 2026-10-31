#!/usr/bin/env bash
# tools/container/in/libs-ok.sh -- can this container load a binary's shared libraries?
#
# Usage (in the container): tools/container/in/libs-ok.sh <binary>
# Exits 0 when ldd finds every library, 1 when one is "not found" (e.g. a binary built
# natively on a host with a newer glibc).
set -euo pipefail

if ldd "$1" 2>&1 | grep -q "not found"; then
    exit 1
fi
