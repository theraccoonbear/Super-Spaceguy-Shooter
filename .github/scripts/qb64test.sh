#!/usr/bin/env bash
# Build and run the QB64-PE headless test suite, several tests at once.
# Expects QB64_BIN_DIR to point at an already-installed QB64-PE tree
# (same convention as qb64build.sh). Runs on Linux, macOS, and Windows
# (via Git Bash, as GitHub Actions' windows-latest runner provides).
#
#   QB64_TEST_JOBS=N   parallel workers (default: half the logical CPUs, at least 2 --
#                      compiles are CPU-bound and hyperthreads mostly just contend)
#   QB64_TEST_SHARD=I/N  run only shard I of N (1-based): every Nth test and tool,
#                      http_queue_test in shard 1. CI splits the slow Windows suite (#341).
#
# Each test is built and run by one worker; its output is printed in suite order once
# everything has finished, followed by a pass/fail summary with timings.
#
# Why per-worker QB64-PE copies: on Linux and macOS, qb64pe picks its temp folder
# (internal/temp, tempN) without a lock, so two compiles on one install can silently
# swap or clobber each other's output -- a test binary that is really another test
# and still passes (#239). Each worker gets its own copy instead. Windows does lock
# its temp folder, but every compile also builds any missing libqb_make_*.o and
# internal/c/parts objects into the install's shared internal/c, and two compiles
# building or linking the same object at once leave a broken one there that fails
# every later compile on every worker (#270). So Windows workers get their own copy
# too, minus the bundled compiler (too big to copy), which they share read-only
# through a junction. Every test must still print its own "=== <name> ===" banner,
# so a mixed-up binary fails loudly instead.
set -euo pipefail

REPODIR="$(cd "$(dirname "$0")/../.." && pwd)"

if [ -z "${QB64_BIN_DIR:-}" ]; then
  echo "ERROR: QB64_BIN_DIR must be set"
  exit 1
fi
QB64_DIR="$(realpath "$QB64_BIN_DIR")"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) IS_WIN=1; QB64="$QB64_DIR/qb64pe.exe" ;;
  *)                    IS_WIN=0; QB64="$QB64_DIR/qb64pe" ;;
esac

if [ ! -x "$QB64" ]; then
  echo "ERROR: $QB64 not found or not executable"
  exit 1
fi

# The mnv tests include src/gameplay/spline_path_gen.bi, which is generated (not
# committed). Regenerate it as tools/buildqb sss.bas does when it's missing or older
# than its inputs, so a fresh checkout can run the suite without a game build (#254).
SPLINE_GEN="$REPODIR/src/gameplay/spline_path_gen.bi"
SPLINE_INPUTS=(math/formula.expr math/package.json math/package-lock.json tools/emit-spline.js)
if [ ! -f "$SPLINE_GEN" ] || [ -n "$(cd "$REPODIR" && find "${SPLINE_INPUTS[@]}" -newer "$SPLINE_GEN" -print -quit)" ]; then
  echo "==> Generating spline math from DSL (spline_path_gen.bi missing or stale)..."
  for tool in node npm; do
    if ! command -v "$tool" > /dev/null 2>&1; then
      echo "ERROR: $tool not found, and src/gameplay/spline_path_gen.bi needs regenerating."
      echo "       Install Node.js, or run the suite in the container: tools/dev test"
      exit 1
    fi
  done
  (cd "$REPODIR/math" && npm install --prefer-offline --silent)
  (cd "$REPODIR" && node tools/emit-spline.js)
fi

# Longest-running first, so it isn't the last thing left. http_queue_test runs on its
# own at the end (it needs the mock server on a fixed port).
TESTS=(
  crawl_step_test
  mnv_transition_test
  mnv_conformance_test
  crawl_plan_test
  seq_dispatch_test
  seq_trace_test
  seq_graph_test
  scene_jump_planet_test
  spk_timing_test
  narr_drain_test
  snd_init_test
  music_test
  telem_creds_test
  death_telem_test
  run_end_test
  tutorial_run_test
  tutorial_script_test
  tutorial_gate_test
  dbg_output_test
  mnv_load_test
  spore_test
  attack_test
  inputscript_test
  pad_map_test
  rng_test
  titlenav_test
  textedit_test
  lbrd_test
  font_render_test
  upgrade_test
  dock_test
  remap_test
  menu_test
  callsign_pad_test
  powerup_test
  wave_timing_test
  boss_hp_test
  readonly_io_test
  settings_dir_test
  tty_probe_test
  cam_default_test
  difficulty_test
)

