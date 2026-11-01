' tutorial.bas -- the tutorial step runner (#240)
'
' A linear script (assets/tutorial.txt) run one frame at a time. The runner knows nothing
' about the game: the caller (src/state/tutorialplay.bas) fills the tutIn* snapshot before each
' TUT_Tick and acts on the tutOut* requests after it, so tests can drive it with plain numbers.
' Nothing advances on a timer: a SAY ends when the spoken line has finished (the speech clock
' counts game frames, #329) or is skipped, and a WAIT ends only when the player has done it.
'
' Script lines (one step each; ; starts a comment; verbs are case-insensitive):
'   LESSON <key>              start of a lesson; <key> is a gametext block holding its title
'   SAY <key>                 the instructor speaks gametext block <key> and shows it on screen
'   HIGHLIGHT <element>       outline a HUD element: sh la fu score hi lives reticle; off clears it
'   SPAWN <type> [count=<n>]  put objects in play at once: ship bolt asteroid shield fuel points
'   STREAM ship [kills=<n>] [fire]  keep drones coming (never more than two at a time, and
'                             never more than the kills still needed) until n are shot down
'                             (default 3); fire = they shoot back. STREAM off stops it
'   WAIT <condition> [arg]    hold the script until the player has:
'                               move [dist]   flown dist units in all (default 12)
'                               camera        entered camera mode and left it
'                               shoot [n]     fired n shots (default 1)
'                               hit [n]       landed n shots on a drone (default 1)
'                               kills <n>     shot down n drones in all
'                               dodge [n]     let n enemy bolts pass without a hit (default 1);
'                                             a bolt is fed to them while none is in flight
'                               pickup <kind> caught a shield, fuel or points canister; one is
'                                             fed to them while none is in flight
'                               clear         no asteroid left in flight
' A lesson skip (the next-lesson key) jumps to the next LESSON line with the stream off and the
' highlight cleared, so a lesson must start by saying what it needs (STREAM, SPAWN).
'
' TUT_Parse%(src)    1 when the script loaded clean, else 0 with tutErrors$ (one "line N: ..." each)
' TUT_Validate$()    "" when sound (see the checks below), else one problem per line
' TUT_Start          begin a run at the first step
' TUT_Tick           one frame; needs tutIn* filled, leaves tutOut* requests and tutDone
' TUT_SkipTick%(d)   the narration skip key, d = down this frame: TUT_SKIP_TAP on a short tap,
'                    TUT_SKIP_EXIT once held TUT_HOLD_FRAMES; never both for one press
' TUT_Wrap           break a line into at most two lines of a given width
' TUT_GateDue%       whether New Game should start the tutorial first
' Local variable prefix: tu*

Const TUT_MAX = 160
Const TUT_LESSON = 1
Const TUT_SAY = 2
Const TUT_HIGHLIGHT = 3
Const TUT_WAIT = 4
Const TUT_SPAWN = 5
Const TUT_STREAM = 6

Const TUT_C_MOVE = 1
Const TUT_C_CAMERA = 2
Const TUT_C_SHOOT = 3
Const TUT_C_HIT = 4
Const TUT_C_KILLS = 5
Const TUT_C_DODGE = 6
Const TUT_C_PICKUP = 7
Const TUT_C_CLEAR = 8

Const TUT_HOLD_FRAMES = 120   ' the narration skip key held this long (2 s at 60 fps) leaves the tutorial
Const TUT_TAP_FRAMES = 30     ' released within this many frames it is a tap; between the two it does nothing
Const TUT_SKIP_TAP = 1
Const TUT_SKIP_EXIT = 2
Const TUT_STREAM_DEFAULT = 3
Const TUT_WRAP_W = 36

Dim Shared tutOp(0 To TUT_MAX - 1) As Integer
Dim Shared tutKey(0 To TUT_MAX - 1) As String      ' gametext key, element, spawn type or pickup kind
Dim Shared tutNum(0 To TUT_MAX - 1) As Long         ' count, kills or WAIT amount
Dim Shared tutFlag(0 To TUT_MAX - 1) As Integer     ' WAIT condition id; STREAM fire
Dim Shared tutLineNo(0 To TUT_MAX - 1) As Integer   ' source line, for messages
Dim Shared tutCount As Integer
Dim Shared tutLessonCount As Integer
Dim Shared tutErrors As String

