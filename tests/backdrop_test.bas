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
'  13. SPRITE: path, rest, pingpong, flip, phase, and its parse errors
'  14. LASER and CAMERA: emission timing, the fixed camera's projection, parse errors
'  16. SPRITE scale= and bob=: size along the path, both legs, the hop, its angle, the pause at the ends
'  15. Morse on BLINK: SOS on/off sequence, unit, rest, rise/fall, parse errors
'
' Build: tools/dev test (builds and runs every test)
' Run:   builds/backdrop_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

$EMBED:'assets/backdrops.txt':'BACKDROPS'
$EMBED:'assets/backdrops/tug.png':'BDIMGTUG'
$EMBED:'assets/backdrops/baggage_cart.png':'BDIMGBAGGAGECART'

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
btFx = BD_Find%("dock")
btN = 0 : btA = 0
For btI = bdSetFrom(btFx) To bdSetFrom(btFx) + bdSetN(btFx) - 1
    If bdKind(btI) = BD_KIND_BLINK Then btN = btN + 1 Else btA = btA + 1
Next btI
BT_Assert btN >= 1 And btA >= 1,                        "1.09  the dock has both lights and sparks"
Print ""

Print "--- 2. parse failures name their line ---"
BT_Assert BT_Fails%(BT_Src$("    GLOW at=10,10 color=ff0000"), 2, "unknown effect 'GLOW'"), "2.01  unknown verb"
BT_Assert BT_Fails%(BT_Src$("    SPRITES at=10,10 color=ff0000"), 2, "unknown effect"), "2.02  an effect name that is not a verb"
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
BT_Assert BT_Fails%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=1 life=65" + Chr$(10), 2, "pool holds 1024"), "8.01  16 sparks a frame living 65 could reach 1040: an error"
BT_Assert BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=1 life=64" + Chr$(10)) <> 0, "8.02  exactly 1024 alive at once is allowed"
BT_Assert BT_Fails%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=1 life=10" + Chr$(10) + "    SPARK at=2,2 color=ff0000 count=16 every=1 life=10 phase=7" + Chr$(10) + "    SPARK at=3,3 color=ff0000 count=16 every=1 life=10 phase=9" + Chr$(10) + "    SPARK at=4,4 color=ff0000 count=16 every=1 life=10 phase=11" + Chr$(10) + "    SPARK at=5,5 color=ff0000 count=16 every=1 life=10 phase=13" + Chr$(10) + "    SPARK at=6,6 color=ff0000 count=16 every=1 life=10 phase=15" + Chr$(10) + "    SPARK at=7,7 color=ff0000 count=16 every=1 life=10 phase=17" + Chr$(10), 8, "pool"), "8.03  the effects of one backdrop add up (the error is on the line that tips it)"
BT_Assert BD_Parse%("backdrop:title" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=1 life=64" + Chr$(10) + "backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=1 life=64" + Chr$(10)) <> 0, "8.04  the pool is per screen: two backdrops of 1024 are fine"
btOk = BD_Parse%("backdrop:dock" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=1 life=64" + Chr$(10))
bdLastMain = -9 : bdPDropped = 0
btN = 0
For btF = 0 To 399
    BD_Advance 2000 + btF, "dock"
    If BD_SparksLive% > btN Then btN = BD_SparksLive%
Next btF
BT_Assert btN = 1024 And bdPDropped = 0,                  "8.05  a file at the bound reaches 1024 alive and never overflows"
For btI = 0 To BD_POOL - 1 : bdPAlive(btI) = -1 : Next btI
BD_Spawn 0, 12
BT_Assert BD_SparksLive% = 1024 And bdPDropped = 16,      "8.06  a full pool takes no more and counts what it turned away"
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
BT_Assert BD_Parse%(BT_Src$("    SPARK at=1,1 color=ff0000 count=16 every=1 life=64")) <> 0, "11.14  1024 alive with no jitter is allowed"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=1,1 color=ff0000 count=16 every=10 jitter=9 life=65"), 2, "pool holds 1024"), "11.15  jitter closes the gap between bursts, so the pool bound uses every - jitter"
BT_Assert BD_Parse%(BT_Src$("    SPARK at=1,1 color=ff0000 count=8 every=10 jitter=9 life=100")) <> 0, "11.16  8 sparks with jitter fits (800 at most, under 1024)"
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

Print "--- 12. wrapping parse problems for the dev screen ---"
Dim btRows(0 To 7) As String, btMsg As String, btJoin As String
btMsg = "backdrop 'emperor' could have 90 sparks alive at once, the pool holds 1024 (lower count or life, or raise every)"
btN = BD_WrapText%(btMsg, 40, btRows(), 8)
btOk = -1 : btJoin = ""
For btI = 0 To btN - 1
    If Len(btRows(btI)) > 40 Or Len(btRows(btI)) = 0 Then btOk = 0
    If btI > 0 Then btJoin = btJoin + " "
    btJoin = btJoin + btRows(btI)
Next btI
BT_Assert btN = 3 And btOk,                             "12.01  a 113 character problem is three rows of at most 40"
BT_Assert btJoin = btMsg,                               "12.02  and nothing is lost: the rows read back as the original"
btN = BD_WrapText%("line 2: short", 40, btRows(), 8)
BT_Assert btN = 1 And btRows(0) = "line 2: short",      "12.03  a short problem is one row"
btN = BD_WrapText%("abcdefghijklmnopqrstuvwxyz", 10, btRows(), 8)
BT_Assert btN = 3 And btRows(0) = "abcdefghij" And btRows(1) = "klmnopqrst" And btRows(2) = "uvwxyz", "12.04  a word longer than a row is cut"
btN = BD_WrapText%("one two" + Chr$(10) + "three four five", 9, btRows(), 8)
BT_Assert btN = 3 And btRows(0) = "one two" And btRows(1) = "three" And btRows(2) = "four five", "12.05  each problem starts on a new row"
btN = BD_WrapText%("line 1: a" + Chr$(10) + Chr$(10) + "line 3: b" + Chr$(10), 40, btRows(), 8)
BT_Assert btN = 3 And btRows(1) = "",                  "12.06  a blank line stays a blank row, a trailing line end adds none"
btN = BD_WrapText%("", 40, btRows(), 8)
BT_Assert btN = 0,                                      "12.07  nothing to show is no rows"
btN = BD_WrapText%("aaa bbb ccc ddd eee fff ggg hhh iii jjj", 3, btRows(), 4)
BT_Assert btN = 10 And btRows(0) = "aaa" And btRows(3) = "ddd", "12.08  more rows than fit: the count says so and the first rows are kept"
btOk = BD_Parse%("backdrop:emperor" + Chr$(10) + "    SPARK at=1,1 color=ff0000 count=16 every=1 life=65" + Chr$(10))
btN = BD_WrapText%(bdErrors, 40, btRows(), 8)
BT_Assert btN >= 2 And btN <= 8 And Left$(btRows(0), 7) = "line 2:", "12.09  a real parse problem wraps inside the cap"
btOk = BD_Parse%(BT_Src$("    SPARK at=1,1 color=ff0000 count=16 every=1 life=64"))
btFx = 0
BD_Reset "title"
BT_Assert BD_SparksLive% = 16,                          "12.10  a 1024-spark file loads and its first burst starts"
Print ""

Print "--- 13. SPRITE ---"
Dim btSX As Single, btSY As Single, btFl As Integer, btVis As Integer
BT_Assert Len(_Embedded$("BDIMGTUG")) > 0 And Len(_Embedded$("BDIMGBAGGAGECART")) > 0, "13.01  the sprite images are embedded"
BT_Assert BD_SpriteIdx%("tug") = 1 And BD_SpriteIdx%("baggage_cart") = 2 And BD_SpriteIdx%("nope") = 0 And BD_SpriteIdx%("") = 0, "13.02  image names are looked up"
btOk = BD_Parse%(BT_Src$("    SPRITE img=tug at=0,0 to=100,50 frames=100 rest=50"))
BT_Assert btOk <> 0 And bdKind(0) = BD_KIND_SPRITE,     "13.03  a one-way sprite parses"
btVis = BD_SpriteAt%(0, 0, btSX, btSY, btFl)
BT_Assert btVis And btSX = 0 And btSY = 0,              "13.04  frame 0 is at the start"
btVis = BD_SpriteAt%(0, 50, btSX, btSY, btFl)
BT_Assert btVis And btSX = 50 And btSY = 25,            "13.05  halfway is halfway"
btVis = BD_SpriteAt%(0, 99, btSX, btSY, btFl)
BT_Assert btVis And Abs(btSX - 99) < 0.001,             "13.06  the last travelling frame is next to the end"
btVis = BD_SpriteAt%(0, 100, btSX, btSY, btFl)
BT_Assert btVis = 0,                                    "13.07  it is gone during the rest"
btVis = BD_SpriteAt%(0, 149, btSX, btSY, btFl)
BT_Assert btVis = 0,                                    "13.08  ... through the last frame of it"
btVis = BD_SpriteAt%(0, 150, btSX, btSY, btFl)
BT_Assert btVis And btSX = 0,                           "13.09  and starts again at the start"
btVis = BD_SpriteAt%(0, 1050, btSX, btSY, btFl)
BT_Assert btVis And btSX = 0 And btFl = 0,              "13.10  position comes from the frame alone (frame 1050 = frame 0)"
btOk = BD_Parse%(BT_Src$("    SPRITE img=tug at=0,0 to=100,50 frames=100 rest=50 phase=25"))
btVis = BD_SpriteAt%(0, 0, btSX, btSY, btFl)
BT_Assert btVis And btSX = 25,                          "13.11  phase starts it that many frames in"
btOk = BD_Parse%(BT_Src$("    SPRITE img=tug at=0,0 to=100,50 frames=100 rest=20 pingpong=1 flip=1"))
BT_Assert btOk <> 0,                                    "13.12  pingpong with flip parses"
btVis = BD_SpriteAt%(0, 60, btSX, btSY, btFl)
BT_Assert btVis And Abs(btSX - 60) < 0.01 And btFl = 0,    "13.13  out leg: not mirrored"
btVis = BD_SpriteAt%(0, 110, btSX, btSY, btFl)
BT_Assert btVis And btSX = 100 And btFl = 0,            "13.14  parked at the far end during the rest, still visible"
btVis = BD_SpriteAt%(0, 170, btSX, btSY, btFl)
BT_Assert btVis And btSX = 50 And btSY = 25 And btFl = 1, "13.15  return leg: halfway back, mirrored"
btVis = BD_SpriteAt%(0, 230, btSX, btSY, btFl)
BT_Assert btVis And btSX = 0 And btFl = 0,              "13.16  parked at the start, not mirrored"
btVis = BD_SpriteAt%(0, 240, btSX, btSY, btFl)
BT_Assert btVis And btSX = 0 And btFl = 0,              "13.17  the loop is 2 * (frames + rest): frame 240 is frame 0"
btOk = BD_Parse%(BT_Src$("    SPRITE img=tug at=0,0 to=100,50 frames=100 pingpong=1"))
btVis = BD_SpriteAt%(0, 150, btSX, btSY, btFl)
BT_Assert btVis And btSX = 50 And btFl = 0,             "13.18  pingpong without flip is never mirrored"
btOk = BD_Parse%(BT_Src$("    SPRITE img=tug at=-30,10 to=350,10 frames=100"))
BT_Assert btOk <> 0,                                    "13.19  a sprite may start and end off the painting edge"
BT_Assert BT_Fails%(BT_Src$("    SPRITE img=tug at=-200,10 to=100,10"), 2, "off the 320x240 painting"), "13.20  but not far off"
BT_Assert BT_Fails%(BT_Src$("    SPRITE img=boat at=0,0 to=10,10"), 2, "known: tug"), "13.21  an unknown image lists the known names"
BT_Assert BT_Fails%(BT_Src$("    SPRITE at=0,0 to=10,10"), 2, "needs img"), "13.22  no img"
BT_Assert BT_Fails%(BT_Src$("    SPRITE img=tug to=10,10"), 2, "needs at"), "13.23  no at"
BT_Assert BT_Fails%(BT_Src$("    SPRITE img=tug at=0,0"), 2, "needs to"), "13.24  no to"
BT_Assert BT_Fails%(BT_Src$("    SPRITE img=tug at=0,0 to=10,10 flip=1"), 2, "flip=1 needs pingpong=1"), "13.25  flip without pingpong is an error"
BT_Assert BT_Fails%(BT_Src$("    SPRITE img=tug at=0,0 to=10,10 pingpong=2"), 2, "pingpong must be"), "13.26  pingpong is 0 or 1"
BT_Assert BT_Fails%(BT_Src$("    SPRITE img=tug at=0,0 to=10,10 frames=0"), 2, "frames must be"), "13.27  frames of at least 1"
BT_Assert BT_Fails%(BT_Src$("    SPRITE img=tug at=0,0 to=10,10 color=ff0000"), 2, "unknown SPRITE key 'color'"), "13.28  a key SPRITE does not take"
Print ""

Print "--- 14. LASER and CAMERA ---"
Dim btCm(0 To 3, 0 To 3) As Single, btWX As Single, btWY As Single, btWZ As Single, btPX As Single, btPY As Single, btPW As Single, btD As Single, btDepth As Single
btOk = BD_Parse%(BT_Src$("    LASER from=158,104,40 to=60,150,10 color=ff3030 every=90 speed=4 length=12"))
BT_Assert btOk <> 0 And bdKind(0) = BD_KIND_LASER,      "14.01  the example laser parses"
BT_Assert bdSetFov(0) = BD_CAM_FOV And bdSetHor(0) = BD_CAM_HORIZON, "14.02  no CAMERA gives the defaults"
btOk = BD_Parse%(BT_Src$("    CAMERA fov=40 horizon=90" + BT_Nl$ + "    LASER from=158,104,40 to=60,150,10 color=ff3030"))
BT_Assert btOk <> 0 And bdSetFov(0) = 40 And bdSetHor(0) = 90 And bdFxN = 1, "14.03  CAMERA sets the backdrop's perspective and is not an effect"
btOk = BD_Parse%(BT_Src$("    LASER from=158,104,40 to=60,150,10 color=ff3030" + BT_Nl$ + "    CAMERA horizon=60"))
BT_Assert btOk <> 0 And bdSetFov(0) = BD_CAM_FOV And bdSetHor(0) = 60, "14.04  CAMERA may come after the effects; a missing key keeps its default"
btOk = BD_Parse%("backdrop:title" + BT_Nl$ + "    CAMERA fov=40" + BT_Nl$ + "    BLINK at=1,1 color=ff0000 hold=1" + BT_Nl$ + "backdrop:dock" + BT_Nl$ + "    BLINK at=1,1 color=ff0000 hold=1" + BT_Nl$)
BT_Assert btOk <> 0 And bdSetFov(0) = 40 And bdSetFov(1) = BD_CAM_FOV, "14.05  a CAMERA belongs to its own backdrop"
BT_Assert BT_Fails%(BT_Src$("    CAMERA fov=40" + BT_Nl$ + "    CAMERA fov=50"), 3, "CAMERA is given twice"), "14.06  CAMERA twice in a backdrop"
BT_Assert BT_Fails%(BT_Src$("    CAMERA fov=5"), 2, "fov must be"), "14.07  fov out of range"
BT_Assert BT_Fails%(BT_Src$("    CAMERA horizon=300"), 2, "horizon must be"), "14.08  horizon off the painting"
BT_Assert BT_Fails%(BT_Src$("    CAMERA zoom=2"), 2, "unknown CAMERA key 'zoom'"), "14.09  unknown CAMERA key"
BT_Assert BT_Fails%("    CAMERA fov=40" + BT_Nl$, 1, "before any backdrop"), "14.10  CAMERA before a header"
BT_Assert BT_Fails%(BT_Src$("    LASER from=1,1 to=2,2,3 color=ff0000"), 2, "from must be x,y,depth"), "14.11  from needs a depth"
BT_Assert BT_Fails%(BT_Src$("    LASER from=1,1,1 to=2,2 color=ff0000"), 2, "to must be x,y,depth"), "14.12  to needs a depth"
BT_Assert BT_Fails%(BT_Src$("    LASER from=1,1,1 to=2,2,2"), 2, "needs color"), "14.13  no color"
BT_Assert BT_Fails%(BT_Src$("    LASER from=1,1,1 to=1,1,1 color=ff0000"), 2, "same point"), "14.14  from and to the same"
BT_Assert BT_Fails%(BT_Src$("    LASER from=400,1,1 to=2,2,2 color=ff0000"), 2, "off the 320x240 painting"), "14.15  x off the painting"
BT_Assert BT_Fails%(BT_Src$("    LASER from=1,1,900 to=2,2,2 color=ff0000"), 2, "depth must be"), "14.16  depth out of range"
BT_Assert BT_Fails%(BT_Src$("    LASER from=1,1,1 to=2,2,2 color=ff0000,00ff00"), 2, "at most 1 colour"), "14.17  one colour only"
BT_Assert BT_Fails%(BT_Src$("    LASER from=1,1,1 to=2,2,2 color=ff0000 every=10 jitter=10"), 2, "jitter must be less than every"), "14.18  jitter below every"
BT_Assert BT_Fails%(BT_Src$("    LASER from=1,1,1 to=2,2,2 color=ff0000 at=3,3"), 2, "unknown LASER key 'at'"), "14.19  at is not a LASER key"
' the camera: every point projects back to its own painting x,y, at any depth
btOk = BD_Parse%(BT_Src$("    CAMERA fov=50 horizon=100" + BT_Nl$ + "    LASER from=158,104,40 to=60,150,10 color=ff3030"))
BD_CamMatrix 0, btCm()
btOk = -1
For btDepth = -40 To 400 Step 40
    BD_World 0, 77, 181, btDepth, btWX, btWY, btWZ
    btPW = btWX * btCm(3, 0) + btWY * btCm(3, 1) + btWZ * btCm(3, 2) + btCm(3, 3)
    btPX = ((btWX * btCm(0, 0) + btWY * btCm(0, 1) + btWZ * btCm(0, 2) + btCm(0, 3)) / btPW + 1) * BD_PAINT_W * 0.5
    btPY = (1 - (btWX * btCm(1, 0) + btWY * btCm(1, 1) + btWZ * btCm(1, 2) + btCm(1, 3)) / btPW) * BD_PAINT_H * 0.5
    If Abs(btPX - 77) > 0.05 Or Abs(btPY - 181) > 0.05 Then btOk = 0
Next btDepth
BT_Assert btOk,                                         "14.20  a point projects back to its painting x,y at every depth"
BD_World 0, 160, 100, 0, btWX, btWY, btWZ
btPW = btWX * btCm(3, 0) + btWY * btCm(3, 1) + btWZ * btCm(3, 2) + btCm(3, 3)
BT_Assert Abs(btPW - BD_CamF!(0)) < 0.01 And Abs(btWX - 160) < 0.001 And Abs(btWY - 100) < 0.001, "14.21  at depth 0 world and painting coincide, w = the focal length"
BT_Assert Abs(BD_CamF!(0) - 160 / Tan(25 * 3.14159265 / 180)) < 0.01, "14.22  fov is the angle the 320 pixel width spans at depth 0"
BD_World 0, 160 + 50, 100, 100, btWX, btWY, btWZ
btPW = btWX * btCm(3, 0) + btWY * btCm(3, 1) + btWZ * btCm(3, 2) + btCm(3, 3)
btPX = ((btWX * btCm(0, 0) + btWY * btCm(0, 1) + btWZ * btCm(0, 2) + btCm(0, 3)) / btPW + 1) * BD_PAINT_W * 0.5
BT_Assert Abs(btPX - 210) < 0.05 And Abs(btPW - (BD_CamF!(0) + 100)) < 0.01, "14.23  the divisor at depth d is F + d, so a world length shrinks as F / (F + d)"
BD_World 0, 160, 100, 200, btWX, btWY, btWZ
BT_Assert Abs(btWX - 160) < 0.001 And Abs(btWY - 100) < 0.001, "14.24  the vanishing point (160, horizon) stays put at any depth"
BD_World 0, 60, 100, 200, btWX, btWY, btWZ
BT_Assert btWX < 60 And Abs(btWY - 100) < 0.001,        "14.25  a deeper point at the same painting x lies farther from the vanishing point in the world"
' emission timing
btOk = BD_Parse%(BT_Src$("    LASER from=100,100,0 to=200,100,0 color=ff0000 every=90 speed=10 length=12"))
btD = BD_LaserPath!(0)
BT_Assert Abs(btD - 100) < 0.01,                        "14.26  depth 0 path length is the pixel distance"
btOk = BD_LaserHead%(0, 0, 0, btDepth)
BT_Assert btOk And btDepth = 0,                         "14.27  a bolt leaves on frame 0"
btOk = BD_LaserHead%(0, 5, 0, btDepth)
BT_Assert btOk And btDepth = 50,                        "14.28  it moves speed units a frame"
btOk = BD_LaserHead%(0, 10, 0, btDepth)
BT_Assert btOk And btDepth = 100,                       "14.29  it is still drawn arriving on the end"
btOk = BD_LaserHead%(0, 11, 0, btDepth)
BT_Assert btOk = 0,                                     "14.30  and gone after it"
btOk = BD_LaserHead%(0, 89, 0, btDepth)
BT_Assert btOk = 0,                                     "14.31  nothing in flight before the next shot"
btOk = BD_LaserHead%(0, 90, 0, btDepth)
BT_Assert btOk And btDepth = 0,                         "14.32  the next bolt leaves on frame 90 (every)"
btOk = BD_LaserHead%(0, 95, 1, btDepth)
BT_Assert btOk = 0,                                     "14.33  the older bolt is long gone"
btOk = BD_Parse%(BT_Src$("    LASER from=100,100,0 to=200,100,0 color=ff0000 every=4 speed=10 length=12"))
btOk = BD_LaserHead%(0, 9, 0, btDepth)
btA = -(btDepth = 10)
btOk = BD_LaserHead%(0, 9, 2, btDepth) And btA
BT_Assert btOk And btDepth = 90,                        "14.34  a fast shooter has several bolts in flight: the newest has gone 10 units, the one 2 back 90"
btOk = BD_Parse%(BT_Src$("    LASER from=100,100,0 to=200,100,0 color=ff0000 every=90 speed=10 phase=85"))
btOk = BD_LaserHead%(0, 0, 0, btDepth)
btA = BD_LaserHead%(0, 5, 0, btDepth)
BT_Assert btOk = 0 And btA <> 0 And btDepth = 0, "14.35  phase shifts it: the shot leaves at frame 5"
btOk = BD_Parse%(BT_Src$("    LASER from=100,100,0 to=200,100,0 color=ff0000 every=60 speed=10 jitter=20"))
btN = 0 : btOk = -1
For btF = 0 To 599
    If BD_LaserHead%(0, btF, 0, btDepth) Then
        If btDepth = 0 Then
            btN = btN + 1
            If btF Mod 60 > 20 Then btOk = 0
        End If
    End If
Next btF
BT_Assert btN = 10 And btOk,                            "14.36  jitter delays each shot by up to that many frames, one shot per every"
btS = "" : btT = ""
For btF = 0 To 599
    If BD_LaserHead%(0, btF, 0, btDepth) Then btS = btS + Str$(btF) + ":" + Str$(btDepth) + ";"
Next btF
For btF = 0 To 599
    If BD_LaserHead%(0, btF, 0, btDepth) Then btT = btT + Str$(btF) + ":" + Str$(btDepth) + ";"
Next btF
BT_Assert btS = btT And Len(btS) > 0,                   "14.37  the same frames give the same bolts"
btOk = BD_Parse%(BT_Src$("    LASER from=1,1,0 to=300,1,0 color=ff0000 every=10 speed=1"))
btErr = BD_Validate$
BT_Assert InStr(btErr, "bolts would be in flight") > 0 And InStr(btErr, "line 2") > 0, "14.38  a shooter that could have more bolts than the limit in flight fails validation"
Print ""

Print "--- 15. Morse ---"
Dim btM As String
btOk = BD_Parse%(BT_Src$("    BLINK at=5,5 color=ffffff morse=sos unit=2 rest=10"))
BT_Assert btOk <> 0 And Len(bdMorse(0)) > 0,            "15.01  a morse blink parses"
BT_Assert bdMorse(0) = "10101" + "000" + "11101110111" + "000" + "10101", "15.02  SOS is dot dot dot, dash dash dash, dot dot dot, with letter gaps of 3"
' the on/off sequence a frame at a time: unit 2, so each slot is two frames
btS = ""
For btF = 0 To 2 * Len(bdMorse(0)) + 10 - 1
    If BD_BlinkLevel!(0, btF) > 0.5 Then btS = btS + "1" Else btS = btS + "0"
Next btF
btT = ""
For btI = 1 To Len(bdMorse(0))
    btT = btT + Mid$(bdMorse(0), btI, 1) + Mid$(bdMorse(0), btI, 1)
Next btI
btT = btT + String$(10, "0")
BT_Assert btS = btT,                                    "15.03  on/off per frame is the slots doubled for unit=2, then 10 dark frames of rest"
BT_Assert Len(bdMorse(0)) = 27,                        "15.04  SOS is 27 units"
BT_Assert BD_BlinkLevel!(0, 2 * Len(bdMorse(0)) + 10) = BD_BlinkLevel!(0, 0), "15.05  and then it repeats"
BT_Assert BD_BlinkLevel!(0, 1) = 1 And BD_BlinkLevel!(0, 2) = 0, "15.06  with no rise or fall a flash is hard-edged: lit 1 slot, dark 1 slot"
btOk = BD_Parse%(BT_Src$("    BLINK at=5,5 color=ffffff morse=sos unit=2 rest=10 phase=2"))
BT_Assert BD_BlinkLevel!(0, 0) = 0 And BD_BlinkLevel!(0, 2) = 1, "15.07  phase shifts the sequence"
btOk = BD_Parse%(BT_Src$("    BLINK at=5,5 color=ffffff morse=e unit=10 rise=4 fall=4"))
BT_Assert bdMorse(0) = "1",                             "15.08  E is one dot"
BT_Assert BD_BlinkLevel!(0, 0) = 0 And BD_BlinkLevel!(0, 2) > 0.4 And BD_BlinkLevel!(0, 2) < 0.6 And BD_BlinkLevel!(0, 4) = 1, "15.09  rise eases the flash in over those frames"
BT_Assert BD_BlinkLevel!(0, 6) = 1 And BD_BlinkLevel!(0, 8) > 0.4 And BD_BlinkLevel!(0, 8) < 0.6, "15.10  fall eases it out over the last frames of the flash"
btOk = BD_Parse%(BT_Src$("    BLINK at=5,5 color=ffffff morse=t unit=10 rise=30 fall=30"))
BT_Assert bdMorse(0) = "111" And BD_BlinkLevel!(0, 15) > 0.4 And BD_BlinkLevel!(0, 15) < 0.6 And BD_BlinkLevel!(0, 0) = 0, "15.11  ramps longer than the flash meet in the middle, never above the shorter ramp"
btOk = BD_Parse%(BT_Src$("    BLINK at=5,5 color=ffffff morse=a_b unit=1"))
BT_Assert bdMorse(0) = "10111" + "0000000" + "111010101", "15.12  a word gap is 7 dark units in all, between the words' symbols"
btOk = BD_Parse%(BT_Src$("    BLINK at=5,5 color=ffffff morse=5"))
BT_Assert bdMorse(0) = "101010101" And bdUnit(0) = 6, "15.13  digits work and unit defaults to 6"
btOk = BD_Parse%(BT_Src$("    BLINK at=5,5 color=ffffff morse=SoS"))
BT_Assert btOk <> 0 And Len(bdMorse(0)) = 27,         "15.14  the text is not case sensitive"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=5,5 color=ffffff morse=s.s"), 2, "only letters, digits and _"), "15.15  other characters are an error"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=5,5 color=ffffff morse=_sos"), 2, "single _"), "15.16  a leading _"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=5,5 color=ffffff morse=a__b"), 2, "single _"), "15.17  a doubled _"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=5,5 color=ffffff morse=sos hold=5"), 2, "hold cannot be used with morse"), "15.18  hold with morse"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=5,5 color=ffffff hold=5 unit=3"), 2, "unit only goes with morse"), "15.19  unit without morse"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=5,5 color=ffffff morse=sos unit=0"), 2, "unit must be"), "15.20  unit of at least 1"
BT_Assert BT_Fails%(BT_Src$("    BLINK at=5,5 color=ffffff morse=sossossossossossossossossos"), 2, "at most 24"), "15.21  too long"
BT_Assert BT_Fails%(BT_Src$("    SPARK at=5,5 color=ffffff morse=sos"), 2, "unknown SPARK key 'morse'"), "15.22  morse is a BLINK key only"
Print ""

