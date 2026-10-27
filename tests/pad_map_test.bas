' pad_map_test.bas -- real controllers' recorded raw input -> game actions (src/3d/input.bas)
'
' Loads every fixture in tests/input/pads/ (recorded with tools/padrecord.bas), sets the
' raw pad state from each control's row and runs E3D_PadMap, the same code the game runs
' on a real pad, then checks exactly the expected held() slots are down. A control the
' mapping drops (the d-pad, before #223) fails here by fixture and control name.
' Also: E3D_CtrlPick% on real _DEVICE$ strings, and the late-plug rescan decision.
'
' Build: ./tools/buildqb tests/pad_map_test.bas
' Run:   ./tests/pad_map_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

'$INCLUDE:'../src/3d/input.bas'

Dim Shared pmPassed As Integer, pmFailed As Integer
Dim Shared pmHeld(0 To 32767) As Integer

Sub PM_Assert (pmaCond As Integer, pmaName As String)
    If pmaCond Then
        Print "PASS  " + pmaName
        pmPassed = pmPassed + 1
    Else
        Print "FAIL  " + pmaName
        pmFailed = pmFailed + 1
    End If
End Sub

Function PM_SlotName$ (pmsSlot As Long)
    Select Case pmsSlot
        Case E3D_KEY_UP : PM_SlotName$ = "UP"
        Case E3D_KEY_DOWN : PM_SlotName$ = "DOWN"
        Case E3D_KEY_LEFT : PM_SlotName$ = "LEFT"
        Case E3D_KEY_RIGHT : PM_SlotName$ = "RIGHT"
        Case E3D_KEY_SPACE : PM_SlotName$ = "SPACE"
        Case E3D_KEY_ESCAPE : PM_SlotName$ = "ESCAPE"
        Case E3D_KEY_TAB : PM_SlotName$ = "TAB"
        Case E3D_KEY_PAD_A : PM_SlotName$ = "PAD_A"
        Case E3D_KEY_PAD_B : PM_SlotName$ = "PAD_B"
        Case E3D_KEY_PAD_X : PM_SlotName$ = "PAD_X"
        Case E3D_KEY_PAD_Y : PM_SlotName$ = "PAD_Y"
        Case E3D_KEY_PAD_START : PM_SlotName$ = "PAD_START"
        Case E3D_KEY_PAD_SELECT : PM_SlotName$ = "PAD_SELECT"
        Case Else : PM_SlotName$ = "slot" + LTrim$(Str$(pmsSlot))
    End Select
End Function

' The held() slots a control must press, as " slot slot ... " ("" for none).
Function PM_Expected$ (pmeCtl As String)
    Dim pmeS As String
    Select Case pmeCtl
        Case "STICK_UP", "DPAD_UP" : pmeS = Str$(E3D_KEY_UP)
        Case "STICK_DOWN", "DPAD_DOWN" : pmeS = Str$(E3D_KEY_DOWN)
        Case "STICK_LEFT", "DPAD_LEFT" : pmeS = Str$(E3D_KEY_LEFT)
        Case "STICK_RIGHT", "DPAD_RIGHT" : pmeS = Str$(E3D_KEY_RIGHT)
        Case "A" : pmeS = Str$(E3D_KEY_SPACE) + Str$(E3D_KEY_PAD_A)
        Case "B" : pmeS = Str$(E3D_KEY_SPACE) + Str$(E3D_KEY_PAD_B)
        Case "X" : pmeS = Str$(E3D_KEY_PAD_X)
        Case "Y" : pmeS = Str$(E3D_KEY_PAD_Y)
        Case "START" : pmeS = Str$(E3D_KEY_ESCAPE) + Str$(E3D_KEY_PAD_START)
        Case "BACK" : pmeS = Str$(E3D_KEY_TAB) + Str$(E3D_KEY_PAD_SELECT)
        Case "IDLE" : pmeS = ""
        Case Else : pmeS = "?"
    End Select
    If pmeS <> "" And pmeS <> "?" Then pmeS = pmeS + " "
    PM_Expected$ = pmeS
