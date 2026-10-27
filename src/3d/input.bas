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
Const E3D_CTRL_BTN_FIRE    = 1     ' A / Cross
Const E3D_CTRL_BTN_B       = 2     ' B / Circle
Const E3D_CTRL_BTN_X       = 3     ' X / Square
Const E3D_CTRL_BTN_Y       = 4     ' Y / Triangle
Const E3D_CTRL_BTN_SELECT  = 7     ' Back / Select
Const E3D_CTRL_BTN_START   = 8     ' Start / Options

' Scan for a connected gamepad/joystick; call once at startup after SCREEN is open.
Sub E3D_CtrlInit
    Dim ctrlN As Integer, ctrlI As Integer
    ctrlN = _DEVICES
    ctrlDev = 0
    DBG_Print "Input devices (" + LTRIM$(STR$(ctrlN)) + "):"
    For ctrlI = 1 To ctrlN
        DBG_Print "  [" + LTRIM$(STR$(ctrlI)) + "] " + _DEVICE$(ctrlI)
        If InStr(_DEVICE$(ctrlI), "[CONTROLLER]") > 0 Or InStr(_DEVICE$(ctrlI), "[GAMEPAD]") > 0 Or InStr(_DEVICE$(ctrlI), "[JOYSTICK]") > 0 Then
            ctrlDev = ctrlI
        End If
    Next ctrlI
    If ctrlDev > 0 Then
        DBG_Print "Gamepad: device " + LTRIM$(STR$(ctrlDev))
    Else
        DBG_Print "No gamepad found; keyboard-only"
    End If
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
    held(E3D_KEY_P)      = Abs(_KeyDown(80)) OR Abs(_KeyDown(112))
    held(E3D_KEY_ENTER)  = Abs(_KeyDown(13))
    held(E3D_KEY_PAD_START) = 0 : held(E3D_KEY_PAD_A) = 0 : held(E3D_KEY_PAD_B) = 0
    held(E3D_KEY_PAD_X) = 0 : held(E3D_KEY_PAD_Y) = 0 : held(E3D_KEY_PAD_SELECT) = 0

    If ctrlDev = 0 Then Exit Sub

    Static ctrlAxX    As Single
    Static ctrlAxY    As Single
    Static ctrlFire   As Integer
    Static ctrlB      As Integer
    Static ctrlX      As Integer
    Static ctrlY      As Integer
    Static ctrlStart  As Integer
    Static ctrlSel    As Integer

    Dim ctrlD As Integer
    Do
        ctrlD = _DEVICEINPUT
        If ctrlD = ctrlDev Then
            If _LASTAXIS(ctrlDev)   >= E3D_CTRL_AXIS_X     Then ctrlAxX   = _AXIS(E3D_CTRL_AXIS_X)
            If _LASTAXIS(ctrlDev)   >= E3D_CTRL_AXIS_Y     Then ctrlAxY   = _AXIS(E3D_CTRL_AXIS_Y)
            If _LASTBUTTON(ctrlDev) >= E3D_CTRL_BTN_FIRE   Then ctrlFire  = Abs(_BUTTON(E3D_CTRL_BTN_FIRE))
            If _LASTBUTTON(ctrlDev) >= E3D_CTRL_BTN_B      Then ctrlB     = Abs(_BUTTON(E3D_CTRL_BTN_B))
            If _LASTBUTTON(ctrlDev) >= E3D_CTRL_BTN_X      Then ctrlX     = Abs(_BUTTON(E3D_CTRL_BTN_X))
            If _LASTBUTTON(ctrlDev) >= E3D_CTRL_BTN_Y      Then ctrlY     = Abs(_BUTTON(E3D_CTRL_BTN_Y))
            If _LASTBUTTON(ctrlDev) >= E3D_CTRL_BTN_START  Then ctrlStart = Abs(_BUTTON(E3D_CTRL_BTN_START))
            If _LASTBUTTON(ctrlDev) >= E3D_CTRL_BTN_SELECT Then ctrlSel   = Abs(_BUTTON(E3D_CTRL_BTN_SELECT))
        End If
    Loop While ctrlD <> 0

    E3D_PadApply held(), ctrlAxX, ctrlAxY, ctrlFire, ctrlB, ctrlX, ctrlY, ctrlStart, ctrlSel
End Sub

' The one gamepad -> held() mapping, shared by the real pad (E3D_InputUpdate) and
' scripted pad input (ISC_Apply), so a script presses exactly what a controller would.
' Only sets slots; the caller clears held() first.
Sub E3D_PadApply (held() As Integer, padAxX As Single, padAxY As Single, padA As Integer, padB As Integer, padX As Integer, padY As Integer, padStart As Integer, padSel As Integer)
    If padAxX < -E3D_AXIS_DEADZONE Then held(E3D_KEY_LEFT)  = 1
    If padAxX >  E3D_AXIS_DEADZONE Then held(E3D_KEY_RIGHT) = 1
    If padAxY < -E3D_AXIS_DEADZONE Then held(E3D_KEY_UP)    = 1
    If padAxY >  E3D_AXIS_DEADZONE Then held(E3D_KEY_DOWN)  = 1
    If padA     <> 0 Then held(E3D_KEY_SPACE)  = 1 : held(E3D_KEY_PAD_A) = 1
    If padB     <> 0 Then held(E3D_KEY_PAD_B)  = 1
    If padX     <> 0 Then held(E3D_KEY_PAD_X)  = 1
    If padY     <> 0 Then held(E3D_KEY_PAD_Y)  = 1
    If padStart <> 0 Then held(E3D_KEY_ESCAPE) = 1 : held(E3D_KEY_PAD_START) = 1
    If padSel   <> 0 Then held(E3D_KEY_TAB)    = 1 : held(E3D_KEY_PAD_SELECT) = 1
End Sub
