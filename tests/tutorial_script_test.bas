' tutorial_script_test.bas -- the tutorial step runner and its script (#240)
'
' Drives src/sys/tutorial.bas with the real assets/tutorial.txt and the real gametext.txt:
'   1. the shipped script parses and validates clean: five lessons, every key a gametext block,
'      every spoken line short enough for the panel, every wait fed
'   2. parse failures name their line: unknown step, element, spawn type, condition, bad
'      counts and arguments
'   3. validation failures: no opening LESSON, a missing gametext key, a line too long for
'      two rows, a WAIT that nothing can satisfy (kills without ships, hit without ships)
'   4. the runner, with a simulated game: a SAY holds until its line has been spoken, each WAIT
'      holds until its condition, SPAWN / STREAM / HIGHLIGHT reach the outbox, WAIT dodge and
'      WAIT pickup ask for a bolt or canister while none is in flight
'   5. nothing advances on a timer: any number of frames with an idle player never moves a WAIT
'   6. skipping: a tap ends the line being spoken, the next-lesson key jumps to the next LESSON
'      (flushing, stream and highlight off), skipping the last lesson ends the script
'   7. the real script, played by a simulated pilot who does what each WAIT asks, finishes
'      having visited every lesson; one who does nothing never finishes
'   8. the narration skip key: tap vs hold, the 2-second hold, a key still held at the start
'   9. the first-play gate, the line wrapping, the pickup and condition tables
'
' Build: tools/dev test (builds and runs every test)
' Run:   builds/tutorial_script_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

$EMBED:'assets/tutorial.txt':'TUTSCRIPT'
$EMBED:'assets/gametext.txt':'GAMETEXT'
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'

Sub DBG_Print (msg As String) : End Sub

'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/sys/gametext.bas'
'$INCLUDE:'../src/sys/tutorial.bas'

Dim Shared tsPass As Integer, tsFail As Integer

Sub TS_Assert (condition As Integer, label As String)
    If condition Then
        Print "PASS  " + label
        tsPass = tsPass + 1
    Else
        Print "FAIL  " + label
        tsFail = tsFail + 1
    End If
End Sub

' The game's side of one frame: clears the one-shot inputs, ticks, and keeps what the runner asked for.
Dim Shared tsSaid As String, tsSpawned As String, tsSpawnedN As Integer, tsFed As String
Dim Shared tsFlushed As Integer, tsSilenced As Integer

Sub TS_World0
    Dim twI As Integer
    tutInMoved = 0 : tutInOrbit = 0 : tutInShots = 0 : tutInHits = 0 : tutInKills = 0 : tutInDodged = 0
    For twI = 1 To 3 : tutInGot(twI) = 0 : tutInPups(twI) = 0 : Next twI
    tutInBolts = 0 : tutInHazards = 0 : tutInSpeaking = 0 : tutInSkipLine = 0 : tutInSkipLesson = 0
End Sub

Sub TS_Frame
    TUT_Tick
    tsSaid = tutOutSay : tsSpawned = tutOutSpawn : tsSpawnedN = tutOutSpawnN : tsFed = tutOutFeed
    tsFlushed = tutOutFlush : tsSilenced = tutOutSilence
    ' the line takes a frame to start playing, as in the game
    If Len(tutOutSay) > 0 Then tutInSpeaking = -1
    tutInSkipLine = 0 : tutInSkipLesson = 0
End Sub

' Load a script from text, start it, and clear the simulated world.
Function TS_Run% (trSrc As String)
    TS_Run% = TUT_Parse%(trSrc)
    TS_World0
    TUT_Start
End Function

' The skip key held down for thN frames, then (thUp) let go for one: the events as "<event>@<frame>"
' while down, "<event>@up" for the release, nothing when there were none.
Function TS_Hold$ (thN As Long, thUp As Integer)
    Dim thI As Long, thEv As Integer, thOut As String
    For thI = 1 To thN
        thEv = TUT_SkipTick%(-1)
        If thEv <> 0 Then thOut = thOut + LTrim$(Str$(thEv)) + "@" + LTrim$(Str$(thI))
    Next thI
    If thUp Then
        thEv = TUT_SkipTick%(0)
        If thEv <> 0 Then thOut = thOut + LTrim$(Str$(thEv)) + "@up"
    End If
    TS_Hold$ = thOut
End Function

Function TS_Count% (tcHay As String, tcNeedle As String)
    Dim tcP As Integer, tcN As Integer
    tcP = InStr(tcHay, tcNeedle)
    Do While tcP > 0
        tcN = tcN + 1
        tcP = InStr(tcP + Len(tcNeedle), tcHay, tcNeedle)
    Loop
    TS_Count% = tcN
End Function

Function TS_Script$
    TS_Script$ = _EMBEDDED$("TUTSCRIPT")
End Function