End Function

Function PM_Controls$
    PM_Controls$ = " IDLE STICK_UP STICK_DOWN STICK_LEFT STICK_RIGHT DPAD_UP DPAD_DOWN DPAD_LEFT DPAD_RIGHT A B X Y START BACK "
End Function

' Sets the raw pad state from one fixture row's btn= and axes= fields; returns the
' number of axis values found (-1 if a button number is out of range).
Function PM_SetRaw% (pmrBtns As String, pmrAxes As String)
    Dim pmrI As Integer, pmrP As Integer, pmrT As String, pmrN As Integer, pmrS As String
    For pmrI = 1 To E3D_PAD_MAX_AXES : padRawAxis(pmrI) = 0 : Next pmrI
    For pmrI = 1 To E3D_PAD_MAX_BTNS : padRawBtn(pmrI) = 0 : Next pmrI
    pmrS = pmrBtns + ","
    Do While Len(pmrS) > 0
        pmrP = InStr(pmrS, ",")
        pmrT = LTrim$(RTrim$(Left$(pmrS, pmrP - 1)))
        pmrS = Mid$(pmrS, pmrP + 1)
        If pmrT <> "" Then
            If Val(pmrT) < 1 Or Val(pmrT) > E3D_PAD_MAX_BTNS Then PM_SetRaw% = -1 : Exit Function
            padRawBtn(Val(pmrT)) = 1
        End If
    Loop
    pmrS = LTrim$(RTrim$(pmrAxes)) + " "
    pmrN = 0
    Do While Len(LTrim$(pmrS)) > 0
        pmrS = LTrim$(pmrS)
        pmrP = InStr(pmrS, " ")
        pmrT = Left$(pmrS, pmrP - 1)
        pmrS = Mid$(pmrS, pmrP + 1)
        pmrN = pmrN + 1
        If pmrN <= E3D_PAD_MAX_AXES Then padRawAxis(pmrN) = Val(pmrT)
    Loop
    PM_SetRaw% = pmrN
End Function

' " slot slot ... " for every held() slot that is down ("" for none).
Function PM_Pressed$
    Dim pmpI As Long, pmpS As String
    For pmpI = 0 To 32767
        If pmHeld(pmpI) <> 0 Then pmpS = pmpS + Str$(pmpI)
    Next pmpI
    If pmpS <> "" Then pmpS = pmpS + " "
    PM_Pressed$ = pmpS
End Function

' "UP, SPACE" for a " slot slot " list.
Function PM_Names$ (pmnList As String)
    Dim pmnS As String, pmnT As String, pmnP As Integer, pmnOut As String
    pmnS = LTrim$(pmnList)
    Do While Len(pmnS) > 0
        pmnP = InStr(pmnS, " ")
        pmnT = Left$(pmnS, pmnP - 1)
        pmnS = LTrim$(Mid$(pmnS, pmnP + 1))
        If pmnOut <> "" Then pmnOut = pmnOut + ", "
        pmnOut = pmnOut + PM_SlotName$(Val(pmnT))
    Loop
    PM_Names$ = pmnOut
End Function

