' tty_probe_test.bas -- regression test for issue #300
'
' sss.bas probes /dev/tty at module level with ON ERROR. After a failed open
' (no terminal) the handler must RESUME and then ON ERROR GOTO 0, or the next
' ON ERROR probe turns its own error into a fatal "Bad file name". This runs
' the same probe pattern as sss.bas, then a second probe that must fail
' cleanly and be caught. The first probe's outcome depends on whether the
' run has a terminal, so only the second probe is asserted.
'
' Build: ./tools/buildqb tests/tty_probe_test.bas
' Run:   builds/tty_probe_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

Dim ttyOK As Integer, ttyProbeFH As Integer, secondProbeFH As Integer
Dim secondCaught As Integer, passed As Integer, failed As Integer

Print "=== tty_probe_test ==="

ttyProbeFH = FreeFile
ON ERROR GOTO ttyFail
Open "/dev/tty" For Append As #ttyProbeFH : Close #ttyProbeFH
ttyOK = -1
GoTo ttyDone
ttyFail:
Resume ttyDone
ttyDone:
ON ERROR GOTO 0

secondProbeFH = FreeFile
ON ERROR GOTO secondFail
Open "/nonexistent-dir-300/probe.tmp" For Output As #secondProbeFH : Close #secondProbeFH
GoTo secondDone
secondFail:
secondCaught = -1
Resume secondDone
secondDone:
ON ERROR GOTO 0

If secondCaught Then
    Print "PASS  a probe after the /dev/tty probe traps its own error"
    passed = passed + 1
Else
    Print "FAIL  a probe after the /dev/tty probe traps its own error"
    failed = failed + 1
End If

Print passed; " passed,"; failed; " failed"
If failed > 0 Then System 1
System 0
