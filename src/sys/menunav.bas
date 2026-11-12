' menunav.bas -- moving a cursor through a menu's rows, shared by every menu
'
' pick = MENU_Nav%(sel, count, up, dn, confirm)   rows 0..count-1; up / dn move sel one row,
'                                                 wrapping; confirm (on a frame with no move)
'                                                 returns sel, else -1; uiSfx gets the move /
'                                                 confirm sound (callers override it for a
'                                                 cancel row). No input read: tests
'                                                 drive it with plain flags.
' pick = MENU_Input%(sel, count)                  the same from this frame's presses: up / down
'                                                 (arrows, stick, d-pad; not W/S, which some
'                                                 menus use as hotkeys) and ENTER / pad A
' Local variable prefix: mn*

Function MENU_Nav% (mnSel As Integer, mnCount As Integer, mnUp As Integer, mnDn As Integer, mnPick As Integer)
    MENU_Nav% = -1
    If mnCount < 1 Then Exit Function
    If mnUp Then
        mnSel = (mnSel + mnCount - 1) Mod mnCount
        uiSfx = SND_UI_MOVE
    ElseIf mnDn Then
        mnSel = (mnSel + 1) Mod mnCount
        uiSfx = SND_UI_MOVE
    ElseIf mnPick Then
        MENU_Nav% = mnSel
        uiSfx = SND_UI_OK
    End If
End Function

Function MENU_Input% (mniSel As Integer, mniCount As Integer)
    MENU_Input% = MENU_Nav%(mniSel, mniCount, KEY_Pressed%(E3D_KEY_UP), KEY_Pressed%(E3D_KEY_DOWN), KEY_Confirm%)
End Function

' ---- which input does what, per screen family (the convention; tests/input_map_test.bas) ----
' Proceed = ENTER / pad A (KEY_Confirm%; the flow screens also take the fire key, KEY_Proceed%).
' Back = ESC / pad B. Menu = ESC / pad Start, inside a run (the pause dialog, pauselogic.bas).
' These take plain flags, so tests drive them without a keyboard.

' Title root: Back (ESC, pad B, pad Select) opens the command console and closes it again; pad Start
' also sets ESC and means "play" there, and B inside the open console is its cancel row, not a toggle.
Function NAV_TitleToggle% (nttEscEdge As Integer, nttStart As Integer, nttSelect As Integer, nttPadB As Integer, nttConsole As Integer, nttLaunchOpen As Integer)
    NAV_TitleToggle% = 0
    If nttLaunchOpen <> 0 Then Exit Function
    If nttEscEdge <> 0 And nttStart = 0 Then NAV_TitleToggle% = -1
    If nttSelect <> 0 Then NAV_TitleToggle% = -1
    If nttPadB <> 0 And nttConsole = 0 Then NAV_TitleToggle% = -1
End Function

' Title root: what opens LAUNCH NOW? (P, pad Start, ENTER, pad A; not the fire key, which is mashed
' through game over). nttConfirm is an edge, so a key still down from the screen before never counts.
Function NAV_TitleGo% (ntgPStart As Integer, ntgConfirm As Integer, ntgLaunchOpen As Integer)
    NAV_TitleGo% = (ntgPStart <> 0)
    If ntgLaunchOpen = 0 And ntgConfirm <> 0 Then NAV_TitleGo% = -1
End Function

' A crawl: ENTER or pad B skips it (pad A fast-forwards); outside a run ESC / Start back out too. Never
' on the frame the in-run menu closes (ncWasOpen), so the press that cancels it can't also skip.
Function NAV_CrawlSkip% (ncEnter As Integer, ncPadB As Integer, ncBack As Integer, ncInRun As Integer, ncWasOpen As Integer)
    NAV_CrawlSkip% = (ncEnter <> 0) Or (ncPadB <> 0)
    If ncInRun = 0 And ncBack <> 0 Then NAV_CrawlSkip% = -1
    If ncWasOpen <> 0 Then NAV_CrawlSkip% = 0
End Function