Print "--- 16. SPRITE scale and bob ---"
Dim btSc As Single, btBX As Single, btBY As Single
Const btSprP = "    SPRITE img=tug at=0,0 to=100,0 frames=100 rest=20 pingpong=1"
btOk = BD_Parse%(BT_Src$(btSprP))
btVis = BD_SpriteState%(0, 40, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert btVis And btSc = 1 And btBX = 0 And btBY = 0, "16.01  no scale or bob: size 1, no hop"
btOk = BD_Parse%(BT_Src$(btSprP + " scale=2"))
btVis = BD_SpriteState%(0, 0, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert btSc = 2,                                     "16.02  one value is a fixed size ..."
btVis = BD_SpriteState%(0, 77, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert btSc = 2,                                     "16.03  ... all along the path"
btOk = BD_Parse%(BT_Src$(btSprP + " scale=0.5,2"))
BT_Assert btOk <> 0,                                    "16.04  two values parse"
btVis = BD_SpriteState%(0, 0, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert btVis And btSc = 0.5,                         "16.05  the start has the first size"
btVis = BD_SpriteState%(0, 50, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btSc - 1.25) < 0.001,                     "16.06  the middle is halfway between"
btVis = BD_SpriteState%(0, 110, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert btSc = 2,                                     "16.07  parked at the far end it has the second size"
btVis = BD_SpriteState%(0, 170, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btSc - 1.25) < 0.001 And Abs(btSX - 50) < 0.01, "16.08  on the return leg the size follows the position on the path"
btVis = BD_SpriteState%(0, 239, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert btSc = 0.5,                                   "16.09  parked at the start it has the first size again"
BT_Assert BT_Fails%(BT_Src$(btSprP + " scale=0.05"), 2, "scale must be 0.1 to 4"), "16.10  too small"
BT_Assert BT_Fails%(BT_Src$(btSprP + " scale=1,4.5"), 2, "scale must be 0.1 to 4"), "16.11  too big"
BT_Assert BT_Fails%(BT_Src$(btSprP + " scale=1,2,3"), 2, "at most 2"), "16.12  three values"
BT_Assert BT_Fails%(BT_Src$(btSprP + " scale=big"), 2, "scale must be numbers"), "16.13  not a number"
BT_Assert BT_Fails%(BT_Src$(btSprP + " scale=1,"), 2, "scale must be numbers"), "16.14  a trailing comma"
btOk = BD_Parse%(BT_Src$(btSprP + " bob=10,20"))
btVis = BD_SpriteState%(0, 10, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btBX) < 0.01 And Abs(btBY + 10) < 0.01,   "16.15  the hop peaks amp pixels up (the default angle, 270, is up on screen) halfway through a period"
btVis = BD_SpriteState%(0, 20, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btBX) < 0.01 And Abs(btBY) < 0.01,        "16.16  and is back on the ground at the end of it"
btVis = BD_SpriteState%(0, 30, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btBY + 10) < 0.01,                        "16.17  and hops again: |sin|, never below the ground"
btVis = BD_SpriteState%(0, 5, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert btBY < 0 And Abs(btBY + 10 * Sin(3.14159265 / 4)) < 0.01, "16.18  a quarter in is amp * sin(pi/4)"
btOk = BD_Parse%(BT_Src$(btSprP + " bob=10,20,0"))
btVis = BD_SpriteState%(0, 10, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btBX - 10) < 0.01 And Abs(btBY) < 0.01,   "16.19  angle 0 hops to the right"
btOk = BD_Parse%(BT_Src$(btSprP + " bob=10,20,90"))
btVis = BD_SpriteState%(0, 10, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btBX) < 0.01 And Abs(btBY - 10) < 0.01,   "16.20  angle 90 hops down (as dir= on SPARK)"
btOk = BD_Parse%(BT_Src$(btSprP + " scale=2,2 bob=10,20"))
btVis = BD_SpriteState%(0, 10, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btBY + 20) < 0.01,                        "16.21  the hop is multiplied by the size"
btOk = BD_Parse%(BT_Src$(btSprP + " scale=1,3 bob=10,20"))
btVis = BD_SpriteState%(0, 10, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btBY + 10 * btSc) < 0.01 And btSc > 1.1,  "16.22  with a size that changes it uses the current one"
btOk = BD_Parse%(BT_Src$(btSprP + " bob=10,20"))
btVis = BD_SpriteState%(0, 110, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert btVis And btBX = 0 And btBY = 0,              "16.23  parked at the far end it does not hop (frame 110 would be mid-hop)"
btVis = BD_SpriteState%(0, 130, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btBY + 10) < 0.01,                        "16.24  the return leg starts its hop count afresh"
btVis = BD_SpriteState%(0, 230, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert btBX = 0 And btBY = 0,                        "16.25  and it stands still at the start end too"
btOk = BD_Parse%(BT_Src$("    SPRITE img=tug at=0,0 to=100,0 frames=100 rest=20 bob=10,20"))
btVis = BD_SpriteState%(0, 10, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert Abs(btBY + 10) < 0.01,                        "16.26  a one-way sprite hops too"
btVis = BD_SpriteState%(0, 105, btSX, btSY, btFl, btSc, btBX, btBY)
BT_Assert btVis = 0,                                    "16.27  hidden during rest, so no hop to speak of"
BT_Assert BT_Fails%(BT_Src$(btSprP + " bob=10"), 2, "bob needs at least 2"), "16.28  amplitude only"
BT_Assert BT_Fails%(BT_Src$(btSprP + " bob=10,20,90,1"), 2, "bob takes at most 3"), "16.29  four values"
BT_Assert BT_Fails%(BT_Src$(btSprP + " bob=-1,20"), 2, "bob amplitude must be"), "16.30  negative amplitude"
BT_Assert BT_Fails%(BT_Src$(btSprP + " bob=99,20"), 2, "bob amplitude must be"), "16.31  huge amplitude"
BT_Assert BT_Fails%(BT_Src$(btSprP + " bob=5,1"), 2, "bob period must be"), "16.32  period under 2 frames"
BT_Assert BT_Fails%(BT_Src$(btSprP + " bob=5,20,400"), 2, "bob angle must be"), "16.33  angle over 360"
BT_Assert BT_Fails%(BT_Src$(btSprP + " bob=a,b"), 2, "bob must be numbers"), "16.34  not numbers"
btOk = BD_Parse%(BT_Src$("    SPRITE img=baggage_cart at=26,166 to=80,205 scale=0.3,0.75"))
BT_Assert btOk <> 0 And bdImg(0) = 2,                   "16.35  the baggage cart is the second image"
Print ""

Print "=== " + LTrim$(Str$(btPass + btFail)) + " tests: " _
    + LTrim$(Str$(btPass)) + " passed, " + LTrim$(Str$(btFail)) + " failed ==="
If btFail > 0 Then System 1 Else System 0
