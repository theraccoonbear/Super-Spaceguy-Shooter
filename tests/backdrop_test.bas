' backdrop_test.bas -- the matte-painting effect list and its timing (#369)
'
' Drives src/2d/backdrop.bas with the real assets/backdrops.txt and plain frame numbers:
'   1. the shipped file parses and validates clean, with the title and dock effects
'   2. parse failures name their line: unknown verb, unknown or repeated key, bad numbers and
'      colours, positions off the painting, a missing at= or color=, effects before a header
'   3. validation: an unknown screen name, an empty backdrop, a backdrop listed twice
'   4. fixed tables: more effects or backdrops than the tables hold is an error, never a dropped line
'   5. BLINK timing: hard blink, phase, the rise/hold/fall/rest envelope, its period and eased fades
'   6. the hash: in range, spread out, repeatable, a function of its inputs only
'   7. SPARK: bursts on every= from phase=, fly and fall, fade out by life=, deterministic
'   8. the pool: a file that could overflow it is an error; a full pool drops and counts
'   9. screen entry: frame 0 on entry, a gap or another backdrop starts over, a repeat is ignored
'  10. no RNG stream is read, so nothing else in the game shifts
'
' Build: tools/dev test (builds and runs every test)
' Run:   builds/backdrop_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

$EMBED:'assets/backdrops.txt':'BACKDROPS'

'$INCLUDE:'../src/2d/backdrop.bas'

Dim Shared btPass As Integer, btFail As Integer

Sub BT_Assert (condition As Integer, label As String)
    If condition Then
        Print "PASS  " + label
        btPass = btPass + 1
    Else
        Print "FAIL  " + label
        btFail = btFail + 1
    End If
End Sub

Function BT_Count% (bcHay As String, bcNeedle As String)
    Dim bcP As Integer, bcN As Integer
    bcP = InStr(bcHay, bcNeedle)
    Do While bcP > 0
        bcN = bcN + 1
        bcP = InStr(bcP + Len(bcNeedle), bcHay, bcNeedle)
    Loop
    BT_Count% = bcN
End Function

Function BT_Nl$ ()
    BT_Nl$ = Chr$(10)
End Function

' 1 when parsing src fails with a message holding btWant on line btLine.
Function BT_Fails% (btSrc As String, btLine As Integer, btWant As String)
    Dim btOk As Integer, btRes As Integer
    btOk = BD_Parse%(btSrc)
    btRes = (btOk = 0 And InStr(bdErrors, "line " + LTrim$(Str$(btLine)) + ": ") > 0 And InStr(LCase$(bdErrors), LCase$(btWant)) > 0)
    BT_Fails% = btRes
    If btRes = 0 Then Print "      got: " + bdErrors + " (ok=" + Str$(btOk) + ")"
End Function

' A one-backdrop file with btBody on line 2.
Function BT_Src$ (btBody As String)
    BT_Src$ = "backdrop:title" + Chr$(10) + btBody + Chr$(10)
End Function

' Runs the first btFrames frames of backdrop btName and returns where every live spark is, as text.
Function BT_Trace$ (btName As String, btFrames As Long)
    Dim btF As Long, btI As Integer, btOut As String
    bdLastMain = -9
    For btF = 0 To btFrames
        BD_Advance 1000 + btF, btName
    Next btF
    For btI = 0 To BD_POOL - 1
        If bdPAlive(btI) Then btOut = btOut + Str$(Int(bdPX(btI) * 1000)) + "," + Str$(Int(bdPY(btI) * 1000)) + "," + Str$(bdPCol(btI)) + ";"
    Next btI
    BT_Trace$ = btOut
End Function

Dim btI As Integer, btN As Integer, btOk As Integer, btF As Long, btS As String, btT As String, btErr As String
Dim btSum As Double, btV As Single, btMin As Single, btMax As Single, btA As Long, btB As Long
Dim btU As String
Dim btRnd1 As Single, btRnd2 As Single, btFx As Integer, btBig As String

Print "=== backdrop_test ==="
Print ""

Print "--- 1. the shipped file ---"
btOk = BD_Parse%(_Embedded$("BACKDROPS"))
BT_Assert btOk <> 0 And Len(bdErrors) = 0,              "1.01  backdrops.txt parses clean"
If Len(bdErrors) > 0 Then Print bdErrors
btErr = BD_Validate$
BT_Assert Len(btErr) = 0,                               "1.02  it validates clean"
If Len(btErr) > 0 Then Print btErr
BT_Assert BD_Find%("title") >= 0,                       "1.03  the title has effects"
BT_Assert BD_Find%("dock") >= 0,                        "1.04  the dock has effects"
BT_Assert BD_Find%("nope") = -1,                        "1.05  a painting that is not listed has none"
BT_Assert bdFxN >= 4 And bdFxN <= BD_MAX_FX,            "1.06  a handful of effects (" + LTrim$(Str$(bdFxN)) + ")"
btN = 0
For btI = 0 To bdFxN - 1
    If bdKind(btI) = BD_KIND_BLINK Then btN = btN + 1