# Dev tools (path from the repo root, no .bas): compiled only (they're interactive), so an engine change
# that breaks them fails CI instead of going unnoticed (#224).
TOOLS=(
  viewer
  stress
  obj2e3d
  tools/padrecord
  musicplayer
  tools/musrender
)

RUN_HTTP=1
if [ -n "${QB64_TEST_SHARD:-}" ]; then
  SHARD_I="${QB64_TEST_SHARD%/*}" SHARD_N="${QB64_TEST_SHARD#*/}"
  if ! [[ "$SHARD_I" =~ ^[1-9][0-9]*$ && "$SHARD_N" =~ ^[1-9][0-9]*$ ]] || [ "$SHARD_I" -gt "$SHARD_N" ]; then
    echo "ERROR: QB64_TEST_SHARD must be I/N with 1 <= I <= N, got '$QB64_TEST_SHARD'"
    exit 1
  fi
  # alternate down the longest-first lists so each shard gets a share of the slow tests
  pick_shard() { local i=0 x; for x in "$@"; do [ $((i++ % SHARD_N + 1)) -eq "$SHARD_I" ] && echo "$x"; done; return 0; }
  mapfile -t TESTS < <(pick_shard "${TESTS[@]}")
  mapfile -t TOOLS < <(pick_shard "${TOOLS[@]}")
  [ "$SHARD_I" -eq 1 ] || RUN_HTTP=0
  echo "==> Shard $QB64_TEST_SHARD: ${#TESTS[@]} tests, ${#TOOLS[@]} tools$([ "$RUN_HTTP" = 1 ] && echo ', http_queue_test')"
fi

CPUS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
JOBS="${QB64_TEST_JOBS:-$((CPUS / 2))}"
[ "$JOBS" -lt 2 ] && JOBS=2
[ "$JOBS" -gt "$((${#TESTS[@]} + ${#TOOLS[@]}))" ] && JOBS="$((${#TESTS[@]} + ${#TOOLS[@]}))"

WORK="$(mktemp -d)"

