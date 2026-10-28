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
Const E3D_KEY_Q      = 113   ' nova pulse (#268)
Const E3D_KEY_E      = 101   ' evasive roll (#268)
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

' Remappable actions (#266). Each has a keyboard key (keyBind) and a pad button (padBind);
' E3D_InputUpdate / E3D_PadMap turn them into the held() slots the game reads. The sticks
' and d-pad (axes 1/2, 7/8) are not remappable.
Const E3D_ACT_FIRE    = 1   ' SPACE
Const E3D_ACT_FIRE2   = 2   ' SPACE too: the default B fires as well as backing out of menus
Const E3D_ACT_ROLL    = 3   ' E / PAD_X
Const E3D_ACT_NOVA    = 4   ' Q / PAD_Y
Const E3D_ACT_PAUSE   = 5   ' ESCAPE + PAD_START
Const E3D_ACT_CAMERA  = 6   ' TAB + PAD_SELECT
Const E3D_ACT_CONFIRM = 7   ' ENTER / PAD_A
Const E3D_ACT_BACK    = 8   ' ESCAPE / PAD_B
Const E3D_ACT_PAD_COUNT = 8   ' actions 1-8 take a pad button; the rest are keyboard-only (the stick moves)
Const E3D_ACT_UP      = 9   ' W slot: the keyboard movement set beside the fixed arrows (#192)
Const E3D_ACT_DOWN    = 10  ' S slot
Const E3D_ACT_LEFT    = 11  ' A slot
Const E3D_ACT_RIGHT   = 12  ' D slot
Const E3D_ACT_COUNT   = 12

' Built-in pad layouts, picked by E3D_PadLayoutFor% from the pad's name and counts.
Const E3D_LAYOUT_UNKNOWN = 0   ' gets the xpad defaults until the setup wizard runs
Const E3D_LAYOUT_XPAD    = 1   ' Xbox 360 pad on Linux xpad: A=1 B=2 X=3 Y=4 LB=5 RB=6 Back=7 Start=8 Guide=9
Const E3D_LAYOUT_BT      = 2   ' generic Bluetooth HID "Gamepad": A=1 B=2 C=3 X=4 Y=5 Z=6 LB=7 RB=8 LT=9 RT=10 Back=11 Start=12 Home=13

Const E3D_BIND_PAD = 0
Const E3D_BIND_KEY = 1
Const E3D_PAD_SAVED_MAX = 16

Dim Shared padBind(1 To E3D_ACT_COUNT) As Integer
Dim Shared keyBind(1 To E3D_ACT_COUNT) As Long
Dim Shared padActDown(1 To E3D_ACT_COUNT) As Integer
Dim Shared ctrlName$, ctrlBtnN As Integer, ctrlAxisN As Integer
Dim Shared ctrlLayout As Integer, ctrlGuideBtn As Integer
Dim Shared padSetupDue As Integer   ' an unknown pad with no saved bindings: the title runs the setup wizard
Dim Shared padSavedN As Integer
Dim Shared padSavedName$(1 To E3D_PAD_SAVED_MAX), padSavedBinds$(1 To E3D_PAD_SAVED_MAX)

' The device last used, so prompts name only its buttons: a keyboard key going down picks the
' keyboard, a pad button or a stick / d-pad push past the deadzone picks the pad (and a pad
' found at startup starts it on the pad). Both the real input (E3D_InputUpdate) and scripted
' input (ISC_Apply) report through INP_NoteKeys / E3D_PadMap.
'   dev = INP_LastDevice%     INP_DEV_KEYS or INP_DEV_PAD
Const INP_DEV_KEYS = 0
Const INP_DEV_PAD  = 1
Dim Shared inpLastDev As Integer, inpKeysWas As Integer
Dim Shared inpPadBtnWas(1 To E3D_PAD_MAX_BTNS) As Integer, inpPadAxWas(1 To 4) As Integer

E3D_KeyDefaults
E3D_PadDefaults E3D_LAYOUT_XPAD
ctrlLayout = E3D_LAYOUT_XPAD   ' names buttons the xpad way until a pad is picked

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
        inpLastDev = INP_DEV_PAD
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
    If ctrlDev > 0 Then E3D_PadSelect E3D_PadNameOf$(ctrlScanNames(ctrlDev)), _LastButton(ctrlDev), _LastAxis(ctrlDev)
End Sub