Next btI
BT_Assert btN >= 2 And btN < bdFxN,                     "1.07  both BLINK and SPARK are in use"
btOk = -1
For btI = 0 To bdFxN - 1
    If bdX(btI) < 0 Or bdX(btI) > 320 Or bdY(btI) < 0 Or bdY(btI) > 240 Then btOk = 0
Next btI
BT_Assert btOk,                                         "1.08  every effect sits on the painting"
' the dock's list panel covers x >= 104: nothing is placed under it
btOk = -1
btFx = BD_Find%("dock")
For btI = bdSetFrom(btFx) To bdSetFrom(btFx) + bdSetN(btFx) - 1
    If bdX(btI) >= 104 Then btOk = 0
Next btI
BT_Assert btOk,                                         "1.09  the dock's effects are clear of the list panel"
Print ""

Print "--- 2. parse failures name their line ---"
BT_Assert BT_Fails%(BT_Src$("    GLOW at=10,10 color=ff0000"), 2, "unknown effect 'GLOW'"), "2.01  unknown verb"
BT_Assert BT_Fails%(BT_Src$("    SPRITE at=10,10 color=ff0000"), 2, "unknown effect"), "2.02  SPRITE is not an effect yet"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 colour=ff0000"), 2, "unknown BLINK key 'colour'"), "2.03  unknown key"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000 hold=1 count=3"), 2, "unknown BLINK key 'count'"), "2.04  a SPARK key on a BLINK"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000 hold=5 hold=6"), 2, "given twice"), "2.05  a key given twice"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000 hold=1 on"), 2, "key=value"), "2.06  a word with no ="
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000 hold="), 2, "key=value"), "2.07  a key with no value"
BT_Assert BT_Fails%(BT_Src$("    BLINK color=ff0000"), 2, "needs at"), "2.08  no at="
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10"), 2, "needs color"), "2.09  no color="
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10 color=ff0000 hold=1"), 2, "at must be x,y"), "2.10  at= with one number"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,20,30 color=ff0000 hold=1"), 2, "at must be x,y"), "2.11  at= with three numbers (not yet)"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=a,b color=ff0000 hold=1"), 2, "at must be x,y"), "2.12  at= with words"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=321,10 color=ff0000 hold=1"), 2, "off the 320x240 painting"), "2.13  x off the painting"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,-1 color=ff0000 hold=1"), 2, "off the 320x240 painting"), "2.14  a negative y (negatives parse, then fail the range)"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff00 hold=1"), 2, "rrggbb"), "2.15  a short colour"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=gg0000"), 2, "rrggbb"), "2.16  a colour that is not hex"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000,00ff00 hold=1"), 2, "at most 1"), "2.17  two colours on a BLINK"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=10,10 color=ff0000,00ff00,0000ff,ffffff,ff00ff"), 2, "at most 4"), "2.18  five colours on a SPARK"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000 hold=601"), 2, "hold must be a whole number 0 to 600"), "2.19  hold=601"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000 rest=2.5"), 2, "rest must be a whole number"), "2.20  a fraction where a whole number goes"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000 hold=1 size=9"), 2, "size must be"), "2.21  size too big"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000 hold=1 mode=pulse"), 2, "unknown BLINK key 'mode'"), "2.22  mode= is gone"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000 hold=0 rest=0"), 2, "at least 1 frame"), "2.23  an envelope of no frames"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=10,10 color=ff0000 hold=1 phase=-3"), 2, "phase must be"), "2.24  a negative phase"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=10,10 color=ff0000 count=0"), 2, "count must be"), "2.25  no sparks"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=10,10 color=ff0000 gravity=2"), 2, "gravity must be a number -1 to 1"), "2.26  gravity out of range"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=10,10 color=ff0000 speed=fast"), 2, "speed must be"), "2.27  speed not a number"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=10,10 color=ff0000 life=0"), 2, "life must be"), "2.28  life 0"
BT_Assert BT_Fails%("    BLINK at=10,10 color=ff0000 hold=1" + Chr$(10), 1, "before any backdrop"), "2.29  an effect before a header"
BT_Assert BT_Fails%("backdrop:title" + Chr$(10) + "backdrop:dock extra" + Chr$(10), 2, "only its name"), "2.30  a header with a stray word"
BT_Assert BT_Fails%("scene:title" + Chr$(10), 1, "unknown header"), "2.31  a header of another kind"
BT_Assert BT_Fails%("backdrop:" + Chr$(10), 1, "needs a name"), "2.32  a header with no name"
BT_Assert BT_Fails%("backdrop:Ti-tle" + Chr$(10), 1, "lower-case"), "2.33  a bad name"
BT_Assert BT_Fails%("backdrop:title" + Chr$(10) + BT_Nl$ + "    BLINK at=10,10 color=ff0000 hold=x", 3, "hold must be"), "2.34  the line number counts blank lines"
BT_Assert bdSets = 0 And bdFxN = 0,                     "2.35  a broken file leaves the tables empty"
BT_Assert BD_Parse%(BT_Src$("    BLINK at=10,10 color=ff0000 hold=0 rest=0 phase=-1")) = 0 And BT_Count%(bdErrors, "line ") = 1, "2.36  one problem is reported once per line"
Print ""

