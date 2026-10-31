' narr_drain_test.bas — crawl narration follows game frames, not the audio device (#329)
'
' Plays real crawls frame by frame (CRAWL_Step%, then the audio fill's synthesis, then
' SPK_Tick, in the main loop's order) while the audio fill synthesises a different
' amount of speech per frame:
'   - starved: nothing (the device isn't draining, so the buffer stays full)
'   - normal:  735 samples (44100 / 60, a device keeping pace with 60 fps)
'   - flooded: 4410 samples (the device drained the whole 0.1 s buffer every frame)
'   - jitter:  0 / 1470 / 300 / 2000 / 735 in turn
' and checks every mode starts each paragraph on the same frame, and highlights the same
' word (and occurrence) on every frame, as the normal run. One crawl run includes a
' fast-forward stretch.
'
' Build: ./tools/buildqb tests/narr_drain_test.bas
' Run:   ./tests/narr_drain_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

Const SAMPLE_RATE = 44100

$EMBED:'assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'assets/gametext.txt':'GAMETEXT'
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'

Sub DBG_Print(ndDbgMsg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/sys/gametext.bas'
'$INCLUDE:'../src/2d/crawllayout.bas'

Const ND_START_Y = 240 ' scrH, as CRAWL_Prep passes
Const ND_TRIG_Y = 218 ' scrH - CRAWL_LINE_H
Const ND_LEVEL = 2 ' NORMAL
Const ND_MAX_FRAMES = 12000
Const ND_MODES = 4

Dim Shared stPassed As Integer, stFailed As Integer
Dim Shared ndRefSaid$(0 To ND_MAX_FRAMES), ndRefWord$(0 To ND_MAX_FRAMES), ndRefN As Long
Dim Shared ndSaid$(0 To ND_MAX_FRAMES), ndWord$(0 To ND_MAX_FRAMES), ndN As Long

Sub ST_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        stPassed = stPassed + 1
    Else
        Print "FAIL  " + testName
        stFailed = stFailed + 1
    End If
End Sub

' Samples the audio fill synthesises on frame ndsF in drain mode ndsMode.
Function ND_FillSamples& (ndsMode As Integer, ndsF As Long)
    Select Case ndsMode
        Case 0 : ND_FillSamples& = 735
        Case 1 : ND_FillSamples& = 0
        Case 2 : ND_FillSamples& = 4410
        Case Else
            Select Case ndsF Mod 5
                Case 0 : ND_FillSamples& = 0
                Case 1 : ND_FillSamples& = 1470
                Case 2 : ND_FillSamples& = 300
                Case 3 : ND_FillSamples& = 2000
                Case Else : ND_FillSamples& = 735
            End Select
    End Select
End Function

Function ND_ModeName$ (ndmMode As Integer)
    Select Case ndmMode
        Case 0 : ND_ModeName$ = "normal"
        Case 1 : ND_ModeName$ = "starved"
        Case 2 : ND_ModeName$ = "flooded"
        Case Else : ND_ModeName$ = "jitter"
    End Select
End Function

' Plays crawl ndpKey to its exit in drain mode ndpMode, recording per frame the
' paragraphs started ("" if none) and the highlighted word into ndSaid$ / ndWord$.
' ndpFFAt > 0 holds fast-forward for ndpFFLen frames from that frame on.
Sub ND_Play (ndpKey As String, ndpMode As Integer, ndpFFAt As Long, ndpFFLen As Long)
    Dim ndpSeen As Integer, ndpEvt As Integer, ndpS As Long, ndpK As Long
    SPK_Say ""
    CRAWL_Start GTEXT_Get$(ndpKey), ND_LEVEL, ND_START_Y, ND_TRIG_Y
    ndN = 0 : ndpSeen = 0
    Do Until crawlScroll + crawlLineCount * CRAWL_LINE_H < -20 Or ndN >= ND_MAX_FRAMES
        ndpEvt = CRAWL_Step%(ndpFFAt > 0 And ndN >= ndpFFAt And ndN < ndpFFAt + ndpFFLen, ND_LEVEL)
        ndSaid$(ndN) = ""
        Do While ndpSeen < crawlSaidCount
            ndSaid$(ndN) = ndSaid$(ndN) + Str$(ndpSeen)
            ndpSeen = ndpSeen + 1
        Loop
        ndWord$(ndN) = SPK_CurWord$ + "#" + LTrim$(Str$(SPK_CurWordOcc%)) + "@" + LTrim$(Str$(crawlParaIdx))
        ndpK = ND_FillSamples&(ndpMode, ndN)
        For ndpS = 1 To ndpK : SPK_Advance : Next ndpS
        SPK_Tick
        ndN = ndN + 1
    Loop
End Sub

Sub ND_Check (ndcKey As String, ndcMode As Integer, ndcFFAt As Long, ndcFFLen As Long)
    Dim ndcI As Long, ndcBadSaid As Long, ndcBadWord As Long, ndcFirst As Long, ndcName As String
    ND_Play ndcKey, ndcMode, ndcFFAt, ndcFFLen
    ndcName = ndcKey + " " + ND_ModeName$(ndcMode)
    If ndcFFAt > 0 Then ndcName = ndcName + " (fast-forward frames" + Str$(ndcFFAt) + " -" + Str$(ndcFFAt + ndcFFLen) + ")"
    ndcFirst = -1
    For ndcI = 0 To ndN - 1
        If ndcI < ndRefN Then
            If ndSaid$(ndcI) <> ndRefSaid$(ndcI) Then ndcBadSaid = ndcBadSaid + 1 : If ndcFirst < 0 Then ndcFirst = ndcI
            If ndWord$(ndcI) <> ndRefWord$(ndcI) Then ndcBadWord = ndcBadWord + 1 : If ndcFirst < 0 Then ndcFirst = ndcI
        End If
    Next ndcI
    ST_Assert ndN = ndRefN, ndcName + ": same length (" + LTrim$(Str$(ndN)) + " frames)"
    ST_Assert ndcBadSaid = 0, ndcName + ": every paragraph starts on the same frame" + Mid$(" (first miss at frame" + Str$(ndcFirst) + ")", 1, 40 * -(ndcBadSaid > 0))
    ST_Assert ndcBadWord = 0, ndcName + ": same word highlighted every frame" + Mid$(" (first miss at frame" + Str$(ndcFirst) + ")", 1, 40 * -(ndcBadWord > 0))
End Sub

' The normal-drain run of ndrKey as the reference.
Sub ND_Reference (ndrKey As String, ndrFFAt As Long, ndrFFLen As Long)
    Dim ndrI As Long
    ND_Play ndrKey, 0, ndrFFAt, ndrFFLen
    ndRefN = ndN
    For ndrI = 0 To ndN - 1
        ndRefSaid$(ndrI) = ndSaid$(ndrI) : ndRefWord$(ndrI) = ndWord$(ndrI)
    Next ndrI
    ST_Assert ndN < ND_MAX_FRAMES, ndrKey + ": the crawl reaches its exit"
    ST_Assert crawlSaidCount = crawlParaCount And crawlParaCount > 0, ndrKey + ": every paragraph spoken (" + LTrim$(Str$(crawlParaCount)) + ")"
End Sub

Print "=== narr_drain_test ==="
Print ""

SPK_Init
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")

Dim ndKeys$(0 To 1), ndC As Integer, ndM As Integer, ndFFAt As Long
ndKeys$(0) = "intro" : ndKeys$(1) = "stage3"
For ndC = 0 To 1
    Print "--- " + ndKeys$(ndC) + " ---"
    ND_Reference ndKeys$(ndC), 0, 0
    For ndM = 1 To ND_MODES - 1
        ND_Check ndKeys$(ndC), ndM, 0, 0
    Next ndM
    ndFFAt = ndRefN \ 3
    ND_Reference ndKeys$(ndC), ndFFAt, 90
    For ndM = 1 To ND_MODES - 1
        ND_Check ndKeys$(ndC), ndM, ndFFAt, 90
    Next ndM
    Print ""
Next ndC

Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