' Back to the shipped gametext after a test loaded its own.
Sub TS_RealText
    GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
    GTEXT_Load _EMBEDDED$("GAMETEXT")
End Sub

Dim tsI As Integer, tsOk As Integer, tsN As Integer, tsS As String, tsFrames As Long, tsErr As String, tsGot As String
Dim tsLines(0 To 3) As String

Print "=== tutorial_script_test ==="
Print ""

TS_RealText

Print "--- 1. the shipped script ---"
tsOk = TUT_Parse%(TS_Script$)
TS_Assert tsOk <> 0 And Len(tutErrors) = 0,       "1.01  tutorial.txt parses clean"
tsErr = TUT_Validate$
TS_Assert Len(tsErr) = 0,                         "1.02  it validates clean"
If Len(tsErr) > 0 Then Print tsErr
TS_Assert tutLessonCount = 5,                     "1.03  five lessons"
TS_Assert tutOp(0) = TUT_LESSON,                  "1.04  it opens with a LESSON"
tsN = 0 : tsFrames = 0
For tsI = 0 To tutCount - 1
    If tutOp(tsI) = TUT_SAY Then tsN = tsN + 1
    If tutOp(tsI) = TUT_WAIT Then tsFrames = tsFrames + 1
Next tsI
TS_Assert tsN >= 25,                              "1.05  at least 25 spoken lines (" + LTrim$(Str$(tsN)) + ")"
TS_Assert tsFrames >= 8,                          "1.06  at least 8 waits on the player (" + LTrim$(Str$(tsFrames)) + ")"
tsOk = -1
For tsI = 0 To tutCount - 1
    If tutOp(tsI) = TUT_SAY Then
        TUT_Wrap TUT_Text$(tutKey(tsI)), TUT_WRAP_W, tsLines(), tsN
        If tsN > 2 Or tsN = 0 Then tsOk = 0 : Print "      too long: " + tutKey(tsI)
    End If
Next tsI
TS_Assert tsOk <> 0,                              "1.07  every SAY fits two rows of the panel"
tsOk = 0
For tsI = 0 To tutCount - 1
    If tutOp(tsI) = TUT_SPAWN And tutKey(tsI) = "ship" Then tsOk = -1
    If tutOp(tsI) = TUT_STREAM And tutKey(tsI) = "ship" Then tsOk = -1
Next tsI
TS_Assert tsOk <> 0,                              "1.08  drones come (STREAM or SPAWN ship)"
tsOk = 0
For tsI = 0 To tutCount - 1
    If tutOp(tsI) = TUT_WAIT And tutFlag(tsI) = TUT_C_KILLS And tutNum(tsI) = 3 Then tsOk = -1
Next tsI
TS_Assert tsOk <> 0,                              "1.09  drones keep coming until 3 are shot down"
tsOk = -1
For tsI = 0 To tutCount - 1
    If tutOp(tsI) = TUT_LESSON Then
        If Len(TUT_Text$(tutKey(tsI))) = 0 Then tsOk = 0
    End If
Next tsI
TS_Assert tsOk <> 0,                              "1.10  every lesson has a title"
Print ""