' The [NAME] part of a _DEVICE$ string ("Microsoft X-Box 360 pad"), or the whole string.
Function E3D_PadNameOf$ (pnoDev As String)
    Dim pnoP As Integer, pnoE As Integer
    E3D_PadNameOf$ = pnoDev
    pnoP = InStr(pnoDev, "[NAME][")
    If pnoP = 0 Then Exit Function
    pnoE = InStr(pnoP + 7, pnoDev, "]]")
    If pnoE = 0 Then Exit Function
    E3D_PadNameOf$ = Mid$(pnoDev, pnoP + 7, pnoE - pnoP - 7)
End Function

' Which built-in layout a pad is, from its name and button / axis counts. No hardware calls.
Function E3D_PadLayoutFor% (plfName As String, plfBtns As Integer, plfAxes As Integer)
    Dim plfU As String
    plfU = UCase$(plfName)
    E3D_PadLayoutFor% = E3D_LAYOUT_UNKNOWN
    If (InStr(plfU, "X-BOX") > 0 Or InStr(plfU, "XBOX") > 0) And plfBtns = 11 And plfAxes = 8 Then E3D_PadLayoutFor% = E3D_LAYOUT_XPAD
    If plfU = "GAMEPAD" And plfBtns >= 15 And plfBtns <= 16 And plfAxes >= 4 Then E3D_PadLayoutFor% = E3D_LAYOUT_BT
End Function

' Home / Guide button of a layout (never captured by the setup wizard), 0 if unknown.
Function E3D_PadGuide% (pgLayout As Integer)
    Select Case pgLayout
        Case E3D_LAYOUT_XPAD : E3D_PadGuide% = 9
        Case E3D_LAYOUT_BT : E3D_PadGuide% = 13
        Case Else : E3D_PadGuide% = 0
    End Select
End Function

Sub E3D_PadDefaults (pdLayout As Integer)
    If pdLayout = E3D_LAYOUT_BT Then
        padBind(E3D_ACT_FIRE) = 1 : padBind(E3D_ACT_FIRE2) = 2 : padBind(E3D_ACT_ROLL) = 4 : padBind(E3D_ACT_NOVA) = 5
        padBind(E3D_ACT_PAUSE) = 12 : padBind(E3D_ACT_CAMERA) = 11 : padBind(E3D_ACT_CONFIRM) = 1 : padBind(E3D_ACT_BACK) = 2
    Else
        padBind(E3D_ACT_FIRE) = E3D_CTRL_BTN_FIRE : padBind(E3D_ACT_FIRE2) = E3D_CTRL_BTN_B
        padBind(E3D_ACT_ROLL) = E3D_CTRL_BTN_X : padBind(E3D_ACT_NOVA) = E3D_CTRL_BTN_Y
        padBind(E3D_ACT_PAUSE) = E3D_CTRL_BTN_START : padBind(E3D_ACT_CAMERA) = E3D_CTRL_BTN_SELECT
        padBind(E3D_ACT_CONFIRM) = E3D_CTRL_BTN_FIRE : padBind(E3D_ACT_BACK) = E3D_CTRL_BTN_B
    End If
End Sub

' ESC is fixed to pause and back, and to nothing else.
Sub E3D_KeyDefaults
    keyBind(E3D_ACT_FIRE) = E3D_KEY_SPACE : keyBind(E3D_ACT_FIRE2) = 0
    keyBind(E3D_ACT_ROLL) = E3D_KEY_E : keyBind(E3D_ACT_NOVA) = E3D_KEY_Q
    keyBind(E3D_ACT_PAUSE) = E3D_KEY_ESCAPE : keyBind(E3D_ACT_CAMERA) = E3D_KEY_TAB
    keyBind(E3D_ACT_CONFIRM) = E3D_KEY_ENTER : keyBind(E3D_ACT_BACK) = E3D_KEY_ESCAPE
    keyBind(E3D_ACT_UP) = E3D_KEY_W : keyBind(E3D_ACT_DOWN) = E3D_KEY_S
    keyBind(E3D_ACT_LEFT) = E3D_KEY_A : keyBind(E3D_ACT_RIGHT) = E3D_KEY_D
End Sub

Function E3D_KeyFixed% (kfAct As Integer)
    E3D_KeyFixed% = (kfAct = E3D_ACT_PAUSE Or kfAct = E3D_ACT_BACK)
End Function

