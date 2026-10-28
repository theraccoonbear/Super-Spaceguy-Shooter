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
$EMBED:'assets/music.mus':'MUSICDATA'
$EMBED:'assets/sequence.txt':'SEQTXT'

Const SAMPLE_RATE = 44100
' UI sound ids (dims.bas in the game)
Const SND_UI_MOVE   = 1
Const SND_UI_DENY   = 2
Const SND_UI_PUP    = 3
Const SND_UI_TYPE   = 4
Const SND_UI_DEL    = 5
Const SND_UI_COLOR  = 6
Const SND_UI_SPIN   = 7
Const SND_UI_SPIN_N = 39
Const SND_UI_LAST   = SND_UI_SPIN + SND_UI_SPIN_N - 1

' music.bas's mixer reads these (dims.bas / speech.bas in the game)
Dim Shared volMusic As Single, volSfx As Single, volSpeech As Single, spkSampleOut As Single
Sub SPK_Advance () : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/audio/snd.bas'
'$INCLUDE:'../src/audio/music.bas'

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

Function ST_CueIdx% (stCIn As String)
    Dim stCIi As Integer
    ST_CueIdx% = -1
    For stCIi = 0 To musCueCnt - 1
        If musCueN$(stCIi) = stCIn Then ST_CueIdx% = stCIi
    Next stCIi
End Function

' Lines of a text asset whose first token is stCDdir (case-insensitive).
Function ST_CountDirective% (stCDdat As String, stCDdir As String)
    Dim stCDrest As String, stCDln As String, stCDp As Integer, stCDn As Integer
    stCDrest = stCDdat
    Do While Len(stCDrest) > 0
        stCDp = InStr(stCDrest, Chr$(10))
        If stCDp > 0 Then stCDln = Left$(stCDrest, stCDp - 1) : stCDrest = Mid$(stCDrest, stCDp + 1) Else stCDln = stCDrest : stCDrest = ""
        stCDln = UCase$(LTrim$(RTrim$(stCDln))) + " "
        If Left$(stCDln, Len(stCDdir) + 1) = UCase$(stCDdir) + " " Then stCDn = stCDn + 1
    Loop
    ST_CountDirective% = stCDn
End Function

' Renders stCRsec seconds of a cue through the real mixer (music only, before volMusic)
' and returns its RMS, skipping the first 2 s while the pads fade in.
Function ST_CueRms! (stCRn As String, stCRsec As Single, stCRpeak As Single)
    Dim stCRk As Long, stCRs As Single, stCRsum As Double, stCRcnt As Long
    sndKickPos = -1 : sndSnarePos = -1 : sndHihatPos = -1
    MUS_SetCue stCRn
    stCRpeak = 0
    For stCRk = 0 To CLng(stCRsec * SAMPLE_RATE) - 1
        stCRs = MUS_MusicSample!
        If stCRk >= 2 * SAMPLE_RATE Then
            stCRsum = stCRsum + CDbl(stCRs) * stCRs : stCRcnt = stCRcnt + 1
            If Abs(stCRs) > stCRpeak Then stCRpeak = Abs(stCRs)
        End If
    Next stCRk
    ST_CueRms! = Sqr(stCRsum / stCRcnt)
End Function

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

' ── UI one-shots (#268, #266): the dock's cursor tick, its "can't" buzz, the power-up chime and the callsign sounds
' (dock purchase, Settings' SFX slider) must start and end at 0, with no DC left at the
' end, and a retrigger must not step the waveform (the click / hiss the dock had).
Print ""
Print "--- UI one-shots end cleanly (#268) ---"
Dim sndTId As Integer, sndTLen As Long, sndTK As Long, sndTEdge As Single, sndTDC As Single
For sndTId = SND_UI_MOVE To SND_UI_LAST
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