' --- run state ---
Dim Shared tutActive As Integer       ' the script is running
Dim Shared tutDone As Integer         ' the last step has finished
Dim Shared tutPc As Integer           ' current step
Dim Shared tutInit As Integer         ' the current WAIT has taken its baselines
Dim Shared tutLesson As Integer       ' lessons begun so far (1-based while running)
Dim Shared tutLessonKey As String
Dim Shared tutSayKey As String        ' the line on screen (stays until the next SAY)
Dim Shared tutSayOn As Integer        ' the current SAY is still being spoken
Dim Shared tutHL As String            ' highlighted element, "" = none
Dim Shared tutStreamOn As Integer
Dim Shared tutStreamKills As Long
Dim Shared tutStreamFire As Integer
Dim Shared tutWaitCond As Integer     ' condition of the WAIT being held, 0 = not waiting
Dim Shared tutWaitKind As String

' --- what the caller tells the runner each frame ---
Dim Shared tutInMoved As Single       ' flight distance so far
Dim Shared tutInOrbit As Integer      ' camera mode is on
Dim Shared tutInShots As Long
Dim Shared tutInHits As Long
Dim Shared tutInKills As Long
Dim Shared tutInDodged As Long
Dim Shared tutInGot(1 To 3) As Long   ' canisters caught: 1 shield, 2 fuel, 3 points
Dim Shared tutInPups(1 To 3) As Integer   ' canisters in flight, same order
Dim Shared tutInBolts As Integer      ' enemy bolts in flight
Dim Shared tutInHazards As Integer    ' asteroids in flight
Dim Shared tutInSpeaking As Integer   ' the instructor's line is still playing
Dim Shared tutInSkipLine As Integer   ' a skip-line tap this frame
Dim Shared tutInSkipLesson As Integer ' a next-lesson press this frame

' --- what the runner asks the caller to do ---
Dim Shared tutOutSay As String        ' speak this gametext block now
Dim Shared tutOutSilence As Integer   ' cut the line being spoken
Dim Shared tutOutFlush As Integer     ' clear every tutorial object (a lesson was skipped)
Dim Shared tutOutSpawn As String      ' spawn type to place now, "" = none
Dim Shared tutOutSpawnN As Integer
Dim Shared tutOutFeed As String       ' a WAIT wants this type in play ("bolt", "shield", "fuel", "points")

Dim Shared tutBMoved As Single, tutBShots As Long, tutBHits As Long, tutBDodged As Long
Dim Shared tutBGot(1 To 3) As Long
Dim Shared tutOrbitSeen As Integer

' --- skip key ---
Dim Shared tutSkHeld As Long          ' frames the skip key has been down (the waiver meter reads this)
Dim Shared tutSkLatched As Integer    ' ignore the key until it has been released once

Dim Shared tutGated As Integer        ' the running tutorial is the first-play gate, so it ends in a New Game

Function TUT_PickupIdx% (tpKind As String)
    Select Case tpKind
        Case "shield" : TUT_PickupIdx% = 1
        Case "fuel"   : TUT_PickupIdx% = 2
        Case "points" : TUT_PickupIdx% = 3
        Case Else     : TUT_PickupIdx% = 0
    End Select
End Function

Function TUT_CondId% (tcName As String)
    Select Case tcName
        Case "move"   : TUT_CondId% = TUT_C_MOVE
        Case "camera" : TUT_CondId% = TUT_C_CAMERA
        Case "shoot"  : TUT_CondId% = TUT_C_SHOOT
        Case "hit"    : TUT_CondId% = TUT_C_HIT
        Case "kills"  : TUT_CondId% = TUT_C_KILLS
        Case "dodge"  : TUT_CondId% = TUT_C_DODGE
        Case "pickup" : TUT_CondId% = TUT_C_PICKUP
        Case "clear"  : TUT_CondId% = TUT_C_CLEAR
        Case Else     : TUT_CondId% = 0
    End Select
End Function

Function TUT_ElementOk% (teName As String)
    TUT_ElementOk% = (InStr(" sh la fu score hi lives reticle off ", " " + teName + " ") > 0)
End Function

Function TUT_SpawnOk% (tsName As String)
    TUT_SpawnOk% = (InStr(" ship bolt asteroid shield fuel points ", " " + tsName + " ") > 0)
End Function