Print "--- 3. what a good file may hold ---"
btOk = BD_Parse%("; a comment" + Chr$(13) + Chr$(10) + "backdrop:title ; trailing" + Chr$(13) + Chr$(10) + Chr$(9) + "blink AT=10.5,20 Color=#FF0000 SIZE=0 HOLD=1 ; x" + Chr$(13) + Chr$(10) + Chr$(13) + Chr$(10))
BT_Assert btOk <> 0,                                    "3.01  comments, CRLF, tabs, case, # colours and decimals parse"
If btOk = 0 Then Print bdErrors
BT_Assert bdFxN = 1 And bdKind(0) = BD_KIND_BLINK And bdX(0) = 10.5 And bdY(0) = 20 And bdSize(0) = 0, "3.02  and read as written"
BT_Assert _Red32(bdCol(0, 0)) = 255 And _Green32(bdCol(0, 0)) = 0 And _Blue32(bdCol(0, 0)) = 0,            "3.03  the colour"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=1" + Chr$(10))
BT_Assert bdRise(0) = 0 And bdHold(0) = 1 And bdFall(0) = 0 And bdRest(0) = 0 And bdSize(0) = 1 And bdPhase(0) = 0, "3.04  BLINK defaults: every envelope key is 0, glow 3, size 1"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    SPARK at=1,1 color=ff0000" + Chr$(10))
BT_Assert bdCount(0) = 3 And bdEvery(0) = 60 And bdLife(0) = 20 And bdDir(0) = 270 And Abs(bdGrav(0) - 0.05) < 0.0001 And Abs(bdSpeed(0) - 0.6) < 0.0001, "3.05  SPARK defaults"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    SPARK at=1,1 color=ff0000 gravity=-0.25" + Chr$(10))
BT_Assert btOk <> 0 And Abs(bdGrav(0) + 0.25) < 0.0001, "3.06  a negative decimal"
BT_Assert BD_ParseNum%("-.5", btV) <> 0 And Abs(btV + 0.5) < 0.0001 And BD_ParseNum%("1.2.3", btV) = 0 And BD_ParseNum%("-", btV) = 0 And BD_ParseNum%("1-", btV) = 0 And BD_ParseNum%("", btV) = 0, "3.07  number syntax"
btOk = BD_Parse%("backdrop:nowhere" + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=1" + Chr$(10))
btErr = BD_Validate$
BT_Assert btOk <> 0 And InStr(btErr, "line 1: backdrop 'nowhere' is not a painted screen") > 0, "3.08  validation: an unknown screen"
btOk = BD_Parse%("backdrop:dock" + Chr$(10))
btErr = BD_Validate$
BT_Assert InStr(btErr, "line 1: backdrop 'dock' has no effects") > 0, "3.09  validation: an empty backdrop"
BT_Assert BT_Fails%("backdrop:dock" + Chr$(10) + "backdrop:dock" + Chr$(10), 2, "listed twice"), "3.10  a backdrop listed twice"
Print ""

Print "--- 4. fixed tables ---"
btBig = "backdrop:title" + Chr$(10)
For btI = 1 To BD_MAX_FX
    btBig = btBig + "    BLINK at=1,1 color=ff0000 hold=1" + Chr$(10)
Next btI
btOk = BD_Parse%(btBig)
BT_Assert btOk <> 0 And bdFxN = BD_MAX_FX, "4.01  exactly BD_MAX_FX effects fit"
btBig = btBig + "    BLINK at=1,1 color=ff0000 hold=1" + Chr$(10) + "    BLINK at=1,1 color=ff0000" + Chr$(10)
BT_Assert BT_Fails%(btBig, BD_MAX_FX + 2, "more than BD_MAX_FX"), "4.02  one more is an error on its line"
BT_Assert BT_Count%(bdErrors, "BD_MAX_FX") = 1,         "4.03  reported once, not once per extra line"
btBig = ""
For btI = 1 To BD_MAX_SETS
    btBig = btBig + "backdrop:set" + LTrim$(Str$(btI)) + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=1" + Chr$(10)
Next btI
btOk = BD_Parse%(btBig)
BT_Assert btOk <> 0 And bdSets = BD_MAX_SETS, "4.04  exactly BD_MAX_SETS backdrops fit"
btBig = btBig + "backdrop:one_more" + Chr$(10)
BT_Assert BT_Fails%(btBig, BD_MAX_SETS * 2 + 1, "more than BD_MAX_SETS"), "4.05  one more is an error"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=1,1 color=1 hold=1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17"), 2, "options on one line"), "4.06  too many words on a line"
Print ""

Print "--- 5. BLINK timing ---"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=12 rest=48" + Chr$(10))
BT_Assert BD_BlinkLevel!(0, 0) = 1 And BD_BlinkLevel!(0, 11) = 1 And BD_BlinkLevel!(0, 12) = 0 And BD_BlinkLevel!(0, 59) = 0 And BD_BlinkLevel!(0, 60) = 1, "5.01  hard: on 12 frames, off 48, repeating"
btOk = -1
For btF = 0 To 599
    If BD_BlinkLevel!(0, btF) <> BD_BlinkLevel!(0, btF Mod 60) Then btOk = 0
Next btF
BT_Assert btOk,                                         "5.02  a frame's level depends only on its place in the period"
btN = 0
For btF = 0 To 599
    If BD_BlinkLevel!(0, btF) = 1 Then btN = btN + 1
Next btF
BT_Assert btN = 120,                                    "5.03  10 periods are lit for 120 frames"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=12 rest=48 phase=20" + Chr$(10))
BT_Assert BD_BlinkLevel!(0, 0) = 0 And BD_BlinkLevel!(0, 39) = 0 And BD_BlinkLevel!(0, 40) = 1 And BD_BlinkLevel!(0, 51) = 1 And BD_BlinkLevel!(0, 52) = 0, "5.04  phase=20 starts the loop 20 frames in"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=5 rest=0" + Chr$(10))
btOk = -1
For btF = 0 To 30
    If BD_BlinkLevel!(0, btF) <> 1 Then btOk = 0
Next btF
BT_Assert btOk,                                         "5.05  rest=0 with no fades is a steady light"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 rise=30 fall=30 hold=0 rest=0" + Chr$(10))
btMin = 9 : btMax = -9
For btF = 0 To 59
    btV = BD_BlinkLevel!(0, btF)
    If btV < btMin Then btMin = btV
    If btV > btMax Then btMax = btV
Next btF
BT_Assert btMin >= 0 And btMin < 0.01 And btMax <= 1 And btMax > 0.99, "5.06  pulse: sweeps 0 to 1"
BT_Assert BD_BlinkLevel!(0, 0) = 0 And Abs(BD_BlinkLevel!(0, 30) - 1) < 0.001 And Abs(BD_BlinkLevel!(0, 15) - 0.5) < 0.001, "5.07  pulse: dark at the start, full at half the period, half at a quarter"
BT_Assert Abs(BD_BlinkLevel!(0, 7) - BD_BlinkLevel!(0, 67)) < 0.0001, "5.08  the fade repeats every rise+fall frames"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 rise=10 hold=5 fall=20 rest=25" + Chr$(10))
BT_Assert btOk <> 0 And bdRise(0) = 10 And bdHold(0) = 5 And bdFall(0) = 20 And bdRest(0) = 25, "5.09  all four envelope keys are read"
BT_Assert BD_BlinkLevel!(0, 0) = 0 And Abs(BD_BlinkLevel!(0, 5) - 0.5) < 0.001 And BD_BlinkLevel!(0, 10) = 1 And BD_BlinkLevel!(0, 14) = 1, "5.10  rise: dark, half way at half the rise, full when the hold starts"
BT_Assert BD_BlinkLevel!(0, 15) = 1 And Abs(BD_BlinkLevel!(0, 25) - 0.5) < 0.001 And BD_BlinkLevel!(0, 34) > 0 And BD_BlinkLevel!(0, 35) = 0 And BD_BlinkLevel!(0, 59) = 0 And BD_BlinkLevel!(0, 60) = 0, "5.11  fall: full as it starts, half way at half the fall, dark for the rest"
btOk = -1
For btF = 0 To 59
    If BD_BlinkLevel!(0, btF) <> BD_BlinkLevel!(0, btF + 60) Or BD_BlinkLevel!(0, btF) <> BD_BlinkLevel!(0, btF + 600) Then btOk = 0
Next btF
BT_Assert btOk,                                         "5.12  the period is the sum of the four (60 frames)"
btOk = -1
For btF = 1 To 9
    If BD_BlinkLevel!(0, btF) <= BD_BlinkLevel!(0, btF - 1) Then btOk = 0
Next btF
For btF = 16 To 34
    If BD_BlinkLevel!(0, btF) >= BD_BlinkLevel!(0, btF - 1) Then btOk = 0
Next btF
BT_Assert btOk,                                         "5.13  the fades are smooth and only go one way"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 rise=7 fall=7 hold=0 rest=0" + Chr$(10) + "    BLINK at=1,1 color=ff0000 rise=30 fall=30 hold=0 rest=0" + Chr$(10))
btOk = -1
For btF = 0 To 13
    If Abs(BD_BlinkLevel!(0, btF) - (0.5 - 0.5 * Cos(6.2831853 * btF / 14))) > 0.0001 Then btOk = 0
Next btF
For btF = 0 To 59
    If Abs(BD_BlinkLevel!(1, btF) - (0.5 - 0.5 * Cos(6.2831853 * btF / 60))) > 0.0001 Then btOk = 0
Next btF
BT_Assert btOk,                                         "5.14  rise=N fall=N (no hold, no rest) is the plain sine pulse of 2N frames"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 rise=10 fall=10 rest=40 phase=20" + Chr$(10) + "    BLINK at=1,1 color=ff0000 rise=10 fall=10 hold=0 rest=40 phase=10" + Chr$(10) + "    BLINK at=1,1 color=ff0000 rise=10 fall=10 hold=0 rest=40" + Chr$(10))
BT_Assert BD_BlinkLevel!(0, 50) = 1 And BD_BlinkLevel!(1, 0) = 1 And BD_BlinkLevel!(2, 10) = 1 And BD_BlinkLevel!(0, 0) = 0 And BD_BlinkLevel!(1, 10) = 0 And BD_BlinkLevel!(2, 0) = 0, "5.15  a landing-light chase: phases 20, 10, 0 peak at frames 50, 0 and 10 of a 60-frame loop, 10 apart, in that order"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=1 rest=0" + Chr$(10) + "    BLINK at=1,1 color=ff0000 rise=1 hold=0 fall=0 rest=0" + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=0 rest=1" + Chr$(10))
BT_Assert btOk <> 0 And BD_BlinkLevel!(0, 5) = 1 And BD_BlinkLevel!(1, 5) = 0 And BD_BlinkLevel!(2, 5) = 0, "5.16  a period of 1 frame is allowed: hold=1 is steady, rise=1 or rest=1 stays dark"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=1,1 color=ff0000 hold=1 on=10 off=10"), 2, "unknown BLINK key 'on'"), "5.17  on= is no longer a key"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=1,1 color=ff0000 hold=1 off=10"), 2, "unknown BLINK key 'off'"), "5.18  off= is no longer a key"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=1,1 color=ff0000 rise=0 hold=0 fall=0 rest=0"), 2, "rise + hold + fall + rest must add up to at least 1"), "5.19  an all-zero envelope is an error"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=1,1 color=ff0000 rise=-1"), 2, "rise must be a whole number 0 to 600"), "5.20  a negative fade"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=1,1 color=ff0000 fall=601"), 2, "fall must be"), "5.21  a fall over 600 frames"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=1,1 color=ff0000 rise=5"), 2, "unknown SPARK key 'rise'"), "5.22  rise= is not a SPARK key"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=1,1 color=ff0000 rise=2.5"), 2, "rise must be a whole number"), "5.23  a fractional fade"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=1,1 color=ff0000"), 2, "must add up to at least 1 frame (for example hold=30 rest=30)"), "5.24  no envelope at all is an error, and says how to write one"
btOk = BD_Parse%(BT_Src$("    BLINK at=1,1 color=ff0000 rise=10 fall=10 rest=40"))
BT_Assert btOk <> 0 And bdHold(0) = 0, "5.25  unset keys are 0: rise=10 fall=10 rest=40 has no hold"
BT_Assert bdRise(0) + bdHold(0) + bdFall(0) + bdRest(0) = 60, "5.26  the loop is the sum of what is written"
Print ""