' the callsign sounds (#266): type click, delete / back blip, color shimmer, spinner ticks
Dim sndTPk As Single, sndTZc As Long, sndTZcPrev As Long, sndTRise As Integer, sndTZcA As Long
sndTRise = -1 : sndTZcPrev = 0
For sndTId = SND_UI_TYPE To SND_UI_LAST
    sndTLen = SND_UiLen&(sndTId)
    sndTPk = 0 : sndTZc = 0
    For sndTK = 0 To sndTLen - 1
        If Abs(SND_UiSample!(sndTId, sndTK)) > sndTPk Then sndTPk = Abs(SND_UiSample!(sndTId, sndTK))
        If sndTK > 0 Then
            If (SND_UiSample!(sndTId, sndTK) >= 0) <> (SND_UiSample!(sndTId, sndTK - 1) >= 0) Then sndTZc = sndTZc + 1
        End If
    Next sndTK
    ST_Assert sndTLen > 0 And SND_UiSample!(sndTId, 0) = 0 And SND_UiSample!(sndTId, sndTLen - 1) = 0, "UI sound" + Str$(sndTId) + ": first and last samples exactly 0"
    ST_Assert sndTPk > 0.05 And sndTPk < 0.5, "UI sound" + Str$(sndTId) + ": audible, not loud (peak" + Str$(sndTPk) + ")"
    If sndTId > SND_UI_SPIN And sndTZc < sndTZcPrev Then sndTRise = 0
    If sndTId = SND_UI_SPIN Then sndTZcA = sndTZc
    sndTZcPrev = sndTZc
Next sndTId
ST_Assert sndTRise And sndTZc > sndTZcA * 1.5, "spinner ticks rise in pitch through the set (zero crossings" + Str$(sndTZcA) + " ->" + Str$(sndTZc) + ", never falling)"
ST_Assert SND_UiLen&(SND_UI_SPIN) < SAMPLE_RATE * 5 / 60, "a spinner tick ends before the next at the 12/s hold-repeat (5 frames)"

' worst step between consecutive output samples, retriggering each sound mid-play at
' varying phases, against the sound's own steepest step played once
Dim sndTStep As Single, sndTPrev As Single, sndTCur As Single, sndTN As Integer, sndTBase As Single
For sndTId = SND_UI_MOVE To SND_UI_LAST
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

' ── music data (#268): SND_Init above ran the real MUS_Load on assets/music.mus ──
Print ""
Print "--- music.mus loads whole; the dock cue (#268) ---"
Dim stMusDat As String : stMusDat = _EMBEDDED$("MUSICDATA")
ST_Assert musCueCnt = ST_CountDirective%(stMusDat, "CUE"), "every CUE in music.mus loaded (" + LTrim$(Str$(musCueCnt)) + " of max" + Str$(MUS_CUE_MAX) + ")"
ST_Assert musInstCnt = ST_CountDirective%(stMusDat, "INST"), "every INST loaded (" + LTrim$(Str$(musInstCnt)) + " of max" + Str$(MUS_INST_MAX) + ")"
ST_Assert musSeqCnt = ST_CountDirective%(stMusDat, "SEQ"), "every SEQ loaded (" + LTrim$(Str$(musSeqCnt)) + " of max" + Str$(MUS_SEQ_MAX) + ")"
ST_Assert musPadTotal = ST_CountDirective%(stMusDat, "PAD"), "every PAD loaded (" + LTrim$(Str$(musPadTotal)) + " of max" + Str$(MUS_PAD_MAX) + ")"
ST_Assert musDrumCnt = ST_CountDirective%(stMusDat, "DRUM"), "every DRUM loaded (" + LTrim$(Str$(musDrumCnt)) + " of max" + Str$(MUS_DRUM_MAX) + ")"
ST_Assert musNCount < MUS_NOTE_MAX, "note pool not full (" + LTrim$(Str$(musNCount)) + " of" + Str$(MUS_NOTE_MAX) + ")"