Print "--- 2. parse failures ---"
tsOk = TUT_Parse%("LESSON a" + Chr$(10) + "FLY a")
TS_Assert tsOk = 0 And InStr(tutErrors, "line 2: unknown step 'FLY'") > 0, "2.01  an unknown step, with its line"
tsOk = TUT_Parse%("HIGHLIGHT moon")
TS_Assert tsOk = 0 And InStr(tutErrors, "line 1: unknown HIGHLIGHT element 'moon'") > 0, "2.02  an unknown HIGHLIGHT element"
tsOk = TUT_Parse%("SPAWN dragon")
TS_Assert tsOk = 0 And InStr(tutErrors, "unknown SPAWN type 'dragon'") > 0, "2.03  an unknown SPAWN type"
tsOk = TUT_Parse%("SPAWN ship count=0")
TS_Assert tsOk = 0 And InStr(tutErrors, "count=1 to count=8") > 0, "2.04  SPAWN count 0"
tsOk = TUT_Parse%("SPAWN ship count=9")
TS_Assert tsOk = 0,   "2.05  SPAWN count 9"
tsOk = TUT_Parse%("SPAWN ship 3")
TS_Assert tsOk = 0,         "2.06  SPAWN count without count="
tsOk = TUT_Parse%("WAIT dream")
TS_Assert tsOk = 0 And InStr(tutErrors, "unknown WAIT condition 'dream'") > 0, "2.07  an unknown WAIT condition"
tsOk = TUT_Parse%("WAIT")
TS_Assert tsOk = 0,                 "2.08  WAIT with nothing"
tsOk = TUT_Parse%("WAIT kills")
TS_Assert tsOk = 0,           "2.09  WAIT kills needs a count"
tsOk = TUT_Parse%("WAIT kills x")
TS_Assert tsOk = 0,         "2.10  WAIT kills with text"
tsOk = TUT_Parse%("WAIT kills 0")
TS_Assert tsOk = 0,         "2.11  WAIT kills 0"
tsOk = TUT_Parse%("WAIT pickup rock")
TS_Assert tsOk = 0 And InStr(tutErrors, "shield, fuel or points") > 0, "2.12  WAIT pickup of an unknown kind"
tsOk = TUT_Parse%("WAIT pickup")
TS_Assert tsOk = 0,          "2.13  WAIT pickup with no kind"
tsOk = TUT_Parse%("WAIT camera now")
TS_Assert tsOk = 0,      "2.14  WAIT camera takes no argument"
tsOk = TUT_Parse%("WAIT move 1 2")
TS_Assert tsOk = 0,        "2.15  too many arguments"
tsOk = TUT_Parse%("WAIT move 0")
TS_Assert tsOk = 0,          "2.16  WAIT move 0"
tsOk = TUT_Parse%("STREAM ship kills=0")
TS_Assert tsOk = 0,  "2.17  STREAM kills=0"
tsOk = TUT_Parse%("STREAM ship wings")
TS_Assert tsOk = 0 And InStr(tutErrors, "unknown STREAM option") > 0, "2.18  an unknown STREAM option"
tsOk = TUT_Parse%("STREAM boss")
TS_Assert tsOk = 0,          "2.19  STREAM of something that is not a ship"
tsOk = TUT_Parse%("STREAM off now")
TS_Assert tsOk = 0,       "2.20  STREAM off takes nothing more"
tsOk = TUT_Parse%("SAY")
TS_Assert tsOk = 0,          "2.21  SAY takes a key"
tsOk = TUT_Parse%("LESSON")
TS_Assert tsOk = 0,          "2.21b LESSON takes a key"
tsOk = TUT_Parse%("SAY a b")
TS_Assert tsOk = 0,          "2.21c SAY takes one key"
tsOk = TUT_Parse%("HIGHLIGHT")
TS_Assert tsOk = 0,            "2.22  HIGHLIGHT takes an element"
tsS = ""
For tsI = 1 To TUT_MAX + 1 : tsS = tsS + "SAY a" + Chr$(10) : Next tsI
tsOk = TUT_Parse%(tsS)
TS_Assert tsOk = 0 And InStr(tutErrors, "more than TUT_MAX") > 0, "2.23  more steps than TUT_MAX"
tsOk = TUT_Parse%("; a comment" + Chr$(10) + Chr$(10) + "  say  Hello  " + Chr$(13) + Chr$(10) + "Wait Move")
TS_Assert tsOk <> 0 And tutCount = 2, "2.24  comments, blank lines, case, spaces and CRLF are fine"
tsOk = TUT_Parse%("SPAWN ship" + Chr$(10) + "SPAWN bogus" + Chr$(10) + "WAIT nope")
TS_Assert tsOk = 0 And TS_Count%(tutErrors, "line ") = 2, "2.25  every bad line is reported, not only the first"
tsOk = TUT_Parse%("LESSON x" + Chr$(10) + "WAIT hit 2" + Chr$(10) + "WAIT shoot" + Chr$(10) + "WAIT dodge" + Chr$(10) + "WAIT clear" + Chr$(10) + "WAIT camera")
TS_Assert tsOk <> 0 And tutNum(1) = 2 And tutNum(2) = 1 And tutNum(3) = 1, "2.26  counts default to 1"
tsOk = TUT_Parse%("WAIT move")
TS_Assert tsOk <> 0 And tutNum(0) = 12, "2.27  WAIT move defaults to 12 units"
tsOk = TUT_Parse%("STREAM ship")
TS_Assert tsOk <> 0 And tutNum(0) = 3 And tutFlag(0) = 0, "2.28  STREAM defaults to 3 kills, no return fire"
tsOk = TUT_Parse%("STREAM ship fire kills=5")
TS_Assert tsOk <> 0 And tutNum(0) = 5 And tutFlag(0) <> 0, "2.29  STREAM fire kills=5"
Print ""

