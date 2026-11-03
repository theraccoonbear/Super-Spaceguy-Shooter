' pause_settings_test.bas -- Settings opened from the pause dialog (#419)
'
' The dialog's Settings row and S hotkey (src/state/pauselogic.bas), the rows Settings shows mid-run
' (src/state/optionsnav.bas), and the way back: pause -> Settings -> Controls remap -> Settings ->
' pause -> resume, by keyboard and by pad, driven by scripted input through the real input path.
' Each step out closes one level: the ESC / B that leaves Settings must not also close the dialog.
'
' Build: ./tools/buildqb tests/pause_settings_test.bas
' Run:   builds/pause_settings_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

Sub DBG_Print (psDbg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/inputscript.bas'
'$INCLUDE:'../src/sys/menunav.bas'
'$INCLUDE:'../src/state/pauselogic.bas'
'$INCLUDE:'../src/state/remaplogic.bas'
'$INCLUDE:'../src/state/titlenav.bas'
'$INCLUDE:'../src/state/optionsnav.bas'

Dim Shared psPassed As Integer, psFailed As Integer

Sub PS_Assert (psaCond As Integer, psaName As String)
    If psaCond Then
        Print "PASS  " + psaName
        psPassed = psPassed + 1
    Else
        Print "FAIL  " + psaName
        psFailed = psFailed + 1
    End If
End Sub

Sub PS_Script (pssLines As String)
    Dim pssP As Integer, pssQ As Integer, pssOk As Integer
    ISC_Clear
    iscActive = -1
    For pssP = 0 To 32767 : held(pssP) = 0 : keyPrevHeld(pssP) = 0 : Next pssP
    pssP = 1
    Do While pssP <= Len(pssLines)
        pssQ = InStr(pssP, pssLines, "/")
        If pssQ = 0 Then pssQ = Len(pssLines) + 1
        pssOk = ISC_ParseLine%(Mid$(pssLines, pssP, pssQ - pssP))
        If pssOk = 0 Then Print "bad script line: "; iscError
        pssP = pssQ + 1
    Loop
End Sub

Sub PS_Frame (psfF As Long)
    KEY_FrameBegin
    ISC_Apply psfF, held()
End Sub

' Runs the pause dialog on frames from..to of the loaded script; returns the first pick.
Function PS_Pause% (psp1 As Long, psp2 As Long)
    Dim pspF As Long, pspR As Integer
    PS_Pause% = PAUSE_NONE
    For pspF = psp1 To psp2
        PS_Frame pspF
        pspR = PAUSE_Input%
        If pspR <> PAUSE_NONE Then PS_Pause% = pspR : Exit Function
    Next pspF
End Function

Dim psR As Integer, psI As Integer, psIds As String, psSfx As Integer

E3D_KeyDefaults
E3D_PadSelect "Microsoft X-Box 360 pad", 11, 8

Print "=== pause_settings_test ==="
Print ""

Print "--- the dialog ---"
PS_Script "2 2 ESC/4 4 UP"
escConfirm = 0 : escWas = 0 : pauseSel = PAUSE_ROW_RETREAT : uiSfx = 0
psR = PS_Pause%(0, 4)
PS_Assert pauseSel = PAUSE_ROW_SETTINGS, "UP from CANCEL lands on SETTINGS"
PS_Script "2 2 ESC/4 4 UP/6 6 ENTER"
escConfirm = 0 : escWas = 0 : pauseSel = PAUSE_ROW_RETREAT
psR = PS_Pause%(0, 8)
PS_Assert psR = PAUSE_SETTINGS And escConfirm <> 0, "ENTER on SETTINGS picks it, the dialog stays up"
PS_Script "2 2 ESC/4 4 S"
escConfirm = 0 : escWas = 0 : pauseSel = PAUSE_ROW_RETREAT
psR = PS_Pause%(0, 6)
PS_Assert psR = PAUSE_SETTINGS And escConfirm <> 0, "S picks SETTINGS from any row"
PS_Script "2 2 PAD_START/4 4 PAD_DPAD_UP/6 6 PAD_A"
escConfirm = 0 : escWas = 0 : pauseSel = PAUSE_ROW_RETREAT
psR = PS_Pause%(0, 8)
PS_Assert psR = PAUSE_SETTINGS, "pad: d-pad up, A picks SETTINGS"

Print ""
Print "--- rows shown ---"
optReturn = 0
PS_Assert OPTS_RowCount% = OPT_ROWS_ALL, "from the title all rows show"
psIds = ""
For psI = 0 To OPTS_RowCount% - 1 : psIds = psIds + LTrim$(Str$(OPTS_RowId%(psI))) + "," : Next psI
PS_Assert psIds = "0,1,2,3,4,5,6,7,", "from the title the ids run in order"
gameState = GS_PLAYING
OPTS_OpenFromPause GS_PLAYING
PS_Assert gameState = GS_OPTIONS And optReturn = GS_PLAYING, "opening goes to Settings and remembers the run state"
PS_Assert musHold <> 0, "music and narration are held"
PS_Assert optSel = 0, "opens on the first row"
psIds = ""
For psI = 0 To OPTS_RowCount% - 1 : psIds = psIds + LTrim$(Str$(OPTS_RowId%(psI))) + "," : Next psI
PS_Assert psIds = "0,1,2,4,7,", "in-run rows: MUSIC, SFX, SPEECH, FULLSCREEN, CONTROLS"
PS_Assert OPTS_RowCount% = 5, "callsign, difficulty and narration are hidden in-run"

Print ""
Print "--- the way back, keyboard ---"
' pause (frames 0-4) -> Settings -> remap -> Settings -> ESC out -> pause -> ESC resumes
optReturn = 0 : musHold = 0 : gameState = GS_PLAYING
PS_Script "2 2 ESC/4 4 UP/6 6 ENTER/12 14 ESC/20 22 ESC"
escConfirm = 0 : escWas = 0 : pauseSel = PAUSE_ROW_RETREAT : uiSfx = 0
psR = PS_Pause%(0, 8)
PS_Assert psR = PAUSE_SETTINGS, "pause: SETTINGS picked"
OPTS_OpenFromPause gameState
RMP_Open GS_OPTIONS
PS_Assert gameState = GS_REMAP And optReturn = GS_PLAYING, "Settings -> remap keeps the in-run context"
RMP_Leave
PS_Assert gameState = GS_OPTIONS And optReturn = GS_PLAYING And musHold <> 0, "remap -> back in Settings, still in-run and held"
PS_Frame 12
OPTS_Leave
PS_Assert gameState = GS_PLAYING And optReturn = 0 And musHold = 0, "ESC in Settings -> the run's state, music released"
PS_Assert escConfirm <> 0, "the pause dialog is still up"
For psI = 13 To 14
    PS_Frame psI
    psR = PAUSE_Input%
Next psI
PS_Assert escConfirm <> 0 And pauseShown <> 0 And psR = PAUSE_NONE, "the ESC that left Settings does not close the dialog"
PS_Assert pauseSel = PAUSE_ROW_SETTINGS, "the cursor is still on SETTINGS"
For psI = 15 To 22
    PS_Frame psI
    psR = PAUSE_Input%
Next psI
PS_Assert escConfirm = 0, "a fresh ESC closes the dialog: the run resumes"

Print ""
Print "--- the way back, pad ---"
optReturn = 0 : musHold = 0 : gameState = GS_PLAYING
PS_Script "2 2 PAD_START/4 4 PAD_DPAD_UP/6 6 PAD_A/12 14 PAD_B/20 20 PAD_B"
escConfirm = 0 : escWas = 0 : pauseSel = PAUSE_ROW_RETREAT : uiSfx = 0
psR = PS_Pause%(0, 8)
PS_Assert psR = PAUSE_SETTINGS, "pad: SETTINGS picked"
OPTS_OpenFromPause gameState
PS_Frame 12
OPTS_Leave
For psI = 13 To 16
    PS_Frame psI
    psR = PAUSE_Input%
Next psI
PS_Assert gameState = GS_PLAYING And escConfirm <> 0 And psR = PAUSE_NONE, "pad B out of Settings does not also cancel the dialog"
For psI = 17 To 20
    PS_Frame psI
    psR = PAUSE_Input%
Next psI
PS_Assert escConfirm = 0, "a fresh pad B cancels the dialog: the run resumes"

Print ""
Print "--- the title is unchanged ---"
optReturn = 0 : musHold = 0 : gameState = GS_OPTIONS
OPTS_Leave
PS_Assert gameState = GS_TITLE And musHold = 0, "from the title, ESC returns to the title"

Print ""
Print "=== " + LTrim$(Str$(psPassed + psFailed)) + " tests: " + LTrim$(Str$(psPassed)) + " passed, " + LTrim$(Str$(psFailed)) + " failed ==="
If psFailed > 0 Then System 1
System 0
