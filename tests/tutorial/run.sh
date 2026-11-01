#!/usr/bin/env bash
# tests/tutorial/run.sh -- scripted runs of the tutorial (#240).
#
# Starts the game in the tutorial (--scene tutorial, which goes through the real
# GAME_StartTutorial entry), plays it with an input script, seeded, and checks that:
#   1. the game exited cleanly (exit 0) when --frames ran out, within the time limit;
#   2. the milestone log (SSS_MILESTONE_LOG, see DBG_MilestoneInit in src/sys/debug.bas)
#      matches the case's expected file in order. Nothing advances on a timer, so a script
#      that stalls (a WAIT nothing can meet) never reaches the next line and fails here,
#      naming the step it stopped at;
#   3. the tutorial left no record: no telemetry CSV, the settings file kept highscore=0, and
#      tutorial_done=1 was saved.
# Cases:
#   full     (default) tutorial.txt: a pilot that never presses a skip key and meets every WAIT:
#            the tutorial block, the five lessons, the end of the script, then the title; the
#            script must finish by DONE_FRAME_MAX
#   waiver   waiver.txt: a tap of the narration skip key skips a line (the next one starts at once),
#            N skips a lesson, and holding the key 130 frames files the waiver and leaves
#   gated    gated.txt: --gate-tutorial on a fresh launch folder: the title's start runs the tutorial,
#            and its end flows into a normal New Game (stage 1, its session started once)
#
# Usage (needs an X display, or xvfb-run when DISPLAY is unset; in the container:
#   tools/dev shell tests/tutorial/run.sh [full|waiver|gated] [extra sss args...]
# Env:
#   SSS_BIN             binary to test (default: builds/sss)
#   TUTORIAL_OUT        launch folder, wiped first (default: builds/tutorial)
#   TUTORIAL_TIMEOUT    wall-clock limit in seconds (default: 300)
#
# The binary must be built without telemetry credentials (empty assets/.env).
set -uo pipefail

CASE=full
if [ "${1:-}" = full ] || [ "${1:-}" = waiver ] || [ "${1:-}" = gated ]; then CASE="$1"; shift; fi

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$REPO/tests/tutorial"
BIN="${SSS_BIN:-$REPO/builds/sss}"
OUT="${TUTORIAL_OUT:-$REPO/builds/tutorial}"
TIME_LIMIT="${TUTORIAL_TIMEOUT:-300}"
# Latest frame the full script may finish at: the measured finishing frame (about 12000, 3:20 at
# 60 fps with the scripted pilot) plus about 8%. A longer script or a slower tutorial fails here;
# raise it only on purpose, and say so in the PR.
DONE_FRAME_MAX=13000
case "$CASE" in
    waiver) SCRIPT="$HERE/waiver.txt"; EXPECTED="$HERE/expected-waiver.txt" ;;
    gated)  SCRIPT="$HERE/gated.txt";  EXPECTED="$HERE/expected-gated.txt" ;;
    *)      SCRIPT="$HERE/tutorial.txt"; EXPECTED="$HERE/expected.txt" ;;
esac
FRAMES="$(sed -n 's/^#! *frames:\{0,1\} *\([0-9][0-9]*\) *$/\1/p' "$SCRIPT")"

last_step() { grep " STEP " milestones.log 2> /dev/null | tail -1 | tr -d "\r"; }

fail() {
    echo "TUTORIAL RUN FAILED ($CASE): $*" >&2
    echo "  launch folder (milestones.log, game.out): $OUT" >&2
    exit 1
}