' Checks every control row of one fixture file, then its header and device string.
Sub PM_RunFixture (pmfPath As String, pmfFile As String)
    Dim pmfH As Integer, pmfLine As String, pmfName As String, pmfDevice As String
    Dim pmfAxes As Integer, pmfBtnCount As Integer, pmfSeen As String, pmfCtl As String
    Dim pmfBP As Integer, pmfAP As Integer, pmfN As Integer, pmfI As Long
    Dim pmfWant As String, pmfGot As String, pmfP As Integer, pmfTok As String, pmfRest As String
    Dim pmfMissing As String, pmfExtra As String, pmfMsg As String

    pmfName = pmfFile
    pmfH = FreeFile
    Open pmfPath For Input As #pmfH
    Do While Not EOF(pmfH)
        Line Input #pmfH, pmfLine
        pmfP = InStr(pmfLine, Chr$(13))
        If pmfP > 0 Then pmfLine = Left$(pmfLine, pmfP - 1)
        pmfLine = LTrim$(RTrim$(pmfLine))
        If pmfLine = "" Or Left$(pmfLine, 1) = "#" Then _Continue
        pmfP = InStr(pmfLine, " ")
        If pmfP = 0 Then pmfP = Len(pmfLine) + 1
        pmfCtl = Left$(pmfLine, pmfP - 1)
        pmfRest = LTrim$(Mid$(pmfLine, pmfP + 1))
        Select Case pmfCtl
            Case "NAME" : pmfName = pmfRest
            Case "DEVICE" : pmfDevice = pmfRest
            Case "BUTTONS" : pmfBtnCount = Val(pmfRest)
            Case "AXES" : pmfAxes = Val(pmfRest)
            Case Else
                If InStr(PM_Controls$, " " + pmfCtl + " ") = 0 Then
                    PM_Assert 0, pmfName + ": unknown control " + pmfCtl
                    _Continue
                End If
                pmfSeen = pmfSeen + " " + pmfCtl + " "
                pmfBP = InStr(pmfLine, " btn=")
                pmfAP = InStr(pmfLine, " axes=")
                If pmfBP = 0 Or pmfAP < pmfBP Then
                    PM_Assert 0, pmfName + ": " + pmfCtl + " row needs btn= then axes="
                    _Continue
                End If
                pmfN = PM_SetRaw%(Mid$(pmfLine, pmfBP + 5, pmfAP - pmfBP - 5), Mid$(pmfLine, pmfAP + 6))
                If pmfN <> pmfAxes Then
                    PM_Assert 0, pmfName + ": " + pmfCtl + " has" + Str$(pmfN) + " axis values, header says" + Str$(pmfAxes)
                    _Continue
                End If
                For pmfI = 0 To 32767 : pmHeld(pmfI) = 0 : Next pmfI
                E3D_PadMap pmHeld()
                pmfWant = PM_Expected$(pmfCtl)
                pmfGot = PM_Pressed$
                pmfMissing = "" : pmfExtra = ""
                pmfRest = LTrim$(pmfWant)
                Do While Len(pmfRest) > 0
                    pmfP = InStr(pmfRest, " ")
                    pmfTok = Left$(pmfRest, pmfP - 1)
                    pmfRest = LTrim$(Mid$(pmfRest, pmfP + 1))
                    If InStr(pmfGot, " " + pmfTok + " ") = 0 Then pmfMissing = pmfMissing + " " + pmfTok
                Loop
                pmfRest = LTrim$(pmfGot)
                Do While Len(pmfRest) > 0
                    pmfP = InStr(pmfRest, " ")
                    pmfTok = Left$(pmfRest, pmfP - 1)
                    pmfRest = LTrim$(Mid$(pmfRest, pmfP + 1))
                    If InStr(pmfWant, " " + pmfTok + " ") = 0 Then pmfExtra = pmfExtra + " " + pmfTok
                Loop
                If pmfGot = "" And pmfWant <> "" Then
                    pmfMsg = pmfName + ": " + pmfCtl + " produced nothing (want " + PM_Names$(pmfWant) + ")"
                ElseIf pmfMissing <> "" Or pmfExtra <> "" Then
                    pmfMsg = pmfName + ": " + pmfCtl + " produced " + PM_Names$(pmfGot)
                    pmfMsg = pmfMsg + " (want "
                    If pmfWant = "" Then pmfMsg = pmfMsg + "nothing)" Else pmfMsg = pmfMsg + PM_Names$(pmfWant) + ")"
                ElseIf pmfWant = "" Then
                    pmfMsg = pmfName + ": " + pmfCtl + " -> nothing"
                Else
                    pmfMsg = pmfName + ": " + pmfCtl + " -> " + PM_Names$(pmfGot)
                End If
                PM_Assert pmfMissing = "" And pmfExtra = "", pmfMsg
        End Select
    Loop
    Close #pmfH

    PM_Assert pmfAxes >= 1 And pmfAxes <= E3D_PAD_MAX_AXES, pmfName + ": AXES header (" + LTrim$(Str$(pmfAxes)) + ") in 1.." + LTrim$(Str$(E3D_PAD_MAX_AXES))
    PM_Assert pmfBtnCount >= 1 And pmfBtnCount <= E3D_PAD_MAX_BTNS, pmfName + ": BUTTONS header (" + LTrim$(Str$(pmfBtnCount)) + ") in 1.." + LTrim$(Str$(E3D_PAD_MAX_BTNS))
    pmfRest = LTrim$(PM_Controls$)
    pmfMissing = ""
    Do While Len(pmfRest) > 0
        pmfP = InStr(pmfRest, " ")
        pmfTok = Left$(pmfRest, pmfP - 1)
        pmfRest = LTrim$(Mid$(pmfRest, pmfP + 1))
        If InStr(pmfSeen, " " + pmfTok + " ") = 0 Then pmfMissing = pmfMissing + " " + pmfTok
    Loop
    PM_Assert pmfMissing = "", pmfName + ": has a row for every control" + pmfMissing

    ' the recorded _DEVICE$ string must be picked as the pad, after the keyboard and mouse
    ReDim pmfNames(1 To 3) As String
    pmfNames(1) = "[KEYBOARD][BUTTON]" : pmfNames(2) = "[MOUSE][BUTTON][AXIS][WHEEL]" : pmfNames(3) = pmfDevice
    pmfN = E3D_CtrlPick%(pmfNames(), 3)
    PM_Assert pmfN = 3, pmfName + ": its DEVICE string is picked as a gamepad"
