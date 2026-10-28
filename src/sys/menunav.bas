' menunav.bas -- moving a cursor through a menu's rows, shared by every menu
'
' pick = MENU_Nav%(sel, count, up, dn, confirm)   rows 0..count-1; up / dn move sel one row,
'                                                 wrapping; confirm (on a frame with no move)
'                                                 returns sel, else -1. No input read: tests
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
    ElseIf mnDn Then
        mnSel = (mnSel + 1) Mod mnCount
    ElseIf mnPick Then
        MENU_Nav% = mnSel
    End If
End Function

Function MENU_Input% (mniSel As Integer, mniCount As Integer)
    MENU_Input% = MENU_Nav%(mniSel, mniCount, KEY_Pressed%(E3D_KEY_UP), KEY_Pressed%(E3D_KEY_DOWN), KEY_Confirm%)
End Function