Print "--- 6. the hash ---"
btMin = 9 : btMax = -9 : btSum = 0 : btOk = -1
For btF = 0 To 3999
    btV = BD_Hash!(btF, 3, 7)
    If btV < 0 Or btV >= 1 Then btOk = 0
    If btV < btMin Then btMin = btV
    If btV > btMax Then btMax = btV
    btSum = btSum + btV
Next btF
BT_Assert btOk,                                         "6.01  always 0 <= n < 1"
BT_Assert btSum / 4000 > 0.47 And btSum / 4000 < 0.53,  "6.02  mean near one half (" + Str$(btSum / 4000) + ")"
BT_Assert btMin < 0.02 And btMax > 0.98,                "6.03  covers the range"
btN = 0
For btF = 0 To 3999
    If BD_Hash!(btF, 3, 7) < 0.5 Then btN = btN + 1
Next btF
BT_Assert btN > 1900 And btN < 2100,                    "6.04  half the frames fall under one half (" + LTrim$(Str$(btN)) + ")"
BT_Assert BD_Hash!(120, 2, 5) = BD_Hash!(120, 2, 5),    "6.05  the same inputs give the same number"
BT_Assert BD_Hash!(120, 2, 5) <> BD_Hash!(121, 2, 5) And BD_Hash!(120, 2, 5) <> BD_Hash!(120, 3, 5) And BD_Hash!(120, 2, 5) <> BD_Hash!(120, 2, 6), "6.06  each input changes it"
btN = 0
For btF = 0 To 999
    If Abs(BD_Hash!(btF, 0, 0) - BD_Hash!(btF, 0, 1)) < 0.05 Then btN = btN + 1