End Sub

Print "=== pad_map_test ==="
Print ""

' ---- fixtures ----
Dim pmDir As String, pmF As String, pmCount As Integer, pmExe As String, pmSlash As Integer, pmI As Integer
If _DirExists("tests/input/pads") Then
    pmDir = "tests/input/pads/"
ElseIf _DirExists("input/pads") Then
    pmDir = "input/pads/"
Else
    pmExe = Command$(0)
    For pmI = 1 To Len(pmExe)
        If Mid$(pmExe, pmI, 1) = "/" Or Mid$(pmExe, pmI, 1) = "\" Then pmSlash = pmI
    Next pmI
    pmDir = Left$(pmExe, pmSlash) + "input/pads/"
End If
Print "--- fixtures in " + pmDir + " ---"
ReDim pmFiles(1 To 64) As String
pmF = _Files$(pmDir + "*.txt")
Do While pmF <> "" And pmCount < 64
    If Right$(pmF, 1) <> "/" And Right$(pmF, 1) <> "\" Then
        pmCount = pmCount + 1
        pmFiles(pmCount) = pmF
    End If
    pmF = _Files$
Loop
PM_Assert pmCount > 0, "found at least one fixture (" + LTrim$(Str$(pmCount)) + ")"
For pmI = 1 To pmCount
    PM_RunFixture pmDir + pmFiles(pmI), pmFiles(pmI)
Next pmI