# Windows junctions: $1 = link, $2 = target. Removed with rmdir, which drops the
# link only -- a recursive delete could follow it into the shared install.
win_junction() {
  WIN_LINK="$(cygpath -w "$1")" WIN_TARGET="$(cygpath -w "$2")" \
    powershell -Command 'if (Test-Path $env:WIN_LINK) { cmd /c rmdir $env:WIN_LINK }; New-Item -ItemType Junction -Path $env:WIN_LINK -Target $env:WIN_TARGET' > /dev/null
}
cleanup() {
  if [ "$IS_WIN" = 1 ]; then
    local link
    for link in "$WORK"/qb*/assets "$WORK"/qb*/internal/c/c_compiler; do
      [ -e "$link" ] && cmd //c rmdir "$(cygpath -w "$link")"
    done
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# QB64-PE resolves $EMBED paths relative to its binary directory.
# Mirror the link that buildqb creates so $EMBED:'assets/...' resolves.
link_assets() {
  local qbdir="$1"
  if [ "$IS_WIN" = 1 ]; then
    win_junction "$qbdir/assets" "$REPODIR/assets"
  else
    ln -sfn "$REPODIR/assets" "$qbdir/assets"
  fi
}
link_assets "$QB64_DIR"

# Worker N compiles with $WORK/qb<N>/qb64pe: a private copy of the parts of the
# install a compile touches. Windows copies run in parallel (many small files are
# slow to copy there).
setup_worker() {
  local w="$1" d="$WORK/qb$1" entry
  mkdir -p "$d/internal"
  cp -a "$QB64" "$QB64_DIR/Makefile" "$d/"
  # settings/ only exists once qb64pe has run; a fresh install (container, CI cache
  # miss) has none, and qb64pe creates its own
  [ -d "$QB64_DIR/settings" ] && cp -a "$QB64_DIR/settings" "$d/"
  cp -a "$QB64_DIR/internal/source" "$QB64_DIR/internal/support" "$d/internal/"
  if [ "$IS_WIN" = 1 ]; then
    mkdir -p "$d/internal/c"
    for entry in "$QB64_DIR/internal/c"/*; do
      [ "$(basename "$entry")" = c_compiler ] || cp -a "$entry" "$d/internal/c/"
    done
    win_junction "$d/internal/c/c_compiler" "$QB64_DIR/internal/c/c_compiler"
  else
    cp -a "$QB64_DIR/internal/c" "$d/internal/"
  fi
  link_assets "$d"
  echo "$d" > "$WORK/qbdir$w"
}
if [ "$IS_WIN" = 1 ]; then
  for ((w = 1; w <= JOBS; w++)); do setup_worker "$w" & done
  wait
  for ((w = 1; w <= JOBS; w++)); do
    [ -f "$WORK/qbdir$w" ] || { echo "ERROR: setting up QB64-PE copy for worker $w failed"; exit 1; }
  done
else
  for ((w = 1; w <= JOBS; w++)); do setup_worker "$w"; done
fi

# Compile a test .bas into an executable. $1 = qb64pe dir, $2 = source, $3 = output
# path (no extension). Prints the runnable path on success.
#
# Windows: QB64-PE's exit code can't be trusted after a successful -x compile
# on this platform (same issue qb64build.sh works around), so run it via
# PowerShell and verify the output file directly instead of checking $?.
build_test() {
  local qbdir="$1" src="$2" out="$3" qb
  rm -f "$out" "${out}.exe"
  if [ "$IS_WIN" = 1 ]; then
    QB64_WIN="$(cygpath -w "$qbdir/qb64pe.exe")" SRC_WIN="$(cygpath -w "$src")" OUT_WIN="$(cygpath -w "${out}.exe")" \
      powershell -Command '& $env:QB64_WIN -x $env:SRC_WIN -o $env:OUT_WIN; exit 0' >&2
    [ -f "${out}.exe" ] || { echo "ERROR: ${out}.exe not produced by QB64-PE" >&2; return 1; }
    echo "${out}.exe"
  else
    qb="$qbdir/qb64pe"
    if command -v xvfb-run &>/dev/null; then
      xvfb-run -a "$qb" -x "$src" -o "$out" >&2 || return 1
    else
      "$qb" -x "$src" -o "$out" >&2 || return 1
    fi
    [ -x "$out" ] || { echo "ERROR: $out not produced by QB64-PE" >&2; return 1; }
    echo "$out"
  fi
}

# Build and run one test on the first free worker slot (xargs never runs more than
# JOBS of these at once). Writes $WORK/<name>.log, .result ("PASS"/"FAIL <why>"),
# .time ("<build>s build, <run>s run").
test_job() {
  local name="$1" slot qbdir bin t0 t1 t2 log="$WORK/$1.log" src out is_tool=0
  case " $TOOL_NAMES " in *" $name "*) is_tool=1 ;; esac
  mkdir -p "$(dirname "$log")"  # a tool under tools/ keeps its log, result and binary in $WORK/tools/
  if [ "$is_tool" = 1 ]; then
    src="$REPODIR/${name}.bas"; out="$WORK/${name}"
  else
    src="$REPODIR/tests/${name}.bas"; out="$REPODIR/tests/${name}"
  fi
  for ((slot = 1; slot <= JOBS; slot++)); do
    mkdir "$WORK/lock$slot" 2> /dev/null && break
  done
  qbdir="$(cat "$WORK/qbdir$slot")"
  t0=$SECONDS
  if ! bin="$(build_test "$qbdir" "$src" "$out" 2>> "$log")"; then
    cat "$qbdir"/internal/temp*/compilelog.txt >> "$log" 2> /dev/null || true
    rmdir "$WORK/lock$slot"
    echo "FAIL build" > "$WORK/$name.result"
    echo "$((SECONDS - t0))s build" > "$WORK/$name.time"
    return 0
  fi
  rmdir "$WORK/lock$slot"
  t1=$SECONDS
  if [ "$is_tool" = 1 ]; then
    echo "PASS" > "$WORK/$name.result"
    echo "$((t1 - t0))s build (compile only)" > "$WORK/$name.time"
    return 0
  fi
  if "$bin" >> "$log" 2>&1; then
    if grep -q "=== ${name} ===" "$log"; then
      echo "PASS" > "$WORK/$name.result"
    else
      echo "FAIL ran a different test's binary (parallel build mix-up?)" > "$WORK/$name.result"
    fi
  else
    echo "FAIL exit $?" > "$WORK/$name.result"
  fi
  t2=$SECONDS
  echo "$((t1 - t0))s build, $((t2 - t1))s run" > "$WORK/$name.time"
}

TOOL_NAMES="${TOOLS[*]}"
export REPODIR QB64_DIR IS_WIN WORK JOBS TOOL_NAMES
export -f build_test test_job

echo "==> Building and running ${#TESTS[@]} tests and compiling ${#TOOLS[@]} tools, $JOBS at a time..."
touch "$WORK/suite_start"
SUITE_T0=$SECONDS
printf '%s\n' "${TESTS[@]}" "${TOOLS[@]}" | xargs -P "$JOBS" -I{} bash -c 'test_job "$1"' _ {}

# Windows: copy the libqb/parts objects the workers had to build back into the shared
# install (never overwriting), so a QB64-PE cache saved after this run has them and
# later runs' workers start warm instead of each rebuilding them (#270).
if [ "$IS_WIN" = 1 ]; then
  for ((w = 1; w <= JOBS; w++)); do
    (cd "$WORK/qb$w/internal/c" && find . -path ./c_compiler -prune -o -type f \( -name '*.o' -o -name '*.a' \) \
      ! -name 'qbx*.o' -newer "$WORK/suite_start" -print) | while read -r obj; do
      [ -e "$QB64_DIR/internal/c/$obj" ] && continue
      cp "$WORK/qb$w/internal/c/$obj" "$QB64_DIR/internal/c/$obj"
      echo "${obj#./}" >> "$WORK/kept_objects"
    done
  done
  if [ -f "$WORK/kept_objects" ]; then
    echo "==> Kept $(wc -l < "$WORK/kept_objects") QB64-PE objects the workers built in the shared install"
  fi
fi

FAILED=()
for name in "${TESTS[@]}" "${TOOLS[@]}"; do
  echo ""
  echo "==> ${name}"
  cat "$WORK/$name.log" 2> /dev/null || true
  result="$(cat "$WORK/$name.result" 2> /dev/null || echo "FAIL no result")"
  [ "$result" = "PASS" ] || FAILED+=("$name")
done

run_http_test() {
  local name="$1" bin
  echo ""
  echo "==> ${name}"
  local t0=$SECONDS
  if ! bin="$(build_test "$(cat "$WORK/qbdir1")" "$REPODIR/tests/${name}.bas" "$REPODIR/tests/${name}")"; then
    cat "$(cat "$WORK/qbdir1")"/internal/temp*/compilelog.txt 2> /dev/null || true
    echo "FAIL build" > "$WORK/$name.result"
    return 0
  fi

  echo "    Starting HTTP mock server..."
  # Use a fixed port and poll for reachability via curl instead of reading a
  # printed port back from redirected stdout -- that read was silently never
  # satisfied on macOS CI (untested there before this branch; no diagnosis
  # possible, not even stderr, so this sidesteps whatever the cause is).
  local mock_port=18752
  local errfile
  errfile="$(mktemp)"
  node "$REPODIR/tools/http_mock_server" --port "$mock_port" > /dev/null 2> "$errfile" &
  local mock_pid=$!
  local ready=0
  for i in $(seq 1 150); do
    if curl -sf "http://127.0.0.1:${mock_port}/requests" > /dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 0.1
  done

  if [ "$ready" -ne 1 ]; then
    echo "ERROR: mock server not reachable on port $mock_port"
    echo "--- stderr ---"
    cat "$errfile" 2>/dev/null || true
    rm -f "$errfile"
    kill "$mock_pid" 2>/dev/null || true
    echo "FAIL mock server" > "$WORK/$name.result"
    return 0
  fi
  rm -f "$errfile"
  echo "    Mock listening on http://127.0.0.1:${mock_port}"

  if "$bin" "http://127.0.0.1:$mock_port"; then
    echo "PASS" > "$WORK/$name.result"
  else
    echo "FAIL exit $?" > "$WORK/$name.result"
  fi
  kill "$mock_pid" 2>/dev/null || true
  echo "$((SECONDS - t0))s build+run" > "$WORK/$name.time"
}
HTTP_TESTS=()
if [ "$RUN_HTTP" = 1 ]; then
  HTTP_TESTS=(http_queue_test)
  run_http_test http_queue_test
  [ "$(cat "$WORK/http_queue_test.result")" = "PASS" ] || FAILED+=(http_queue_test)
fi

echo ""
echo "==> Summary ($((SECONDS - SUITE_T0))s, $JOBS workers)"
for name in "${TESTS[@]}" "${TOOLS[@]}" ${HTTP_TESTS[@]+"${HTTP_TESTS[@]}"}; do
  printf '    %-24s %-6s %s\n' "$name" "$(cut -d' ' -f1 < "$WORK/$name.result")" "$(cat "$WORK/$name.time" 2> /dev/null || true)"
done

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo ""
  for name in "${FAILED[@]}"; do
    echo "==> TESTS FAILED — ${name}: $(cat "$WORK/$name.result") — see its output above"
  done
  exit 1
fi
echo "==> All tests passed"