' A whole number in tnText, or -1 when it is not one.
Function TUT_Num& (tnText As String)
    Dim tnI As Integer
    If Len(tnText) = 0 Or Len(tnText) > 6 Then TUT_Num& = -1 : Exit Function
    For tnI = 1 To Len(tnText)
        If Mid$(tnText, tnI, 1) < "0" Or Mid$(tnText, tnI, 1) > "9" Then TUT_Num& = -1 : Exit Function
    Next tnI
    TUT_Num& = Val(tnText)
End Function

Sub TUT_Err (teLine As Integer, teMsg As String)
    tutErrors = tutErrors + "line " + LTrim$(Str$(teLine)) + ": " + teMsg + Chr$(10)
End Sub

Sub TUT_AddStep (tasOp As Integer, tasKey As String, tasNum As Long, tasFlag As Integer, tasLine As Integer)
    If tutCount >= TUT_MAX Then
        If InStr(tutErrors, "more than TUT_MAX") = 0 Then TUT_Err tasLine, "more than TUT_MAX (" + LTrim$(Str$(TUT_MAX)) + ") steps"
        Exit Sub
    End If
    tutOp(tutCount) = tasOp : tutKey(tutCount) = tasKey : tutNum(tutCount) = tasNum
    tutFlag(tutCount) = tasFlag : tutLineNo(tutCount) = tasLine
    tutCount = tutCount + 1
End Sub

' Splits tsText on single spaces into tsOut(0..), at most 6 words; returns the count.
Function TUT_Words% (twText As String, twOut() As String)
    Dim twN As Integer, twRest As String, twSp As Integer
    twRest = LTrim$(RTrim$(twText))
    Do While Len(twRest) > 0 And twN < 6
        twSp = InStr(twRest, " ")
        If twSp = 0 Then
            twOut(twN) = twRest : twRest = ""
        Else
            twOut(twN) = Left$(twRest, twSp - 1) : twRest = LTrim$(Mid$(twRest, twSp + 1))
        End If
        twN = twN + 1
    Loop
    TUT_Words% = twN
End Function

' One WAIT line, already split into words pwW(0..pwN-1).
Sub TUT_ParseWait (pwW() As String, pwN As Integer, pwLn As Integer)
    Dim pwCond As Integer, pwArg As String, pwNum As Long
    If pwN < 2 Then TUT_Err pwLn, "WAIT takes a condition" : Exit Sub
    pwCond = TUT_CondId%(LCase$(pwW(1)))
    If pwCond = 0 Then TUT_Err pwLn, "unknown WAIT condition '" + pwW(1) + "' (move camera shoot hit kills dodge pickup clear)" : Exit Sub
    pwArg = ""
    If pwN > 2 Then pwArg = LCase$(pwW(2))
    If pwN > 3 Then TUT_Err pwLn, "WAIT " + LCase$(pwW(1)) + " takes at most one argument" : Exit Sub
    pwNum = 1
    Select Case pwCond
        Case TUT_C_MOVE
            pwNum = 12
            If pwN = 3 Then pwNum = TUT_Num&(pwArg)
            If pwNum < 1 Then TUT_Err pwLn, "WAIT move needs a distance of 1 or more" : Exit Sub
        Case TUT_C_SHOOT, TUT_C_HIT, TUT_C_DODGE
            If pwN = 3 Then pwNum = TUT_Num&(pwArg)
            If pwNum < 1 Or pwNum > 99 Then TUT_Err pwLn, "WAIT " + LCase$(pwW(1)) + " needs a count of 1 to 99" : Exit Sub
        Case TUT_C_KILLS
            If pwN <> 3 Then TUT_Err pwLn, "WAIT kills needs a count" : Exit Sub
            pwNum = TUT_Num&(pwArg)
            If pwNum < 1 Or pwNum > 99 Then TUT_Err pwLn, "WAIT kills needs a count of 1 to 99" : Exit Sub
        Case TUT_C_PICKUP
            If pwN <> 3 Then TUT_Err pwLn, "WAIT pickup needs shield, fuel or points" : Exit Sub
            If TUT_PickupIdx%(pwArg) = 0 Then TUT_Err pwLn, "WAIT pickup needs shield, fuel or points, not '" + pwW(2) + "'" : Exit Sub
        Case TUT_C_CAMERA, TUT_C_CLEAR
            If pwN <> 2 Then TUT_Err pwLn, "WAIT " + LCase$(pwW(1)) + " takes no argument" : Exit Sub
    End Select
    TUT_AddStep TUT_WAIT, pwArg, pwNum, pwCond, pwLn
End Sub