' Keys that can't be bound: ESC, the arrows (menus and movement), R/P (camera reset, start game),
' backtick (debug), F11 (fullscreen), and anything outside held()'s range.
Function E3D_KeyReserved% (krCode As Long)
    E3D_KeyReserved% = -1
    If krCode < 8 Or krCode > 32767 Then Exit Function
    Select Case krCode
        Case E3D_KEY_ESCAPE, E3D_KEY_LEFT, E3D_KEY_RIGHT, E3D_KEY_UP, E3D_KEY_DOWN, 96, 34048
            Exit Function
        Case 114, 112, 82, 80
            Exit Function
    End Select
    E3D_KeyReserved% = 0
End Function

' Two actions can't share a button or key, except a ship control (fire, roll, nova) with a
' menu one (confirm, back): menus and flight never read both at once.
Function E3D_BindClash% (bcA As Integer, bcB As Integer)
    Dim bcShipA As Integer, bcShipB As Integer
    E3D_BindClash% = 0
    If bcA = bcB Then Exit Function
    bcShipA = (bcA = E3D_ACT_FIRE Or bcA = E3D_ACT_FIRE2 Or bcA = E3D_ACT_ROLL Or bcA = E3D_ACT_NOVA)
    bcShipB = (bcB = E3D_ACT_FIRE Or bcB = E3D_ACT_FIRE2 Or bcB = E3D_ACT_ROLL Or bcB = E3D_ACT_NOVA)
    If bcShipA And (bcB = E3D_ACT_CONFIRM Or bcB = E3D_ACT_BACK) Then Exit Function
    If bcShipB And (bcA = E3D_ACT_CONFIRM Or bcA = E3D_ACT_BACK) Then Exit Function
    E3D_BindClash% = -1
End Function

Function E3D_ActName$ (anAct As Integer)
    Select Case anAct
        Case E3D_ACT_FIRE : E3D_ActName$ = "FIRE"
        Case E3D_ACT_FIRE2 : E3D_ActName$ = "ALT FIRE"
        Case E3D_ACT_ROLL : E3D_ActName$ = "EVASIVE ROLL"
        Case E3D_ACT_NOVA : E3D_ActName$ = "NOVA PULSE"
        Case E3D_ACT_PAUSE : E3D_ActName$ = "PAUSE"
        Case E3D_ACT_CAMERA : E3D_ActName$ = "OPTIONS/CAMERA"
        Case E3D_ACT_CONFIRM : E3D_ActName$ = "MENU OK"
        Case E3D_ACT_BACK : E3D_ActName$ = "MENU BACK"
        Case E3D_ACT_UP : E3D_ActName$ = "MOVE UP"
        Case E3D_ACT_DOWN : E3D_ActName$ = "MOVE DOWN"
        Case E3D_ACT_LEFT : E3D_ActName$ = "MOVE LEFT"
        Case E3D_ACT_RIGHT : E3D_ActName$ = "MOVE RIGHT"
        Case Else : E3D_ActName$ = "?"
    End Select
End Function

Function E3D_KeyName$ (knCode As Long)
    Select Case knCode
        Case 0 : E3D_KeyName$ = "---"
        Case 8 : E3D_KeyName$ = "BKSP"
        Case 9 : E3D_KeyName$ = "TAB"
        Case 13 : E3D_KeyName$ = "ENTER"
        Case 27 : E3D_KeyName$ = "ESC"
        Case 32 : E3D_KeyName$ = "SPACE"
        Case 33 To 126 : E3D_KeyName$ = UCase$(Chr$(knCode))
        Case 15104 To 17408
            If (knCode - 15104) Mod 256 = 0 Then E3D_KeyName$ = "F" + LTrim$(Str$((knCode - 15104) \ 256 + 1)) Else E3D_KeyName$ = "#" + LTrim$(Str$(knCode))
        Case 34304 : E3D_KeyName$ = "F12"
        Case Else : E3D_KeyName$ = "#" + LTrim$(Str$(knCode))
    End Select
End Function

Function E3D_PadBtnName$ (pbnBtn As Integer, pbnLayout As Integer)
    Dim pbnL As String
    If pbnBtn <= 0 Then E3D_PadBtnName$ = "---" : Exit Function
    If pbnLayout = E3D_LAYOUT_BT Then
        pbnL = "A    B    C    X    Y    Z    LB   RB   LT   RT   BACK STARTHOME LS   RS   "
    ElseIf pbnLayout = E3D_LAYOUT_XPAD Then
        pbnL = "A    B    X    Y    LB   RB   BACK STARTGUIDELS   RS   "
    End If
    If pbnBtn * 5 <= Len(pbnL) Then
        E3D_PadBtnName$ = RTrim$(Mid$(pbnL, pbnBtn * 5 - 4, 5))
    Else
        E3D_PadBtnName$ = "BTN" + LTrim$(Str$(pbnBtn))
    End If
