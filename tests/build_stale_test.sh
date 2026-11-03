#!/usr/bin/env bash
# Checks tools/buildqb --check (#233): a build is current while the content of its inputs is
# unchanged (a re-run, a touch) and stale once an included file, an embedded asset or the
# entry file changes. Runs against a throwaway repo, so it needs no QB64-PE compile.
set -euo pipefail

echo "=== build_stale_test ==="

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/tools" "$WORK/src/deep" "$WORK/lib" "$WORK/assets" "$WORK/builds"
cp "$REPO/tools/buildqb" "$REPO/tools/build-manifest" "$REPO/tools/make-version.sh" "$WORK/tools/"
cd "$WORK"
echo "0.0.1" > VERSION
printf '%s\n' "'\$INCLUDE:'src/mid.bi'" "\$EMBED:'assets/data.txt':'DATA'" "Print 1" > main.bas
printf '%s\n' "'\$INCLUDE:'deep/leaf.bi'" > src/mid.bi
printf '%s\n' "'\$INCLUDE:'../../lib/last.bas'" > src/deep/leaf.bi
printf '%s\n' "Print 2" > lib/last.bas
echo "one" > assets/data.txt
echo "unrelated" > lib/unused.bas

fails=0
expect() {   # expect <label> <want exit> <want output part> <actual exit> <output>
    if [ "$4" = "$2" ] && [[ "$5" == *"$3"* ]]; then
        echo "ok:   $1"
    else
        echo "FAIL: $1 (exit $4, wanted $2 with '$3')"
        echo "$5" | sed 's/^/      /'
        fails=$((fails + 1))
    fi
}
check() {   # sets rc and out
    rc=0
    out="$(./tools/buildqb --check main.bas 2>&1)" || rc=$?
}

check
expect "no build yet is stale" 1 "does not exist" "$rc" "$out"

: > builds/main
check
expect "an executable with no manifest is stale" 1 "no manifest" "$rc" "$out"

./tools/build-manifest main.bas > builds/main.manifest
manifest="$(cat builds/main.manifest)"
for want in "main.bas:" "src/mid.bi:" "src/deep/leaf.bi:" "lib/last.bas:" "assets/data.txt:"; do
    if [[ "$manifest" == *"$want"* ]]; then
        echo "ok:   manifest lists $want"
    else
        echo "FAIL: manifest is missing $want"
        fails=$((fails + 1))
    fi
done
if [[ "$manifest" == *"unused.bas"* ]]; then
    echo "FAIL: manifest lists a file nothing includes"
    fails=$((fails + 1))
fi

check
expect "a fresh build is current" 0 "current" "$rc" "$out"
check
expect "a re-run is current" 0 "current" "$rc" "$out"

touch -t 200001010000 lib/last.bas assets/data.txt main.bas
check
expect "an mtime-only touch is current" 0 "current" "$rc" "$out"

echo "unrelated, edited" > lib/unused.bas
check
expect "editing a file nothing includes is current" 0 "current" "$rc" "$out"

echo "Print 3" > lib/last.bas
check
expect "editing a nested include is stale" 1 "changed: lib/last.bas" "$rc" "$out"
echo "Print 2" > lib/last.bas
check
expect "restoring the content is current again" 0 "current" "$rc" "$out"

echo "two" > assets/data.txt
check
expect "editing an embedded asset is stale" 1 "changed: assets/data.txt" "$rc" "$out"
echo "one" > assets/data.txt

printf '%s\n' "'\$INCLUDE:'extra.bi'" >> main.bas
echo "Print 4" > extra.bi
check
expect "a new include is stale" 1 "added:   extra.bi" "$rc" "$out"

./tools/build-manifest main.bas > builds/main.manifest
check
expect "rebaselined is current" 0 "current" "$rc" "$out"

rc=0
out="$(SSS_RELEASE=1 ./tools/buildqb --check main.bas 2>&1)" || rc=$?
expect "a release build of a dev build is stale" 1 "env/release" "$rc" "$out"

rm extra.bi
check
expect "a removed include is stale" 1 "changed: extra.bi" "$rc" "$out"

if [ "$fails" -gt 0 ]; then
    echo "$fails check(s) failed"
    exit 1
fi
echo "all checks passed"
