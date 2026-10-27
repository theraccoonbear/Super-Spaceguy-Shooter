#!/usr/bin/env bash
# tests/playthrough/run.sh -- full-playthrough regression smoke test (#100).
#
# Plays the whole game once, scripted and seeded, the way a fresh install sees it:
# data notice, callsign, lead-in cards, intro crawl, emperor card, title, all six
# stages (crawls, combat, bosses, the asteroid field, planet arrivals, cinematics),
# the outro and back to the title. Then it checks that:
#   1. the game exited cleanly (exit 0) when --frames ran out, within the time limit
#      (a crash dialog or hang under Xvfb shows up as the timeout);
#   2. the milestone log (SSS_MILESTONE_LOG, see DBG_MilestoneInit in src/sys/debug.bas),
#      one line per change of game state or sequence step, matches expected.txt in
#      order, with nothing missing or extra; reaching the final title inside the
#      --frames budget is the "didn't stall" check;
#   3. the local telemetry CSV agrees: one boss_defeated per boss and a session_end
#      with exit=win.
#
# Usage (from anywhere; needs an X display, or xvfb-run when DISPLAY is unset):
#   tests/playthrough/run.sh [extra sss args...]   e.g. --screenshot-at 3000,9000
#   tools/dev shell tests/playthrough/run.sh       in the container
# Env:
#   SSS_BIN               binary to test (default: builds/sss)
#   PLAYTHROUGH_OUT       launch folder, wiped first (default: builds/playthrough);
#                         milestones.log, game.out, sss_telemetry.csv end up here
#   PLAYTHROUGH_TIMEOUT   wall-clock limit in seconds (default: 900)
#
# The binary must be built without telemetry credentials (empty assets/.env): the run
# OKs the data notice, so a build with DB_URL set would send its telemetry and post
# its score to the real leaderboard.
#
# When the game changes on purpose (a stage added, a scene reordered), update
# expected.txt, and playthrough.txt / FRAMES if the run gets longer.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$REPO/tests/playthrough"
BIN="${SSS_BIN:-$REPO/builds/sss}"
OUT="${PLAYTHROUGH_OUT:-$REPO/builds/playthrough}"
TIME_LIMIT="${PLAYTHROUGH_TIMEOUT:-900}"
FRAMES=20000
SEED=1

fail() {
    echo "PLAYTHROUGH FAILED: $*" >&2
    echo "  launch folder (milestones.log, game.out, sss_telemetry.csv): $OUT" >&2
    exit 1
}

[ -x "$BIN" ] || fail "no game binary at $BIN (build it first: tools/dev build)"
case "$BIN" in /*) ;; *) BIN="$(pwd)/$BIN" ;; esac
if [ -f "$REPO/assets/.env" ] && grep -Eq '^DB_URL=.+' "$REPO/assets/.env"; then
    fail "assets/.env sets DB_URL, so $BIN may send telemetry and a leaderboard score; rebuild with an empty assets/.env"
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$OUT" || fail "can't enter $OUT"

XVFB=()
if [ -z "${DISPLAY:-}" ]; then
    command -v xvfb-run > /dev/null || fail "no DISPLAY and no xvfb-run"
    XVFB=(xvfb-run -a -s "-screen 0 1280x720x24")
fi

echo "=== playthrough: --god --nerf --seed $SEED --frames $FRAMES, input $HERE/playthrough.txt ==="
start=$SECONDS
SSS_MILESTONE_LOG=milestones.log timeout "$TIME_LIMIT" "${XVFB[@]}" "$BIN" \
    --god --nerf --seed "$SEED" --frames "$FRAMES" --input-script "$HERE/playthrough.txt" "$@" \
    > game.out 2>&1
rc=$?
elapsed=$((SECONDS - start))
echo "game exited with $rc after ${elapsed}s"

[ -s milestones.log ] || fail "no milestone log written (exit $rc); the game didn't start? see game.out"

# "<frame> <state> <seqIdx> [<label> <TASK> <args>]" -> "<state> [<label> <TASK> [type=...]]"
normalize() {
    local fr st sq lab task rest line
    while read -r fr st sq lab task rest; do
        [ "$st" = EXIT ] && continue
        line="$st"
        [ -n "$lab" ] && line+=" $lab $task"
        [[ " $rest " =~ \ (type=[a-z]+)\  ]] && line+=" ${BASH_REMATCH[1]}"
        echo "$line"
    done
}

# QB64-PE writes CRLF line ends
mapfile -t raw < <(tr -d "\r" < milestones.log)
mapfile -t got < <(printf "%s\n" "${raw[@]}" | normalize)
mapfile -t want < <(grep -v '^#' "$HERE/expected.txt" | grep -v '^$')
printf "%s\n" "${got[@]}" > milestones.actual.txt

echo "--- milestones (frame: state step) ---"
for line in "${raw[@]}"; do
    read -r fr rest <<< "$line"
    printf '%6s  %.100s\n' "$fr" "$rest"
done

# 1. clean exit at --frames
if [ "$rc" -eq 124 ]; then
    fail "timed out after ${TIME_LIMIT}s: the game hung or showed an error dialog (last milestone: ${raw[-1]})"
fi
[ "$rc" -eq 0 ] || fail "the game exited with status $rc (last milestone: ${raw[-1]}); see game.out"
[ "${raw[-1]}" = "$FRAMES EXIT" ] || fail "the game quit before --frames $FRAMES (last milestone: ${raw[-1]})"

# 2. every milestone, in order, nothing extra
n=${#want[@]}
for ((i = 0; i < n || i < ${#got[@]}; i++)); do
    if [ "$i" -ge "${#got[@]}" ]; then
        read -r fr _ <<< "${raw[$((i - 1))]}"
        fail "stalled for $((FRAMES - fr)) frames at '${got[$((i - 1))]}' (since frame $fr) until --frames $FRAMES ran out; never reached milestone $((i + 1))/$n '${want[$i]}'"
    fi
    if [ "$i" -ge "$n" ]; then
        fail "unexpected milestone after the last expected one: '${raw[$i]}'"
    fi
    if [ "${got[$i]}" != "${want[$i]}" ]; then
        fail "milestone $((i + 1))/$n: expected '${want[$i]}', got '${raw[$i]}'"
    fi
done

# 3. the telemetry CSV agrees
bosses=$(grep -c 'type=boss' <<< "$(printf '%s\n' "${want[@]}")")
defeated=$(grep -c ',boss_defeated,' sss_telemetry.csv 2> /dev/null)
[ "${defeated:-0}" -eq "$bosses" ] || fail "sss_telemetry.csv has ${defeated:-0} boss_defeated rows, expected $bosses"
grep -q ',session_end,exit=win|' sss_telemetry.csv || fail "sss_telemetry.csv has no session_end with exit=win"

title_frame=$(read -r fr _ <<< "${raw[-2]}"; echo "$fr")
echo "PLAYTHROUGH PASSED: $n milestones in order, back at the title by frame $title_frame of $FRAMES, $bosses bosses defeated, ${elapsed}s wall time"