End Function

' Binds the pad named psName: its layout's defaults, then any saved bindings for that name.
' No hardware calls (E3D_CtrlScan passes the counts), so tests drive it with fixture data.
Sub E3D_PadSelect (psName As String, psBtns As Integer, psAxes As Integer)
    Dim psIdx As Integer
    ctrlName$ = psName : ctrlBtnN = psBtns : ctrlAxisN = psAxes
    ctrlLayout = E3D_PadLayoutFor%(psName, psBtns, psAxes)
    ctrlGuideBtn = E3D_PadGuide%(ctrlLayout)
    E3D_PadDefaults ctrlLayout
    psIdx = E3D_PadSavedIdx%(psName)
    If psIdx > 0 Then E3D_BindsParse E3D_BIND_PAD, padSavedBinds$(psIdx)
    padSetupDue = (ctrlLayout = E3D_LAYOUT_UNKNOWN And psIdx = 0)
End Sub

' Re-binds the current pad once SETTINGS_Load has filled the saved table.
Sub E3D_PadReselect
    If ctrlDev > 0 Then E3D_PadSelect ctrlName$, ctrlBtnN, ctrlAxisN
End Sub

Function E3D_PadSavedIdx% (psiName As String)
    Dim psiI As Integer
    E3D_PadSavedIdx% = 0
    For psiI = 1 To padSavedN
        If padSavedName$(psiI) = psiName Then E3D_PadSavedIdx% = psiI : Exit Function
    Next psiI
End Function

' Stores the current pad bindings under the current pad's name (saved by SETTINGS_Save).
Sub E3D_PadRemember
    Dim prmIdx As Integer
    If ctrlName$ = "" Then Exit Sub
    prmIdx = E3D_PadSavedIdx%(ctrlName$)
    If prmIdx = 0 Then
        If padSavedN >= E3D_PAD_SAVED_MAX Then Exit Sub
        padSavedN = padSavedN + 1 : prmIdx = padSavedN
        padSavedName$(prmIdx) = ctrlName$
    End If
    padSavedBinds$(prmIdx) = E3D_BindsStr$(E3D_BIND_PAD)
    padSetupDue = 0
End Sub

' "1,2,3,4,8,7,1,2": one binding per action, in action order.
Function E3D_BindsStr$ (bsKind As Integer)
    Dim bsI As Integer, bsS As String
    For bsI = 1 To E3D_ACT_COUNT
        If bsI > 1 Then bsS = bsS + ","
        If bsKind = E3D_BIND_PAD Then bsS = bsS + LTrim$(Str$(padBind(bsI))) Else bsS = bsS + LTrim$(Str$(keyBind(bsI)))
    Next bsI
    E3D_BindsStr$ = bsS
End Function

' Sets bindings from an E3D_BindsStr$ string; a missing or out-of-range entry keeps its binding.
Sub E3D_BindsParse (bpKind As Integer, bpStr As String)
    Dim bpS As String, bpP As Integer, bpI As Integer, bpV As Long, bpT As String
    bpS = bpStr + ","
    For bpI = 1 To E3D_ACT_COUNT
        bpP = InStr(bpS, ",")
        If bpP = 0 Then Exit For
        bpT = LTrim$(RTrim$(Left$(bpS, bpP - 1)))
        bpS = Mid$(bpS, bpP + 1)
        If bpT <> "" Then
            bpV = Val(bpT)
            If bpKind = E3D_BIND_PAD Then
                If bpI <= E3D_ACT_PAD_COUNT And bpV >= 0 And bpV <= E3D_PAD_MAX_BTNS Then padBind(bpI) = bpV
            ElseIf E3D_KeyFixed%(bpI) = 0 Then
                If bpV = 0 Or E3D_KeyReserved%(bpV) = 0 Then keyBind(bpI) = bpV
            End If
        End If
    Next bpI
End Sub