Print "--- 3. validation failures ---"
GTEXT_Load "[BLOCK:ok]" + Chr$(10) + "Short line." + Chr$(10) + Chr$(10) + "[BLOCK:long]" + Chr$(10) + "This line is far too long to fit on the two rows that the tutorial panel has, so it must be refused." + Chr$(10) + Chr$(10) + "[BLOCK:two]" + Chr$(10) + "Exactly as many words as fit" + Chr$(10) + "on two rows, no more." + Chr$(10)
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "SAY ok")
TS_Assert tsOk <> 0 And Len(TUT_Validate$) = 0,   "3.01  a small clean script validates"
tsOk = TUT_Parse%("SAY ok")
TS_Assert InStr(TUT_Validate$, "must open with a LESSON") > 0, "3.02  a script that does not open with a LESSON"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "SAY nowhere")
TS_Assert InStr(TUT_Validate$, "line 2: no gametext block 'nowhere'") > 0, "3.03  a SAY key that is no gametext block"
tsOk = TUT_Parse%("LESSON gone")
TS_Assert InStr(TUT_Validate$, "no gametext block 'gone'") > 0, "3.04  a LESSON key that is no gametext block"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "SAY long")
TS_Assert InStr(TUT_Validate$, "'long' is longer than two lines") > 0, "3.05  a line too long for two rows"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "SAY two")
TS_Assert Len(TUT_Validate$) = 0,                 "3.06  a line of exactly two rows is fine"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "WAIT kills 2")
TS_Assert InStr(TUT_Validate$, "WAIT kills 2 but no STREAM or SPAWN ship") > 0, "3.07  WAIT kills with no ships coming"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "STREAM ship kills=1" + Chr$(10) + "WAIT kills 2")
TS_Assert InStr(TUT_Validate$, "WAIT kills 2 but no STREAM") > 0, "3.08  WAIT kills beyond what the stream brings"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "STREAM ship kills=2" + Chr$(10) + "WAIT kills 2")
TS_Assert Len(TUT_Validate$) = 0,                 "3.09  WAIT kills within the stream"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "SPAWN ship count=2" + Chr$(10) + "WAIT kills 2")
TS_Assert Len(TUT_Validate$) = 0,                 "3.10  WAIT kills within the ships spawned"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "STREAM ship kills=3" + Chr$(10) + "STREAM off" + Chr$(10) + "WAIT kills 3")
TS_Assert InStr(TUT_Validate$, "WAIT kills 3 but no STREAM") > 0, "3.11  a stream switched off brings nothing"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "WAIT hit")
TS_Assert InStr(TUT_Validate$, "WAIT hit but no ship is coming") > 0, "3.12  WAIT hit with no ships coming"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "STREAM ship" + Chr$(10) + "LESSON ok" + Chr$(10) + "WAIT kills 1")
TS_Assert InStr(TUT_Validate$, "WAIT kills 1 but no STREAM") > 0, "3.13  a stream does not carry into the next lesson (a lesson skip clears it)"
tsOk = TUT_Parse%("LESSON ok" + Chr$(10) + "FLY")
TS_Assert Left$(TUT_Validate$, 5) = "line " And InStr(TUT_Validate$, "unknown step") > 0, "3.14  parse problems lead the validation"
tsOk = TUT_Parse%("")
TS_Assert InStr(TUT_Validate$, "no steps") > 0,   "3.15  an empty script"
TS_RealText
Print ""

Print "--- 4. the runner ---"
GTEXT_Load "[BLOCK:l]" + Chr$(10) + "Lesson" + Chr$(10) + Chr$(10) + "[BLOCK:a]" + Chr$(10) + "Line a." + Chr$(10) + Chr$(10) + "[BLOCK:b]" + Chr$(10) + "Line b." + Chr$(10)
tsOk = TS_Run%("LESSON l" + Chr$(10) + "HIGHLIGHT fu" + Chr$(10) + "SAY a" + Chr$(10) + "WAIT move 10" + Chr$(10) + "HIGHLIGHT off" + Chr$(10) + "SAY b")
TS_Frame
TS_Assert tsSaid = "a" And tutSayKey = "a" And tutSayOn <> 0, "4.01  the first frame starts line a (and applies the instant steps before it)"
TS_Assert tutLesson = 1 And tutLessonKey = "l" And tutHL = "fu", "4.02  lesson 1 is on, fu highlighted"
TS_Frame
TS_Assert tsSaid = "" And tutPc = 2,              "4.03  a line is not asked for twice while it plays"
For tsI = 1 To 50 : TS_Frame : Next tsI
TS_Assert tutPc = 2 And tutSayOn <> 0,            "4.04  it holds while the line is still speaking"
tutInSpeaking = 0
TS_Frame
TS_Assert tutPc = 3 And tutSayOn = 0 And tutWaitCond = TUT_C_MOVE, "4.05  the line ends when the speech ends, and the WAIT begins"
TS_Assert tutSayKey = "a",                        "4.06  the line stays on screen during the wait"
tutInMoved = 9.9
TS_Frame
TS_Assert tutPc = 3,                              "4.07  9.9 of 10 units: still waiting"
tutInMoved = 10.5
TS_Frame
TS_Assert tutHL = "" And tsSaid = "b" And tutPc = 5, "4.08  10 units flown: the highlight clears and line b starts in the same frame"
tutInSpeaking = 0
TS_Frame
TS_Assert tutDone <> 0 And tutActive = 0,         "4.09  the last step ends the script"
TS_Frame
TS_Assert tsSaid = "" And tutDone <> 0,           "4.10  a finished script does nothing more"

