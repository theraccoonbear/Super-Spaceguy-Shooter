' Key index constants — pass these to E3D_KeyHeld
Const E3D_KEY_LEFT   = 19200
Const E3D_KEY_RIGHT  = 19712
Const E3D_KEY_UP     = 18432
Const E3D_KEY_DOWN   = 20480
Const E3D_KEY_SPACE  = 32
Const E3D_KEY_W      = 119
Const E3D_KEY_A      = 97
Const E3D_KEY_S      = 115
Const E3D_KEY_D      = 100
Const E3D_KEY_ESCAPE = 27
Const E3D_KEY_TAB    = 9
Const E3D_KEY_R      = 114
Const E3D_KEY_P      = 112
Const E3D_KEY_ENTER  = 13
' Virtual slots, one per gamepad button (no keyboard key uses codes 1-6), so menus can
' tell a pad button from the key it doubles as: Start also sets ESCAPE, A sets SPACE,
' Back sets TAB.
Const E3D_KEY_PAD_START  = 1
Const E3D_KEY_PAD_A      = 2
Const E3D_KEY_PAD_B      = 3
Const E3D_KEY_PAD_X      = 4
Const E3D_KEY_PAD_Y      = 5
Const E3D_KEY_PAD_SELECT = 6

' Controller mapping constants — adjust if your gamepad layout differs
Const E3D_AXIS_DEADZONE    = 0.25  ' ignore stick deflection below this threshold
Const E3D_CTRL_AXIS_X      = 1     ' left stick horizontal
Const E3D_CTRL_AXIS_Y      = 2     ' left stick vertical
Const E3D_CTRL_HAT_X       = 7     ' d-pad horizontal (xpad reports the hat as axes)
Const E3D_CTRL_HAT_Y       = 8     ' d-pad vertical (xpad reports the hat as axes)
Const E3D_CTRL_BTN_FIRE    = 1     ' A / Cross
Const E3D_CTRL_BTN_B       = 2     ' B / Circle
Const E3D_CTRL_BTN_X       = 3     ' X / Square
Const E3D_CTRL_BTN_Y       = 4     ' Y / Triangle
Const E3D_CTRL_BTN_SELECT  = 7     ' Back / Select
Const E3D_CTRL_BTN_START   = 8     ' Start / Options
Const E3D_CTRL_RESCAN_TICKS = 60   ' with no pad, look for a newly plugged one this often (frames)

' Raw pad state: the last value of every axis and button of the pad (ctrlDev), as
' E3D_PadRead copied it from the hardware, or as scripted input (ISC_Apply) set it.
' E3D_PadMap turns it into held() slots, so a test can set it from a recorded pad.
Const E3D_PAD_MAX_AXES = 16
Const E3D_PAD_MAX_BTNS = 32
Dim Shared padRawAxis(1 To E3D_PAD_MAX_AXES) As Single
Dim Shared padRawBtn(1 To E3D_PAD_MAX_BTNS) As Integer

Dim Shared ctrlDev As Integer

' Scan for a connected gamepad/joystick; call once at startup after SCREEN is open.
Sub E3D_CtrlInit
    Dim ctrlN As Integer, ctrlI As Integer
    ctrlN = _DEVICES
    DBG_Print "Input devices (" + LTRIM$(STR$(ctrlN)) + "):"
    For ctrlI = 1 To ctrlN
        DBG_Print "  [" + LTRIM$(STR$(ctrlI)) + "] " + _DEVICE$(ctrlI)
    Next ctrlI
    E3D_CtrlScan ctrlN
    If ctrlDev > 0 Then
        DBG_Print "Gamepad: device " + LTRIM$(STR$(ctrlDev))
    Else
        DBG_Print "No gamepad found; keyboard-only"
    End If
End Sub

' Sets ctrlDev to E3D_CtrlPick% of devices 1..ctrlScanN's real names.
Sub E3D_CtrlScan (ctrlScanN As Integer)
    Dim ctrlScanI As Integer
    ReDim ctrlScanNames(0 To ctrlScanN) As String
    For ctrlScanI = 1 To ctrlScanN
        ctrlScanNames(ctrlScanI) = _DEVICE$(ctrlScanI)
    Next ctrlScanI
    ctrlDev = E3D_CtrlPick%(ctrlScanNames(), ctrlScanN)
