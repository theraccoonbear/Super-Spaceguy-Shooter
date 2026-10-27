' spk_timing_test.bas — narration speed presets and crawl-pacing duration math
'
' Runs the real speech.bas against the real crawl text (gametext.txt + gamevalues.ini):
'   - SPK_QueueSamples& (used to pace the crawl) equals the samples SPK_Advance emits
'   - each preset's words/min over all crawl blocks lands in its target band
'   - presets are ordered, and FAST keeps stops long enough to hear
'
' Build: ./tools/buildqb tests/spk_timing_test.bas
' Run:   ./tests/spk_timing_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

Const SAMPLE_RATE = 44100

$EMBED:'assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'assets/gametext.txt':'GAMETEXT'
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'

Sub DBG_Print(stDbgMsg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/sys/gametext.bas'

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

' Block text with ~X color codes removed (the crawl speaks it the same way).
Function ST_Plain$(stpS As String)
    Dim stpR As String, stpI As Integer, stpH As Integer
    stpI = 1
    Do While stpI <= Len(stpS)
        If Mid$(stpS, stpI, 1) = "~" And stpI < Len(stpS) Then
            stpH = Asc(UCase$(Mid$(stpS, stpI + 1, 1)))
            If (stpH >= 48 And stpH <= 57) Or (stpH >= 65 And stpH <= 70) Then
                stpI = stpI + 2
                _Continue
            End If
        End If
        stpR = stpR + Mid$(stpS, stpI, 1)
        stpI = stpI + 1
    Loop
    ST_Plain$ = stpR
End Function

Dim Shared stTotWords As Long, stTotSamples As Double, stTallyLevel As Integer

' Speaks every blank-line-separated paragraph of a block (queue only) and tallies words/samples.
Sub ST_TallyBlock(sttKey As String)
    Dim sttB As String, sttPos As Long, sttNxt As Long, sttLn As String, sttPara As String
    sttB = ST_Plain$(GTEXT_Get$(sttKey)) + Chr$(10) + Chr$(10)
    sttPos = 1
    Do While sttPos <= Len(sttB)
        sttNxt = InStr(sttPos, sttB, Chr$(10))
        If sttNxt = 0 Then sttNxt = Len(sttB) + 1
        sttLn = LTrim$(RTrim$(Mid$(sttB, sttPos, sttNxt - sttPos)))
        sttPos = sttNxt + 1
        If Len(sttLn) > 0 Then
            sttPara = sttPara + sttLn + " "
        ElseIf Len(sttPara) > 0 Then
            SPK_Say sttPara
            If stTallyLevel > 0 Then SPK_SetPreset stTallyLevel
            stTotWords = stTotWords + spkWordCount
            stTotSamples = stTotSamples + SPK_QueueSamples&
            sttPara = ""
        End If
    Loop
End Sub

Function ST_PresetWPM! (stwLevel As Integer)
    Dim stwKeys As String, stwK As String, stwP As Integer
    stTallyLevel = stwLevel
    stTotWords = 0 : stTotSamples = 0
    stwKeys = "intro stage1 stage2 stage3 stage4 stage5 stage6 outro death_final "
    Do While Len(stwKeys) > 0
        stwP = InStr(stwKeys, " ")
        stwK = Left$(stwKeys, stwP - 1) : stwKeys = Mid$(stwKeys, stwP + 1)
        ST_TallyBlock stwK
    Loop
    ST_PresetWPM! = stTotWords / (stTotSamples / SAMPLE_RATE / 60)
End Function

Print "=== spk_timing_test ==="
Print ""

SPK_Init
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")
ST_Assert Len(GTEXT_Get$("stage1")) > 0, "gametext loaded (stage1 present)"

Print "--- SPK_QueueSamples& matches synthesized length ---"
Dim stLvl As Integer, stQ As Long, stN As Long
For stLvl = 1 To 3
    SPK_Say ST_Plain$(GTEXT_Get$("death_final"))
    SPK_SetPreset stLvl
    stQ = SPK_QueueSamples&
    stN = 0
    Do While SPK_IsPlaying%
        SPK_Advance
        stN = stN + 1
    Loop
    ST_Assert stQ = stN, "preset" + Str$(stLvl) + ": queue estimate" + Str$(stQ) + " = synthesized" + Str$(stN)
Next stLvl

Print "--- preset words/min over all crawl text ---"
Dim stSlow As Single, stNorm As Single, stFast As Single, stNat As Single
stTallyLevel = -1 ' natural: SPK_Say leaves speed at 1.0
stTotWords = 0 : stTotSamples = 0
ST_TallyBlock "intro" : ST_TallyBlock "stage1" : ST_TallyBlock "stage2" : ST_TallyBlock "stage3"
ST_TallyBlock "stage4" : ST_TallyBlock "stage5" : ST_TallyBlock "stage6" : ST_TallyBlock "outro" : ST_TallyBlock "death_final"
stNat = stTotWords / (stTotSamples / SAMPLE_RATE / 60)
stSlow = ST_PresetWPM!(1)
stNorm = ST_PresetWPM!(2)
stFast = ST_PresetWPM!(3)
Print "      natural (k=1.0):" + Str$(Int(stNat)) + " wpm"
Print "      SLOW:" + Str$(Int(stSlow)) + "  NORMAL:" + Str$(Int(stNorm)) + "  FAST:" + Str$(Int(stFast)) + " wpm"
ST_Assert stSlow < stNorm And stNorm < stFast, "presets ordered SLOW < NORMAL < FAST"
ST_Assert stSlow >= 110 And stSlow <= 130, "SLOW in 110-130 wpm"
ST_Assert stNorm >= 130 And stNorm <= 150, "NORMAL in 130-150 wpm"
ST_Assert stFast >= 152 And stFast <= 175, "FAST in 152-175 wpm"

Print "--- non-narration speech stays at natural speed ---"
SPK_SetPreset 3
SPK_Say GTEXT_Get$("speech_title")
ST_Assert SPK_PhoneDur&(SPK_AA, 1) = spkDur(SPK_AA, 1), "SPK_Say resets to natural speed (title / callouts unaffected by preset)"

Print "--- articulation floor ---"
SPK_SetPreset 3
ST_Assert SPK_PhoneDur&(SPK_T, 0) >= SAMPLE_RATE * 0.055, "FAST: unvoiced stop >= 55 ms"
ST_Assert SPK_PhoneDur&(SPK_S, 0) >= SAMPLE_RATE * 0.09, "FAST: unvoiced fricative >= 90 ms"
ST_Assert SPK_PhoneDur&(SPK_SIL, 0) < SPK_PhoneDur&(SPK_T, 0), "FAST: pauses compress below stops"
SPK_SetPreset 2 : stQ = SPK_PhoneDur&(SPK_AA, 1)
SPK_SetPreset 0
ST_Assert SPK_PhoneDur&(SPK_AA, 1) = stQ, "invalid preset falls back to NORMAL"

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