Next btF
BT_Assert btN < 150,                                    "6.07  neighbouring salts are not correlated (" + LTrim$(Str$(btN)) + " of 1000 within 0.05)"
BT_Assert BD_Hash!(1048575, 1048575, 1048575) >= 0 And BD_Hash!(1048575, 1048575, 1048575) < 1 And BD_Hash!(2147483647, 0, 0) < 1, "6.08  the largest inputs stay exact and in range"
Print ""

Print "--- 7. SPARK ---"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=50,100 color=ff0000,00ff00 count=3 every=90 speed=1 gravity=0.1 life=20 phase=10" + Chr$(10))
bdLastMain = -9
BD_Advance 500, "dock"
BT_Assert BD_SparksLive% = 0,                           "7.01  phase=10: no burst at frame 0"
For btF = 1 To 9 : BD_Advance 500 + btF, "dock" : Next btF
BT_Assert BD_SparksLive% = 0,                           "7.02  none at frame 9"
BD_Advance 510, "dock"
BT_Assert BD_SparksLive% = 3,                           "7.03  three sparks at frame 10"
btOk = -1
For btI = 0 To BD_POOL - 1
    If bdPAlive(btI) Then
        If bdPX(btI) <> 50 Or bdPY(btI) <> 100 Then btOk = 0
    End If
