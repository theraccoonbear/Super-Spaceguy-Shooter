' snd_init_test.bas — verify SND_*_LEN constants fit in Integer and SND_Init runs clean
'
' Regression guard for the Integer overflow bug where SND_WHOOSH_LEN = 44100
' caused "Illegal function call" and "Subscript out of range" at runtime because
' the loop counter (was As Integer, max 32767) and sndWhooshPos (As Integer) both
' overflow when the length exceeds 32767.
'
' Build: ./tools/buildqb tests/snd_init_test.bas
' Run:   ./tests/snd_init_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

Const SAMPLE_RATE = 44100

Sub MUS_Load() : End Sub
Sub MUS_Fill(n As Integer) : End Sub

'$INCLUDE:'../src/snd.bas'

Dim Shared stPassed As Integer, stFailed As Integer

Sub ST_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        stPassed = stPassed + 1
    Else
        Print "FAIL  " + testName
        stFailed = stFailed + 1
    End If
End Sub

Print "=== snd_init_test ==="
Print ""

' All *Pos playback counters are Dim As Integer (max 32767).
' No SND_*_LEN may exceed that or the counter overflows at runtime.
Const SND_INT_MAX = 32767

Print "--- buffer lengths fit in Integer ---"
ST_Assert SND_SHOOT_LEN  <= SND_INT_MAX, "SND_SHOOT_LEN <= 32767"
ST_Assert SND_BOOM_LEN   <= SND_INT_MAX, "SND_BOOM_LEN <= 32767"
ST_Assert SND_HIT_LEN    <= SND_INT_MAX, "SND_HIT_LEN <= 32767"
ST_Assert SND_PUP_LEN    <= SND_INT_MAX, "SND_PUP_LEN <= 32767"
ST_Assert SND_WHOOSH_LEN <= SND_INT_MAX, "SND_WHOOSH_LEN <= 32767"
ST_Assert SND_KICK_LEN   <= SND_INT_MAX, "SND_KICK_LEN <= 32767"
ST_Assert SND_SNARE_LEN  <= SND_INT_MAX, "SND_SNARE_LEN <= 32767"
ST_Assert SND_HIHAT_LEN  <= SND_INT_MAX, "SND_HIHAT_LEN <= 32767"

Print ""
Print "--- SND_Init runs without overflow ---"
SND_Init
' Reaching this line means no Integer overflow crashed the generation loops
ST_Assert -1, "SND_Init completed without runtime error"

' Playback positions must remain at their sentinel -1 after init; only
' SND_Whoosh() / SND_Shoot() etc. arm them by setting to 0.
ST_Assert sndWhooshPos = -1, "sndWhooshPos = -1 after SND_Init (not armed)"
ST_Assert sndShootPos  = -1, "sndShootPos = -1 after SND_Init"

' Verify array is accessible at both bounds; a subscript error here means the
' buffer was declared with the wrong size constant.
Dim sndTFirst As Single, sndTLast As Single
sndTFirst = sndWhoosh(0)
sndTLast  = sndWhoosh(SND_WHOOSH_LEN - 1)
ST_Assert -1, "sndWhoosh index 0 and SND_WHOOSH_LEN-1 are valid"

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