' Parses script text into the step table. 1 = clean; 0 = problems, listed in tutErrors.
Function TUT_Parse% (tpSrc As String)
    Dim tpI As Long, tpNL As Long, tpLn As Integer
    Dim tpRaw As String, tpLine As String
    Dim tpW(0 To 5) As String, tpN As Integer, tpVerb As String
    Dim tpA As Integer, tpNum As Long, tpFire As Integer, tpKills As Long, tpArg As String
    tutCount = 0 : tutLessonCount = 0 : tutErrors = ""
    tpI = 1
    Do While tpI <= Len(tpSrc)
        tpNL = InStr(tpI, tpSrc, Chr$(10))
        If tpNL = 0 Then tpNL = Len(tpSrc) + 1
        tpRaw = Mid$(tpSrc, tpI, tpNL - tpI)
        tpI = tpNL + 1
        tpLn = tpLn + 1
        If Right$(tpRaw, 1) = Chr$(13) Then tpRaw = Left$(tpRaw, Len(tpRaw) - 1)
        tpLine = LTrim$(RTrim$(tpRaw))
        If Len(tpLine) = 0 Or Left$(tpLine, 1) = ";" Then GoTo tpNext
        tpN = TUT_Words%(tpLine, tpW())
        tpVerb = UCase$(tpW(0))
        Select Case tpVerb
            Case "LESSON"
                If tpN <> 2 Then
                    TUT_Err tpLn, "LESSON takes one gametext key"
                Else
                    tutLessonCount = tutLessonCount + 1
                    TUT_AddStep TUT_LESSON, LCase$(tpW(1)), 0, 0, tpLn
                End If
            Case "SAY"
                If tpN <> 2 Then TUT_Err tpLn, "SAY takes one gametext key" Else TUT_AddStep TUT_SAY, LCase$(tpW(1)), 0, 0, tpLn
            Case "HIGHLIGHT"
                If tpN <> 2 Then
                    TUT_Err tpLn, "HIGHLIGHT takes one element"
                ElseIf TUT_ElementOk%(LCase$(tpW(1))) = 0 Then
                    TUT_Err tpLn, "unknown HIGHLIGHT element '" + tpW(1) + "' (sh la fu score hi lives reticle off)"
                Else
                    TUT_AddStep TUT_HIGHLIGHT, LCase$(tpW(1)), 0, 0, tpLn
                End If
            Case "SPAWN"
                tpNum = 1
                If tpN < 2 Or tpN > 3 Then
                    TUT_Err tpLn, "SPAWN takes a type and an optional count=<n>"
                ElseIf TUT_SpawnOk%(LCase$(tpW(1))) = 0 Then
                    TUT_Err tpLn, "unknown SPAWN type '" + tpW(1) + "' (ship bolt asteroid shield fuel points)"
                Else
                    If tpN = 3 Then
                        If LCase$(Left$(tpW(2), 6)) = "count=" Then tpNum = TUT_Num&(Mid$(tpW(2), 7)) Else tpNum = -1
                        If tpNum < 1 Or tpNum > 8 Then TUT_Err tpLn, "SPAWN count must be count=1 to count=8" : GoTo tpNext
                    End If
                    TUT_AddStep TUT_SPAWN, LCase$(tpW(1)), tpNum, 0, tpLn
                End If
            Case "STREAM"
                If tpN < 2 Then
                    TUT_Err tpLn, "STREAM takes ship or off"
                ElseIf LCase$(tpW(1)) = "off" Then
                    If tpN <> 2 Then TUT_Err tpLn, "STREAM off takes nothing more" Else TUT_AddStep TUT_STREAM, "off", 0, 0, tpLn
                ElseIf LCase$(tpW(1)) <> "ship" Then
                    TUT_Err tpLn, "STREAM takes ship or off, not '" + tpW(1) + "'"
                Else
                    tpKills = TUT_STREAM_DEFAULT : tpFire = 0
                    For tpA = 2 To tpN - 1
                        tpArg = LCase$(tpW(tpA))
                        If tpArg = "fire" Then
                            tpFire = -1
                        ElseIf Left$(tpArg, 6) = "kills=" Then
                            tpKills = TUT_Num&(Mid$(tpArg, 7))
                            If tpKills < 1 Or tpKills > 20 Then TUT_Err tpLn, "STREAM kills must be kills=1 to kills=20" : GoTo tpNext
                        Else
                            TUT_Err tpLn, "unknown STREAM option '" + tpW(tpA) + "'" : GoTo tpNext
                        End If
                    Next tpA
                    TUT_AddStep TUT_STREAM, "ship", tpKills, tpFire, tpLn
                End If
            Case "WAIT"
                TUT_ParseWait tpW(), tpN, tpLn
            Case Else
                TUT_Err tpLn, "unknown step '" + tpW(0) + "'"
        End Select
        tpNext:
    Loop
    TUT_Parse% = (Len(tutErrors) = 0)