Next btI
BT_Assert btOk,                                         "7.04  they start on the effect's point"
For btF = 11 To 15 : BD_Advance 500 + btF, "dock" : Next btF
btOk = -1
btN = 0
For btI = 0 To BD_POOL - 1
    If bdPAlive(btI) Then
        btN = btN + 1
        If bdPY(btI) >= 100 Then btOk = 0
    End If
Next btI
BT_Assert btN = 3 And btOk,                             "7.05  dir=270 (up): five frames on they have risen"
For btF = 16 To 29 : BD_Advance 500 + btF, "dock" : Next btF
BT_Assert BD_SparksLive% = 3,                           "7.06  still alive at age 19"
BD_Advance 530, "dock"
BT_Assert BD_SparksLive% = 0,                           "7.07  gone at age 20 (life=20 frames)"
For btF = 31 To 99 : BD_Advance 500 + btF, "dock" : Next btF
BT_Assert BD_SparksLive% = 0,                           "7.08  nothing between bursts"
BD_Advance 600, "dock"
BT_Assert BD_SparksLive% = 3,                           "7.09  the next burst is every=90 frames later (frame 100)"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=50,100 color=ff0000 count=1 speed=0 gravity=0.5 life=40 every=100 dir=270 spread=0" + Chr$(10))
btT = BT_Trace$("dock", 10)
BT_Assert bdPAlive(0) <> 0 And bdPX(0) = 50 And bdPY(0) > 100 And bdPVY(0) > 0, "7.10  with speed 0 only gravity moves a spark, downward"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=50,100 color=ff0000 count=8 speed=1 gravity=0 life=30 every=100 dir=0 spread=0" + Chr$(10))
btT = BT_Trace$("dock", 5)
btOk = -1
For btI = 0 To BD_POOL - 1
    If bdPAlive(btI) Then
        If bdPX(btI) <= 50 Or Abs(bdPY(btI) - 100) > 0.01 Then btOk = 0
    End If
Next btI
BT_Assert btOk,                                         "7.11  dir=0 spread=0 flies straight right"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=50,100 color=ff0000,00ff00,0000ff count=12 speed=1 life=30 every=100" + Chr$(10))
BD_Reset "dock"
btN = 0 : btA = 0 : btB = 0
For btI = 0 To BD_POOL - 1
    If bdPAlive(btI) Then
        If _Red32(bdPCol(btI)) = 255 Then btN = 1
        If _Green32(bdPCol(btI)) = 255 Then btA = 1
        If _Blue32(bdPCol(btI)) = 255 Then btB = 1
    End If
Next btI
BT_Assert btN + btA + btB = 3,                                      "7.12  twelve sparks use all three colours"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=50,100 color=ff0000,00ff00 count=5 every=17 speed=1.5 gravity=0.07 life=25" + Chr$(10) + "    SPARK at=70,80 color=ffffff count=2 every=23 speed=0.4 life=15 phase=5" + Chr$(10))
btS = BT_Trace$("dock", 200)
btT = BT_Trace$("dock", 200)
BT_Assert Len(btS) > 20 And btS = btT,                  "7.13  the same 200 frames twice leave the same sparks, to the pixel fraction"
btS = BT_Trace$("dock", 201)
BT_Assert btS <> btT,                                   "7.14  one frame later they have moved"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=50,100 color=ff0000 count=5 every=1000 speed=1 life=25" + Chr$(10) + "    SPARK at=50,100 color=ff0000 count=5 every=1000 speed=1 life=25" + Chr$(10))
BD_Reset "dock"
btA = 0
For btI = 0 To 4 : If bdPVX(btI) <> bdPVX(btI + 5) Then btA = btA + 1
Next btI
BT_Assert btA >= 4,                                     "7.15  two identical effects scatter differently (the effect number is hashed in)"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=50,100 color=ff0000 count=4 speed=1 life=25 every=50" + Chr$(10))
BD_Reset "dock"
btA = Int(bdPVX(0) * 1000)
BD_Reset "dock"
BT_Assert btA = Int(bdPVX(0) * 1000),                   "7.16  entering the screen again repeats the first burst"
Print ""

