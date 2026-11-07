#!/usr/bin/env bash
# Checks the container command `tools/dev run` builds, via its SSS_DEV_DRYRUN seam.
# Guards #223: without /dev/input in the container the game sees no controller.
# Also checks `tools/dev record` (#321): its options, its defaults, and that it plays
# its own binary, built with assets/.env masked. And `tools/dev completion` (#333):
# commands, options, scene names (from a stub builds/sss) and file names.
set -euo pipefail

echo "=== tools_dev_test ==="

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE=localhost/sss-dev:test

cmdline="$(SSS_DEV_DRYRUN=1 SSS_ENGINE=podman SSS_IMAGE="$IMAGE" DISPLAY=:0 XDG_CONFIG_HOME=/tmp/sss-xdg-test \
    "$REPO/tools/dev" run --version)"
echo "$cmdline"

fails=0
expect() {
    if [[ " $cmdline " == *" $1 "* ]]; then
        echo "ok:   $1"
    else
        echo "FAIL: missing '$1'"
        fails=$((fails + 1))
    fi
}

expect "-e DISPLAY"
expect "-e XDG_CONFIG_HOME=/tmp/sss-config"
expect "-v /tmp/sss-xdg-test/sss:/tmp/sss-config/sss"
expect "-v /tmp/.X11-unix:/tmp/.X11-unix"
if [ -e /dev/dri ]; then
    expect "--device /dev/dri"
fi
if [ -d /dev/input ]; then
    expect "-v /dev/input:/dev/input"
else
    echo "skip: no /dev/input on this machine"
fi
expect "$IMAGE builds/sss --version"

# `tools/dev record` (#321): defaults, overrides, bad values, and the DB_URL refusal.
dev() { (cd "$1" && shift && SSS_DEV_DRYRUN=1 SSS_ENGINE=podman SSS_IMAGE="$IMAGE" ./tools/dev "$@" 2>&1); }
cmdline_ends() {
    if [[ "$cmdline" == *"$1 " ]]; then
        echo "ok:   ends with '$1'"
    else
        echo "FAIL: expected the command to end with '$1'"
        fails=$((fails + 1))
    fi
}
refused() {   # refused <message part> <args...>
    local want="$1" out
    shift
    if out="$(dev "$REPO" record "$@")"; then
        echo "FAIL: record $* was accepted"
        fails=$((fails + 1))
    elif [[ "$out" == *"$want"* ]]; then
        echo "ok:   record $* refused: $want"
    else
        echo "FAIL: record $* refused without '$want': $out"
        fails=$((fails + 1))
    fi
}

cmdline="$(dev "$REPO" record)"
cmdline_ends " 2 453 --god --nerf --realtime --seed 1 --frames 20000 --input-script $REPO/tests/playthrough/playthrough.txt"
cmdline="$(dev "$REPO" record --scale 3 --frames 600 --seed 7 --timeout 99 \
    --script tests/input/boss-hold-left.txt --out /tmp/x.mp4 --scene boss3 --god)"
cmdline_ends " 3 99 --scene boss3 --god --realtime --seed 7 --frames 600 --input-script $REPO/tests/input/boss-hold-left.txt"
cmdline="$(dev "$REPO" record --frames 120 -- --scene title --god)"
cmdline_ends " 2 122 --scene title --god --realtime --seed 1 --frames 120 --input-script $REPO/tests/playthrough/playthrough.txt"
refused "--frames needs a whole number" --frames abc
refused "--scale needs a whole number 1 or more" --scale 0
refused "--out needs a value" --out
refused "no input script" --script tests/no-such-script.txt
refused "must be inside the repo" --script /etc/hostname

