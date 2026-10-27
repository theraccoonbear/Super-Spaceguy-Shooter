#!/usr/bin/env bash
# tests/render/run.sh -- golden-screenshot render tests (#71). Linux only (needs xvfb-run).
#
# Usage: tests/render/run.sh [--update] [--no-build] [--repeat N] [scene ...]
#   --update     bless: save this run's screenshots as the goldens in tests/render/golden/
#   --no-build   use the existing builds/sss instead of building it first (CI builds it earlier)
#   --repeat N   run every scene N times and fail unless all N runs are byte-identical
#                (determinism check; --update uses at least 3)
#   scene ...    only these scenes (names of tests/render/scenes/*.txt); default all
#
# Each scene is an input script, tests/render/scenes/<scene>.txt, whose "#!" comment lines say
# how to run it:
#   #! args: --scene boss3        extra sss options (always added: --god --no-telem --seed 1)
#   #! shots: 360,440             frames to screenshot; the run stops after the last
#   #! mask: x,y,w,h              rectangle left out of the comparison (repeatable)
# Every screenshot is compared with tests/render/golden/<scene>-<frame>.png by tools/imgdiff.bas.
# The actual screenshots go to tests/render/out/<scene>/, plus diff-<frame>.png for each
# mismatch (red = differs, yellow = differs within the tolerance, blue = masked).
#
# Env: QB64_BIN_DIR    QB64-PE install to build with (default: the qb64pe on PATH)
#      RENDER_TOL      per-channel tolerance, 0-255 (default 0: exact)
#      RENDER_MAX_FRAC fraction of pixels allowed beyond the tolerance (default 0)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
RDIR="$REPO/tests/render"
OUT="$RDIR/out"
TOL="${RENDER_TOL:-0}"
MAXFRAC="${RENDER_MAX_FRAC:-0}"
COMMON_ARGS=(--god --no-telem --seed 1)

UPDATE=0; BUILD=1; REPEAT=1; SCENES=()
while [ $# -gt 0 ]; do
    case "$1" in
        --update)   UPDATE=1 ;;
        --no-build) BUILD=0 ;;
        --repeat)   shift; REPEAT="${1:?--repeat needs a count}" ;;
        -h|--help)  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)         echo "Error: unknown option $1" >&2; exit 2 ;;
        *)          SCENES+=("$1") ;;
    esac
    shift