' Writes the bindings into the open settings file: keys=<binds>, then one
' padbind=<pad name>|<binds> line per pad seen.
Sub E3D_BindsWrite (bwFH As Integer)
    Dim bwI As Integer
    Print #bwFH, "keys=" + E3D_BindsStr$(E3D_BIND_KEY)
    For bwI = 1 To padSavedN
        Print #bwFH, "padbind=" + padSavedName$(bwI) + "|" + padSavedBinds$(bwI)
    Next bwI
End Sub

' One settings line (key, value) -> bindings. -1 if it was a binding line.
Function E3D_BindsLoadLine% (blKey As String, blRaw As String)
    Dim blP As Integer, blI As Integer, blName As String
    E3D_BindsLoadLine% = 0
    If blKey = "keys" Then
        E3D_BindsParse E3D_BIND_KEY, blRaw
        E3D_BindsLoadLine% = -1
    ElseIf blKey = "padbind" Then
        E3D_BindsLoadLine% = -1
        For blI = Len(blRaw) To 1 Step -1
            If Mid$(blRaw, blI, 1) = "|" Then blP = blI : Exit For
        Next blI
        If blP < 2 Then Exit Function
        blName = Left$(blRaw, blP - 1)
        blI = E3D_PadSavedIdx%(blName)
        If blI = 0 Then
            If padSavedN >= E3D_PAD_SAVED_MAX Then Exit Function
            padSavedN = padSavedN + 1 : blI = padSavedN
            padSavedName$(blI) = blName
        End If
        padSavedBinds$(blI) = Mid$(blRaw, blP + 1)
    End If
End Function

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
    held(E3D_KEY_SPACE)  = E3D_KeyBindDown%(keyBind(E3D_ACT_FIRE)) Or E3D_KeyBindDown%(keyBind(E3D_ACT_FIRE2))
    held(E3D_KEY_W)      = E3D_KeyBindDown%(keyBind(E3D_ACT_UP))
    held(E3D_KEY_A)      = E3D_KeyBindDown%(keyBind(E3D_ACT_LEFT))
    held(E3D_KEY_S)      = E3D_KeyBindDown%(keyBind(E3D_ACT_DOWN))
    held(E3D_KEY_D)      = E3D_KeyBindDown%(keyBind(E3D_ACT_RIGHT))
    held(E3D_KEY_ESCAPE) = Abs(_KeyDown(27))
    held(E3D_KEY_TAB)    = E3D_KeyBindDown%(keyBind(E3D_ACT_CAMERA))
    held(E3D_KEY_R)      = Abs(_KeyDown(82)) OR Abs(_KeyDown(114))
    held(E3D_KEY_P)      = Abs(_KeyDown(80)) OR Abs(_KeyDown(112))
    held(E3D_KEY_ENTER)  = E3D_KeyBindDown%(keyBind(E3D_ACT_CONFIRM))
    held(E3D_KEY_Q)      = E3D_KeyBindDown%(keyBind(E3D_ACT_NOVA))
    held(E3D_KEY_E)      = E3D_KeyBindDown%(keyBind(E3D_ACT_ROLL))
    held(E3D_KEY_PAD_START) = 0 : held(E3D_KEY_PAD_A) = 0 : held(E3D_KEY_PAD_B) = 0
    held(E3D_KEY_PAD_X) = 0 : held(E3D_KEY_PAD_Y) = 0 : held(E3D_KEY_PAD_SELECT) = 0
    Dim inpKc As Integer, inpKAny As Integer
    inpKAny = held(E3D_KEY_LEFT) Or held(E3D_KEY_RIGHT) Or held(E3D_KEY_UP) Or held(E3D_KEY_DOWN) Or held(E3D_KEY_ESCAPE) Or held(E3D_KEY_ENTER) Or held(E3D_KEY_TAB)
    For inpKc = 32 To 126
        If _KeyDown(inpKc) Then inpKAny = -1 : Exit For
    Next inpKc
    INP_NoteKeys inpKAny

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
' (whichever is pushed further wins); each action is down when its bound button is
' (padBind), then E3D_PadApply sets the slots.
Sub E3D_PadMap (held() As Integer)
    Dim padMapX As Single, padMapY As Single, padMapI As Integer, padMapB As Integer
    INP_NotePad
    padMapX = padRawAxis(E3D_CTRL_AXIS_X)
    If Abs(padRawAxis(E3D_CTRL_HAT_X)) > Abs(padMapX) Then padMapX = padRawAxis(E3D_CTRL_HAT_X)
    padMapY = padRawAxis(E3D_CTRL_AXIS_Y)
    If Abs(padRawAxis(E3D_CTRL_HAT_Y)) > Abs(padMapY) Then padMapY = padRawAxis(E3D_CTRL_HAT_Y)
    For padMapI = 1 To E3D_ACT_COUNT
        padActDown(padMapI) = 0
        padMapB = padBind(padMapI)
        If padMapI <= E3D_ACT_PAD_COUNT And padMapB >= 1 And padMapB <= E3D_PAD_MAX_BTNS Then padActDown(padMapI) = padRawBtn(padMapB)
    Next padMapI
    E3D_PadApply held(), padMapX, padMapY, padActDown()