# record plays its own binary, built with an empty file over assets/.env, so telemetry
# credentials there never reach it; the user's assets/.env and builds/sss stay as they are.
fake="$(mktemp -d)"
trap 'rm -rf "$fake"' EXIT
mkdir -p "$fake/tools" "$fake/assets" "$fake/builds" "$fake/tests/playthrough"
cp "$REPO/tools/dev" "$fake/tools/dev"
: > "$fake/tests/playthrough/playthrough.txt"
has() {   # has <what> <text>: the record dry run's output contains <text>
    if [[ "$out" == *"$2"* ]]; then
        echo "ok:   $1"
    else
        echo "FAIL: $1: missing '$2'"
        fails=$((fails + 1))
    fi
}
echo "DB_URL=https://example.invalid" > "$fake/assets/.env"
echo "user build" > "$fake/builds/sss"
before="$(cat "$fake/assets/.env" "$fake/builds/sss")"
if out="$(dev "$fake" record)"; then
    has "record build writes builds/record/sss" "-e SSS_BUILD_OUT=builds/record/sss "
    has "record build masks assets/.env" "-v $fake/builds/record/env-empty:$fake/assets/.env:Z "
    has "record build runs buildqb" "$IMAGE ./tools/buildqb sss.bas"
    has "record plays builds/record/sss" "$IMAGE tools/container/in/record.sh $fake/builds/record/sss $fake/builds/.record-"
    if [[ "$out" == *"$fake/builds/sss "* ]]; then
        echo "FAIL: record uses the user's builds/sss: $out"
        fails=$((fails + 1))
    fi
else
    echo "FAIL: record with DB_URL set in assets/.env failed: $out"
    fails=$((fails + 1))
fi
if [ "$(cat "$fake/assets/.env" "$fake/builds/sss")" = "$before" ] && [ ! -e "$fake/builds/record" ]; then
    echo "ok:   assets/.env and builds/sss untouched"
else
    echo "FAIL: the dry run changed assets/.env, builds/sss or builds/record"
    fails=$((fails + 1))
fi
rm "$fake/assets/.env"
if out="$(dev "$fake" record)" && [[ "$out" != *"assets/.env"* ]]; then
    echo "ok:   no assets/.env: nothing to mask"
else
    echo "FAIL: record without assets/.env: $out"
    fails=$((fails + 1))
fi