Print "--- 8. the pool ---"
BT_Assert BT_Fails%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=10 life=45" + Chr$(10), 2, "pool holds 64"), "8.01  16 sparks per 10 frames living 45 could reach 80: an error"
BT_Assert BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=10 life=40" + Chr$(10)) <> 0, "8.02  exactly 64 alive at once is allowed"
BT_Assert BT_Fails%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=10 every=60 life=60" + Chr$(10) + "    SPARK at=2,2 color=ff0000 count=10 every=60 life=60 phase=7" + Chr$(10) + "    SPARK at=3,3 color=ff0000 count=10 every=60 life=60 phase=9" + Chr$(10) + "    SPARK at=4,4 color=ff0000 count=10 every=60 life=60 phase=11" + Chr$(10) + "    SPARK at=5,5 color=ff0000 count=10 every=60 life=60 phase=13" + Chr$(10) + "    SPARK at=6,6 color=ff0000 count=10 every=60 life=60 phase=15" + Chr$(10) + "    SPARK at=7,7 color=ff0000 count=10 every=60 life=60 phase=17" + Chr$(10), 8, "pool"), "8.03  the effects of one backdrop add up (the error is on the line that tips it)"
BT_Assert BD_Parse%("backdrop:title" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=10 life=40" + Chr$(10) + "backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=10 life=40" + Chr$(10)) <> 0, "8.04  the pool is per screen: two backdrops of 64 are fine"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=10 life=40" + Chr$(10))
bdLastMain = -9 : bdPDropped = 0
btN = 0
For btF = 0 To 399
    BD_Advance 2000 + btF, "dock"
    If BD_SparksLive% > btN Then btN = BD_SparksLive%
Next btF
BT_Assert btN = 64 And bdPDropped = 0,                  "8.05  a file at the bound reaches 64 alive and never overflows"
For btI = 0 To BD_POOL - 1 : bdPAlive(btI) = -1 : Next btI
BD_Spawn 0, 12
BT_Assert BD_SparksLive% = 64 And bdPDropped = 16,      "8.06  a full pool takes no more and counts what it turned away"
BD_Reset "dock"
BT_Assert BD_SparksLive% = 16,                          "8.07  entering a screen clears the pool"
Print ""

Print "--- 9. screen entry ---"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=2 every=30 life=10" + Chr$(10) + "backdrop:dock" + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=1" + Chr$(10))
bdLastMain = -9
BD_Advance 100, "title"
BT_Assert bdFrame = 0 And bdCur = BD_Find%("title") And BD_SparksLive% = 2, "9.01  the first call is frame 0, and the frame-0 burst has started"
BD_Advance 101, "title"
BD_Advance 102, "title"
BT_Assert bdFrame = 2,                                  "9.02  each following main-loop frame is the next frame"
BD_Advance 102, "title"
BT_Assert bdFrame = 2,                                  "9.03  a second call in the same main-loop frame changes nothing"
BD_Advance 140, "title"
BT_Assert bdFrame = 0,                                  "9.04  a gap (the screen was left and entered again) starts over"
BD_Advance 141, "title"
BD_Advance 142, "dock"
BT_Assert bdFrame = 0 And bdCur = BD_Find%("dock") And BD_SparksLive% = 0, "9.05  another backdrop starts at frame 0 with no sparks"
BD_Advance 143, "nowhere"
BT_Assert bdCur = -1 And BD_SparksLive% = 0,            "9.06  a painting with no effects draws nothing"
BD_Advance 5, "dock"
BT_Assert bdFrame = 0,                                  "9.07  the frame counter running backwards also starts over"
BD_Advance 6, "dock"
BT_Assert bdFrame = 1,                                  "9.08  and counts on from there"
Print ""

Print "--- 10. no RNG stream ---"
btOk = BD_Parse%(_Embedded$("BACKDROPS"))
Randomize 7
btRnd1 = Rnd : btRnd1 = Rnd(0)
bdLastMain = -9
For btF = 0 To 599
    BD_Advance 3000 + btF, "title"
    BD_Advance 3000 + btF, "title"
Next btF
btRnd2 = Rnd(0)
BT_Assert btRnd1 = btRnd2,                              "10.01  600 frames of the real title backdrop draw nothing from the Rnd stream (its last number is unchanged)"
Print ""

