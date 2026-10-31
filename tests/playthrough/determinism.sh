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
#   tests/playthrough/determinism.sh
# Env: SSS_BIN, PLAYTHROUGH_TIMEOUT as run.sh; PLAYTHROUGH_OUT is the base for the two
# launch folders <base>-uncapped and <base>-realtime (default: builds/playthrough).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BASE="${PLAYTHROUGH_OUT:-$REPO/builds/playthrough}"
FAST="$BASE-uncapped"
REAL="$BASE-realtime"

fail() {
    echo "DETERMINISM FAILED: $*" >&2
    echo "  launch folders: $FAST $REAL" >&2
    exit 1
}

PLAYTHROUGH_OUT="$FAST" "$REPO/tests/playthrough/run.sh" || fail "the uncapped playthrough failed"
PLAYTHROUGH_OUT="$REAL" "$REPO/tests/playthrough/run.sh" --realtime || fail "the --realtime playthrough failed"

milestones() { tr -d '\r' < "$1/milestones.log"; }
telemetry() { tr -d '\r' < "$1/sss_telemetry.csv" | cut -d, -f3- | sed -E 's/(^|[,|])player_id=[^|]*/\1/'; }

narr=$(milestones "$FAST" | grep -c ' NARR ')
[ "$narr" -gt 0 ] || fail "no NARR lines in $FAST/milestones.log; is narration on?"

echo "--- milestones: uncapped vs --realtime ---"
diff <(milestones "$FAST") <(milestones "$REAL") || fail "milestone logs differ (above: < uncapped, > --realtime)"
echo "--- telemetry: uncapped vs --realtime ---"
diff <(telemetry "$FAST") <(telemetry "$REAL") || fail "telemetry differs (above: < uncapped, > --realtime)"

echo "DETERMINISM PASSED: $(milestones "$FAST" | wc -l) milestone lines ($narr NARR) and $(telemetry "$FAST" | wc -l) telemetry rows identical uncapped and at 60 fps"
