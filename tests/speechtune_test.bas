' speechtune_test.bas -- the voice-tuning tool's logic (src/audio/speechrender.bas, speechcfg.bas; #236)
'
' Renders lines offline with the game's speech.bas: a render is repeatable, a nudged knob or a switched
' feature changes it, and it leaves the settings alone. The playhead maps to the word under it, a
' re-render keeps the playhead time (clamped), scrub and loop arithmetic clamp and wrap, and
' speech.ini saves and loads back to the same knobs and switches with its comments intact.
'
' Build: ./tools/buildqb tests/speechtune_test.bas
' Run:   ./builds/speechtune_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
'$INCLUDE:'../src/sys/failfast.bi'

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/audiorate.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'

$EMBED:'assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'assets/gametext.txt':'GAMETEXT'
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'
$EMBED:'assets/config/speech.ini':'CFGSPEECH'

Sub DBG_Print (stDbgMsg As String) : End Sub

'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/audio/speechcfg.bas'
'$INCLUDE:'../src/sys/gametext.bas'
'$INCLUDE:'../src/2d/crawllayout.bas'
'$INCLUDE:'../src/audio/speechrender.bas'

Dim Shared stPassed As Integer, stFailed As Integer

Sub ST_Assert (saCond As Integer, saName As String)
    If saCond Then
        Print "PASS  " + saName
        stPassed = stPassed + 1
    Else
        Print "FAIL  " + saName
        stFailed = stFailed + 1
    End If
End Sub

Function ST_Hash# ()
    Dim shI As Long, shH As Double
    For shI = 0 To tnLen - 1
        shH = shH + tnBuf(shI) * ((shI Mod 1009) + 1)
    Next shI
    ST_Hash# = shH
End Function

Function ST_Peak! ()
    Dim spI As Long, spM As Single
    For spI = 0 To tnLen - 1
        If Abs(tnBuf(spI)) > spM Then spM = Abs(tnBuf(spI))
    Next spI
    ST_Peak! = spM
End Function

' Lines of s that are not "key=value": the comments and blanks, in order
Function ST_Frame$ (sfS As String)
    Dim sfP As Long, sfQ As Long, sfL As String, sfOut As String
    sfP = 1
    Do While sfP <= Len(sfS)
        sfQ = InStr(sfP, sfS, Chr$(10))
        If sfQ = 0 Then sfQ = Len(sfS) + 1
        sfL = Mid$(sfS, sfP, sfQ - sfP)
        sfP = sfQ + 1
        If Left$(LTrim$(sfL), 1) = ";" Or InStr(sfL, "=") = 0 Then sfOut = sfOut + sfL + Chr$(10)
    Loop
    ST_Frame$ = sfOut
End Function

Function ST_Count& (scS As String, scNeedle As String)
    Dim scP As Long, scN As Long
    scP = InStr(scS, scNeedle)
    Do While scP > 0
        scN = scN + 1
        scP = InStr(scP + Len(scNeedle), scS, scNeedle)
    Loop
    ST_Count& = scN
End Function

Const ST_LINE = "SHIELDS FAILING. LINK UNSTABLE."

Print "=== speechtune_test ==="
Print ""

SPK_Init
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")
Dim stI As Integer, stH1 As Double, stH2 As Double, stLen1 As Long, stOk As Integer, stS As Single, stN As Long
Dim stFx(0 To SPK_FX_N - 1) As Integer, stPk(0 To SPK_PK_N - 1) As Single
Dim stSrc As String, stOut As String, stBad As String

Print "--- render ---"
TUNE_NewLine ST_LINE, 2
stH1 = ST_Hash# : stLen1 = tnLen
ST_Assert tnLen > 20000 And ST_Peak! > 0.05, "a line renders to audible samples (" + LTrim$(Str$(tnLen)) + ")"
ST_Assert tnLen = SPK_QueueSamples&, "the buffer holds exactly the queued line's samples"
TUNE_NewLine ST_LINE, 2
ST_Assert ST_Hash# = stH1 And tnLen = stLen1, "rendering the same line twice with the same settings gives identical buffers"
TUNE_NewLine "GAME OVER", 2
TUNE_NewLine ST_LINE, 2
ST_Assert ST_Hash# = stH1, "another line in between does not change a later render"

SPK_PkSet SPK_PK_FALL, 7
TUNE_Render ST_LINE, 2
ST_Assert ST_Hash# <> stH1, "a nudged knob (final fall) changes the buffer"
ST_Assert tnLen = stLen1, "and no knob changes the length"
SPK_PkSet SPK_PK_FALL, spkPkDef(SPK_PK_FALL)
TUNE_Render ST_LINE, 2
ST_Assert ST_Hash# = stH1, "putting the knob back gives the first buffer again"

spkFx(SPK_FX_GL) = 0
TUNE_Render ST_LINE, 2
ST_Assert ST_Hash# <> stH1, "switching a clarity feature off changes the buffer"
spkFx(SPK_FX_GL) = -1
TUNE_Render ST_LINE, 1
ST_Assert tnLen > stLen1, "the Slow preset renders a longer buffer"

For stI = 0 To SPK_PK_N - 1 : stPk(stI) = spkPk(stI) : Next stI
For stI = 0 To SPK_FX_N - 1 : stFx(stI) = spkFx(stI) : Next stI
spkHold = -1 : spkTimeScale = 5
TUNE_Render ST_LINE, 2
stOk = -1
For stI = 0 To SPK_PK_N - 1 : If stPk(stI) <> spkPk(stI) Then stOk = 0
Next stI
For stI = 0 To SPK_FX_N - 1 : If stFx(stI) <> spkFx(stI) Then stOk = 0
Next stI
ST_Assert stOk, "a render leaves every knob and clarity switch as it was"
ST_Assert spkHold = 0 And spkTimeScale = 1, "a render runs the synth un-held at normal speed (it sets spkHold 0, spkTimeScale 1)"
ST_Assert ST_Hash# = stH1, "a held game state (spkHold, fast-forward) does not leak into a render"

Print ""
Print "--- playhead and words ---"
TUNE_NewLine ST_LINE, 2
ST_Assert tnWordN = 4, "four words (" + LTrim$(Str$(tnWordN)) + ")"
stOk = tnWordAt(0) >= 0
For stI = 0 To tnWordN - 1
    If tnWordAt(stI) >= tnWordEnd(stI) Or tnWordEnd(stI) > tnLen Then stOk = 0
    If stI > 0 Then If tnWordAt(stI) < tnWordEnd(stI - 1) Then stOk = 0
Next stI
ST_Assert stOk, "word offsets are monotonic, do not overlap and stay inside the buffer"
stOk = -1
For stI = 0 To tnWordN - 1
    If TUNE_WordAt%(tnWordAt(stI)) <> stI Or TUNE_WordAt%(tnWordEnd(stI) - 1) <> stI Then stOk = 0
    If TUNE_WordAt%((tnWordAt(stI) + tnWordEnd(stI)) \ 2) <> stI Then stOk = 0
Next stI
ST_Assert stOk, "the word at the first, middle and last sample of each word is that word"
ST_Assert tnWordTxt(0) = "SHIELDS" And tnWordTxt(3) = "UNSTABLE", "the words are the spoken words, in order"
ST_Assert TUNE_WordAt%(tnWordEnd(1)) = -1, "the pause after a sentence belongs to no word"
ST_Assert TUNE_WordAt%(tnLen + 1000) = -1, "past the end there is no word"
ST_Assert tnWordEnd(3) <= tnLen And tnWordEnd(3) > tnLen \ 2, "the last word ends inside the buffer, in its second half"

stN = tnWordAt(2) + 50
tnPos = stN
SPK_PkSet SPK_PK_FALL, 6
TUNE_RenderKeep ST_LINE, 2
ST_Assert tnPos = stN And TUNE_WordAt%(tnPos) = 2, "a re-render keeps the playhead time: the same word is under it"
ST_Assert tnLen = stLen1, "and the new buffer is as long as before"
SPK_PkSet SPK_PK_FALL, spkPkDef(SPK_PK_FALL)

TUNE_NewLine GTEXT_Get$("speech_boss_phase3"), 2
tnPos = tnLen - 100 : tnLooping = -1 : tnLoopA = 5000
TUNE_RenderKeep "GAME OVER", 2
ST_Assert tnPos = tnLen - 100 Or tnPos = tnLen, "a shorter line clamps the playhead into the new buffer"
tnPos = tnLen - 10
TUNE_RenderKeep "ZERO ONE TWO THREE FOUR FIVE", 2
tnPos = tnLen
TUNE_RenderKeep "GAME OVER", 2
ST_Assert tnPos = tnLen, "a playhead at the end of a longer line sits at the end of the shorter one"
ST_Assert tnLoopB = tnLen And tnLoopA <= tnLoopB, "the loop region follows the new length"

Print ""
Print "--- scrub and loop ---"
TUNE_NewLine ST_LINE, 2
tnPos = 1000
TUNE_Scrub -1
ST_Assert tnPos = 0, "scrubbing back before the start stops at 0"
tnPos = 2 * SAMPLE_RATE
TUNE_Scrub -1
ST_Assert tnPos = SAMPLE_RATE, "back 1.0 s moves one second of samples"
TUNE_Scrub 0.25
ST_Assert tnPos = SAMPLE_RATE + SAMPLE_RATE \ 4, "forward 0.25 s moves a quarter second"
TUNE_Scrub 600
ST_Assert tnPos = tnLen, "scrubbing past the end stops at the end"
TUNE_Scrub -0.25
ST_Assert tnPos = tnLen - SAMPLE_RATE \ 4, "scrubbing back from the end works"

tnLoopA = 100 : tnLoopB = 200 : tnLooping = -1 : tnPlaying = -1 : tnPos = 198
stS = TUNE_Next!
ST_Assert stS = tnBuf(198) And tnPos = 199, "playback hands out the sample at the playhead and moves on"
stS = TUNE_Next!
ST_Assert stS = tnBuf(199) And tnPos = 100, "looping wraps from the loop end back to its start"
tnPos = 450
stS = TUNE_Next!
ST_Assert stS = tnBuf(100) And tnPos = 101, "a playhead past the loop end jumps into the loop"
tnLooping = 0 : tnPos = 199
stS = TUNE_Next! : stS = TUNE_Next!
ST_Assert tnPos = 201, "with looping off it plays on past the loop end"
tnPos = tnLen - 1
stS = TUNE_Next!
ST_Assert tnPlaying <> 0 And tnPos = tnLen, "the last sample plays"
stS = TUNE_Next!
ST_Assert tnPlaying = 0 And stS = 0 And tnPos = tnLen, "at the end playback stops and is silent"
stS = TUNE_Next!
ST_Assert stS = 0 And tnPos = tnLen, "a stopped player stays silent"

tnLoopA = 600 : tnLoopB = tnLen : tnPos = 500
TUNE_SetLoopEnd
ST_Assert tnLoopB = 500 And tnLoopA = 0, "] before the loop start moves the start to 0"
tnPos = 700
TUNE_SetLoopStart
ST_Assert tnLoopA = 700 And tnLoopB = tnLen, "[ past the loop end runs the loop to the end of the line"
tnPos = 900
TUNE_SetLoopEnd
ST_Assert tnLoopA = 700 And tnLoopB = 900, "[ then ] mark a region"

Print ""
Print "--- lines ---"
TUNE_LoadLines
ST_Assert tnLineN > 20, "the game's spoken paragraphs load (" + LTrim$(Str$(tnLineN)) + ")"
stOk = -1 : stBad = ""
For stI = 0 To tnLineN - 1
    If InStr(tnLineTxt(stI), "~") > 0 Or Left$(tnLineKey(stI), 7) = "palette" Or tnLineTxt(stI) <> LTrim$(RTrim$(tnLineTxt(stI))) Then stOk = 0 : stBad = tnLineKey(stI)
Next stI
ST_Assert stOk, "no colour codes, no palette chart, trimmed (" + stBad + ")"
ST_Assert tnLineKey(0) = "intro 1", "the first line is the first paragraph of the first block"
stOk = 0
For stI = 0 To tnLineN - 1
    If tnLineKey(stI) = "speech_boss_phase2 1" Then stOk = (tnLineTxt(stI) = ST_LINE)
Next stI
ST_Assert stOk, "a one-line block (speech_boss_phase2) is one line, as the game says it"

Print ""
Print "--- speech.ini save and load ---"
stSrc = _EMBEDDED$("CFGSPEECH")
SPK_PkSet SPK_PK_STEP, 0.5 : SPK_PkSet SPK_PK_DECL, 0.35 : SPK_PkSet SPK_PK_ACC, 2.5
SPK_PkSet SPK_PK_NACC, 2 : SPK_PkSet SPK_PK_FALL, 5.5 : SPK_PkSet SPK_PK_RISE, 3.5
SPK_PkSet SPK_PK_SPREAD, 0.4 : SPK_PkSet SPK_PK_GPITCH, 1 : SPK_PkSet SPK_PK_LIQ, 2.25
SPK_PkSet SPK_PK_LOUD, 4.5
spkFx(SPK_FX_GL) = 0 : spkFx(SPK_FX_HB) = 0 : spkFx(SPK_FX_IN) = 0
For stI = 0 To SPK_PK_N - 1 : stPk(stI) = spkPk(stI) : Next stI
For stI = 0 To SPK_FX_N - 1 : stFx(stI) = spkFx(stI) : Next stI
stOut = SPK_ProsodySave$(stSrc)
For stI = 0 To SPK_PK_N - 1 : SPK_PkSet stI, spkPkDef(stI) : Next stI
For stI = 0 To SPK_FX_N - 1 : spkFx(stI) = -1 : Next stI
ST_Assert SPK_ProsodyLoad%(stOut), "the saved text loads (" + spkCfgErr + ")"
stOk = -1
For stI = 0 To SPK_PK_N - 1
    If Abs(spkPk(stI) - stPk(stI)) > 0.0001 Then stOk = 0 : Print "  knob " + spkPkKey(stI) + ":" + Str$(spkPk(stI)) + " <>" + Str$(stPk(stI))
Next stI
ST_Assert stOk, "save then load reproduces every knob"
stOk = -1
For stI = 0 To SPK_FX_N - 1
    If spkFx(stI) <> stFx(stI) Then stOk = 0 : Print "  feature " + SPK_FxKey$(stI)
Next stI
ST_Assert stOk, "save then load reproduces every clarity switch"
ST_Assert ST_Frame$(stOut) = ST_Frame$(stSrc), "comments and layout survive the save, line for line"
ST_Assert SPK_ProsodySave$(stOut) = stOut, "saving twice changes nothing more"
ST_Assert ST_Count&(stOut, "step_semitones=") = 1 And ST_Count&(stOut, "feature_glides=") = 1, "each key is written once, in place"
ST_Assert Left$(stOut, 30) = Left$(stSrc, 30), "the file still starts with its own header"

stOut = SPK_ProsodySave$("; only a comment" + Chr$(10))
ST_Assert Left$(stOut, 16) = "; only a comment" And ST_Count&(stOut, "=") = SPK_PK_N + SPK_FX_N, "keys missing from the file are appended"
ST_Assert SPK_ProsodyLoad%(stOut), "and the result loads"
stOut = SPK_ProsodySave$("final_fall_semitones=1" + Chr$(13) + Chr$(10) + "; note" + Chr$(13) + Chr$(10))
stBad = "final_fall_semitones=" + SPK_Num$(spkPk(SPK_PK_FALL)) + Chr$(13)
ST_Assert Left$(stOut, Len(stBad)) = stBad And InStr(stOut, "; note" + Chr$(13)) > 0, "CRLF line ends are kept"
ST_Assert SPK_ProsodyLoad%("feature_glides=2") = 0, "a feature value other than 0 or 1 is refused"
ST_Assert InStr(spkCfgErr, "feature_glides") > 0, "and the error names the key"

' rows with no effect
For stI = 0 To SPK_FX_N - 1 : spkFx(stI) = -1 : Next stI
SPK_PkSet SPK_PK_NACC, 1
stOk = -1
For stI = 0 To SPK_PK_N - 1
    If Len(SPK_PkInactive$(stI)) > 0 Then stOk = 0 : Print "  inactive: " + spkPkKey(stI)
Next stI
ST_Assert stOk, "with every switch on and one accent per phrase no knob is inactive"
spkFx(SPK_FX_IN) = 0
stOk = -1
For stI = 0 To SPK_PK_N - 1
    If stI <> SPK_PK_GPITCH And stI <> SPK_PK_LIQ Then
        If SPK_PkInactive$(stI) <> "no effect: needs Intonation on" Then stOk = 0 : Print "  active: " + spkPkKey(stI)
    End If
Next stI
ST_Assert stOk, "with Intonation off the eight intonation knobs are inactive, with the reason"
ST_Assert SPK_PkInactive$(SPK_PK_GPITCH) = "" And SPK_PkInactive$(SPK_PK_LIQ) = "", "Intonation off leaves Glide pitch and Liquid glide length in play"
spkFx(SPK_FX_IN) = -1
spkFx(SPK_FX_GL) = 0
ST_Assert SPK_PkInactive$(SPK_PK_GPITCH) = "no effect: needs Glides on", "Glide pitch is inactive with Glides off"
ST_Assert SPK_PkInactive$(SPK_PK_LIQ) = "no effect: needs Glides on", "Liquid glide length is inactive with Glides off"
ST_Assert SPK_PkInactive$(SPK_PK_FALL) = "", "Glides off leaves the intonation knobs in play"
spkFx(SPK_FX_NL) = 0
ST_Assert SPK_PkInactive$(SPK_PK_LIQ) = "no effect: needs Glides and Nasals and liquids on", "Liquid glide length names both missing switches"
spkFx(SPK_FX_GL) = -1
ST_Assert SPK_PkInactive$(SPK_PK_LIQ) = "no effect: needs Nasals and liquids on", "Liquid glide length is inactive with Nasals and liquids off"
ST_Assert SPK_PkInactive$(SPK_PK_GPITCH) = "", "Glide pitch is in play with Glides on, whatever Nasals and liquids are"
spkFx(SPK_FX_NL) = -1
ST_Assert SPK_PkInactive$(SPK_PK_LIQ) = "", "Liquid glide length is in play with Glides and Nasals and liquids on"
SPK_PkSet SPK_PK_NACC, 0
ST_Assert SPK_PkInactive$(SPK_PK_ACC) = "no effect: Accents per phrase is 0", "Accent size is inactive with no accents per phrase"
ST_Assert SPK_PkInactive$(SPK_PK_NACC) = "" And SPK_PkInactive$(SPK_PK_FALL) = "", "Accents per phrase 0 leaves the other intonation knobs in play"
spkFx(SPK_FX_IN) = 0
ST_Assert SPK_PkInactive$(SPK_PK_ACC) = "no effect: needs Intonation on", "Intonation off is the reason given first for Accent size"
SPK_PkSet SPK_PK_SPREAD, 0
spkFx(SPK_FX_IN) = -1
SPK_PkSet SPK_PK_NACC, 1
ST_Assert SPK_PkInactive$(SPK_PK_GPITCH) = "", "stress spread 0 does not dim Glide pitch"
spkFx(SPK_FX_GL) = -1

Print ""
Print "Passed:"; stPassed; " Failed:"; stFailed
If stFailed > 0 Then System 1
System 0