Dim stDockCue As Integer : stDockCue = ST_CueIdx%("dock")
ST_Assert stDockCue >= 0, "cue 'dock' exists"
If stDockCue >= 0 Then
    ST_Assert musCueVCnt(stDockCue) >= 3, "dock has voices (" + LTrim$(Str$(musCueVCnt(stDockCue))) + ")"
    ST_Assert musCueBPM(stDockCue) >= 80 And musCueBPM(stDockCue) <= 110, "dock BPM is relaxed mid-tempo (" + LTrim$(Str$(musCueBPM(stDockCue))) + ")"
    ST_Assert musCueDrum(stDockCue) >= 0, "dock has its drum pattern"
    ' loop seam: every sequenced voice spans the same number of steps, a whole number of drum bars
    Dim stDV As Integer, stDN As Integer, stDSteps As Integer, stDFirst As Integer, stDSeam As Integer
    stDFirst = -1 : stDSeam = -1
    For stDV = 0 To musCueVCnt(stDockCue) - 1
        If musCueTmpl(stDockCue, stDV).isPad = 0 Then
            stDSteps = 0
            For stDN = 0 To musCueTmpl(stDockCue, stDV).seqLen - 1
                stDSteps = stDSteps + musND(musCueTmpl(stDockCue, stDV).seqBase + stDN)
            Next stDN
            If stDFirst < 0 Then stDFirst = stDSteps
            If stDSteps <> stDFirst Or stDSteps Mod musDrumLen(musCueDrum(stDockCue)) <> 0 Then stDSeam = 0
        End If
    Next stDV
    ST_Assert stDFirst > 0 And stDSeam, "dock voices loop together (" + LTrim$(Str$(stDFirst)) + " steps each, whole drum bars)"
End If

' every DOCK step in sequence.txt names a cue that exists
Dim stSeqRest As String, stSeqLn As String, stSeqP As Integer, stSeqMus As String, stSeqDocks As Integer, stSeqBad As Integer
stSeqRest = _EMBEDDED$("SEQTXT")
Do While Len(stSeqRest) > 0
    stSeqP = InStr(stSeqRest, Chr$(10))
    If stSeqP > 0 Then stSeqLn = Left$(stSeqRest, stSeqP - 1) : stSeqRest = Mid$(stSeqRest, stSeqP + 1) Else stSeqLn = stSeqRest : stSeqRest = ""
    stSeqLn = LTrim$(RTrim$(stSeqLn))
    If Len(stSeqLn) > 0 And Right$(stSeqLn, 1) = Chr$(13) Then stSeqLn = RTrim$(Left$(stSeqLn, Len(stSeqLn) - 1))
    If UCase$(stSeqLn) = "DOCK" Or UCase$(Left$(stSeqLn, 5)) = "DOCK " Then
        stSeqDocks = stSeqDocks + 1
        stSeqP = InStr(stSeqLn, "mus=")
        stSeqMus = ""
        If stSeqP > 0 Then
            stSeqMus = Mid$(stSeqLn, stSeqP + 4)
            If InStr(stSeqMus, " ") > 0 Then stSeqMus = Left$(stSeqMus, InStr(stSeqMus, " ") - 1)
        End If
        If Len(stSeqMus) = 0 Or ST_CueIdx%(stSeqMus) < 0 Then
            stSeqBad = stSeqBad + 1 : Print "      DOCK step with missing/unknown cue: " + stSeqLn
        End If
    End If
Loop
ST_Assert stSeqDocks > 0, "sequence.txt has DOCK steps (" + LTrim$(Str$(stSeqDocks)) + ")"
ST_Assert stSeqBad = 0, "every DOCK step sets mus= to a cue in music.mus"

' loudness: the dock sits about where the planet cue does, under the dock's UI beeps
Dim stDockPk As Single, stPlnPk As Single, stDockRms As Single, stPlnRms As Single
stDockRms = ST_CueRms!("dock", 12, stDockPk)
stPlnRms = ST_CueRms!("planet", 12, stPlnPk)
Print "      dock   peak" + Str$(stDockPk) + "  rms" + Str$(stDockRms)
Print "      planet peak" + Str$(stPlnPk) + "  rms" + Str$(stPlnRms)
ST_Assert stDockRms > stPlnRms * 0.5 And stDockRms < stPlnRms * 1.5, "dock RMS within 0.5x-1.5x of planet's"
ST_Assert stDockPk < 1.0, "dock peak stays under full scale before volMusic"

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
