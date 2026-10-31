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
#      one line per change of game state or sequence step (NARR lines aside, see
#      tests/playthrough/determinism.sh), matches expected.txt in
#      order, with nothing missing or extra; reaching the final title inside the
#      --frames budget is the "didn't stall" check;
#   3. the local telemetry CSV agrees: one boss_defeated per boss and a session_end
#      with exit=win;
#   4. the final title arrives no later than FINAL_FRAME_MAX (#325), so added dead time
#      or a slower scene fails here instead of going unnoticed until --frames runs out.
# It then prints the finishing frame and a per-segment timing table (frames and m:ss at
# 60 fps for each milestone span), also printed when a check fails.
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
# expected.txt, FINAL_FRAME_MAX, and playthrough.txt / its "#! frames" if the run gets longer.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$REPO/tests/playthrough"
BIN="${SSS_BIN:-$REPO/builds/sss}"
OUT="${PLAYTHROUGH_OUT:-$REPO/builds/playthrough}"
TIME_LIMIT="${PLAYTHROUGH_TIMEOUT:-900}"
# Latest frame the final title may arrive at: the measured finishing frame plus ~5%.
# When the run gets longer on purpose, take the new "final title reached at frame N"
# from this script's output (the CI Playthrough job log), set this to about N * 1.05,
# and say in the PR which segments grew (compare the segment tables). Measured: 17502
# (4:51) on master 2deea1f (#318's tuning lengthened the stages); combat stages end on a kill count, so their length moves
# whenever weapons, enemies or the RNG stream change.
FINAL_FRAME_MAX=18400

raw=()

# m:ss of a frame count at 60 fps
mss() { printf '%d:%02d' $(($1 / 3600)) $(($1 / 60 % 60)); }

# Final title frame and how long each milestone span lasted, from milestones.log.
timing_report() {
    local i fr nfr st sq lab task rest name line final="" played=0
    [ "${#raw[@]}" -gt 1 ] || return 0
    # the final title is the first title after any gameplay
    for line in "${raw[@]}"; do
        read -r fr st _ <<< "$line"
        [ "$st" = GS_PLAYING ] && played=1
        if [ "$st" = GS_TITLE ] && [ "$played" -eq 1 ]; then final=$fr; break; fi
    done
    echo "--- segment timings (60 fps: frames / m:ss) ---"
    printf '%6s %6s %6s  %s\n' start frames m:ss segment
    declare -A tot=()
    local order=()
    for ((i = 0; i < ${#raw[@]} - 1; i++)); do
        read -r fr st sq lab task rest <<< "${raw[$i]}"
        read -r nfr _ <<< "${raw[$((i + 1))]}"
        name="$st"
        [ -n "$lab" ] && name+=" $lab $task"
        [[ " $rest " =~ \ (type=[a-z]+)\  ]] && name+=" ${BASH_REMATCH[1]}"
        [ "$fr" = "$final" ] && name+=" (final title, idle until --frames)"
        printf '%6d %6d %6s  %s\n' "$fr" $((nfr - fr)) "$(mss $((nfr - fr)))" "$name"
        [ "$fr" = "$final" ] && continue
        [ -z "${tot[$st]+x}" ] && order+=("$st")
        tot[$st]=$((${tot[$st]:-0} + nfr - fr))
    done
    echo "--- time per state, up to the final title ---"
    for st in "${order[@]}"; do
        printf '%-16s %6d %6s\n' "$st" "${tot[$st]}" "$(mss "${tot[$st]}")"
    done
    if [ -n "$final" ]; then
        echo "FINAL TITLE: reached at frame $final ($(mss "$final") at 60 fps; limit FINAL_FRAME_MAX=$FINAL_FRAME_MAX)"
    else
        echo "FINAL TITLE: not reached"
    fi
}
# seed, flags and frames come from playthrough.txt's "#!" header (#324); the checks need frames
FRAMES="$(sed -n 's/^#! *frames:\{0,1\} *\([0-9][0-9]*\) *$/\1/p' "$HERE/playthrough.txt")"

fail() {
    timing_report
    echo "PLAYTHROUGH FAILED: $*" >&2
    echo "  launch folder (milestones.log, game.out, sss_telemetry.csv): $OUT" >&2
    exit 1
}

[ -x "$BIN" ] || fail "no game binary at $BIN (build it first: tools/dev build)"
[ -n "$FRAMES" ] || fail "no '#! frames N' line in $HERE/playthrough.txt"
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

echo "=== playthrough: input $HERE/playthrough.txt ($(grep '^#!' "$HERE/playthrough.txt" | tr '\n' ' ')) ==="
start=$SECONDS
SSS_MILESTONE_LOG=milestones.log timeout "$TIME_LIMIT" "${XVFB[@]}" "$BIN" \
    --input-script "$HERE/playthrough.txt" "$@" \
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

# QB64-PE writes CRLF line ends. NARR lines (narration paragraph starts) stay in
# milestones.log for the capped-vs-uncapped comparison but aren't milestones here.
mapfile -t raw < <(tr -d "\r" < milestones.log | grep -v '^[0-9]* NARR ')
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

# 4. the run didn't get longer
[ "$title_frame" -le "$FINAL_FRAME_MAX" ] || fail "the final title arrived at frame $title_frame ($(mss "$title_frame")), later than FINAL_FRAME_MAX=$FINAL_FRAME_MAX ($(mss "$FINAL_FRAME_MAX")); compare the segment table with the last passing run, and raise FINAL_FRAME_MAX only if the longer run is intended"

timing_report
echo "PLAYTHROUGH PASSED: $n milestones in order, back at the title by frame $title_frame of $FRAMES, $bosses bosses defeated, ${elapsed}s wall time"