done
[ "$UPDATE" = 1 ] && [ "$REPEAT" -lt 3 ] && REPEAT=3
if [ ${#SCENES[@]} -eq 0 ]; then
    for f in "$RDIR"/scenes/*.txt; do SCENES+=("$(basename "$f" .txt)"); done
fi

command -v xvfb-run > /dev/null || { echo "Error: xvfb-run not found (try tools/dev render)" >&2; exit 2; }
[ -n "${QB64_BIN_DIR:-}" ] && export PATH="$(realpath "$QB64_BIN_DIR"):$PATH"

cd "$REPO"
mkdir -p "$OUT"
build() {
    echo "==> building $1"
    xvfb-run -a ./tools/buildqb "$1" > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; echo "Error: building $1 failed" >&2; exit 2; }
}
[ "$BUILD" = 1 ] && build sss.bas
[ -x builds/sss ] || { echo "Error: builds/sss missing (build it, or drop --no-build)" >&2; exit 2; }
build tools/imgdiff.bas

# directive value(s) from a scene file: directive <file> <name>
directive() { sed -n "s/^#! *$2: *//p" "$1"; }

FAILED=()
fail() { echo "    FAIL $1"; FAILED+=("$2"); }

for scene in "${SCENES[@]}"; do
    sf="$RDIR/scenes/$scene.txt"
    echo "==> $scene"
    [ -f "$sf" ] || { fail "no scene file $sf" "$scene"; continue; }
    read -r -a args <<< "$(directive "$sf" args)"
    shots="$(directive "$sf" shots)"
    [ -n "$shots" ] || { fail "no '#! shots:' line" "$scene"; continue; }
    IFS=, read -r -a frames <<< "$shots"
    last=0
    for fr in "${frames[@]}"; do [ "$fr" -gt "$last" ] && last=$fr; done
    masks=()
    while read -r m; do [ -n "$m" ] && masks+=(--mask "$m"); done <<< "$(directive "$sf" mask)"

    rm -rf "${OUT:?}/$scene"
    ok=1
    for ((run = 1; run <= REPEAT; run++)); do
        rd="$OUT/$scene/run$run"
        mkdir -p "$rd"
        # its own launch folder: screenshots and a fresh sss_settings.ini land there
        if ! (cd "$rd" && xvfb-run -a -s "-screen 0 1280x720x24" "$REPO/builds/sss" "${COMMON_ARGS[@]}" "${args[@]}" \
                --frames "$((last + 1))" --screenshot-at "$shots" --input-script "$sf" > sss.log 2>&1); then
            fail "sss exited non-zero (run $run); see $rd/sss.log" "$scene"; ok=0; break
        fi
        for fr in "${frames[@]}"; do
            [ -f "$rd/shot-$fr.png" ] || { fail "run $run saved no shot-$fr.png" "$scene"; ok=0; }
        done
        [ "$ok" = 1 ] || break
        if [ "$run" -gt 1 ]; then
            for fr in "${frames[@]}"; do
                cmp -s "$OUT/$scene/run1/shot-$fr.png" "$rd/shot-$fr.png" ||
                    { fail "frame $fr differs between run 1 and run $run: the scene isn't deterministic" "$scene"; ok=0; }
            done
            [ "$ok" = 1 ] || break
        fi
    done
    [ "$ok" = 1 ] || continue
    for fr in "${frames[@]}"; do mv "$OUT/$scene/run1/shot-$fr.png" "$OUT/$scene/"; done
    [ "$REPEAT" -gt 1 ] && echo "    $REPEAT runs byte-identical"
    [ "$ok" = 1 ] && rm -rf "$OUT/$scene"/run*

    if [ "$UPDATE" = 1 ]; then
        mkdir -p "$RDIR/golden"
        rm -f "$RDIR/golden/$scene"-*.png
        for fr in "${frames[@]}"; do
            cp "$OUT/$scene/shot-$fr.png" "$RDIR/golden/$scene-$fr.png"
            echo "    blessed golden/$scene-$fr.png"
        done
        continue
    fi
    for fr in "${frames[@]}"; do
        golden="$RDIR/golden/$scene-$fr.png"
        if [ ! -f "$golden" ]; then
            fail "no golden $golden (bless it with --update)" "$scene"; continue
        fi
        if res="$(builds/imgdiff "$golden" "$OUT/$scene/shot-$fr.png" --tol "$TOL" --max-frac "$MAXFRAC" "${masks[@]}" \
                --diff "$OUT/$scene/diff-$fr.png")"; then
            echo "    frame $fr ok: ${res#imgdiff: }"
            rm -f "$OUT/$scene/diff-$fr.png"
        else
            echo "    $res"
            fail "frame $fr doesn't match its golden; see $OUT/$scene/diff-$fr.png" "$scene"
        fi
    done
done

# goldens no scene produces any more
if [ "$UPDATE" = 0 ] && [ -d "$RDIR/golden" ]; then
    for g in "$RDIR"/golden/*.png; do
        [ -e "$g" ] || continue
        b="$(basename "$g" .png)"; scene="${b%-*}"; fr="${b##*-}"
        printf '%s\n' "${SCENES[@]}" | grep -qx "$scene" || continue
        grep -q "^#! *shots:.*\b$fr\b" "$RDIR/scenes/$scene.txt" 2> /dev/null ||
            fail "golden $b.png has no matching shot in scenes/$scene.txt (delete it or re-bless)" "$scene"
    done
fi

echo ""
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "==> RENDER TESTS FAILED: $(printf '%s\n' "${FAILED[@]}" | sort -u | tr '\n' ' ')"
    echo "    actual screenshots and diffs: $OUT/"
    echo "    if the change is intended, re-bless: tests/render/run.sh --update (tools/dev render --update)"
    exit 1
fi
echo "==> All ${#SCENES[@]} render scenes passed"