' ---- device selection from real _DEVICE$ strings ----
Print ""
Print "--- E3D_CtrlPick% ---"
Dim pmKbd As String, pmMouse As String, pmPad As String, pmPad2 As String, pmPick As Integer
pmKbd = "[KEYBOARD][BUTTON]"
pmMouse = "[MOUSE][BUTTON][AXIS][WHEEL]"
pmPad = "[CONTROLLER][[NAME][Microsoft X-Box 360 pad]][BUTTON][AXIS]"
pmPad2 = "[CONTROLLER][[NAME][Sony Interactive Entertainment Wireless Controller]][BUTTON][AXIS]"
ReDim pmNames(1 To 4) As String
pmNames(1) = pmKbd : pmNames(2) = pmMouse
pmPick = E3D_CtrlPick%(pmNames(), 2)
PM_Assert pmPick = 0, "keyboard + mouse only -> 0 (keyboard-only)"
pmNames(3) = pmPad
pmPick = E3D_CtrlPick%(pmNames(), 3)
PM_Assert pmPick = 3, "keyboard, mouse, pad -> the pad (3)"
pmNames(3) = pmPad + "[DISCONNECTED]"
pmPick = E3D_CtrlPick%(pmNames(), 3)
PM_Assert pmPick = 0, "pad marked [DISCONNECTED] -> 0"
pmNames(3) = pmPad : pmNames(4) = pmPad2
pmPick = E3D_CtrlPick%(pmNames(), 4)
PM_Assert pmPick = 4, "two pads -> the last one (4)"
pmNames(4) = pmPad2 + "[DISCONNECTED]"
pmPick = E3D_CtrlPick%(pmNames(), 4)
PM_Assert pmPick = 3, "two pads, the last unplugged -> the connected one (3)"
pmNames(3) = "[GAMEPAD][BUTTON][AXIS]"
pmPick = E3D_CtrlPick%(pmNames(), 3)
PM_Assert pmPick = 3, "[GAMEPAD] counts as a pad"
pmNames(3) = "[JOYSTICK][BUTTON][AXIS]"
pmPick = E3D_CtrlPick%(pmNames(), 3)
PM_Assert pmPick = 3, "[JOYSTICK] counts as a pad"

' ---- a pad plugged in after startup ----
Print ""
Print "--- late plug rescan ---"
Dim pmDue As Integer, pmSeen As Integer, pmDev As Integer
pmNames(1) = pmKbd : pmNames(2) = pmMouse : pmNames(3) = pmPad
pmDev = E3D_CtrlPick%(pmNames(), 2)
pmSeen = 0
pmDue = E3D_CtrlRescanDue%(E3D_CTRL_RESCAN_TICKS - 1, 2, pmSeen, pmDev)
PM_Assert pmDev = 0 And pmDue = 0, "no pad at startup; no rescan before the tick interval"
pmDue = E3D_CtrlRescanDue%(E3D_CTRL_RESCAN_TICKS, 2, pmSeen, pmDev)
PM_Assert pmDue <> 0, "first look at the device count rescans"
If pmDue Then pmSeen = 2 : pmDev = E3D_CtrlPick%(pmNames(), 2)
pmDue = E3D_CtrlRescanDue%(E3D_CTRL_RESCAN_TICKS, 2, pmSeen, pmDev)
PM_Assert pmDev = 0 And pmDue = 0, "same device count -> no rescan"
pmDue = E3D_CtrlRescanDue%(E3D_CTRL_RESCAN_TICKS, 3, pmSeen, pmDev)
PM_Assert pmDue <> 0, "pad plugged in (count 2 -> 3) -> rescan"
If pmDue Then pmSeen = 3 : pmDev = E3D_CtrlPick%(pmNames(), 3)
PM_Assert pmDev = 3, "the rescan picks up the new pad (3)"
pmDue = E3D_CtrlRescanDue%(E3D_CTRL_RESCAN_TICKS, 4, pmSeen, pmDev)
PM_Assert pmDue = 0, "with a pad in use, no more rescans"

Print ""
Print "=== " + LTrim$(Str$(pmPassed + pmFailed)) + " tests: " + LTrim$(Str$(pmPassed)) + " passed, " + LTrim$(Str$(pmFailed)) + " failed ==="
If pmFailed > 0 Then System 1 Else System 0

' stub: input.bas logs devices through debug.bas, which this test doesn't include
Sub DBG_Print (pmDbgMsg As String)
End Sub