Print "--- 11. glow, spark size and jitter ---"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=1" + Chr$(10))
BT_Assert bdGlow(0) = 3,                                "11.01  BLINK glow defaults to 3"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    BLINK at=1,1 color=ff0000 hold=1 glow=12 size=2" + Chr$(10))
BT_Assert btOk <> 0 And bdGlow(0) = 12 And bdSize(0) = 2, "11.02  glow=12 is allowed"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=1,1 color=ff0000 hold=1 glow=13"), 2, "glow must be a whole number 0 to 12"), "11.03  glow=13 is an error"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=1,1 color=ff0000 glow=2"), 2, "unknown SPARK key 'glow'"), "11.04  glow is not a SPARK key"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    SPARK at=1,1 color=ff0000" + Chr$(10))
BT_Assert bdSize(0) = 1 And bdJitter(0) = 0,            "11.05  SPARK size defaults to 1 and jitter to 0"
btOk = BD_Parse%("backdrop:title" + Chr$(10) + "    SPARK at=1,1 color=ff0000 size=6 jitter=20 every=60" + Chr$(10))
BT_Assert btOk <> 0 And bdSize(0) = 6 And bdJitter(0) = 20, "11.06  size=6 and jitter=20 are read"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=1,1 color=ff0000 size=0"), 2, "size must be a whole number 1 to 6"), "11.07  SPARK size=0 is an error"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=1,1 color=ff0000 size=7"), 2, "size must be a whole number 1 to 6"), "11.08  SPARK size=7 is an error"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=1,1 color=ff0000 size=2.5"), 2, "size must be"), "11.09  SPARK size must be whole"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=1,1 color=ff0000 hold=1 size=8 jitter=3"), 2, "unknown BLINK key 'jitter'"), "11.10  jitter is not a BLINK key"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=1,1 color=ff0000 every=30 jitter=30"), 2, "jitter must be less than every (30)"), "11.11  jitter must stay under every"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=1,1 color=ff0000 every=3600 jitter=3600"), 2, "jitter must be"), "11.12  jitter has an upper limit"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=1,1 color=ff0000 jitter=x"), 2, "jitter must be a whole number"), "11.13  jitter must be a number"
BT_Assert BD_Parse%(BT_Src$("    SPARK at=1,1 color=ff0000 count=16 every=10 life=40")) <> 0, "11.14  64 alive with no jitter is allowed"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=1,1 color=ff0000 count=16 every=10 jitter=5 life=40"), 2, "pool holds 64"), "11.15  jitter closes the gap between bursts, so the pool bound uses every - jitter"
BT_Assert BD_Parse%(BT_Src$("    SPARK at=1,1 color=ff0000 count=8 every=10 jitter=5 life=40")) <> 0, "11.16  8 sparks with jitter fits (8 bursts of 8 never exceed 64)"
' bursts of an effect: the frames on which sparks of age 0 exist, as "f,f,f,"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=1 every=50 jitter=20 life=5" + Chr$(10) + "    SPARK at=2,2 color=ff0000 count=1 every=50 jitter=20 life=5" + Chr$(10))
bdLastMain = -9
btS = "" : btT = ""
For btF = 0 To 2999
    BD_Advance 4000 + btF, "dock"
    For btI = 0 To BD_POOL - 1
        If bdPAlive(btI) Then
            If bdPAge(btI) = 0 And bdPFx(btI) = 0 Then btS = btS + LTrim$(Str$(btF)) + ","
            If bdPAge(btI) = 0 And bdPFx(btI) = 1 Then btT = btT + LTrim$(Str$(btF)) + ","
        End If
    Next btI
Next btF
btOk = -1 : btN = 0 : btMin = 99 : btMax = 0 : btA = -1 : btB = 0
Dim btP As Integer, btC As Integer, btCur As Long, btWin As Long, btSeen(0 To 59) As Integer
btP = 1 : btWin = 0
Do While btP < Len(btS)
    btC = InStr(btP, btS, ",")
    btCur = Val(Mid$(btS, btP, btC - btP)) : btP = btC + 1
    btN = btN + 1
    If btCur \ 50 <> btWin Then btOk = 0
    btWin = btWin + 1
    If btCur - (btCur \ 50) * 50 > 20 Then btOk = 0
    btSeen(btCur - (btCur \ 50) * 50) = -1
    If btA >= 0 Then
        If btCur - btA < 30 Or btCur - btA > 70 Then btOk = 0
    End If
    btA = btCur
Loop
btC = 0
For btP = 0 To 59 : If btSeen(btP) Then btC = btC + 1
Next btP
BT_Assert btN = 60 And btOk,                            "11.17  jitter=20, every=50: one burst in each 50-frame window, at most 20 frames late, 30 to 70 frames apart (60 bursts in 3000 frames)"
BT_Assert btC >= 10,                                    "11.18  the bursts are not on a fixed beat (" + LTrim$(Str$(btC)) + " different offsets in 60 bursts)"
BT_Assert btS <> btT,                                   "11.19  two identical effects keep different beats (the effect number is hashed in)"
btA = 0
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=1 every=50 jitter=20 life=5" + Chr$(10) + "    SPARK at=2,2 color=ff0000 count=1 every=50 jitter=20 life=5" + Chr$(10))
bdLastMain = -9
btU = ""
For btF = 0 To 2999
    BD_Advance 4000 + btF, "dock"
    For btI = 0 To BD_POOL - 1
        If bdPAlive(btI) Then
            If bdPAge(btI) = 0 And bdPFx(btI) = 0 Then btU = btU + LTrim$(Str$(btF)) + ","
        End If
    Next btI
Next btF
BT_Assert btU = btS,                                   "11.20  the same 3000 frames again give the same bursts"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=1 every=50 life=5" + Chr$(10))
bdLastMain = -9
btN = 0 : btOk = -1
For btF = 0 To 999
    BD_Advance 8000 + btF, "dock"
    For btI = 0 To BD_POOL - 1
        If bdPAlive(btI) Then
            If bdPAge(btI) = 0 Then
                btN = btN + 1
                If btF Mod 50 <> 0 Then btOk = 0
            End If
        End If
    Next btI
Next btF
BT_Assert btN = 20 And btOk,                            "11.21  jitter=0 keeps the plain every= beat"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=1 every=1000 speed=0 gravity=0 life=30 size=3" + Chr$(10))
BD_Reset "dock"
BT_Assert bdSize(bdPFx(0)) = 3,                         "11.22  a spark reads its size from its effect"
Print ""

Print "=== " + LTrim$(Str$(btPass + btFail)) + " tests: " _
    + LTrim$(Str$(btPass)) + " passed, " + LTrim$(Str$(btFail)) + " failed ==="
If btFail > 0 Then System 1 Else System 0
