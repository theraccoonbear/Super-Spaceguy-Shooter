' inputscript_test.bas — scripted input for headless playtests (src/sys/inputscript.bas)
'
' Drives the real module: parsing (ranges, several keys, comments, blanks, tabs, case),
' rejecting malformed lines, ISC_Apply holding exactly the scripted keys on the
' scripted frames (inclusive ends, overlapping ranges, everything else up), and a
' missing file.
'
' Build: ./tools/buildqb tests/inputscript_test.bas
' Run:   ./tests/inputscript_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

'$INCLUDE:'../src/3d/input.bas'
'$INCLUDE:'../src/sys/inputscript.bas'

Dim Shared isPassed As Integer, isFailed As Integer
Dim Shared isHeld(0 To 32767) As Integer
Dim isOk As Integer, isOk2 As Integer, isOk3 As Integer

Sub IS_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        isPassed = isPassed + 1
    Else
        Print "FAIL  " + testName
        isFailed = isFailed + 1
    End If
End Sub

' Number of held() slots that are down.
Function IS_Down%
    Dim isI As Long, isN As Integer
    For isI = 0 To 32767
        If isHeld(isI) Then isN = isN + 1
    Next isI
    IS_Down% = isN
End Function

Print "=== inputscript_test ==="
Print ""

Print "--- parsing ---"
ISC_Clear
isOk = ISC_ParseLine%("0 10 LEFT")
IS_Assert isOk And iscCount = 1, "one key, one range"
isOk = ISC_ParseLine%("  5   20  fire  Up ")
IS_Assert isOk And iscCount = 3, "several keys, extra spaces, any case"
isOk = ISC_ParseLine%("7" + Chr$(9) + "8" + Chr$(9) + "ESC")
IS_Assert isOk And iscCount = 4, "tabs separate too"
isOk = ISC_ParseLine%("# just a comment") And ISC_ParseLine%("") And ISC_ParseLine%("   ")
IS_Assert isOk And iscCount = 4, "comments and blank lines add nothing"
IS_Assert iscFrom(2) = 5 And iscTo(2) = 20 And iscKey(2) = E3D_KEY_SPACE And iscKey(3) = E3D_KEY_UP, "FIRE is SPACE; ranges stored"

Print "--- rejects ---"
isOk = ISC_ParseLine%("10 5 LEFT")
IS_Assert isOk = 0 And InStr(iscError, "before start") > 0, "end before start"
isOk = ISC_ParseLine%("x 5 LEFT")
IS_Assert isOk = 0 And InStr(iscError, "start frame") > 0, "non-numeric start"
isOk = ISC_ParseLine%("1 y LEFT")
IS_Assert isOk = 0 And InStr(iscError, "end frame") > 0, "non-numeric end"
isOk = ISC_ParseLine%("-1 5 LEFT")
IS_Assert isOk = 0, "negative frame"
isOk = ISC_ParseLine%("1 5 JUMP")
IS_Assert isOk = 0 And InStr(iscError, "JUMP") > 0, "unknown key named in the error"
isOk = ISC_ParseLine%("1 5")
IS_Assert isOk = 0 And InStr(iscError, "no keys") > 0, "a range with no keys"

Print "--- ISC_Apply ---"
ISC_Clear
IS_Assert ISC_ParseLine%("10 20 LEFT FIRE"), "load: 10-20 LEFT FIRE"
IS_Assert ISC_ParseLine%("15 30 UP"), "load: 15-30 UP"
isHeld(E3D_KEY_DOWN) = -1 : isHeld(500) = -1
ISC_Apply 9, isHeld()
IS_Assert IS_Down% = 0, "before any range: nothing held, stale keys cleared"
ISC_Apply 10, isHeld()
IS_Assert isHeld(E3D_KEY_LEFT) And isHeld(E3D_KEY_SPACE) And IS_Down% = 2, "first frame of a range is held"
ISC_Apply 17, isHeld()
IS_Assert isHeld(E3D_KEY_LEFT) And isHeld(E3D_KEY_SPACE) And isHeld(E3D_KEY_UP) And IS_Down% = 3, "overlapping ranges combine"
ISC_Apply 20, isHeld()
IS_Assert isHeld(E3D_KEY_LEFT) And IS_Down% = 3, "last frame of a range is held (inclusive)"
ISC_Apply 21, isHeld()
IS_Assert isHeld(E3D_KEY_LEFT) = 0 And isHeld(E3D_KEY_UP) And IS_Down% = 1, "after a range ends its keys come up"
ISC_Apply 31, isHeld()
IS_Assert IS_Down% = 0, "after every range: nothing held"

Print "--- files ---"
isOk = ISC_Load%("no/such/script.txt")
IS_Assert isOk = 0 And InStr(iscError, "not found") > 0 And iscActive = 0, "missing file: error, not active"

Print ""
Print "=== " + LTrim$(Str$(isPassed + isFailed)) + " tests: " + LTrim$(Str$(isPassed)) + " passed, " + LTrim$(Str$(isFailed)) + " failed ==="
If isFailed > 0 Then System 1 Else System 0

' stub: input.bas logs devices through debug.bas, which this test doesn't include
Sub DBG_Print(isDbgMsg As String)
End Sub