End Function

' The gametext block for key ttKey as one line: the line ends of the block become spaces and the
' trailing ones go.
Function TUT_Text$ (ttxKey As String)
    Dim ttxS As String, ttxI As Integer
    ttxS = GTEXT_Get$(ttxKey)
    For ttxI = 1 To Len(ttxS)
        If Mid$(ttxS, ttxI, 1) = Chr$(10) Or Mid$(ttxS, ttxI, 1) = Chr$(13) Then Mid$(ttxS, ttxI, 1) = " "
    Next ttxI
    TUT_Text$ = LTrim$(RTrim$(ttxS))
End Function

' Static checks on a parsed script: "" when sound, else one problem per line. Needs the gametext
' loaded (GTEXT_Get$). Parse problems come first.
'   - the script opens with a LESSON, and has at least one
'   - every LESSON and SAY key is a gametext block, and no SAY wraps past two lines
'   - a lesson that waits on kills or hits has ships coming from a STREAM or a SPAWN in that lesson
'   - a lesson never waits on ships that could not be enough: WAIT kills n needs a stream of n or more
Function TUT_Validate$ ()
    Dim tvI As Integer, tvOut As String, tvTxt As String
    Dim tvLines(0 To 3) As String, tvN As Integer
    Dim tvStream As Long, tvShips As Long
    tvOut = tutErrors
    If tutCount = 0 Then TUT_Validate$ = tvOut + "script has no steps" + Chr$(10) : Exit Function
    If tutOp(0) <> TUT_LESSON Then tvOut = tvOut + "line " + LTrim$(Str$(tutLineNo(0))) + ": the script must open with a LESSON" + Chr$(10)
    For tvI = 0 To tutCount - 1
        Select Case tutOp(tvI)
            Case TUT_LESSON
                tvStream = 0 : tvShips = 0
                If Len(TUT_Text$(tutKey(tvI))) = 0 Then tvOut = tvOut + "line " + LTrim$(Str$(tutLineNo(tvI))) + ": no gametext block '" + tutKey(tvI) + "'" + Chr$(10)
            Case TUT_SAY
                tvTxt = TUT_Text$(tutKey(tvI))
                If Len(tvTxt) = 0 Then
                    tvOut = tvOut + "line " + LTrim$(Str$(tutLineNo(tvI))) + ": no gametext block '" + tutKey(tvI) + "'" + Chr$(10)
                Else
                    TUT_Wrap tvTxt, TUT_WRAP_W, tvLines(), tvN
                    If tvN > 2 Then tvOut = tvOut + "line " + LTrim$(Str$(tutLineNo(tvI))) + ": '" + tutKey(tvI) + "' is longer than two lines of " + LTrim$(Str$(TUT_WRAP_W)) + " characters" + Chr$(10)
                End If
            Case TUT_STREAM
                If tutKey(tvI) = "ship" Then tvStream = tutNum(tvI) Else tvStream = 0
            Case TUT_SPAWN
                If tutKey(tvI) = "ship" Then tvShips = tvShips + tutNum(tvI)
            Case TUT_WAIT
                If tutFlag(tvI) = TUT_C_KILLS Then
                    If tutNum(tvI) > tvStream And tutNum(tvI) > tvShips Then
                        tvOut = tvOut + "line " + LTrim$(Str$(tutLineNo(tvI))) + ": WAIT kills " + LTrim$(Str$(tutNum(tvI))) + " but no STREAM or SPAWN ship in this lesson brings that many" + Chr$(10)
                    End If
                ElseIf tutFlag(tvI) = TUT_C_HIT Then
                    If tvStream = 0 And tvShips = 0 Then tvOut = tvOut + "line " + LTrim$(Str$(tutLineNo(tvI))) + ": WAIT hit but no ship is coming in this lesson" + Chr$(10)
                End If
        End Select
    Next tvI
    TUT_Validate$ = tvOut
End Function

