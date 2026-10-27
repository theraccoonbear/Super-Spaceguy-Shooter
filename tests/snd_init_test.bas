' snd_init_test.bas — verify SND_*_LEN constants fit in Integer and SND_Init runs clean
'
' Regression guard for the Integer overflow bug where SND_WHOOSH_LEN = 44100
' caused "Illegal function call" and "Subscript out of range" at runtime because
' the loop counter (was As Integer, max 32767) and sndWhooshPos (As Integer) both
' overflow when the length exceeds 32767.
'
' Build: ./tools/buildqb tests/snd_init_test.bas
' Run:   ./tests/snd_init_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

Const SAMPLE_RATE = 44100

Sub MUS_Load() : End Sub
Sub MUS_Fill(n As Integer) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/audio/snd.bas'

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
ST_Assert SND_DEATH_LEN  <= SND_INT_MAX, "SND_DEATH_LEN <= 32767"

Print ""
Print "--- SND_Init runs without runtime error ---"

' Wrap SND_Init in an error handler so a runtime error (Integer overflow,
' illegal function call from negative fractional exponent, subscript out of
' range, etc.) is caught and reported as a test failure instead of silently
' continuing or crashing the process with a non-zero exit.
Dim sndTRtErr As Integer
ON ERROR GOTO sndTErrHandler
SND_Init
GOTO sndTAfterInit
sndTErrHandler:
    sndTRtErr = -1
    RESUME NEXT
sndTAfterInit:
ON ERROR GOTO 0

ST_Assert sndTRtErr = 0, "SND_Init completed without runtime error"

' Playback positions must remain at their sentinel -1 after init; only
' SND_Whoosh() / SND_Shoot() etc. arm them by setting to 0.
ST_Assert sndWhooshPos   = -1, "sndWhooshPos = -1 after SND_Init (not armed)"
ST_Assert sndWhooshMdPos = -1, "sndWhooshMdPos = -1 after SND_Init"
ST_Assert sndWhooshLgPos = -1, "sndWhooshLgPos = -1 after SND_Init"
ST_Assert sndShootPos    = -1, "sndShootPos = -1 after SND_Init"
ST_Assert sndDeathPos    = -1, "sndDeathPos = -1 after SND_Init"

' Verify array is accessible at both bounds; a subscript error here means the
' buffer was declared with the wrong size constant.
Dim sndTFirst As Single, sndTLast As Single
ON ERROR GOTO sndTBoundsErr
sndTFirst = sndWhoosh(0)
sndTLast  = sndWhoosh(SND_WHOOSH_LEN - 1)
GOTO sndTAfterBounds
sndTBoundsErr:
    sndTFirst = 0 : sndTLast = 0 : sndTRtErr = -1 : RESUME NEXT
sndTAfterBounds:
ON ERROR GOTO 0
ST_Assert sndTRtErr = 0, "sndWhoosh index 0 and SND_WHOOSH_LEN-1 are valid"

' ── UI one-shots (#268): the dock's cursor tick, its "can't" buzz and the power-up chime
' (dock purchase, Settings' SFX slider) must start and end at 0, with no DC left at the
' end, and a retrigger must not step the waveform (the click / hiss the dock had).
Print ""
Print "--- UI one-shots end cleanly (#268) ---"
Dim sndTId As Integer, sndTLen As Long, sndTK As Long, sndTEdge As Single, sndTDC As Single
For sndTId = SND_UI_MOVE To SND_UI_PUP
    sndTLen = SND_UiLen&(sndTId)
    sndTEdge = 0 : sndTDC = 0
    For sndTK = 0 To 2
        If Abs(SND_UiSample!(sndTId, sndTK)) > sndTEdge Then sndTEdge = Abs(SND_UiSample!(sndTId, sndTK))
        If Abs(SND_UiSample!(sndTId, sndTLen - 1 - sndTK)) > sndTEdge Then sndTEdge = Abs(SND_UiSample!(sndTId, sndTLen - 1 - sndTK))
    Next sndTK
    For sndTK = sndTLen - 64 To sndTLen - 1 : sndTDC = sndTDC + SND_UiSample!(sndTId, sndTK) : Next sndTK
    ST_Assert sndTEdge < 0.01, "UI sound" + Str$(sndTId) + ": first and last 3 samples within 0.01 of zero (max" + Str$(sndTEdge) + ")"
    ST_Assert Abs(sndTDC / 64) < 0.005, "UI sound" + Str$(sndTId) + ": no DC offset over the last 64 samples"
Next sndTId
ST_Assert SND_UiSample!(SND_UI_PUP, SND_PUP_LEN - 1) = 0, "power-up chime's last sample is exactly 0"

' worst step between consecutive output samples, retriggering each sound mid-play at
' varying phases, against the sound's own steepest step played once
Dim sndTStep As Single, sndTPrev As Single, sndTCur As Single, sndTN As Integer, sndTBase As Single
For sndTId = SND_UI_MOVE To SND_UI_PUP
    ' baseline: the sound's own steepest step, played once
    sndUiCurPos = -1 : sndUiOldPos = -1 : sndTPrev = 0 : sndTBase = 0
    SND_UiPlay sndTId
    For sndTK = 0 To SND_UiLen&(sndTId) + 10
        sndTCur = SND_UiNext!
        If Abs(sndTCur - sndTPrev) > sndTBase Then sndTBase = Abs(sndTCur - sndTPrev)
        sndTPrev = sndTCur
    Next sndTK
    ' retriggered every frame, and every 10 ms (faster than any key), at every phase
    sndUiCurPos = -1 : sndUiOldPos = -1 : sndTPrev = 0 : sndTStep = 0
    For sndTN = 1 To 12
        SND_UiPlay sndTId
        For sndTK = 1 To 441 + sndTN * 29
            sndTCur = SND_UiNext!
            If Abs(sndTCur - sndTPrev) > sndTStep Then sndTStep = Abs(sndTCur - sndTPrev)
            sndTPrev = sndTCur
        Next sndTK
    Next sndTN
    ST_Assert sndTStep <= sndTBase * 1.5 + 0.01, "UI sound" + Str$(sndTId) + ": retriggering mid-sound adds no step (worst" + Str$(sndTStep) + " vs own" + Str$(sndTBase) + ")"
    ST_Assert sndUiCurPos >= 0 Or sndUiOldPos = -1, "UI sound" + Str$(sndTId) + ": the replaced voice is gone after its fade"
Next sndTId
' and a hard restart would have failed: the sound's level mid-way is far above that bound
Dim sndTPeak As Single
For sndTK = 0 To SND_UIMOVE_LEN - 1
    If Abs(sndUiMove(sndTK)) > sndTPeak Then sndTPeak = Abs(sndUiMove(sndTK))
Next sndTK
ST_Assert sndTPeak > 0.15, "the check means something: a hard cut at the tick's peak would step by" + Str$(sndTPeak)

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
