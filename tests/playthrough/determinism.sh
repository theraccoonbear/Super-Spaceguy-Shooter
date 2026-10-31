#!/usr/bin/env bash
# tests/playthrough/determinism.sh -- the scripted playthrough reaches the same game
# state at any frame rate (#329).
#
# Runs tests/playthrough/run.sh twice, flat out and with --realtime (60 fps), and checks
# that the two runs match:
#   1. milestones.log line for line, frame numbers and NARR lines (the frame each crawl
#      paragraph starts speaking) included;
#   2. sss_telemetry.csv, without the wall-clock columns (time, session) and player_id.
#
# Usage (needs what run.sh needs; the --realtime run takes the playthrough's length in
# real time, about five minutes):
#   tests/playthrough/determinism.sh                      both runs in turn, then compare
#   tests/playthrough/determinism.sh run <mode> <outdir>  one run; mode: uncapped|realtime
#   tests/playthrough/determinism.sh compare <dirA> <dirB>
# CI runs the two modes in parallel jobs and compares in a third (#341). A run folder
# keeps milestones.log, sss_telemetry.csv and telemetry.normalized.csv (what compare diffs).
# Env: SSS_BIN, PLAYTHROUGH_TIMEOUT as run.sh; PLAYTHROUGH_OUT is the base for the two
# launch folders <base>-uncapped and <base>-realtime when run with no arguments
# (default: builds/playthrough).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

fail() {
    echo "DETERMINISM FAILED: $*" >&2
    [ -n "${FOLDERS:-}" ] && echo "  launch folders: $FOLDERS" >&2
    exit 1
}

milestones() { tr -d '\r' < "$1/milestones.log"; }
telemetry() { tr -d '\r' < "$1/sss_telemetry.csv" | cut -d, -f3- | sed -E 's/(^|[,|])player_id=[^|]*/\1/'; }

run_mode() {
    local mode="$1" out="$2" args=()
    case "$mode" in
        uncapped) ;;
        realtime) args=(--realtime) ;;
        *) echo "unknown mode '$mode' (uncapped|realtime)" >&2; exit 2 ;;
    esac
    FOLDERS="$out"
    PLAYTHROUGH_OUT="$out" "$REPO/tests/playthrough/run.sh" ${args[@]+"${args[@]}"} || fail "the $mode playthrough failed"
    telemetry "$out" > "$out/telemetry.normalized.csv"
}

compare() {
    local a="$1" b="$2" f narr
    FOLDERS="$a $b"
    for f in milestones.log sss_telemetry.csv; do
        [ -f "$a/$f" ] || fail "no $a/$f"
        [ -f "$b/$f" ] || fail "no $b/$f"
    done
    narr=$(milestones "$a" | grep -c ' NARR ')
    [ "$narr" -gt 0 ] || fail "no NARR lines in $a/milestones.log; is narration on?"

    echo "--- milestones: $a vs $b ---"
    diff <(milestones "$a") <(milestones "$b") || fail "milestone logs differ (above: < $a, > $b)"
    echo "--- telemetry: $a vs $b ---"
    diff <(telemetry "$a") <(telemetry "$b") || fail "telemetry differs (above: < $a, > $b)"

    echo "DETERMINISM PASSED: $(milestones "$a" | wc -l) milestone lines ($narr NARR) and $(telemetry "$a" | wc -l) telemetry rows identical in $a and $b"
}

case "${1:-}" in
    run)
        [ $# -eq 3 ] || { echo "usage: $0 run <uncapped|realtime> <outdir>" >&2; exit 2; }
        run_mode "$2" "$3"
        ;;
    compare)
        [ $# -eq 3 ] || { echo "usage: $0 compare <dirA> <dirB>" >&2; exit 2; }
        compare "$2" "$3"
        ;;
    "")
        BASE="${PLAYTHROUGH_OUT:-$REPO/builds/playthrough}"
        run_mode uncapped "$BASE-uncapped"
        run_mode realtime "$BASE-realtime"
        compare "$BASE-uncapped" "$BASE-realtime"
        ;;
    *)
        echo "usage: $0 [run <uncapped|realtime> <outdir> | compare <dirA> <dirB>]" >&2
        exit 2
        ;;
esac