tsOk = TS_Run%("LESSON l" + Chr$(10) + "WAIT camera" + Chr$(10) + "SAY a")
TS_Frame
TS_Assert tutPc = 1 And tutWaitCond = TUT_C_CAMERA, "4.11  WAIT camera holds"
tutInOrbit = -1 : TS_Frame
TS_Assert tutPc = 1,                              "4.12  camera mode on: still holds"
tutInOrbit = 0 : TS_Frame
TS_Assert tsSaid = "a",                           "4.13  camera mode left: the wait is over"
tsOk = TS_Run%("LESSON l" + Chr$(10) + "WAIT camera" + Chr$(10) + "SAY a")
tutInOrbit = -1 : TS_Frame
TS_Assert tutPc = 1,                              "4.14  camera mode already on when the wait begins: not enough"
tutInOrbit = 0 : TS_Frame
TS_Assert tsSaid = "a",                           "4.15  ...leaving it is"

tsOk = TS_Run%("LESSON l" + Chr$(10) + "WAIT shoot 3" + Chr$(10) + "WAIT hit 2" + Chr$(10) + "SAY a")
tutInShots = 100 : tutInHits = 50
TS_Frame
TS_Assert tutPc = 1,                              "4.16  shots before the wait began do not count"
tutInShots = 102 : TS_Frame
TS_Assert tutPc = 1,                              "4.17  2 of 3 shots"
tutInShots = 103 : TS_Frame
TS_Assert tutPc = 2,                              "4.18  3 shots: on to the hits"
tutInHits = 51 : TS_Frame
TS_Assert tutPc = 2,                              "4.19  1 of 2 hits"
tutInHits = 52 : TS_Frame
TS_Assert tsSaid = "a",                           "4.20  2 hits: the next step runs"

tsOk = TS_Run%("LESSON l" + Chr$(10) + "STREAM ship kills=3 fire" + Chr$(10) + "WAIT kills 2" + Chr$(10) + "SAY a")
TS_Frame
TS_Assert tutStreamOn <> 0 And tutStreamKills = 3 And tutStreamFire <> 0, "4.21  STREAM is on, 3 kills, with fire"
tutInKills = 1 : TS_Frame
TS_Assert tutPc = 2 And tutStreamOn <> 0,         "4.22  1 kill: waiting, stream still on"
tutInKills = 2 : TS_Frame
TS_Assert tsSaid = "a" And tutStreamOn <> 0,      "4.23  2 kills: on, the stream keeps going to 3"
tutInKills = 3 : TS_Frame
TS_Assert tutStreamOn = 0,                        "4.24  3 kills: the stream ends"
tsOk = TS_Run%("LESSON l" + Chr$(10) + "STREAM ship kills=2" + Chr$(10) + "STREAM off" + Chr$(10) + "SAY a")
TS_Frame
TS_Assert tutStreamOn = 0 And tsSaid = "a",       "4.25  STREAM off"

tsOk = TS_Run%("LESSON l" + Chr$(10) + "SPAWN fuel" + Chr$(10) + "SPAWN ship count=3" + Chr$(10) + "SAY a")
TS_Frame
TS_Assert tsSpawned = "fuel" And tsSpawnedN = 1 And tutPc = 2, "4.26  SPAWN reaches the outbox and uses the frame"
TS_Frame
TS_Assert tsSpawned = "ship" And tsSpawnedN = 3,  "4.27  SPAWN ship count=3"
TS_Frame
TS_Assert tsSpawned = "" And tsSaid = "a",        "4.28  one request per frame, then the line"

tsOk = TS_Run%("LESSON l" + Chr$(10) + "WAIT dodge 2" + Chr$(10) + "SAY a")
TS_Frame
TS_Assert tsFed = "bolt",                         "4.29  WAIT dodge asks for a bolt when none is in flight"
tutInBolts = 1 : TS_Frame
TS_Assert tsFed = "",                             "4.30  ...and not while one is"
tutInBolts = 0 : tutInDodged = 1 : TS_Frame
TS_Assert tsFed = "bolt" And tutPc = 1,           "4.31  one dodged, one more needed: asks again"
tutInDodged = 2 : TS_Frame
TS_Assert tsSaid = "a",                           "4.32  two dodged: on"

tsOk = TS_Run%("LESSON l" + Chr$(10) + "WAIT pickup fuel" + Chr$(10) + "SAY a")
TS_Frame
TS_Assert tsFed = "fuel",                         "4.33  WAIT pickup fuel asks for a fuel canister"
tutInPups(1) = 1 : tutInPups(3) = 1 : TS_Frame
TS_Assert tsFed = "fuel",                         "4.34  other kinds in flight do not count"
tutInPups(2) = 1 : TS_Frame
TS_Assert tsFed = "",                             "4.35  one in flight: no more asked"
tutInGot(1) = 4 : TS_Frame
TS_Assert tutPc = 1,                              "4.36  a shield canister is not a fuel canister"
tutInGot(2) = 1 : TS_Frame
TS_Assert tsSaid = "a",                           "4.37  a fuel canister caught: on"

