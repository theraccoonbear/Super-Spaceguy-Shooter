#!/usr/bin/env bash
# tools/container/in/current.sh -- is builds/sss ready to run? (`tools/dev run`, inside the container)
#
# Usage (from the repo root, in the container): tools/container/in/current.sh
# Exit 0 if builds/sss is current with its inputs (tools/buildqb --check, #233) and loads
# in this container (a binary built natively on a host with a newer glibc doesn't);
# exit 1, saying why, if it needs a rebuild.
set -uo pipefail

if ! ./tools/buildqb --check sss.bas; then
    echo ">>> sources changed since the last build; rebuilding builds/sss..."
    exit 1
fi
if ! tools/container/in/libs-ok.sh builds/sss; then
    echo ">>> builds/sss was built outside the container; rebuilding it here..."
    exit 1
fi
