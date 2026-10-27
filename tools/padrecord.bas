' padrecord.bas -- record a gamepad fixture for tests/pad_map_test.bas
'
' Prompts for each control in turn ("hold D-PAD UP and press ENTER"), snapshots the
' pad's raw buttons and axes, and writes tests/input/pads/<name>.txt. Commit the file
' and CI checks that pad's every control maps to the right game action.
'
' Build: ./tools/buildqb tools/padrecord.bas   (or tools/dev shell ... in the container)
' Run from the repo root, pad plugged in:  builds/padrecord <name>   e.g. builds/padrecord 8bitdo_sn30
' ESC quits without writing.

Option _Explicit
$Console

'$INCLUDE:'../src/3d/input.bas'

Const PR_COUNT = 15
Dim prCtl(1 To PR_COUNT) As String, prAsk(1 To PR_COUNT) As String, prRow(1 To PR_COUNT) As String
Dim prName As String, prOut As String, prDevice As String, prDevN As Integer, prI As Integer
Dim prAxes As Integer, prBtns As Integer, prStep As Integer, prK As Long, prLine As String
Dim prJ As Integer, prBtnList As String, prFH As Integer, prPick As Integer

prCtl(1) = "IDLE" : prAsk(1) = "let go of everything"
prCtl(2) = "STICK_UP" : prAsk(2) = "hold the LEFT STICK UP"
prCtl(3) = "STICK_DOWN" : prAsk(3) = "hold the LEFT STICK DOWN"
prCtl(4) = "STICK_LEFT" : prAsk(4) = "hold the LEFT STICK LEFT"
prCtl(5) = "STICK_RIGHT" : prAsk(5) = "hold the LEFT STICK RIGHT"
prCtl(6) = "DPAD_UP" : prAsk(6) = "hold D-PAD UP"
prCtl(7) = "DPAD_DOWN" : prAsk(7) = "hold D-PAD DOWN"
prCtl(8) = "DPAD_LEFT" : prAsk(8) = "hold D-PAD LEFT"
prCtl(9) = "DPAD_RIGHT" : prAsk(9) = "hold D-PAD RIGHT"
prCtl(10) = "A" : prAsk(10) = "hold A (bottom face button)"
prCtl(11) = "B" : prAsk(11) = "hold B (right face button)"
prCtl(12) = "X" : prAsk(12) = "hold X (left face button)"
prCtl(13) = "Y" : prAsk(13) = "hold Y (top face button)"
prCtl(14) = "START" : prAsk(14) = "hold START"
prCtl(15) = "BACK" : prAsk(15) = "hold BACK / SELECT"

prName = LTrim$(RTrim$(Command$))
If prName = "" Then prName = "pad"
prOut = _StartDir$ + "/tests/input/pads/" + prName + ".txt"

Screen _NewImage(640, 160, 32)
_Title "padrecord - " + prName

prDevN = _Devices
ReDim prNames(0 To prDevN) As String
For prI = 1 To prDevN
    prNames(prI) = _Device$(prI)
Next prI
ctrlDev = E3D_CtrlPick%(prNames(), prDevN)
If ctrlDev = 0 Then
    Print "No gamepad found. Plug one in and run padrecord again."
    _Display
    Sleep 5
    System 1
End If
prDevice = prNames(ctrlDev)
prAxes = _LastAxis(ctrlDev)
If prAxes > E3D_PAD_MAX_AXES Then prAxes = E3D_PAD_MAX_AXES
prBtns = _LastButton(ctrlDev)
If prBtns > E3D_PAD_MAX_BTNS Then prBtns = E3D_PAD_MAX_BTNS

prStep = 1
Do While prStep <= PR_COUNT
    E3D_PadRead
    prBtnList = ""
    For prJ = 1 To prBtns
        If padRawBtn(prJ) Then
            If prBtnList <> "" Then prBtnList = prBtnList + ","
            prBtnList = prBtnList + LTrim$(Str$(prJ))
        End If
    Next prJ
    prLine = prCtl(prStep) + " btn=" + prBtnList + " axes="
    For prJ = 1 To prAxes
        If prJ > 1 Then prLine = prLine + " "
        prLine = prLine + LTrim$(Str$(CInt(padRawAxis(prJ) * 100) / 100))
    Next prJ

    Cls
    Print "Recording " + prName + ": " + prDevice
    Print
    Print LTrim$(Str$(prStep)) + "/" + LTrim$(Str$(PR_COUNT)) + ": " + UCase$(prAsk(prStep)) + " and press ENTER"
    Print
    Print "now: " + prLine
    Print
    Print "ESC quits without saving"
    _Display

    prK = _KeyHit
    If prK = 27 Then System 1
    If prK = 13 Then prRow(prStep) = prLine : prStep = prStep + 1
    _Limit 60
Loop

prFH = FreeFile
Open prOut For Output As #prFH
Print #prFH, "# Gamepad fixture: one real controller's raw input, read by tests/pad_map_test.bas."
Print #prFH, "# Recorded with tools/padrecord.bas on " + Date$ + "."
Print #prFH, "#"
Print #prFH, "# Format: header lines, then one line per control:"
Print #prFH, "#   <CONTROL> btn=<pressed buttons, comma-separated, or empty> axes=<one value per axis>"
Print #prFH, "NAME " + prName
Print #prFH, "DEVICE " + prDevice
Print #prFH, "BUTTONS " + LTrim$(Str$(prBtns))
Print #prFH, "AXES " + LTrim$(Str$(prAxes))
For prI = 1 To PR_COUNT
    Print #prFH, prRow(prI)
Next prI
Close #prFH

Cls
Print "Wrote " + prOut
Print "Commit it; tests/pad_map_test checks every control."
_Display
_Delay 2
System 0

' input.bas logs devices through the game's DBG_Print (src/sys/debug.bas)
Sub DBG_Print (prDbgMsg As String)
End Sub