tsOk = TS_Run%("LESSON l" + Chr$(10) + "WAIT clear" + Chr$(10) + "SAY a")
tutInHazards = 1 : TS_Frame
TS_Assert tutPc = 1,                              "4.38  WAIT clear holds while an asteroid is in flight"
tutInHazards = 0 : TS_Frame
TS_Assert tsSaid = "a",                           "4.39  clear: on"
Print ""

Print "--- 5. nothing advances on a timer ---"
tsOk = TS_Run%("LESSON l" + Chr$(10) + "SAY a" + Chr$(10) + "WAIT move" + Chr$(10) + "WAIT shoot" + Chr$(10) + "SAY b")
TS_Frame
tutInSpeaking = -1
For tsFrames = 1 To 200000 : TS_Frame : Next tsFrames
TS_Assert tutPc = 1 And tutDone = 0,              "5.01  a line still being spoken holds for 200000 frames"
tutInSpeaking = 0
TS_Frame
For tsFrames = 1 To 200000 : TS_Frame : Next tsFrames
TS_Assert tutPc = 2 And tutDone = 0,              "5.02  WAIT move holds for 200000 idle frames"
tutInMoved = 50 : TS_Frame
For tsFrames = 1 To 200000 : TS_Frame : Next tsFrames
TS_Assert tutPc = 3 And tutDone = 0,              "5.03  WAIT shoot holds for 200000 idle frames"
tsOk = TUT_Parse%(TS_Script$)
tsOk = -1
For tsI = 0 To tutCount - 1
    If tutOp(tsI) < TUT_LESSON Or tutOp(tsI) > TUT_STREAM Then tsOk = 0
Next tsI
TS_Assert tsOk <> 0,                              "5.05  every step is one of LESSON SAY HIGHLIGHT WAIT SPAWN STREAM"
Print ""

Print "--- 6. skipping ---"
GTEXT_Load "[BLOCK:l]" + Chr$(10) + "Lesson" + Chr$(10) + Chr$(10) + "[BLOCK:a]" + Chr$(10) + "Line a." + Chr$(10) + Chr$(10) + "[BLOCK:b]" + Chr$(10) + "Line b." + Chr$(10) + Chr$(10) + "[BLOCK:c]" + Chr$(10) + "Line c." + Chr$(10)
tsOk = TS_Run%("LESSON l" + Chr$(10) + "SAY a" + Chr$(10) + "SAY b" + Chr$(10) + "WAIT move" + Chr$(10) + "LESSON l" + Chr$(10) + "STREAM ship" + Chr$(10) + "HIGHLIGHT sh" + Chr$(10) + "SAY c" + Chr$(10) + "WAIT kills 1" + Chr$(10) + "LESSON l" + Chr$(10) + "SAY a")
TS_Frame
tutInSkipLine = -1 : TS_Frame
TS_Assert tsSilenced <> 0 And tsSaid = "b",       "6.01  a tap ends the line being spoken and the next one starts at once"
TS_Assert tutLesson = 1,                          "6.02  ...in the same lesson"
tutInSkipLine = -1 : TS_Frame
TS_Assert tsSilenced <> 0 And tutWaitCond = TUT_C_MOVE, "6.03  a second tap: on to the WAIT"
tutInSkipLine = -1 : TS_Frame
TS_Assert tutPc = 3 And tsSilenced = 0,           "6.04  a tap while waiting skips nothing (the WAIT is the player's)"
tutInSkipLesson = -1 : TS_Frame
TS_Assert tutLesson = 2 And tsFlushed <> 0 And tsSilenced <> 0, "6.05  the lesson key jumps to the next lesson, flushing the world and silencing the line"
TS_Frame
TS_Assert tutStreamOn <> 0 And tutHL = "sh" And tutSayKey = "c", "6.07  the new lesson sets up its stream, highlight and line"
tutInSkipLesson = -1 : TS_Frame
TS_Assert tutLesson = 3 And tutStreamOn = 0 And tutHL = "",  "6.08  skipping again: stream off, highlight cleared"
tutInSkipLesson = -1 : TS_Frame
TS_Assert tutDone <> 0,                           "6.09  skipping the last lesson ends the script"
tsOk = TS_Run%("LESSON l" + Chr$(10) + "SAY a" + Chr$(10) + "SAY b")
TS_Frame
tutInSkipLine = -1 : tutInSkipLesson = -1 : TS_Frame
TS_Assert tutDone <> 0 And tsSaid = "",           "6.10  a lesson skip in the only lesson ends the script"
tsOk = TS_Run%("LESSON l" + Chr$(10) + "SAY a" + Chr$(10) + "SAY b")
TS_Frame
tutInSkipLine = -1 : TS_Frame
TS_Assert tutSayKey = "b" And tutDone = 0 And tutSayOn <> 0, "6.11  one tap skips one line, not the one that follows"
tutInSkipLine = -1 : TS_Frame
TS_Assert tutDone <> 0,                           "6.12  skipping the last line ends the script"
TS_RealText
Print ""