# `tools/dev completion` (#333): source it and drive _sss_dev the way bash does.
# The fake repo's builds/sss is a stub that prints a --help scene list; no game runs.
# shellcheck disable=SC1090
source <("$REPO/tools/dev" completion)
complete_words() {   # complete_words <word...>: COMPREPLY for the last word, sorted, one line
    COMP_WORDS=("$@")
    COMP_CWORD=$(($# - 1))
    _sss_dev
    printf '%s\n' "${COMPREPLY[@]}" | sort | tr '\n' ' ' | sed 's/ $//'
}
completes() {   # completes <expected> <word...>
    local want="$1" got
    shift
    got="$(complete_words "$@")"
    if [ "$got" = "$want" ]; then
        echo "ok:   complete '$*' -> $want"
    else
        echo "FAIL: complete '$*': expected '$want', got '$got'"
        fails=$((fails + 1))
    fi
}
offers() {   # offers <candidate> <word...>: the candidates include <candidate>
    local want="$1" got
    shift
    got=" $(complete_words "$@") "
    if [[ "$got" == *" $want "* ]]; then
        echo "ok:   complete '$*' offers $want"
    else
        echo "FAIL: complete '$*' doesn't offer '$want': $got"
        fails=$((fails + 1))
    fi
}

for c in ./tools/dev tools/dev "$REPO/tools/dev"; do
    if complete -p "$c" > /dev/null 2>&1; then
        echo "ok:   completion registered for $c"
    else
        echo "FAIL: no completion registered for $c"
        fails=$((fails + 1))
    fi
done
if complete -p dev > /dev/null 2>&1; then
    echo "FAIL: completion claims the bare name dev"
    fails=$((fails + 1))
fi

completes "build" ./tools/dev bu
completes "record render" tools/dev re
completes "--frames --fuel" "$REPO/tools/dev" record --f
completes "--release" ./tools/dev build --
offers "--scene" ./tools/dev run --
offers "--god" ./tools/dev record --scene boss3 --g

# Every cmd_* function dispatches, so every completed command is a real one.
for c in $(complete_words ./tools/dev ""); do
    if [ "$c" = completion ] || [ "$c" = help ]; then continue; fi
    if grep -q "^cmd_$c() {" "$REPO/tools/dev"; then
        echo "ok:   command $c has cmd_$c"
    else
        echo "FAIL: completion offers '$c' but tools/dev has no cmd_$c"
        fails=$((fails + 1))
    fi
done
# record's options are the ones its parser takes.
# shellcheck disable=SC2013
for o in $(sed -n 's/^ *\(--[a-z]*\)) *rec_.*/\1/p' "$REPO/tools/dev"); do
    offers "$o" ./tools/dev record --
done
# The game flags are the ones GAME_Usage prints.
# shellcheck disable=SC2013
for o in $(sed -n 's/^ *CLI_Emit guFH, "  \(-v, \|-h, \)\{0,1\}\(--[a-z-]*\).*/\2/p' "$REPO/src/sys/game.bas" | sort -u); do
    offers "$o" ./tools/dev run --
done

cat > "$fake/builds/sss" << 'EOF'
#!/bin/sh
cat << 'HELP'
Super Spaceguy Shooter 0.0.0

Scene names:
  crawl[0-2]
  playing[1-3]
  boss[3,5]
  dock[1,2]
  title
  crawl:death_final       (game over)
  consent
HELP
EOF
chmod +x "$fake/builds/sss"
completes "boss3 boss5" "$fake/tools/dev" run --scene bo
completes "crawl0 crawl1 crawl2 crawl:death_final" "$fake/tools/dev" headless --scene cr
completes "death_final" "$fake/tools/dev" run --scene crawl : d
completes "dock1 dock2" "$fake/tools/dev" record --scene "do"
rm "$fake/builds/sss"
completes "consent crawl" "$fake/tools/dev" run --scene c

completes "easy hard normal" "$fake/tools/dev" run --difficulty ""
mkdir -p "$fake/assets/config"
printf '; levels=no\nlevels=calm,brutal\ndefault=calm\n' > "$fake/assets/config/difficulty.ini"
completes "brutal calm" "$fake/tools/dev" headless --difficulty ""
completes "brutal" "$fake/tools/dev" record --difficulty b
rm -r "$fake/assets/config"
completes "easy hard normal" "$REPO/tools/dev" run --difficulty ""

mkdir -p "$fake/tests/input"
: > "$fake/tests/input/boss-hold-left.txt"
: > "$fake/tests/input/boss two.txt"
got="$(COMP_WORDS=(./tools/dev headless --input-script "$fake/tests/input/b"); COMP_CWORD=3
    _sss_dev; printf '%s\n' "${COMPREPLY[@]}" | sort | tr '\n' '|')"
want="$(printf '%s\n' "$fake/tests/input/boss two.txt" "$fake/tests/input/boss-hold-left.txt" | sort | tr '\n' '|')"
if [ "$got" = "$want" ]; then
    echo "ok:   --input-script completes file names"
else
    echo "FAIL: --input-script file completion: '$got'"
    fails=$((fails + 1))
fi
completes "" ./tools/dev record --frames ""


# Limits (#427): a stub podman records its arguments, so nothing is built or run.
stubdir="$(mktemp -d)"
trap 'rm -rf "$fake" "$stubdir"' EXIT
cat > "$stubdir/podman" << 'STUB'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
if [ "${1:-}" = run ] && [ -n "${STUB_STDIN:-}" ]; then cat > "$STUB_STDIN"; fi
if [ "${1:-}" = run ] && [ -n "${STUB_SLEEP:-}" ]; then exec sleep "$STUB_SLEEP"; fi
exit 0
STUB
chmod +x "$stubdir/podman"
export STUB_LOG="$stubdir/log"
# the stub (SSS_ENGINE=podman finds it first); env -u keeps the caller's SSS_DEV_* out
stubdev() { PATH="$stubdir:$PATH" SSS_ENGINE=podman SSS_DEV_LOCKDIR="$stubdir/locks" "$REPO/tools/dev" "$@" 2>&1; }
has() {   # has <label> <text> <pattern>
    if [[ "$2" == *$3* ]]; then echo "ok:   $1"; else echo "FAIL: $1 (wanted '$3')"; fails=$((fails + 1)); fi
}
lacks() {
    if [[ "$2" != *$3* ]]; then echo "ok:   $1"; else echo "FAIL: $1 (found '$3')"; fails=$((fails + 1)); fi
}

: > "$STUB_LOG"
(unset SSS_DEV_MEMORY SSS_DEV_CPUS SSS_DEV_PIDS SSS_DEV_JOBS SSS_DEV_SLOTS SSS_DEV_TIMEOUT; stubdev test > /dev/null)
log="$(cat "$STUB_LOG")"
has "default limits: memory" "$log" " --memory "
has "default limits: swap equals memory" "$log" " --memory-swap "
has "default limits: cpus" "$log" " --cpus "
has "default limits: pids" "$log" " --pids-limit "
has "default limits: no container log" "$log" "--log-driver none"
jobs_default="$(sed -n 's/.*QB64_TEST_JOBS=\([0-9]*\).*/\1/p' "$STUB_LOG" | head -n 1)"
if [ "$jobs_default" = 2 ] || [ "$jobs_default" = 3 ]; then
    echo "ok:   tools/dev test caps the test workers (QB64_TEST_JOBS=$jobs_default)"
else
    echo "FAIL: QB64_TEST_JOBS default '$jobs_default', wanted 2 or 3"
    fails=$((fails + 1))
fi
mem="$(sed -n 's/.* --memory \([^ ]*\) .*/\1/p' "$STUB_LOG" | head -n 1)"
swap="$(sed -n 's/.* --memory-swap \([^ ]*\) .*/\1/p' "$STUB_LOG" | head -n 1)"
if [ -n "$mem" ] && [ "$mem" = "$swap" ]; then
    echo "ok:   memory and memory+swap match ($mem), so no swapping"
else
    echo "FAIL: memory '$mem' vs memory-swap '$swap'"
    fails=$((fails + 1))
fi

: > "$STUB_LOG"
SSS_DEV_MEMORY=3g SSS_DEV_CPUS=1.5 SSS_DEV_PIDS=77 SSS_DEV_JOBS=5 stubdev build > /dev/null
log="$(cat "$STUB_LOG")"
has "override: memory" "$log" " --memory 3g "
has "override: cpus" "$log" " --cpus 1.5 "
has "override: pids" "$log" " --pids-limit 77 "
has "override: jobs" "$log" "QB64_TEST_JOBS=5"
: > "$STUB_LOG"
SSS_DEV_MEMORY=0 SSS_DEV_CPUS=none SSS_DEV_PIDS=0 SSS_DEV_JOBS=0 stubdev build > /dev/null
log="$(cat "$STUB_LOG")"
lacks "0 turns the memory limit off" "$log" "--memory"
lacks "none turns the cpu limit off" "$log" "--cpus"
lacks "0 turns the pid limit off" "$log" "--pids-limit"
lacks "0 turns the job cap off" "$log" "QB64_TEST_JOBS"

# Game sessions (`run`, viewer window) get no memory, CPU or pid limit by default: a CFS quota
# freezes the game loop and audio. SSS_DEV_RUN_LIMITS=1 opts back in; other commands keep them.
gamedev() { SSS_DEV_DRYRUN=1 SSS_ENGINE=podman SSS_IMAGE="$IMAGE" DISPLAY=:0 "$REPO/tools/dev" "$@" 2>&1; }
for sub in "run --version" "viewer"; do
    out="$(unset SSS_DEV_MEMORY SSS_DEV_CPUS SSS_DEV_PIDS SSS_DEV_RUN_LIMITS; gamedev $sub)"
    lacks "$sub: no --memory by default" "$out" " --memory"
    lacks "$sub: no --cpus by default" "$out" " --cpus"
    lacks "$sub: no --pids-limit by default" "$out" " --pids-limit"
    has "$sub: still has no container log" "$out" "--log-driver none"
    out="$(unset SSS_DEV_MEMORY SSS_DEV_CPUS SSS_DEV_PIDS; SSS_DEV_RUN_LIMITS=1 gamedev $sub)"
    has "$sub: SSS_DEV_RUN_LIMITS=1 applies memory" "$out" " --memory 4g "
    has "$sub: SSS_DEV_RUN_LIMITS=1 applies cpus" "$out" " --cpus 3 "
    has "$sub: SSS_DEV_RUN_LIMITS=1 applies pids" "$out" " --pids-limit 512 "
done
out="$(unset SSS_DEV_MEMORY SSS_DEV_CPUS SSS_DEV_PIDS SSS_DEV_RUN_LIMITS; gamedev viewer --sheets)"
has "viewer --sheets keeps the limits" "$out" " --cpus 3 "
for sub in build test shell; do
    out="$(unset SSS_DEV_MEMORY SSS_DEV_CPUS SSS_DEV_PIDS SSS_DEV_RUN_LIMITS; gamedev $sub)"
    has "$sub keeps the memory limit" "$out" " --memory 4g "
    has "$sub keeps the cpu limit" "$out" " --cpus 3 "
    has "$sub keeps the pid limit" "$out" " --pids-limit 512 "
done

# The repo mount uses the shared SELinux label (:z): a private :Z label from one container denies
# access to every other container and worktree on the same files.
: > "$STUB_LOG"
stubdev build > /dev/null
log="$(cat "$STUB_LOG")"
has "repo mount is shared-labeled (:z)" "$log" "-v $REPO:$REPO:z "
lacks "repo mount is not private-labeled (:Z)" "$log" "-v $REPO:$REPO:Z"

# timeout: a run that outlasts SSS_DEV_TIMEOUT is stopped and its container removed
: > "$STUB_LOG"
rc=0
start=$SECONDS
out="$(STUB_SLEEP=60 SSS_DEV_TIMEOUT=2 stubdev build)" || rc=$?
if [ "$rc" = 124 ] && [ $((SECONDS - start)) -lt 30 ]; then
    echo "ok:   a run past SSS_DEV_TIMEOUT is stopped (exit $rc after $((SECONDS - start))s)"
else
    echo "FAIL: timeout: exit $rc after $((SECONDS - start))s"
    fails=$((fails + 1))
fi
has "timed-out container is removed" "$(cat "$STUB_LOG")" "rm -f sss-dev-"
has "timeout is reported" "$out" "stopped after 2s"

# No terminal (#427): stdin is /dev/null, and every non-GUI command has a time limit, enforced
# by the client (timeout) and by the engine (podman --timeout), so a loop on EOF stays short.
: > "$STUB_LOG"
echo hello | STUB_STDIN="$stubdir/stdin" stubdev shell true > /dev/null
[ ! -s "$stubdir/stdin" ] && echo "ok:   no terminal: stdin is /dev/null" || { echo "FAIL: stub read '$(cat "$stubdir/stdin")' from stdin"; fails=$((fails + 1)); }
echo hello | SSS_DEV_STDIN=keep STUB_STDIN="$stubdir/stdin" stubdev shell true > /dev/null
has "SSS_DEV_STDIN=keep passes stdin" "$(cat "$stubdir/stdin")" "hello"
out="$(SSS_DEV_NOTTY_TIMEOUT=77 SSS_DEV_DRYRUN=1 SSS_ENGINE=podman SSS_IMAGE="$IMAGE" "$REPO/tools/dev" shell true 2>&1)"
has "no terminal: shell is limited" "$out" "timeout -k 20 77 podman run"
has "no terminal: engine-side limit" "$out" "--timeout 77"
out="$(SSS_DEV_NOTTY_TIMEOUT=0 SSS_DEV_DRYRUN=1 SSS_ENGINE=podman SSS_IMAGE="$IMAGE" "$REPO/tools/dev" shell true 2>&1)"
lacks "NOTTY_TIMEOUT=0 turns the limit off" "$out" "--timeout"
out="$(SSS_DEV_NOTTY_TIMEOUT=77 SSS_DEV_DRYRUN=1 SSS_ENGINE=podman SSS_IMAGE="$IMAGE" DISPLAY=:0 "$REPO/tools/dev" run --version 2>&1)"
lacks "the game window has no no-terminal limit" "$out" "--timeout"
rc=0
start=$SECONDS
out="$(STUB_SLEEP=60 SSS_DEV_NOTTY_TIMEOUT=2 stubdev shell sleep 100)" || rc=$?
if [ "$rc" = 124 ] && [ $((SECONDS - start)) -lt 30 ]; then
    echo "ok:   no terminal: shell past the limit is stopped (exit $rc after $((SECONDS - start))s)"
else
    echo "FAIL: no-terminal timeout: exit $rc after $((SECONDS - start))s"
    fails=$((fails + 1))
fi

# build slots: SSS_DEV_SLOTS runs at once, the rest queue
if command -v flock > /dev/null 2>&1; then
    mkdir -p "$stubdir/locks"
    exec 8>> "$stubdir/locks/slot.1"
    flock -n 8
    : > "$STUB_LOG"
    rc=0
    out="$(SSS_DEV_SLOTS=1 SSS_DEV_SLOT_WAIT=3 stubdev build)" || rc=$?
    has "slot taken: waits for a build slot" "$out" "waiting for a build slot"
    if [ "$rc" = 1 ] && [ ! -s "$STUB_LOG" ]; then
        echo "ok:   slot taken: gives up without running anything"
    else
        echo "FAIL: slot taken: exit $rc, log '$(cat "$STUB_LOG")'"
        fails=$((fails + 1))
    fi
    for c in test render bench; do
        rc=0
        out="$(SSS_DEV_SLOTS=1 SSS_DEV_SLOT_WAIT=1 stubdev $c)" || rc=$?
        has "slot taken: $c queues" "$out" "waiting for a build slot"
    done
    rc=0
    out="$(SSS_DEV_SLOTS=2 SSS_DEV_SLOT_WAIT=3 stubdev build)" || rc=$?
    lacks "second slot free: no waiting" "$out" "waiting for a build slot"
    [ "$rc" = 0 ] && echo "ok:   second slot free: runs" || { echo "FAIL: second slot free: exit $rc"; fails=$((fails + 1)); }
    rc=0
    out="$(SSS_DEV_SLOTS=1 SSS_DEV_SLOT_WAIT=1 stubdev shell true)" || rc=$?
    lacks "shell does not take a slot" "$out" "waiting for a build slot"
    flock -u 8
    exec 8>&-
    out="$(SSS_DEV_SLOTS=1 SSS_DEV_SLOT_WAIT=3 stubdev build)"
    lacks "slot released: runs without waiting" "$out" "waiting for a build slot"
    rc=0
    grep -q -- "--name sss-dev-" "$STUB_LOG" || rc=1
    [ "$rc" = 0 ] && echo "ok:   containers are named for cleanup" || { echo "FAIL: no --name on the run"; fails=$((fails + 1)); }
else
    echo "skip: no flock on this machine"
fi


if [ "$fails" -ne 0 ]; then
    echo "tools_dev_test: $fails check(s) failed"
    exit 1
fi
echo "tools_dev_test: all checks passed"