End Sub

' The one gamepad -> held() mapping, reached only through E3D_PadMap (real pad and
' scripted pad input alike), so a script presses exactly what a controller would.
' Only sets slots; the caller clears held() first.
Sub E3D_PadApply (held() As Integer, padAxX As Single, padAxY As Single, padAct() As Integer)
    If padAxX < -E3D_AXIS_DEADZONE Then held(E3D_KEY_LEFT)  = 1
    If padAxX >  E3D_AXIS_DEADZONE Then held(E3D_KEY_RIGHT) = 1
    If padAxY < -E3D_AXIS_DEADZONE Then held(E3D_KEY_UP)    = 1
    If padAxY >  E3D_AXIS_DEADZONE Then held(E3D_KEY_DOWN)  = 1
    If padAct(E3D_ACT_FIRE) <> 0 Or padAct(E3D_ACT_FIRE2) <> 0 Then held(E3D_KEY_SPACE) = 1
    If padAct(E3D_ACT_CONFIRM) <> 0 Then held(E3D_KEY_PAD_A) = 1
    If padAct(E3D_ACT_BACK)    <> 0 Then held(E3D_KEY_PAD_B) = 1
    If padAct(E3D_ACT_ROLL)    <> 0 Then held(E3D_KEY_PAD_X) = 1
    If padAct(E3D_ACT_NOVA)    <> 0 Then held(E3D_KEY_PAD_Y) = 1
    If padAct(E3D_ACT_PAUSE)   <> 0 Then held(E3D_KEY_ESCAPE) = 1 : held(E3D_KEY_PAD_START) = 1
    If padAct(E3D_ACT_CAMERA)  <> 0 Then held(E3D_KEY_TAB) = 1 : held(E3D_KEY_PAD_SELECT) = 1
End Sub

' A bound key is down (letters in either case; 0 = unbound). Hardware: E3D_InputUpdate only.
Function E3D_KeyBindDown% (kbdCode As Long)
    E3D_KeyBindDown% = 0
    If kbdCode <= 0 Then Exit Function
    If _KeyDown(kbdCode) Then E3D_KeyBindDown% = 1
    If kbdCode >= 97 And kbdCode <= 122 Then
        If _KeyDown(kbdCode - 32) Then E3D_KeyBindDown% = 1
    End If
End Function

Function INP_LastDevice%
    INP_LastDevice% = inpLastDev
End Function

' inkDown: any keyboard key is down this frame; the keyboard is picked when that starts.
Sub INP_NoteKeys (inkDown As Integer)
    If inkDown <> 0 And inpKeysWas = 0 Then inpLastDev = INP_DEV_KEYS
    inpKeysWas = (inkDown <> 0)
End Sub

' From the raw pad state: the pad is picked when a button goes down or the stick / d-pad
' crosses the deadzone.
Sub INP_NotePad
    Dim inpI As Integer, inpOn As Integer, inpAx(1 To 4) As Integer
    For inpI = 1 To E3D_PAD_MAX_BTNS
        inpOn = (padRawBtn(inpI) <> 0)
        If inpOn And inpPadBtnWas(inpI) = 0 Then inpLastDev = INP_DEV_PAD
        inpPadBtnWas(inpI) = inpOn
    Next inpI
    inpAx(1) = E3D_CTRL_AXIS_X : inpAx(2) = E3D_CTRL_AXIS_Y : inpAx(3) = E3D_CTRL_HAT_X : inpAx(4) = E3D_CTRL_HAT_Y
    For inpI = 1 To 4
        inpOn = (Abs(padRawAxis(inpAx(inpI))) > E3D_AXIS_DEADZONE)
        If inpOn And inpPadAxWas(inpI) = 0 Then inpLastDev = INP_DEV_PAD
        inpPadAxWas(inpI) = inpOn
    Next inpI
End Sub
