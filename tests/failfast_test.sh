#!/usr/bin/env bash
# Checks src/sys/failfast.bi (#427): an unhandled QB64-PE runtime error must end the program
# with exit code 1 and a message, within seconds, not wait on the runtime's "Continue? y/n"
# prompt (which loops forever when stdin is at EOF). Compiles two scratch programs with the
# QB64-PE in QB64_BIN_DIR, runs them with stdin closed under a 20 s limit, and checks that
# every program the suite builds includes the handler. Linux and macOS.
set -euo pipefail

echo "=== failfast_test ==="

REPO="$(cd "$(dirname "$0")/.." && pwd)"
QB64="$(realpath "${QB64_BIN_DIR:?QB64_BIN_DIR must be set}")/qb64pe"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
ok() { echo "ok:   $1"; }
bad() { echo "FAIL: $1"; fails=$((fails + 1)); }

cat > "$WORK/plain.bas" << EOF2
Option _Explicit
\$CONSOLE:ONLY
'\$INCLUDE:'$REPO/src/sys/failfast.bi'
Sub Boom
    Dim fh As Long
    fh = FreeFile
    Open "/nonexistent-dir-427/x" For Input As #fh
End Sub
Print "before"
Boom
Print "not reached"
EOF2

# A probe that resets with ON ERROR GOTO SSS_FailFast, as sss.bas does, then a real error
cat > "$WORK/probe.bas" << EOF2
Option _Explicit
\$CONSOLE:ONLY
'\$INCLUDE:'$REPO/src/sys/failfast.bi'
Dim fh As Long
fh = FreeFile
On Error GoTo probeFail
Open "/nonexistent-dir-427/x" For Input As #fh
GoTo probeDone
probeFail:
Resume probeDone
probeDone:
On Error GoTo SSS_FailFast
Print "after probe"
Dim n As Long
Open "/nonexistent-dir-427/y" For Input As #fh
Print "not reached"
EOF2

for prog in plain probe; do
    if ! "$QB64" -x "$WORK/$prog.bas" -o "$WORK/$prog" > "$WORK/$prog.compile" 2>&1; then
        cat "$WORK/$prog.compile"
        bad "$prog.bas compiles"
        continue
    fi
    rc=0
    start=$SECONDS
    timeout 20 "$WORK/$prog" < /dev/null > "$WORK/$prog.out" 2>&1 || rc=$?
    took=$((SECONDS - start))
    if [ "$rc" = 1 ]; then ok "$prog: runtime error exits 1 (${took}s)"; else bad "$prog: exit $rc, wanted 1"; fi
    if [ "$took" -lt 10 ]; then ok "$prog: ends quickly"; else bad "$prog: took ${took}s"; fi
    if grep -q "^Runtime error 53: File not found" "$WORK/$prog.out"; then ok "$prog: prints the error"; else bad "$prog: no 'Runtime error 53' line"; sed 's/^/      /' "$WORK/$prog.out"; fi
    if grep -q "not reached" "$WORK/$prog.out"; then bad "$prog: kept running after the error"; fi
    if grep -q "Continue" "$WORK/$prog.out"; then bad "$prog: showed the Continue prompt"; fi
done

# Every program the suite and the dev tools build includes the handler.
missing=""
for f in "$REPO"/sss.bas "$REPO"/viewer.bas "$REPO"/stress.bas "$REPO"/obj2e3d.bas "$REPO"/musicplayer.bas \
         "$REPO"/tests/*.bas "$REPO"/tools/*.bas; do
    [ "$(basename "$f")" = tool_shell.bas ] && continue
    grep -q "sys/failfast.bi'" "$f" || missing="$missing ${f#"$REPO"/}"
done
if [ -z "$missing" ]; then ok "every program includes failfast.bi"; else bad "no failfast.bi include in:$missing"; fi

# A probe must not drop back to the prompt with ON ERROR GOTO 0.
if grep -rniE '^\s*on error goto 0\s*$' --include=*.bas --include=*.bi "$REPO/sss.bas" "$REPO/src" "$REPO/tests" "$REPO/tools" > "$WORK/goto0"; then
    cat "$WORK/goto0"
    bad "ON ERROR GOTO 0 found (use ON ERROR GOTO SSS_FailFast)"
else
    ok "no ON ERROR GOTO 0"
fi

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
echo "all passed"