' Breaks twText at word boundaries into lines of at most twW characters: twOut(0..twN-1),
' twN up to 4. A word longer than twW is cut.
Sub TUT_Wrap (twText As String, twW As Integer, twOut() As String, twN As Integer)
    Dim twRest As String, twSp As Integer, twWord As String, twCur As String
    twN = 0 : twCur = ""
    twRest = LTrim$(RTrim$(twText))
    Do While Len(twRest) > 0
        twSp = InStr(twRest, " ")
        If twSp = 0 Then twWord = twRest : twRest = "" Else twWord = Left$(twRest, twSp - 1) : twRest = LTrim$(Mid$(twRest, twSp + 1))
        If Len(twWord) > twW Then twWord = Left$(twWord, twW)
        If Len(twCur) = 0 Then
            twCur = twWord
        ElseIf Len(twCur) + 1 + Len(twWord) <= twW Then
            twCur = twCur + " " + twWord
        Else
            If twN < 4 Then twOut(twN) = twCur : twN = twN + 1
            twCur = twWord
        End If
    Loop
    If Len(twCur) > 0 And twN < 4 Then twOut(twN) = twCur : twN = twN + 1
End Sub

Sub TUT_Start
    tutActive = -1 : tutDone = 0 : tutPc = 0 : tutInit = 0 : tutLesson = 0 : tutLessonKey = ""
    tutSayKey = "" : tutSayOn = 0 : tutHL = "" : tutStreamOn = 0 : tutWaitCond = 0 : tutWaitKind = ""
    tutOutSay = "" : tutOutSilence = 0 : tutOutFlush = 0 : tutOutSpawn = "" : tutOutSpawnN = 0 : tutOutFeed = ""
End Sub

' The step index of the first LESSON after step tupFrom, or tutCount when there is none.
Function TUT_NextLesson% (tnlFrom As Integer)
    Dim tnlI As Integer
    For tnlI = tnlFrom + 1 To tutCount - 1
        If tutOp(tnlI) = TUT_LESSON Then TUT_NextLesson% = tnlI : Exit Function
    Next tnlI
    TUT_NextLesson% = tutCount
End Function

Sub TUT_TakeBaselines
    Dim tbI As Integer
    tutBMoved = tutInMoved : tutBShots = tutInShots : tutBHits = tutInHits : tutBDodged = tutInDodged
    For tbI = 1 To 3 : tutBGot(tbI) = tutInGot(tbI) : Next tbI
    tutOrbitSeen = tutInOrbit
End Sub

' Is the WAIT at step twI satisfied? Also asks for a canister or bolt to be fed when it needs one.
Function TUT_WaitMet% (twmI As Integer)
    Dim twmK As Integer, twmMet As Integer
    Select Case tutFlag(twmI)
        Case TUT_C_MOVE
            twmMet = (tutInMoved - tutBMoved >= tutNum(twmI))
        Case TUT_C_CAMERA
            If tutInOrbit Then tutOrbitSeen = -1
            twmMet = (tutOrbitSeen <> 0 And tutInOrbit = 0)
        Case TUT_C_SHOOT
            twmMet = (tutInShots - tutBShots >= tutNum(twmI))
        Case TUT_C_HIT
            twmMet = (tutInHits - tutBHits >= tutNum(twmI))
        Case TUT_C_KILLS
            twmMet = (tutInKills >= tutNum(twmI))
        Case TUT_C_DODGE
            twmMet = (tutInDodged - tutBDodged >= tutNum(twmI))
            If twmMet = 0 And tutInBolts = 0 Then tutOutFeed = "bolt"
        Case TUT_C_PICKUP
            twmK = TUT_PickupIdx%(tutKey(twmI))
            twmMet = (tutInGot(twmK) - tutBGot(twmK) >= 1)
            If twmMet = 0 And tutInPups(twmK) = 0 Then tutOutFeed = tutKey(twmI)
        Case TUT_C_CLEAR
            twmMet = (tutInHazards = 0)
    End Select
    TUT_WaitMet% = twmMet
End Function

