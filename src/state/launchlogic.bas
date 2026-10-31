' launchlogic.bas -- the title's LAUNCH NOW? confirm, input only (title.bas draws it)
'
' pick = LAUNCH_Input%(startHeld)   once per frame on the title (not while its console is up);
'                                   startHeld is P or pad Start down this frame. Returns
'                                   LAUNCH_YES when the game should start, LAUNCH_NO when the
'                                   dialog was closed without starting, else LAUNCH_NONE.
' The first start press opens the dialog (launchOpen) on YES (launchSel); a second start press,
' ENTER or pad A on YES launches. NO, ESC or pad B close it. Only an edge counts (pWas), so the
' press that opened it, or a key held through it, never confirms. Pad Start also sets ESC, which
' therefore doesn't cancel while Start is down.
' uiSfx: move on open and cursor moves, confirm on launch, back on closing it.
' Local variable prefix: ll*

Const LAUNCH_NONE = 0
Const LAUNCH_YES  = 1
Const LAUNCH_NO   = 2

Const LAUNCH_ROW_YES = 0
Const LAUNCH_ROW_NO  = 1
Const LAUNCH_ROWS    = 2

Dim Shared launchOpen As Integer, launchSel As Integer

Function LAUNCH_Input% (llHeld As Integer)
    Dim llEdge As Integer, llPick As Integer, llNo As Integer
    LAUNCH_Input% = LAUNCH_NONE
    llEdge = (llHeld <> 0) And (pWas = 0)
    pWas = llHeld
    If launchOpen = 0 Then
        If llEdge Then launchOpen = -1 : launchSel = LAUNCH_ROW_YES : uiSfx = SND_UI_MOVE
        Exit Function
    End If
    llPick = MENU_Input%(launchSel, LAUNCH_ROWS)
    llNo = (llPick = LAUNCH_ROW_NO) Or KEY_Pressed%(E3D_KEY_PAD_B)
    If KEY_Pressed%(E3D_KEY_ESCAPE) And held(E3D_KEY_PAD_START) = 0 Then llNo = -1
    If llEdge Or llPick = LAUNCH_ROW_YES Then
        launchOpen = 0 : LAUNCH_Input% = LAUNCH_YES : uiSfx = SND_UI_OK
    ElseIf llNo Then
        launchOpen = 0 : LAUNCH_Input% = LAUNCH_NO : uiSfx = SND_UI_BACK
    End If
End Function