End Sub

' The last connected pad among _DEVICE$ names 1..ctrlPkCount, or 0. No hardware calls.
' A pad unplugged mid-run keeps its slot (its name gains "[DISCONNECTED]"), so
' only a pad absent at launch needs the rescan in E3D_InputUpdate.
Function E3D_CtrlPick% (ctrlPkNames() As String, ctrlPkCount As Integer)
    Dim ctrlPkI As Integer, ctrlPkDev As Integer
    ctrlPkDev = 0
    For ctrlPkI = 1 To ctrlPkCount
        If InStr(ctrlPkNames(ctrlPkI), "[DISCONNECTED]") = 0 Then
            If InStr(ctrlPkNames(ctrlPkI), "[CONTROLLER]") > 0 Or InStr(ctrlPkNames(ctrlPkI), "[GAMEPAD]") > 0 Or InStr(ctrlPkNames(ctrlPkI), "[JOYSTICK]") > 0 Then
                ctrlPkDev = ctrlPkI
            End If
        End If
    Next ctrlPkI
    E3D_CtrlPick% = ctrlPkDev
End Function

' Late-plug check, without touching hardware: with no pad (ctrlRsDev = 0), once
' ctrlRsTick frames have passed, rescan when the device count (ctrlRsDevs) differs
' from the count at the last look (ctrlRsSeen).
Function E3D_CtrlRescanDue% (ctrlRsTick As Integer, ctrlRsDevs As Integer, ctrlRsSeen As Integer, ctrlRsDev As Integer)
    E3D_CtrlRescanDue% = 0
    If ctrlRsDev <> 0 Then Exit Function
    If ctrlRsTick < E3D_CTRL_RESCAN_TICKS Then Exit Function
    If ctrlRsDevs = ctrlRsSeen Then Exit Function
    E3D_CtrlRescanDue% = -1
End Function

' Call once per frame before reading input: keyboard, then the pad (E3D_PadRead copies
' the hardware into the raw pad state, E3D_PadMap maps that onto held()).
Sub E3D_InputUpdate (held() As Integer)
    held(E3D_KEY_LEFT)   = Abs(_KeyDown(19200))
    held(E3D_KEY_RIGHT)  = Abs(_KeyDown(19712))
    held(E3D_KEY_UP)     = Abs(_KeyDown(18432))
    held(E3D_KEY_DOWN)   = Abs(_KeyDown(20480))
    held(E3D_KEY_SPACE)  = Abs(_KeyDown(32))
    held(E3D_KEY_W)      = Abs(_KeyDown(119))
    held(E3D_KEY_A)      = Abs(_KeyDown(97))
    held(E3D_KEY_S)      = Abs(_KeyDown(115))
    held(E3D_KEY_D)      = Abs(_KeyDown(100))
    held(E3D_KEY_ESCAPE) = Abs(_KeyDown(27))
    held(E3D_KEY_TAB)    = Abs(_KeyDown(9))
    held(E3D_KEY_R)      = Abs(_KeyDown(82)) OR Abs(_KeyDown(114))
    held(E3D_KEY_P)      = Abs(_KeyDown(80)) OR Abs(_KeyDown(112))
    held(E3D_KEY_ENTER)  = Abs(_KeyDown(13))
    held(E3D_KEY_PAD_START) = 0 : held(E3D_KEY_PAD_A) = 0 : held(E3D_KEY_PAD_B) = 0
    held(E3D_KEY_PAD_X) = 0 : held(E3D_KEY_PAD_Y) = 0 : held(E3D_KEY_PAD_SELECT) = 0

    ' _DEVICES is only counted every E3D_CTRL_RESCAN_TICKS frames
    Static ctrlPlugTick As Integer
    Static ctrlPlugSeen As Integer
    Dim ctrlPlugNow As Integer, ctrlPlugDue As Integer
    If ctrlDev = 0 Then
        ctrlPlugTick = ctrlPlugTick + 1
        If ctrlPlugTick < E3D_CTRL_RESCAN_TICKS Then Exit Sub
        ctrlPlugNow = _DEVICES
        ctrlPlugDue = E3D_CtrlRescanDue%(ctrlPlugTick, ctrlPlugNow, ctrlPlugSeen, ctrlDev)
        ctrlPlugTick = 0
        ctrlPlugSeen = ctrlPlugNow
        If ctrlPlugDue = 0 Then Exit Sub
        E3D_CtrlScan ctrlPlugNow
        If ctrlDev = 0 Then Exit Sub
        DBG_Print "Gamepad: device " + LTRIM$(STR$(ctrlDev))
    End If

    E3D_PadRead
    E3D_PadMap held()
