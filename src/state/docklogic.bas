' docklogic.bas -- the upgrade dock's list and input, without drawing (#268)
'
' Rows 1..UPG_COUNT are the upgrades, row DOCK_LAUNCH leaves. dock.bas draws it and
' calls DOCK_Input% once per frame; tests call DOCK_Input% (scripted input) or
' DOCK_Step% (plain flags) directly.
'   DOCK_Open                      entering the dock: cursor on the first row, per-visit refills
'   r = DOCK_Step%(up, dn, buy, back)
'   r = DOCK_Input%                reads up/down (arrows, W/S, stick, d-pad), ENTER / pad A
'                                  to buy, ESC / pad B / pad Start to leave
' Results: DOCK_NONE, DOCK_MOVED, DOCK_BOUGHT, DOCK_NOFUNDS, DOCK_MAXED, DOCK_FULL, DOCK_LEAVE
' Local variable prefix: dk*

Const DOCK_LAUNCH  = UPG_COUNT + 1
Const DOCK_VISIBLE = 7     ' list rows on screen; the list scrolls to keep the cursor in view
Const DOCK_NONE    = 0
Const DOCK_MOVED   = 1
Const DOCK_BOUGHT  = 2
Const DOCK_NOFUNDS = 3
Const DOCK_MAXED   = 4
Const DOCK_FULL    = 5
Const DOCK_LEAVE   = 6

Dim Shared dockSel As Integer, dockTop As Integer
Dim Shared dockMsg As String, dockMsgTimer As Integer, dockMsgBad As Integer

Sub DOCK_Open
    dockSel = 1 : dockTop = 1
    dockMsg = "" : dockMsgTimer = 0 : dockMsgBad = 0
    UPG_DockVisit
End Sub

Sub DOCK_Say (dksMsg As String, dksBad As Integer)
    dockMsg = dksMsg : dockMsgTimer = 120 : dockMsgBad = dksBad
End Sub

Function DOCK_Step% (dkUp As Integer, dkDn As Integer, dkBuy As Integer, dkBack As Integer)
    Dim dkRes As Integer, dkBuyRes As Integer
    dkRes = DOCK_NONE
    If dockMsgTimer > 0 Then dockMsgTimer = dockMsgTimer - 1
    If dkBack Then DOCK_Step% = DOCK_LEAVE : Exit Function
    If dkUp Then
        dockSel = dockSel - 1 : If dockSel < 1 Then dockSel = DOCK_LAUNCH
        dkRes = DOCK_MOVED
    ElseIf dkDn Then
        dockSel = dockSel + 1 : If dockSel > DOCK_LAUNCH Then dockSel = 1
        dkRes = DOCK_MOVED
    ElseIf dkBuy Then
        If dockSel = DOCK_LAUNCH Then DOCK_Step% = DOCK_LEAVE : Exit Function
        dkBuyRes = UPG_Buy%(dockSel)
        Select Case dkBuyRes
            Case UPG_OK
                dkRes = DOCK_BOUGHT
                DOCK_Say "INSTALLED " + DOCK_BoughtName$(dockSel), 0
            Case UPG_NOFUNDS
                dkRes = DOCK_NOFUNDS
                DOCK_Say "NOT ENOUGH CREDITS", -1
            Case UPG_FULL
                dkRes = DOCK_FULL
                DOCK_Say "SHIELDS ALREADY FULL", -1
            Case Else
                dkRes = DOCK_MAXED
                DOCK_Say "ALREADY AT MAX", -1
        End Select
    End If
    If dockSel < dockTop Then dockTop = dockSel
    If dockSel > dockTop + DOCK_VISIBLE - 1 Then dockTop = dockSel - DOCK_VISIBLE + 1
    DOCK_Step% = dkRes
End Function

' Name of what was just bought: the level now owned.
Function DOCK_BoughtName$ (dknId As Integer)
    Dim dknPart(1 To UPG_MAX_LV + 1) As String, dknCnt As Integer, dknI As Integer
    UPG_Split upgNames$(dknId), ",", dknPart(), dknCnt
    dknI = upgLevel(dknId)
    If dknI > dknCnt Then dknI = dknCnt
    If dknI < 1 Then dknI = 1
    DOCK_BoughtName$ = dknPart(dknI)
End Function

Function DOCK_Input%
    Dim dkiUp As Integer, dkiDn As Integer, dkiBuy As Integer, dkiBack As Integer
    dkiUp = KEY_Pressed%(E3D_KEY_UP) Or KEY_Pressed%(E3D_KEY_W)
    dkiDn = KEY_Pressed%(E3D_KEY_DOWN) Or KEY_Pressed%(E3D_KEY_S)
    dkiBuy = KEY_Confirm%
    dkiBack = KEY_Back%
    DOCK_Input% = DOCK_Step%(dkiUp, dkiDn, dkiBuy, dkiBack)
End Function