Print "--- 7. the real script, played by a simulated pilot ---"
' The pilot does what the WAIT in force asks, one frame at a time. The speech takes 40 frames.
Dim tsSpeakLeft As Long, tsLessonsSeen As String, tsAsked As String
tsOk = TS_Run%(TS_Script$)
tsLessonsSeen = "" : tsSpeakLeft = 0 : tsAsked = ""
For tsFrames = 1 To 100000
    ' the game's side of the frame
    If tsSpeakLeft > 0 Then tsSpeakLeft = tsSpeakLeft - 1
    tutInSpeaking = (tsSpeakLeft > 0)
    Select Case tutWaitCond
        Case TUT_C_MOVE : tutInMoved = tutInMoved + 0.5
        Case TUT_C_CAMERA : tutInOrbit = Not tutInOrbit
        Case TUT_C_SHOOT : tutInShots = tutInShots + 1
        Case TUT_C_HIT : tutInHits = tutInHits + 1
        Case TUT_C_KILLS : If tsFrames Mod 20 = 0 Then tutInKills = tutInKills + 1
        Case TUT_C_DODGE : If tsFed = "bolt" Then tutInDodged = tutInDodged + 1
        Case TUT_C_PICKUP
            If tsFed <> "" Then tutInGot(TUT_PickupIdx%(tsFed)) = tutInGot(TUT_PickupIdx%(tsFed)) + 1
        Case TUT_C_CLEAR : tutInHazards = 0
    End Select
    TUT_Tick
    tsFed = tutOutFeed
    If Len(tutOutSay) > 0 Then tsSpeakLeft = 40
    If tutOutSpawn = "asteroid" Then tutInHazards = 1
    If InStr(tsLessonsSeen, "," + LTrim$(Str$(tutLesson)) + ",") = 0 Then tsLessonsSeen = tsLessonsSeen + "," + LTrim$(Str$(tutLesson)) + ","
    If tutDone Then Exit For
Next tsFrames
TS_Assert tutDone <> 0,                           "7.01  the simulated pilot finishes the real script (frame " + LTrim$(Str$(tsFrames)) + ")"
TS_Assert tutLesson = 5 And InStr(tsLessonsSeen, ",1,") > 0 And InStr(tsLessonsSeen, ",2,") > 0 And InStr(tsLessonsSeen, ",3,") > 0 And InStr(tsLessonsSeen, ",4,") > 0 And InStr(tsLessonsSeen, ",5,") > 0, "7.02  it went through all five lessons"
TS_Assert tutActive = 0 And tutPc = tutCount,     "7.03  at the end of the table"

tsOk = TS_Run%(TS_Script$)
tsSpeakLeft = 0
For tsFrames = 1 To 100000
    If tsSpeakLeft > 0 Then tsSpeakLeft = tsSpeakLeft - 1
    tutInSpeaking = (tsSpeakLeft > 0)
    TUT_Tick
    If Len(tutOutSay) > 0 Then tsSpeakLeft = 40
    If tutDone Then Exit For
Next tsFrames
TS_Assert tutDone = 0 And tutWaitCond = TUT_C_MOVE And tutLesson = 1, "7.04  a pilot who does nothing waits at the first WAIT forever"

tsOk = TS_Run%(TS_Script$)
tsSpeakLeft = 0 : tsN = 0
For tsFrames = 1 To 100000
    If tsSpeakLeft > 0 Then tsSpeakLeft = tsSpeakLeft - 1
    tutInSpeaking = (tsSpeakLeft > 0)
    If tsFrames Mod 10 = 0 Then tutInSkipLesson = -1
    TUT_Tick
    tutInSkipLesson = 0
    If Len(tutOutSay) > 0 Then tsSpeakLeft = 40
    If tutOutFlush Then tsN = tsN + 1
    If tutDone Then Exit For
Next tsFrames
TS_Assert tutDone <> 0 And tsN = 5,               "7.05  pressing the lesson key through the real script ends it after 5 skips"
Print ""