' One frame. Instant steps (LESSON, HIGHLIGHT, STREAM) chain; a SAY or SPAWN uses the frame
' (its request is left in tutOut*); a WAIT that is not met holds.
Sub TUT_Tick
    Dim ttGuard As Integer
    tutOutSay = "" : tutOutSilence = 0 : tutOutFlush = 0 : tutOutSpawn = "" : tutOutSpawnN = 0 : tutOutFeed = ""
    If tutActive = 0 Then Exit Sub

    If tutStreamOn And tutInKills >= tutStreamKills Then tutStreamOn = 0

    If tutInSkipLesson Then
        tutPc = TUT_NextLesson%(tutPc)
        tutInit = 0 : tutSayOn = 0 : tutHL = "" : tutStreamOn = 0 : tutWaitCond = 0
        tutOutFlush = -1 : tutOutSilence = -1
    ElseIf tutInSkipLine And tutSayOn Then
        tutSayOn = 0 : tutInit = 0 : tutOutSilence = -1
        tutPc = tutPc + 1
    End If

    For ttGuard = 1 To TUT_MAX + 1
        If tutPc >= tutCount Then
            tutActive = 0 : tutDone = -1 : tutWaitCond = 0
            Exit Sub
        End If
        Select Case tutOp(tutPc)
            Case TUT_LESSON
                tutLesson = tutLesson + 1 : tutLessonKey = tutKey(tutPc)
                tutPc = tutPc + 1
            Case TUT_HIGHLIGHT
                If tutKey(tutPc) = "off" Then tutHL = "" Else tutHL = tutKey(tutPc)
                tutPc = tutPc + 1
            Case TUT_STREAM
                If tutKey(tutPc) = "off" Then
                    tutStreamOn = 0
                Else
                    tutStreamOn = -1 : tutStreamKills = tutNum(tutPc) : tutStreamFire = tutFlag(tutPc)
                    If tutInKills >= tutStreamKills Then tutStreamOn = 0
                End If
                tutPc = tutPc + 1
            Case TUT_SPAWN
                tutOutSpawn = tutKey(tutPc) : tutOutSpawnN = tutNum(tutPc)
                tutPc = tutPc + 1
                Exit Sub
            Case TUT_SAY
                If tutSayOn = 0 And tutInit = 0 Then
                    tutSayKey = tutKey(tutPc) : tutOutSay = tutKey(tutPc)
                    tutSayOn = -1 : tutInit = -1 : tutWaitCond = 0
                    Exit Sub
                End If
                If tutInSpeaking Then Exit Sub
                tutSayOn = 0 : tutInit = 0
                tutPc = tutPc + 1
            Case TUT_WAIT
                If tutInit = 0 Then TUT_TakeBaselines : tutInit = -1
                tutWaitCond = tutFlag(tutPc) : tutWaitKind = tutKey(tutPc)
                If TUT_WaitMet%(tutPc) = 0 Then Exit Sub
                tutInit = 0 : tutWaitCond = 0
                tutPc = tutPc + 1
        End Select
    Next ttGuard
End Sub

' --- the narration skip key ---

' Call when a run begins, with whether the key is down now: a key still held from the menu that
' started the run does nothing until it has been let go.
Sub TUT_SkipReset (tsrDown As Integer)
    tutSkHeld = 0
    tutSkLatched = (tsrDown <> 0)
End Sub

' One frame of the narration skip key. TUT_SKIP_TAP when it is released after a short press;
' TUT_SKIP_EXIT on the frame it has been held TUT_HOLD_FRAMES (the release after that does
' nothing). A press between a tap and a hold does nothing, so backing out of a hold skips no line.
Function TUT_SkipTick% (tstDown As Integer)
    Dim tstHeld As Long
    TUT_SkipTick% = 0
    If tstDown = 0 Then
        tstHeld = tutSkHeld
        tutSkHeld = 0 : tutSkLatched = 0
        If tstHeld > 0 And tstHeld <= TUT_TAP_FRAMES Then TUT_SkipTick% = TUT_SKIP_TAP
        Exit Function
    End If
    If tutSkLatched Then Exit Function
    tutSkHeld = tutSkHeld + 1
    If tutSkHeld >= TUT_HOLD_FRAMES Then
        tutSkLatched = -1 : tutSkHeld = 0
        TUT_SkipTick% = TUT_SKIP_EXIT
    End If
End Function

' Does New Game start the tutorial first? Only on a fresh install (not done yet), never in a
' scripted or --scene run, and never when the session cannot save the answer.
Function TUT_GateDue% (tgdDone As Integer, tgdScripted As Integer, tgdScene As String, tgdReadOnly As Integer)
    TUT_GateDue% = (tgdDone = 0 And tgdScripted = 0 And Len(tgdScene) = 0 And tgdReadOnly = 0)
End Function
