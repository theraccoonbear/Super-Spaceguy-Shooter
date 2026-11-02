#!/usr/bin/env bash
# tools/container/in/bench.sh -- `tools/dev bench`, inside the dev container.
#
# Usage (from the repo root, in the container): tools/container/in/bench.sh [--repeat N] [sss args...]
# Plays tests/bench/bench.txt on an off-screen X server N times (default 5) with frame pacing
# off, prints each run's per-phase frame-time table, then the spread of the per-run averages.
set -euo pipefail

REPEAT=5
if [ "${1:-}" = --repeat ]; then
    REPEAT="${2:?--repeat needs a count}"
    shift 2
fi
[[ "$REPEAT" =~ ^[1-9][0-9]*$ ]] || { echo "Error: --repeat needs a whole number 1 or more, got '$REPEAT'" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for i in $(seq 1 "$REPEAT"); do
    xvfb-run -a -s "-screen 0 1280x720x24" builds/sss --input-script tests/bench/bench.txt --settings-dir "$tmp" --bench "$tmp/run$i.txt" "$@" > "$tmp/out$i.txt" 2>&1 || {
        grep -v "^ALSA lib" "$tmp/out$i.txt" >&2 || true
        echo "Error: bench run $i failed" >&2
        exit 1
    }
    [ -s "$tmp/run$i.txt" ] || { echo "Error: bench run $i wrote no table" >&2; exit 1; }
    echo "=== run $i of $REPEAT ==="
    cat "$tmp/run$i.txt"
done

echo "=== spread over $REPEAT runs (ms per frame) ==="
printf '%-14s %9s %9s %9s %9s\n' phase min median max "max-min"
for ph in sim backdrop scene_build raster particles overlay fx hud rest total; do
    vals="$(for i in $(seq 1 "$REPEAT"); do sed -n "s/^$ph  *\([0-9.]*\) .*/\1/p" "$tmp/run$i.txt"; done | sort -n)"
    n="$(echo "$vals" | wc -l)"
    lo="$(echo "$vals" | head -n 1)"
    hi="$(echo "$vals" | tail -n 1)"
    mid="$(echo "$vals" | sed -n "$(((n + 1) / 2))p")"
    d=$((10#${hi/.} - 10#${lo/.}))
    printf '%-14s %9s %9s %9s %6d.%03d\n' "$ph" "$lo" "$mid" "$hi" "$((d / 1000))" "$((d % 1000))"
done