Print "--- 8. the narration skip key ---"
TUT_SkipReset 0
TS_Assert TS_Hold$(1, -1) = "1@up",               "8.01  a one-frame press is a tap, seen when it is released"
TUT_SkipReset 0
TS_Assert TS_Hold$(TUT_TAP_FRAMES, -1) = "1@up",  "8.02  held " + LTrim$(Str$(TUT_TAP_FRAMES)) + " frames is still a tap"
TUT_SkipReset 0
TS_Assert TS_Hold$(TUT_TAP_FRAMES + 1, -1) = "",  "8.03  held " + LTrim$(Str$(TUT_TAP_FRAMES + 1)) + " frames and let go: nothing (a half-made hold skips no line)"
TUT_SkipReset 0
TS_Assert TS_Hold$(TUT_HOLD_FRAMES - 1, -1) = "", "8.04  held " + LTrim$(Str$(TUT_HOLD_FRAMES - 1)) + " frames and let go: nothing, no exit"
TUT_SkipReset 0
tsGot = TS_Hold$(TUT_HOLD_FRAMES + 60, 0)
TS_Assert tsGot = "2@" + LTrim$(Str$(TUT_HOLD_FRAMES)), "8.05  held 2 seconds: exit on frame " + LTrim$(Str$(TUT_HOLD_FRAMES)) + ", once, however long it stays down (" + tsGot + ")"
TS_Assert TS_Hold$(0, -1) = "",                   "8.06  letting go after the exit is not a tap"
TUT_SkipReset -1
TS_Assert TS_Hold$(TUT_HOLD_FRAMES * 3, -1) = "", "8.07  a key still down from the menu that started the tutorial never counts, nor does its release"
TS_Assert TS_Hold$(1, -1) = "1@up",               "8.08  after that it works as usual"
TUT_SkipReset 0
tsGot = TS_Hold$(1, -1)
tsGot = tsGot + TS_Hold$(1, -1)
tsGot = tsGot + TS_Hold$(1, -1)
TS_Assert tsGot = "1@up1@up1@up",         "8.09  three taps are three taps"
TUT_SkipReset 0
tsGot = TS_Hold$(100, -1)
TS_Assert tsGot = "",                             "8.10  100 frames and let go: nothing"
TS_Assert TS_Hold$(TUT_HOLD_FRAMES, 0) = "2@" + LTrim$(Str$(TUT_HOLD_FRAMES)), "8.11  a hold abandoned and started again restarts from zero"
TS_Assert TUT_HOLD_FRAMES = 120,                  "8.12  the hold is 120 frames, 2 seconds at 60 fps"
Print ""

Print "--- 9. the first-play gate, wrapping, tables ---"
TS_Assert TUT_GateDue%(0, 0, "", 0) <> 0,         "9.01  a fresh install (not done, no script, no scene, writable): gated"
TS_Assert TUT_GateDue%(-1, 0, "", 0) = 0,         "9.02  done: not gated"
TS_Assert TUT_GateDue%(0, -1, "", 0) = 0,         "9.03  a scripted run bypasses the gate"
TS_Assert TUT_GateDue%(0, 0, "boss3", 0) = 0,     "9.04  a --scene run bypasses the gate"
TS_Assert TUT_GateDue%(0, 0, "title", 0) = 0,     "9.05  --scene title too"
TS_Assert TUT_GateDue%(0, 0, "", -1) = 0,         "9.06  a session that cannot save the answer is not nagged every launch"
TUT_Wrap "alpha beta gamma delta", 11, tsLines(), tsN
TS_Assert tsN = 2 And tsLines(0) = "alpha beta" And tsLines(1) = "gamma delta", "9.07  wrapping at word boundaries"
TUT_Wrap "short", 36, tsLines(), tsN
TS_Assert tsN = 1 And tsLines(0) = "short",       "9.08  a short line is one row"
TUT_Wrap "abcdefghijklmnop", 5, tsLines(), tsN
TS_Assert tsN = 1 And tsLines(0) = "abcde",       "9.09  a word longer than the row is cut"
TUT_Wrap "", 10, tsLines(), tsN
TS_Assert tsN = 0,                                "9.10  nothing is zero rows"
TS_Assert TUT_PickupIdx%("shield") = 1 And TUT_PickupIdx%("fuel") = 2 And TUT_PickupIdx%("points") = 3 And TUT_PickupIdx%("x") = 0, "9.11  pickup kinds"
TS_Assert TUT_CondId%("move") = TUT_C_MOVE And TUT_CondId%("clear") = TUT_C_CLEAR And TUT_CondId%("nope") = 0, "9.12  conditions"
TS_Assert TUT_ElementOk%("reticle") <> 0 And TUT_ElementOk%("off") <> 0 And TUT_ElementOk%("psc") = 0, "9.13  highlight elements (no PSC readout in the tutorial)"
Print ""

Print "=== " + LTrim$(Str$(tsPass + tsFail)) + " tests: " _
    + LTrim$(Str$(tsPass)) + " passed, " + LTrim$(Str$(tsFail)) + " failed ==="
If tsFail > 0 Then System 1 Else System 0