End Sub

' The only code that reads the pad hardware. _AXIS / _BUTTON operate on the device set
' by the most recent _DEVICEINPUT call (no device-number param), so drain the queue and
' copy the pad's axes and buttons when the event is ours. Values persist between events.
Sub E3D_PadRead
    Dim padRdD As Integer, padRdI As Integer, padRdN As Integer
    Do
        padRdD = _DEVICEINPUT
        If padRdD = ctrlDev And ctrlDev > 0 Then
            padRdN = _LASTAXIS(ctrlDev)
            If padRdN > E3D_PAD_MAX_AXES Then padRdN = E3D_PAD_MAX_AXES
            For padRdI = 1 To padRdN
                padRawAxis(padRdI) = _AXIS(padRdI)
            Next padRdI
            padRdN = _LASTBUTTON(ctrlDev)
            If padRdN > E3D_PAD_MAX_BTNS Then padRdN = E3D_PAD_MAX_BTNS
            For padRdI = 1 To padRdN
                padRawBtn(padRdI) = Abs(_BUTTON(padRdI))
            Next padRdI
        End If
    Loop While padRdD <> 0
End Sub

' Raw pad state -> held(), no hardware calls. The stick and d-pad mix per axis
' (whichever is pushed further wins), then E3D_PadApply sets the slots.
Sub E3D_PadMap (held() As Integer)
    Dim padMapX As Single, padMapY As Single
    padMapX = padRawAxis(E3D_CTRL_AXIS_X)
    If Abs(padRawAxis(E3D_CTRL_HAT_X)) > Abs(padMapX) Then padMapX = padRawAxis(E3D_CTRL_HAT_X)
    padMapY = padRawAxis(E3D_CTRL_AXIS_Y)
    If Abs(padRawAxis(E3D_CTRL_HAT_Y)) > Abs(padMapY) Then padMapY = padRawAxis(E3D_CTRL_HAT_Y)
    E3D_PadApply held(), padMapX, padMapY, padRawBtn(E3D_CTRL_BTN_FIRE), padRawBtn(E3D_CTRL_BTN_B), padRawBtn(E3D_CTRL_BTN_X), padRawBtn(E3D_CTRL_BTN_Y), padRawBtn(E3D_CTRL_BTN_START), padRawBtn(E3D_CTRL_BTN_SELECT)
End Sub

' The one gamepad -> held() mapping, reached only through E3D_PadMap (real pad and
' scripted pad input alike), so a script presses exactly what a controller would.
' Only sets slots; the caller clears held() first.
Sub E3D_PadApply (held() As Integer, padAxX As Single, padAxY As Single, padA As Integer, padB As Integer, padX As Integer, padY As Integer, padStart As Integer, padSel As Integer)
    If padAxX < -E3D_AXIS_DEADZONE Then held(E3D_KEY_LEFT)  = 1
    If padAxX >  E3D_AXIS_DEADZONE Then held(E3D_KEY_RIGHT) = 1
    If padAxY < -E3D_AXIS_DEADZONE Then held(E3D_KEY_UP)    = 1
    If padAxY >  E3D_AXIS_DEADZONE Then held(E3D_KEY_DOWN)  = 1
    If padA     <> 0 Then held(E3D_KEY_SPACE)  = 1 : held(E3D_KEY_PAD_A) = 1
    If padB     <> 0 Then held(E3D_KEY_SPACE)  = 1 : held(E3D_KEY_PAD_B) = 1
    If padX     <> 0 Then held(E3D_KEY_PAD_X)  = 1
    If padY     <> 0 Then held(E3D_KEY_PAD_Y)  = 1
    If padStart <> 0 Then held(E3D_KEY_ESCAPE) = 1 : held(E3D_KEY_PAD_START) = 1
    If padSel   <> 0 Then held(E3D_KEY_TAB)    = 1 : held(E3D_KEY_PAD_SELECT) = 1
End Sub