[ -x "$BIN" ] || fail "no game binary at $BIN (build it first: tools/dev build)"
[ -n "$FRAMES" ] || fail "no '#! frames N' line in $SCRIPT"
case "$BIN" in /*) ;; *) BIN="$(pwd)/$BIN" ;; esac
if [ -f "$REPO/assets/.env" ] && grep -Eq '^DB_URL=.+' "$REPO/assets/.env"; then
    fail "assets/.env sets DB_URL, so $BIN may send telemetry; rebuild with an empty assets/.env"
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$OUT" || fail "can't enter $OUT"

XVFB=()
if [ -z "${DISPLAY:-}" ]; then
    command -v xvfb-run > /dev/null || fail "no DISPLAY and no xvfb-run"
    XVFB=(xvfb-run -a -s "-screen 0 1280x720x24")
fi

echo "=== tutorial run ($CASE): input $SCRIPT ($(grep '^#!' "$SCRIPT" | tr '\n' ' ')) ==="
start=$SECONDS
SSS_MILESTONE_LOG=milestones.log timeout "$TIME_LIMIT" "${XVFB[@]}" "$BIN" \
    --settings-dir . --input-script "$SCRIPT" "$@" \
    > game.out 2>&1
rc=$?
echo "game exited with $rc after $((SECONDS - start))s"

[ -s milestones.log ] || fail "no milestone log written (exit $rc); the game didn't start? see game.out"

# QB64-PE writes CRLF line ends
mapfile -t raw < <(tr -d "\r" < milestones.log)
# "<frame> <state> <seqIdx> [<label> <TASK> <args>]" -> "<state> [<label> <TASK> [type=...]]";
# "<frame> TUT ..." -> "TUT ..."; the "STEP" lines (the script position) are for diagnosis only
normalize() {
    local fr st sq lab task rest line
    while read -r fr st sq lab task rest; do
        [ "$st" = EXIT ] && continue
        [ "$st" = STEP ] && continue
        if [ "$st" = TUT ]; then
            echo "TUT $sq $lab $task" | sed 's/ *$//'
            continue
        fi
        line="$st"
        [ -n "$lab" ] && line+=" $lab $task"
        [[ " $rest " =~ \ (type=[a-z]+)\  ]] && line+=" ${BASH_REMATCH[1]}"
        echo "$line"
    done
}
mapfile -t got < <(printf "%s\n" "${raw[@]}" | normalize)
mapfile -t want < <(grep -v '^#' "$EXPECTED" | grep -v '^$')

echo "--- milestones (frame: state step) ---"
for line in "${raw[@]}"; do
    read -r fr rest <<< "$line"
    printf '%6s  %.100s\n' "$fr" "$rest"
done

if [ "$rc" -eq 124 ]; then
    fail "timed out after ${TIME_LIMIT}s: the game hung or showed an error dialog (last milestone: ${raw[-1]})"
fi
[ "$rc" -eq 0 ] || fail "the game exited with status $rc (last milestone: ${raw[-1]}); see game.out"
[ "${raw[-1]}" = "$FRAMES EXIT" ] || fail "the game quit before --frames $FRAMES (last milestone: ${raw[-1]})"

n=${#want[@]}
for ((i = 0; i < n || i < ${#got[@]}; i++)); do
    if [ "$i" -ge "${#got[@]}" ]; then
        fail "stalled after '${got[$((i - 1))]}' until --frames $FRAMES ran out; last step: $(last_step); never reached milestone $((i + 1))/$n '${want[$i]}'"
    fi
    if [ "$i" -ge "$n" ]; then
        fail "unexpected milestone after the last expected one: '${got[$i]}'"
    fi
    if [ "${got[$i]}" != "${want[$i]}" ]; then
        fail "milestone $((i + 1))/$n: expected '${want[$i]}', got '${got[$i]}'"
    fi
done

frame_of() { printf '%s\n' "${raw[@]}" | grep " $1" | head -1 | cut -d" " -f1; }

case "$CASE" in
full)
    done_frame=$(frame_of "TUT done")
    [ "${done_frame:-999999}" -le "$DONE_FRAME_MAX" ] || fail "the script finished at frame $done_frame, later than DONE_FRAME_MAX=$DONE_FRAME_MAX; raise it only if the longer tutorial is intended"
    summary="finished at frame $done_frame of $FRAMES (limit $DONE_FRAME_MAX)"
    ;;
waiver)
    # the tap at frame 100 must have skipped line 1 (it is 9 s long unskipped): line 2 starts within a few frames
    second=$(printf '%s\n' "${raw[@]}" | grep " STEP line 9 " | head -1 | cut -d" " -f1)
    [ "${second:-999999}" -lt 200 ] || fail "a tap of the skip key at frame 100 did not skip the line (the second line started at frame ${second:-never})"
    summary="the tap skipped line 1 (line 2 at frame $second), N skipped lesson 1, the waiver left at frame $(frame_of "TUT waiver")"
    ;;
gated)
    # the hand-over is a normal New Game: its session started once, and stage 1's PLAY ran as a recorded run
    [ -e sss_telemetry.csv ] || fail "no telemetry CSV: the New Game after the tutorial recorded nothing"
    starts=$(tr -d "\r" < sss_telemetry.csv | grep -c ",session_start,")
    [ "$starts" = 1 ] || fail "the telemetry CSV has $starts session_start rows, expected exactly 1 (the New Game after the tutorial)"
    summary="tutorial at frame $(frame_of "TUT lesson 1"), then a New Game with its session started, stage 1 at frame $(frame_of "GS_PLAYING 4")"
    ;;
esac

if [ "$CASE" != gated ]; then [ ! -e sss_telemetry.csv ] || fail "the tutorial wrote a telemetry CSV"; fi
tr -d "\r" < sss_settings.ini | grep -q '^highscore=0$' || fail "the settings file does not keep highscore=0 (the tutorial left a record)"
tr -d "\r" < sss_settings.ini | grep -q '^tutorial_done=1$' || fail "leaving the tutorial did not set tutorial_done=1"

echo "TUTORIAL RUN PASSED ($CASE): $n milestones in order, $summary"
