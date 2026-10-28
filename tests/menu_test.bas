' menu_test.bas -- moving through menus by position (src/sys/menunav.bas): MENU_Nav% itself,
' then the pause dialog (src/state/pauselogic.bas) and the telemetry consent screen
' (src/state/consentlogic.bas) driven by scripted input through the real input path
' (ISC_Apply -> held() / E3D_PadMap -> KEY_Pressed% / KEY_Confirm% / KEY_Hit&): arrows,
' stick and d-pad move the cursor and wrap, ENTER / pad A take the highlighted row, a fresh
' pause opens on CANCEL (so ENTER resumes), W / S never move a cursor, and every hotkey
' still works whatever row is highlighted. Also the last-used device (INP_LastDevice%) that
' prompts follow: a key press picks the keyboard, a pad button / stick / d-pad push the pad.
'
' Build: ./tools/buildqb tests/menu_test.bas
' Run:   builds/menu_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

Sub DBG_Print (mtDbg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/inputscript.bas'
'$INCLUDE:'../src/sys/menunav.bas'
'$INCLUDE:'../src/state/pauselogic.bas'
'$INCLUDE:'../src/state/consentlogic.bas'

Dim Shared mtPassed As Integer, mtFailed As Integer

Sub MT_Assert (mtaCond As Integer, mtaName As String)
    If mtaCond Then
        Print "PASS  " + mtaName
        mtPassed = mtPassed + 1
    Else
        Print "FAIL  " + mtaName
        mtFailed = mtFailed + 1
    End If
End Sub

' Fresh script from lines separated by "/".
Sub MT_Script (mtsLines As String)
    Dim mtsP As Integer, mtsQ As Integer, mtsOk As Integer
    ISC_Clear
    iscActive = -1
    For mtsP = 0 To 32767 : held(mtsP) = 0 : keyPrevHeld(mtsP) = 0 : Next mtsP
    mtsP = 1
    Do While mtsP <= Len(mtsLines)
        mtsQ = InStr(mtsP, mtsLines, "/")
        If mtsQ = 0 Then mtsQ = Len(mtsLines) + 1
        mtsOk = ISC_ParseLine%(Mid$(mtsLines, mtsP, mtsQ - mtsP))
        If mtsOk = 0 Then Print "bad script line: "; iscError
        mtsP = mtsQ + 1
    Loop
End Sub

Sub MT_Frame (mtfF As Long)
    KEY_FrameBegin
    ISC_Apply mtfF, held()
End Sub

' Pause dialog: fresh and closed, then frames 0..mtpLast of the script; returns the first
' pick (PAUSE_NONE if none), stopping there.
Function MT_Pause% (mtpScript As String, mtpLast As Long)
    Dim mtpF As Long, mtpR As Integer
    MT_Script mtpScript
    escConfirm = 0 : escWas = 0 : pauseSel = PAUSE_ROW_RETREAT
    MT_Pause% = PAUSE_NONE
    For mtpF = 0 To mtpLast
        MT_Frame mtpF
        mtpR = PAUSE_Input%
        If mtpR <> PAUSE_NONE Then MT_Pause% = mtpR : Exit Function
    Next mtpF
End Function

' Consent screen from a fresh cursor (on OK); returns the first pick, stopping there.
Function MT_Consent% (mtcScript As String, mtcLast As Long)
    Dim mtcF As Long, mtcR As Integer
    MT_Script mtcScript
    consentSel = 0
    MT_Consent% = CONSENT_NONE
    For mtcF = 0 To mtcLast
        MT_Frame mtcF
        mtcR = CONSENT_Input%
        If mtcR <> CONSENT_NONE Then MT_Consent% = mtcR : Exit Function
    Next mtcF
End Function

Print "=== menu_test ==="
Print ""

Dim mtSel As Integer, mtR As Integer

E3D_KeyDefaults
E3D_PadSelect "Microsoft X-Box 360 pad", 11, 8

' ---- MENU_Nav% ----
Print "--- MENU_Nav% ---"
mtSel = 0
mtR = MENU_Nav%(mtSel, 4, -1, 0, 0)
MT_Assert mtSel = 3 And mtR = -1, "up from the first row wraps to the last, picks nothing"
mtR = MENU_Nav%(mtSel, 4, 0, -1, 0)
MT_Assert mtSel = 0 And mtR = -1, "down from the last row wraps to the first"
mtR = MENU_Nav%(mtSel, 4, 0, -1, 0)
MT_Assert mtSel = 1, "down moves one row"
mtR = MENU_Nav%(mtSel, 4, 0, 0, -1)
MT_Assert mtSel = 1 And mtR = 1, "confirm picks the highlighted row"
mtR = MENU_Nav%(mtSel, 4, -1, 0, -1)
MT_Assert mtSel = 0 And mtR = -1, "a move and a confirm on one frame: the move only"
mtR = MENU_Nav%(mtSel, 4, 0, 0, 0)
MT_Assert mtSel = 0 And mtR = -1, "no input: nothing"
mtSel = 0
mtR = MENU_Nav%(mtSel, 0, -1, 0, -1)
MT_Assert mtSel = 0 And mtR = -1, "an empty menu never moves or picks"

' ---- pause dialog ----
Print ""
Print "--- pause dialog by position ---"
mtR = MT_Pause%("2 2 ESC", 2)
MT_Assert escConfirm <> 0 And pauseSel = PAUSE_ROW_CANCEL, "ESC opens the dialog with CANCEL highlighted"
mtR = MT_Pause%("2 2 ESC/4 4 ENTER", 6)
MT_Assert mtR = PAUSE_NONE And escConfirm = 0, "ENTER on a fresh pause resumes, not retreats"
mtR = MT_Pause%("2 2 PAD_START/4 4 PAD_A", 6)
MT_Assert mtR = PAUSE_NONE And escConfirm = 0, "pad A on a fresh pause (opened with Start) resumes"
mtR = MT_Pause%("2 2 ESC UP", 2)
MT_Assert pauseSel = PAUSE_ROW_CANCEL, "the press that opens it doesn't also move the cursor"
mtR = MT_Pause%("2 2 ESC/4 4 UP", 4)
MT_Assert pauseSel = PAUSE_ROW_REMAP, "UP: CANCEL -> REMAP CONTROLS"
mtR = MT_Pause%("2 2 ESC/4 4 UP/6 6 UP/8 8 UP", 8)
MT_Assert pauseSel = PAUSE_ROW_RETREAT, "UP x3 reaches CONFIRM RETREAT"
mtR = MT_Pause%("2 2 ESC/4 4 UP/6 6 UP/8 8 UP/10 10 ENTER", 12)
MT_Assert mtR = PAUSE_QUIT And escConfirm = 0, "ENTER on CONFIRM RETREAT retreats"
mtR = MT_Pause%("2 2 ESC/4 4 DOWN", 4)
MT_Assert pauseSel = PAUSE_ROW_RETREAT, "DOWN from CANCEL wraps to CONFIRM RETREAT"
mtR = MT_Pause%("2 2 ESC/4 4 DOWN/6 6 DOWN/8 8 ENTER", 10)
MT_Assert mtR = PAUSE_CONTROLS And escConfirm <> 0, "DOWN x2, ENTER: CONTROLS, dialog stays up"
mtR = MT_Pause%("2 2 ESC/4 4 PAD_DPAD_UP/6 6 PAD_A", 8)
MT_Assert mtR = PAUSE_REMAP And escConfirm <> 0, "d-pad up, pad A: REMAP CONTROLS"
mtR = MT_Pause%("2 2 ESC/4 4 PAD_UP/6 6 PAD_UP/8 8 PAD_A", 10)
MT_Assert mtR = PAUSE_CONTROLS, "stick up x2, pad A: CONTROLS"
mtR = MT_Pause%("2 2 ESC/4 4 PAD_DPAD_DOWN/6 6 PAD_A", 8)
MT_Assert mtR = PAUSE_QUIT, "d-pad down wraps to CONFIRM RETREAT, pad A retreats"
mtR = MT_Pause%("2 2 ESC/4 4 UP/6 6 UP/8 8 DOWN/10 10 DOWN/12 12 PAD_A", 14)
MT_Assert mtR = PAUSE_NONE And escConfirm = 0, "up x2, down x2 is back on CANCEL: resumes"
mtR = MT_Pause%("2 30 UP/2 2 ESC", 30)
MT_Assert pauseSel = PAUSE_ROW_CANCEL, "an arrow already held when it opens doesn't move the cursor"
mtR = MT_Pause%("2 2 ESC/4 4 W/6 6 S/8 8 W", 8)
MT_Assert pauseSel = PAUSE_ROW_CANCEL, "W / S don't move the cursor"
mtR = MT_Pause%("2 2 ESC/4 4 UP/6 6 ESC/8 8 ESC", 8)
MT_Assert escConfirm <> 0 And pauseSel = PAUSE_ROW_CANCEL, "closed and reopened: back on CANCEL"

Print ""
Print "--- pause dialog hotkeys ---"
mtR = MT_Pause%("2 2 ESC/4 4 Y", 6)
MT_Assert mtR = PAUSE_QUIT And escConfirm = 0, "Y retreats (cursor on CANCEL)"
mtR = MT_Pause%("2 2 ESC/4 4 UP/6 6 UP/8 8 UP/10 10 N", 12)
MT_Assert mtR = PAUSE_NONE And escConfirm = 0, "N resumes (cursor on CONFIRM RETREAT)"
mtR = MT_Pause%("2 2 ESC/4 4 PAD_B", 6)
MT_Assert mtR = PAUSE_NONE And escConfirm = 0, "pad B resumes"
mtR = MT_Pause%("2 2 ESC/4 4 C", 6)
MT_Assert mtR = PAUSE_CONTROLS And escConfirm <> 0, "C opens Controls"
mtR = MT_Pause%("2 2 ESC/4 4 PAD_X", 6)
MT_Assert mtR = PAUSE_CONTROLS, "pad X opens Controls"
mtR = MT_Pause%("2 2 ESC/4 4 K", 6)
MT_Assert mtR = PAUSE_REMAP And escConfirm <> 0, "K opens Remap"
mtR = MT_Pause%("2 2 ESC/4 4 PAD_Y", 6)
MT_Assert mtR = PAUSE_REMAP, "pad Y opens Remap"
mtR = MT_Pause%("2 2 ESC/4 4 ESC", 6)
MT_Assert mtR = PAUSE_NONE And escConfirm = 0, "ESC again closes it"

' ---- consent screen ----
Print ""
Print "--- consent screen by position ---"
mtR = MT_Consent%("2 2 ENTER", 4)
MT_Assert mtR = CONSENT_OK, "opens on OK: ENTER takes it"
mtR = MT_Consent%("2 2 PAD_A", 4)
MT_Assert mtR = CONSENT_OK, "pad A takes OK"
mtR = MT_Consent%("2 2 DOWN/4 4 ENTER", 6)
MT_Assert mtR = CONSENT_SAVE, "DOWN, ENTER: DON'T ASK AGAIN"
mtR = MT_Consent%("2 2 DOWN/4 4 DOWN/6 6 ENTER", 8)
MT_Assert mtR = CONSENT_NO, "DOWN x2, ENTER: NO THANKS"
mtR = MT_Consent%("2 2 UP", 2)
MT_Assert consentSel = 2, "UP from OK wraps to NO THANKS"
mtR = MT_Consent%("2 2 UP/4 4 PAD_A", 6)
MT_Assert mtR = CONSENT_NO, "UP, pad A: NO THANKS"
mtR = MT_Consent%("2 2 DOWN/4 4 DOWN/6 6 DOWN/8 8 ENTER", 10)
MT_Assert mtR = CONSENT_OK, "DOWN x3 wraps back to OK"
mtR = MT_Consent%("2 2 PAD_DPAD_DOWN/4 4 PAD_A", 6)
MT_Assert mtR = CONSENT_SAVE, "d-pad down, pad A: DON'T ASK AGAIN"
mtR = MT_Consent%("2 2 PAD_DOWN/4 4 PAD_DOWN/6 6 PAD_A", 8)
MT_Assert mtR = CONSENT_NO, "stick down x2, pad A: NO THANKS"
mtR = MT_Consent%("2 2 W", 4)
MT_Assert mtR = CONSENT_NONE And consentSel = 0, "W doesn't move the cursor or pick"

Print ""
Print "--- consent screen hotkeys ---"
mtR = MT_Consent%("0 0 SPACE", 2)
MT_Assert mtR = CONSENT_OK, "SPACE on frame 0: OK (the playthrough's boot)"
mtR = MT_Consent%("2 2 DOWN/4 4 DOWN/6 6 SPACE", 8)
MT_Assert mtR = CONSENT_OK, "SPACE is OK even with NO THANKS highlighted"
mtR = MT_Consent%("2 2 S", 4)
MT_Assert mtR = CONSENT_SAVE, "S: DON'T ASK AGAIN"
mtR = MT_Consent%("2 2 PAD_X", 4)
MT_Assert mtR = CONSENT_SAVE, "pad X: DON'T ASK AGAIN"
mtR = MT_Consent%("2 2 ESC", 4)
MT_Assert mtR = CONSENT_NO, "ESC: NO THANKS"
mtR = MT_Consent%("2 2 PAD_B", 4)
MT_Assert mtR = CONSENT_NO, "pad B: NO THANKS"

' ---- last-used device (prompts show only its buttons) ----
Print ""
Print "--- last-used device ---"
Dim mtF As Long, mtDevAt(0 To 40) As Integer, mtHeld(0 To 32767) As Integer
MT_Script "0 0 ENTER/2 2 PAD_A/4 4 A/6 6 PAD_DPAD_UP/8 8 UP/10 20 PAD_LEFT/15 15 Y/22 30 PAD_B/25 25 ESC/32 32 PADBTN9/34 34 SPACE/36 36 PAD_RIGHT"
For mtF = 0 To 40
    MT_Frame mtF
    mtDevAt(mtF) = INP_LastDevice%
Next mtF
MT_Assert mtDevAt(0) = INP_DEV_KEYS, "ENTER: keyboard"
MT_Assert mtDevAt(2) = INP_DEV_PAD And mtDevAt(3) = INP_DEV_PAD, "pad A: pad, and it stays the pad once released"
MT_Assert mtDevAt(4) = INP_DEV_KEYS, "a letter key: keyboard"
MT_Assert mtDevAt(6) = INP_DEV_PAD, "d-pad: pad"
MT_Assert mtDevAt(8) = INP_DEV_KEYS, "arrow key: keyboard"
MT_Assert mtDevAt(10) = INP_DEV_PAD, "stick push: pad"
MT_Assert mtDevAt(15) = INP_DEV_KEYS And mtDevAt(20) = INP_DEV_KEYS, "a key while the stick is still held: keyboard, and the held stick doesn't take it back"
MT_Assert mtDevAt(22) = INP_DEV_PAD And mtDevAt(25) = INP_DEV_KEYS And mtDevAt(30) = INP_DEV_KEYS, "ESC while pad B is held: keyboard"
MT_Assert mtDevAt(32) = INP_DEV_PAD, "any raw pad button (the Guide button too): pad"
MT_Assert mtDevAt(34) = INP_DEV_KEYS, "SPACE: keyboard"
MT_Assert mtDevAt(36) = INP_DEV_PAD, "stick right: pad"
MT_Script "0 0 ENTER"
MT_Frame 0
padRawAxis(E3D_CTRL_AXIS_X) = E3D_AXIS_DEADZONE / 2
E3D_PadMap mtHeld()
MT_Assert INP_LastDevice% = INP_DEV_KEYS, "a stick inside the deadzone doesn't pick the pad"
padRawAxis(E3D_CTRL_AXIS_X) = 0
Print ""
Print "=== " + LTrim$(Str$(mtPassed + mtFailed)) + " tests: " + LTrim$(Str$(mtPassed)) + " passed, " + LTrim$(Str$(mtFailed)) + " failed ==="
If mtFailed > 0 Then System 1
System 0
