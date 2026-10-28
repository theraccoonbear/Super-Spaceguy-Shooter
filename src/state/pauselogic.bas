' pauselogic.bas -- the in-flight ABORT MISSION (pause) dialog's input, no drawing
'
' pick = PAUSE_Input%   once per frame in play, planet arrival and cinematic: ESC (or the
'                       pad's pause button) toggles the dialog (escConfirm); returns what was
'                       picked this frame. pauseShown is -1 when the dialog was up this frame
'                       (the caller draws it and runs nothing else).
' Rows PAUSE_ROW_RETREAT..PAUSE_ROW_CANCEL, cursor pauseSel (up / down, ENTER / pad A picks).
' It opens on CANCEL, so a confirm press on a fresh pause resumes. Hotkeys: Y retreats,
' N / pad B cancels, C / pad X opens Controls, K / pad Y opens Remap.
' Local variable prefix: pz*

Const PAUSE_NONE     = 0
Const PAUSE_QUIT     = 1
Const PAUSE_CONTROLS = 2
Const PAUSE_REMAP    = 3

Const PAUSE_ROW_RETREAT  = 0
Const PAUSE_ROW_CONTROLS = 1
Const PAUSE_ROW_REMAP    = 2
Const PAUSE_ROW_CANCEL   = 3
Const PAUSE_ROWS         = 4

Dim Shared pauseShown As Integer, pauseSel As Integer

Function PAUSE_Input%
    Dim pzWasOpen As Integer, pzYes As Integer, pzNo As Integer, pzCtl As Integer, pzMap As Integer
    Dim pzYk As Integer, pzNk As Integer, pzCk As Integer, pzKk As Integer, pzPick As Integer
    PAUSE_Input% = PAUSE_NONE
    pauseShown = 0
    pzWasOpen = escConfirm
    pzYk = KEY_Down%(89) Or KEY_Down%(121)
    pzNk = KEY_Down%(78) Or KEY_Down%(110)
    pzCk = KEY_Down%(67) Or KEY_Down%(99)
    pzKk = KEY_Down%(75) Or KEY_Down%(107)
    If held(E3D_KEY_ESCAPE) And escWas = 0 Then
        escConfirm = 1 - escConfirm
        If escConfirm Then
            escYWas = pzYk : escNWas = pzNk : escCWas = pzCk : escKWas = pzKk
            pauseSel = PAUSE_ROW_CANCEL
        End If
    End If
    escWas = held(E3D_KEY_ESCAPE)
    If escConfirm = 0 Then Exit Function
    pauseShown = -1
    ' pad: back cancels, roll opens Controls, nova opens Remap (the pause button toggles, as ESC does)
    pzPick = -1
    If pzWasOpen Then pzPick = MENU_Input%(pauseSel, PAUSE_ROWS)
    pzYes = (pzPick = PAUSE_ROW_RETREAT)
    pzNo = (pzWasOpen And KEY_Pressed%(E3D_KEY_PAD_B)) Or (pzPick = PAUSE_ROW_CANCEL)
    pzCtl = (pzWasOpen And KEY_Pressed%(E3D_KEY_PAD_X)) Or (pzPick = PAUSE_ROW_CONTROLS)
    pzMap = (pzWasOpen And KEY_Pressed%(E3D_KEY_PAD_Y)) Or (pzPick = PAUSE_ROW_REMAP)
    If (pzYk And escYWas = 0) Or pzYes Then escConfirm = 0 : PAUSE_Input% = PAUSE_QUIT
    If (pzNk And escNWas = 0) Or pzNo Then escConfirm = 0
    If escConfirm And ((pzCk And escCWas = 0) Or pzCtl) Then PAUSE_Input% = PAUSE_CONTROLS
    If escConfirm And ((pzKk And escKWas = 0) Or pzMap) Then PAUSE_Input% = PAUSE_REMAP
    escYWas = pzYk : escNWas = pzNk : escCWas = pzCk : escKWas = pzKk
End Function
