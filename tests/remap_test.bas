' remap_test.bas -- remappable controls (#266, #192): the pad setup wizard, the Controls
' page reached from the pause dialog, and saving / loading the bindings.
'
' Plays input scripts through the real input path (ISC_Apply -> padRawBtn / held() ->
' E3D_PadMap) into the real RMP_WizStep% / RMP_Input% / PAUSE_Input% each frame, as the
' game does: a full pad wizard run (a held button ignored, a duplicate refused, a skip, a
' timeout, the Guide button ignored, a ship + menu share allowed), ESC cancelling, the
' keyboard wizard (reserved key refused, a key taken from another action), the first-run
' wizard for an unknown pad, pause -> Controls -> rebind -> resume with the new binding
' live and no phantom press, and a save / load round trip through the settings-file lines.
'
' Build: ./tools/buildqb tests/remap_test.bas
' Run:   builds/remap_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

Sub DBG_Print (rtDbg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/inputscript.bas'
'$INCLUDE:'../src/sys/menunav.bas'
'$INCLUDE:'../src/state/pauselogic.bas'
'$INCLUDE:'../src/state/remaplogic.bas'

Dim Shared rtPassed As Integer, rtFailed As Integer
Dim Shared rtGameFrames As Integer   ' frames the game itself ran (pause dialog not up, not in Controls)
Dim Shared rtPhantom As Integer      ' action presses seen on frames with nothing scripted

Sub RT_Assert (rtaCond As Integer, rtaName As String)
    If rtaCond Then
        Print "PASS  " + rtaName
        rtPassed = rtPassed + 1
    Else
        Print "FAIL  " + rtaName
        rtFailed = rtFailed + 1
    End If
End Sub

' Fresh script from lines separated by "/".
Sub RT_Script (rtsLines As String)
    Dim rtsP As Integer, rtsQ As Integer, rtsOk As Integer
    ISC_Clear
    iscActive = -1
    For rtsP = 0 To 32767 : held(rtsP) = 0 : keyPrevHeld(rtsP) = 0 : Next rtsP
    rtsP = 1
    Do While rtsP <= Len(rtsLines)
        rtsQ = InStr(rtsP, rtsLines, "/")
        If rtsQ = 0 Then rtsQ = Len(rtsLines) + 1
        rtsOk = ISC_ParseLine%(Mid$(rtsLines, rtsP, rtsQ - rtsP))
        If rtsOk = 0 Then Print "bad script line: "; iscError
        rtsP = rtsQ + 1
    Loop
End Sub

Sub RT_Frame (rtfF As Long)
    KEY_FrameBegin
    ISC_Apply rtfF, held()
End Sub

Function RT_Skip%
    RT_Skip% = (held(E3D_KEY_LEFT) <> 0) Or (held(E3D_KEY_RIGHT) <> 0) Or (held(E3D_KEY_UP) <> 0) Or (held(E3D_KEY_DOWN) <> 0)
End Function

' Runs the wizard already started on frame 0 from frame 1 on; returns its result and
' leaves the frame it ended on in rtwEnd.
Function RT_Wizard% (rtwLast As Long, rtwEnd As Long)
    Dim rtwF As Long, rtwR As Integer
    RT_Wizard% = -1
    For rtwF = 1 To rtwLast
        RT_Frame rtwF
        rtwR = RMP_WizStep%(KEY_Down%(27), RT_Skip%, KEY_Hit&)
        If rtwR <> RMP_RUNNING Then RT_Wizard% = rtwR : rtwEnd = rtwF : Exit Function
    Next rtwF
End Function

' One main-loop frame of play, the pause dialog and the Controls page.
Sub RT_GameFrame (rtgF As Long)
    Dim rtgPick As Integer, rtgEv As Integer, rtgI As Integer
    RT_Frame rtgF
    Select Case gameState
        Case GS_PLAYING
            rtgPick = PAUSE_Input%
            If rtgPick = PAUSE_REMAP Then RMP_Open GS_PLAYING
            If pauseShown = 0 Then
                rtGameFrames = rtGameFrames + 1
                If iscCount > 0 Then
                    For rtgI = 1 To iscCount
                        If rtgF >= iscFrom(rtgI) And rtgF <= iscTo(rtgI) Then Exit Sub
                    Next rtgI
                End If
                For rtgI = 1 To 6
                    If KEY_Pressed%(rtgI) Then rtPhantom = rtPhantom + 1
                Next rtgI
                If KEY_Pressed%(E3D_KEY_SPACE) Or KEY_Pressed%(E3D_KEY_ESCAPE) Or KEY_Pressed%(E3D_KEY_TAB) Or KEY_Pressed%(E3D_KEY_ENTER) Then rtPhantom = rtPhantom + 1
            End If
        Case GS_REMAP
            rtgEv = RMP_Input%
            rmpSaveDue = 0 : rmpLeft = 0
    End Select
End Sub

Sub RT_Reset
    E3D_KeyDefaults
    padSavedN = 0
    ctrlDev = 0
    E3D_PadSelect "Microsoft X-Box 360 pad", 11, 8
End Sub

Print "=== remap_test ==="
Print ""

Dim rtR As Integer, rtEnd As Long, rtF As Long, rtOk As Integer, rtI As Integer

' ---- full pad wizard ----
Print "--- pad wizard ---"
RT_Reset
RT_Assert ctrlLayout = E3D_LAYOUT_XPAD And ctrlGuideBtn = 9, "Xbox 360 pad -> xpad layout, Guide is button 9"
RT_Script "0 3 PADBTN1/2 2 PADBTN6/4 4 PADBTN6/6 6 PADBTN5/8 8 PAD_RIGHT/620 620 PADBTN8/622 622 PADBTN9/624 624 PADBTN7/626 626 PADBTN6/628 628 PADBTN6/630 630 PADBTN2"
RT_Frame 0
RMP_WizStart E3D_BIND_PAD, 1, E3D_ACT_PAD_COUNT
RT_Assert rmpWizAct = E3D_ACT_FIRE, "the wizard starts at FIRE"
rtR = RT_Wizard%(700, rtEnd)
RT_Assert rtR = RMP_FINISHED And rtEnd = 630, "finished on the last press (frame" + Str$(rtEnd) + ")"
RT_Assert padBind(E3D_ACT_FIRE) = 6, "FIRE took button 6, not the button 1 held when it opened (" + LTrim$(Str$(padBind(E3D_ACT_FIRE))) + ")"
RT_Assert padBind(E3D_ACT_FIRE2) = 5, "ALT FIRE: button 6 again refused, then 5 taken (" + LTrim$(Str$(padBind(E3D_ACT_FIRE2))) + ")"
RT_Assert padBind(E3D_ACT_ROLL) = E3D_CTRL_BTN_X, "ROLL skipped with the stick: keeps its default"
RT_Assert padBind(E3D_ACT_NOVA) = E3D_CTRL_BTN_Y, "NOVA timed out after 10 s: keeps its default"
RT_Assert padBind(E3D_ACT_PAUSE) = 8, "PAUSE took button 8"
RT_Assert padBind(E3D_ACT_CAMERA) = 7, "CAMERA: the Guide button ignored, 7 taken"
RT_Assert padBind(E3D_ACT_CONFIRM) = 6, "MENU OK may share FIRE's button 6"
RT_Assert padBind(E3D_ACT_BACK) = 2, "MENU BACK: 6 refused (MENU OK has it), 2 taken"

RT_Script "0 0 PADBTN6/1 1 PADBTN1"
RT_Frame 0
RT_Assert held(E3D_KEY_SPACE) <> 0 And held(E3D_KEY_PAD_A) <> 0, "button 6 now fires and confirms"
RT_Frame 1
RT_Assert held(E3D_KEY_SPACE) = 0 And held(E3D_KEY_PAD_A) = 0, "button 1 (the old A) does nothing"

' the duplicate message
RT_Reset
RT_Script "2 2 PADBTN6/4 4 PADBTN6"
RT_Frame 0
RMP_WizStart E3D_BIND_PAD, 1, E3D_ACT_PAD_COUNT
rtR = RT_Wizard%(4, rtEnd)
RT_Assert rtR = -1 And rmpWizAct = E3D_ACT_FIRE2, "a duplicate press doesn't advance the wizard"
RT_Assert InStr(rmpMsg$, "ALREADY FIRE") > 0, "and says which action has it: " + rmpMsg$

' ---- ESC cancels ----
Print ""
Print "--- ESC cancels ---"
RT_Reset
RT_Script "2 2 PADBTN6/4 4 ESC/6 6 PADBTN5"
RT_Frame 0
RMP_WizStart E3D_BIND_PAD, 1, E3D_ACT_PAD_COUNT
rtR = RT_Wizard%(20, rtEnd)
RT_Assert rtR = RMP_CANCELLED And rtEnd = 4, "keyboard ESC cancels the wizard"
RT_Assert padBind(E3D_ACT_FIRE) = E3D_CTRL_BTN_FIRE, "and nothing changes (FIRE still button 1)"
RT_Reset
padBind(E3D_ACT_PAUSE) = 0 : padBind(E3D_ACT_BACK) = 0
RT_Script "0 0 PADBTN8/2 2 ESC"
RT_Frame 0
RMP_WizStart E3D_BIND_PAD, 1, E3D_ACT_PAD_COUNT
rtR = RT_Wizard%(10, rtEnd)
RT_Assert rtR = RMP_CANCELLED, "ESC cancels with pause and back unbound on the pad"

' ---- keyboard wizard ----
Print ""
Print "--- keyboard ---"
RT_Reset
RT_Script "2 2 R/4 4 F"
RT_Frame 0
RMP_WizStart E3D_BIND_KEY, E3D_ACT_FIRE, E3D_ACT_FIRE
rtR = RT_Wizard%(10, rtEnd)
RT_Assert InStr(rmpMsg$, "RESERVED") > 0, "R (camera reset) is refused: " + rmpMsg$
RT_Assert rtR = RMP_FINISHED And keyBind(E3D_ACT_FIRE) = 102, "FIRE on F (" + LTrim$(Str$(keyBind(E3D_ACT_FIRE))) + ")"
RT_Script "2 2 F"
RT_Frame 0
RMP_WizStart E3D_BIND_KEY, E3D_ACT_ROLL, E3D_ACT_ROLL
rtR = RT_Wizard%(10, rtEnd)
RT_Assert keyBind(E3D_ACT_ROLL) = 102 And keyBind(E3D_ACT_FIRE) = 0, "ROLL takes F from FIRE, which is left unbound"
RT_Script "2 2 J"
RT_Frame 0
RMP_WizStart E3D_BIND_KEY, E3D_ACT_UP, E3D_ACT_RIGHT
RT_Assert rmpWizAct = E3D_ACT_UP, "movement keys are rebindable (#192)"
rtR = RT_Wizard%(2000, rtEnd)
RT_Assert keyBind(E3D_ACT_UP) = 106 And keyBind(E3D_ACT_LEFT) = E3D_KEY_A, "MOVE UP on J, the rest time out to their defaults"
RT_Script "0 0 ESC"
RT_Frame 0
RMP_WizStart E3D_BIND_KEY, E3D_ACT_PAUSE, E3D_ACT_PAUSE
RT_Assert rmpWizAct > rmpWizLast, "ESC-fixed PAUSE has no key prompt"
RT_Assert E3D_KeyReserved%(E3D_KEY_ESCAPE) And E3D_KeyReserved%(E3D_KEY_LEFT), "ESC and the arrows can't be bound"
E3D_BindsParse E3D_BIND_KEY, "32,0,101,113,9,9,13,9"
RT_Assert keyBind(E3D_ACT_PAUSE) = E3D_KEY_ESCAPE And keyBind(E3D_ACT_BACK) = E3D_KEY_ESCAPE, "a saved line can't move pause / back off ESC"

' ---- first run with an unknown pad ----
Print ""
Print "--- unknown pad ---"
RT_Reset
E3D_PadSelect "Acme Joypad", 12, 6
RT_Assert ctrlLayout = E3D_LAYOUT_UNKNOWN And padSetupDue <> 0, "unknown pad, nothing saved -> setup due"
RT_Assert padBind(E3D_ACT_FIRE) = E3D_CTRL_BTN_FIRE, "and it plays on the xpad defaults meanwhile"
gameState = GS_TITLE
RT_Script "3 3 PADBTN3/6 6 ESC"
RT_Frame 0
RMP_OpenWizard GS_TITLE
For rtF = 1 To 20 : RT_GameFrame rtF : Next rtF
RT_Assert gameState = GS_TITLE, "cancelled first-run setup goes back to the title"
RT_Assert padSetupDue = 0 And E3D_PadSavedIdx%("Acme Joypad") > 0, "and the pad counts as seen (no prompt next launch)"
RT_Assert padBind(E3D_ACT_FIRE) = E3D_CTRL_BTN_FIRE, "with its bindings unchanged"

' ---- pause -> Controls -> rebind -> resume ----
Print ""
Print "--- from the pause dialog ---"
RT_Reset
gameState = GS_PLAYING : escConfirm = 0 : escWas = 0 : rtGameFrames = 0 : rtPhantom = 0
RT_Script "2 2 ESC/4 4 K/8 8 RIGHT/10 10 DOWN/12 12 DOWN/14 14 DOWN/16 16 DOWN/18 18 ENTER/20 20 PADBTN6/24 24 ESC/28 28 N/34 34 PADBTN6/36 36 PADBTN1"
For rtF = 0 To 3
    RT_GameFrame rtF
Next rtF
RT_Assert escConfirm <> 0 And rtGameFrames = 2, "ESC pauses"
RT_GameFrame 4
RT_Assert gameState = GS_REMAP, "K opens Controls from the pause dialog"
For rtF = 5 To 19 : RT_GameFrame rtF : Next rtF
RT_Assert rmpMode = RMP_MODE_WIZ And rmpWizKind = E3D_BIND_PAD And rmpWizAct = E3D_ACT_FIRE, "PAD column, FIRE row, ENTER -> waiting for a button"
RT_GameFrame 20
RT_Assert padBind(E3D_ACT_FIRE) = 6, "FIRE rebound to button 6, live at once"
For rtF = 21 To 25 : RT_GameFrame rtF : Next rtF
RT_Assert gameState = GS_PLAYING And escConfirm <> 0, "ESC goes back to the still-open pause dialog"
RT_Assert rtGameFrames = 2, "the game didn't run while in Controls"
For rtF = 26 To 33 : RT_GameFrame rtF : Next rtF
RT_Assert escConfirm = 0 And rtGameFrames = 7, "N resumes"
RT_Assert rtPhantom = 0, "no phantom press on resume"
RT_GameFrame 34
RT_Assert held(E3D_KEY_SPACE) <> 0, "button 6 fires in play"
RT_GameFrame 35
RT_GameFrame 36
RT_Assert held(E3D_KEY_SPACE) = 0, "button 1 no longer fires"

' ESC always backs out of the page, whatever the pad's pause / back are
RT_Reset
padBind(E3D_ACT_PAUSE) = 0 : padBind(E3D_ACT_BACK) = 0
gameState = GS_PLAYING : escConfirm = 1 : escWas = 0
RT_Script "2 2 ESC"
RMP_Open GS_PLAYING
For rtF = 0 To 6 : RT_GameFrame rtF : Next rtF
RT_Assert gameState = GS_PLAYING, "keyboard ESC leaves Controls with pad pause and back unbound"

' ---- UI sound events (remap.bas plays RMP_EV_* as uiSfx) ----
Print ""
Print "--- UI sound events ---"
Dim rtEvLog As String, rtEv As Integer
RT_Reset
gameState = GS_TITLE
RT_Script "2 2 DOWN/4 4 RIGHT/6 6 ESC"
RT_Frame 0
RMP_Open GS_TITLE
rtEvLog = ""
For rtF = 1 To 10
    RT_Frame rtF
    rtEv = RMP_Input%
    If rtEv <> RMP_EV_NONE Then rtEvLog = rtEvLog + LTrim$(Str$(rtEv)) + ","
Next rtF
RT_Assert rtEvLog = LTrim$(Str$(RMP_EV_MOVE)) + "," + LTrim$(Str$(RMP_EV_MOVE)) + "," + LTrim$(Str$(RMP_EV_BACK)) + ",", "page: row move, column move, ESC leaving is back (" + rtEvLog + ")"

RT_Reset
gameState = GS_TITLE
RT_Script "2 2 ENTER/4 4 PADBTN6/6 6 PADBTN6/8 8 PAD_RIGHT/10 10 ESC"
RT_Frame 0
RMP_Open GS_TITLE
rtEvLog = ""
For rtF = 1 To 14
    RT_Frame rtF
    If rtF = 2 Then rmpSel = RMP_ROW_SETUP
    rtEv = RMP_Input%
    If rtEv <> RMP_EV_NONE Then rtEvLog = rtEvLog + LTrim$(Str$(rtEv)) + ","
Next rtF
RT_Assert rtEvLog = LTrim$(Str$(RMP_EV_OK)) + "," + LTrim$(Str$(RMP_EV_OK)) + "," + LTrim$(Str$(RMP_EV_DENY)) + "," + LTrim$(Str$(RMP_EV_MOVE)) + "," + LTrim$(Str$(RMP_EV_BACK)) + ",", "wizard: start ok, bind taken ok, duplicate deny, skip move, ESC back (" + rtEvLog + ")"
RMP_Leave
rmpLeft = 0 : rmpSaveDue = 0
RT_Reset

' ---- save / load ----
Print ""
Print "--- save / load ---"
RT_Reset
E3D_PadSelect "Weird=Pad|X", 12, 6
padBind(E3D_ACT_FIRE) = 11 : padBind(E3D_ACT_BACK) = 12
E3D_PadRemember
E3D_PadSelect "Microsoft X-Box 360 pad", 11, 8
padBind(E3D_ACT_NOVA) = 6
E3D_PadRemember
keyBind(E3D_ACT_FIRE) = 102 : keyBind(E3D_ACT_UP) = 105
Dim rtPath As String, rtFH As Integer, rtLine As String, rtEq As Integer
rtPath = _StartDir$ + "/remap_test_settings.ini"
rtFH = FreeFile
Open rtPath For Output As #rtFH
Print #rtFH, "music=0.5"
E3D_BindsWrite rtFH
Close #rtFH

E3D_KeyDefaults
padSavedN = 0
rtFH = FreeFile
Open rtPath For Input As #rtFH
Do While Not EOF(rtFH)
    Line Input #rtFH, rtLine
    rtEq = InStr(rtLine, "=")
    If rtEq > 0 Then rtOk = E3D_BindsLoadLine%(Left$(rtLine, rtEq - 1), Mid$(rtLine, rtEq + 1))
Loop
Close #rtFH
Kill rtPath
RT_Assert padSavedN = 2, "two pads read back (" + LTrim$(Str$(padSavedN)) + ")"
RT_Assert keyBind(E3D_ACT_FIRE) = 102 And keyBind(E3D_ACT_UP) = 105 And keyBind(E3D_ACT_ROLL) = E3D_KEY_E, "keyboard bindings read back"
E3D_PadSelect "Weird=Pad|X", 12, 6
RT_Assert padBind(E3D_ACT_FIRE) = 11 And padBind(E3D_ACT_BACK) = 12 And padSetupDue = 0, "a pad named with = and | reads back, no setup due"
E3D_PadSelect "Microsoft X-Box 360 pad", 11, 8
RT_Assert padBind(E3D_ACT_NOVA) = 6 And padBind(E3D_ACT_FIRE) = E3D_CTRL_BTN_FIRE, "the xpad's saved NOVA overrides its built-in layout"
E3D_PadSelect "Gamepad", 16, 8
RT_Assert ctrlLayout = E3D_LAYOUT_BT And padBind(E3D_ACT_ROLL) = 4 And padSetupDue = 0, "an unsaved Bluetooth Gamepad gets its built-in layout, no setup"

Print ""
Print "=== " + LTrim$(Str$(rtPassed + rtFailed)) + " tests: " + LTrim$(Str$(rtPassed)) + " passed, " + LTrim$(Str$(rtFailed)) + " failed ==="
If rtFailed > 0 Then System 1 Else System 0
