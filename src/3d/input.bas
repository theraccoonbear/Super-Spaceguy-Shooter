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

' Controller mapping constants — adjust if your gamepad layout differs
Const E3D_AXIS_DEADZONE    = 0.25  ' ignore stick deflection below this threshold
Const E3D_CTRL_AXIS_X      = 1     ' left stick horizontal
Const E3D_CTRL_AXIS_Y      = 2     ' left stick vertical
Const E3D_CTRL_BTN_FIRE    = 1     ' A / Cross
Const E3D_CTRL_BTN_SELECT  = 7     ' Back / Select
Const E3D_CTRL_BTN_START   = 8     ' Start / Options

' Scan for a connected gamepad/joystick; call once at startup after SCREEN is open.
Sub E3D_CtrlInit
    Dim ctrlN As Integer, ctrlI As Integer
    ctrlN = _DEVICES
    ctrlDev = 0
    For ctrlI = 1 To ctrlN
        If InStr(_DEVICE$(ctrlI), "[GAMEPAD]") > 0 Or InStr(_DEVICE$(ctrlI), "[JOYSTICK]") > 0 Then
            ctrlDev = ctrlI
            DBG_Print "Gamepad (device" + LTRIM$(STR$(ctrlI)) + "): " + _DEVICE$(ctrlI)
            Exit For
        End If
    Next ctrlI
    If ctrlDev = 0 Then DBG_Print "No gamepad found; keyboard-only"
End Sub

' Call once per frame before reading input.
' _AXIS / _BUTTON operate on the device set by the most recent _DEVICEINPUT call
' (no device-number param), so we poll the queue and capture state when it is our device.
' STATIC vars preserve last-known state for buttons that fire only on press/release events.
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

    If ctrlDev = 0 Then Exit Sub

    Static ctrlAxX    As Single
    Static ctrlAxY    As Single
    Static ctrlFire   As Integer
    Static ctrlStart  As Integer
    Static ctrlSel    As Integer

    Dim ctrlD As Integer
    Do
        ctrlD = _DEVICEINPUT
        If ctrlD = ctrlDev Then
            If _LASTAXIS(ctrlDev)   >= E3D_CTRL_AXIS_X     Then ctrlAxX   = _AXIS(E3D_CTRL_AXIS_X)
            If _LASTAXIS(ctrlDev)   >= E3D_CTRL_AXIS_Y     Then ctrlAxY   = _AXIS(E3D_CTRL_AXIS_Y)
            If _LASTBUTTON(ctrlDev) >= E3D_CTRL_BTN_FIRE   Then ctrlFire  = Abs(_BUTTON(E3D_CTRL_BTN_FIRE))
            If _LASTBUTTON(ctrlDev) >= E3D_CTRL_BTN_START  Then ctrlStart = Abs(_BUTTON(E3D_CTRL_BTN_START))
            If _LASTBUTTON(ctrlDev) >= E3D_CTRL_BTN_SELECT Then ctrlSel   = Abs(_BUTTON(E3D_CTRL_BTN_SELECT))
        End If
    Loop While ctrlD <> 0

    If ctrlAxX < -E3D_AXIS_DEADZONE Then held(E3D_KEY_LEFT)  = 1
    If ctrlAxX >  E3D_AXIS_DEADZONE Then held(E3D_KEY_RIGHT) = 1
    If ctrlAxY < -E3D_AXIS_DEADZONE Then held(E3D_KEY_UP)    = 1
    If ctrlAxY >  E3D_AXIS_DEADZONE Then held(E3D_KEY_DOWN)  = 1
    If ctrlFire  <> 0 Then held(E3D_KEY_SPACE)  = 1
    If ctrlStart <> 0 Then held(E3D_KEY_ESCAPE) = 1
    If ctrlSel   <> 0 Then held(E3D_KEY_TAB)    = 1
End Sub
