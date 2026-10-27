' dock.bas -- the upgrade dock screen (GS_DOCK, #268)
'
' The sequence's DOCK task (assets/sequence.txt, after each planet arrival but the last)
' calls DOCK_Enter. The list and its input live in docklogic.bas; this file draws it over
' the dock background (assets/dock_bg.png, 320x240, embedded as DOCKBG in sss.bas) and
' leaves for the next sequence step on LAUNCH or back.
' Local variable prefix: dkd*

Const DOCK_PX1 = 104   ' list panel: the right two-thirds, so the art's planet and ship stay in view
Const DOCK_PY1 = 4
Const DOCK_PX2 = 315
Const DOCK_PY2 = 235
Const DOCK_ROW_Y = 46
Const DOCK_ROW_H = 17
Const DOCK_PANEL_ALPHA = 100   ' list panel opacity (0-255): low so the dock art shows; text gets a drop shadow

Dim Shared dockShadowSheet As Long   ' all-black font sheet for the 1px text shadow, built on first use

Sub DOCK_Enter
    DOCK_Open
    gameState = GS_DOCK
End Sub

Sub DOCK_Update
    Dim dkdRes As Integer
    dkdRes = DOCK_Input%
    Select Case dkdRes
        Case DOCK_MOVED : SND_UiMove
        Case DOCK_BOUGHT : SND_Pup
        Case DOCK_NOFUNDS, DOCK_MAXED, DOCK_FULL : SND_UiDeny
    End Select
    DOCK_Draw
    If dkdRes = DOCK_LEAVE Then
        _Dest backBuffer
        Line (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
        SEQ_Advance
    End If
End Sub

' Text with a 1px dark drop shadow, so it reads over the see-through panel.
Sub DOCK_Text (dktPal As Integer, dktTxt As String, dktX As Integer, dktY As Integer, dktA As Integer)
    If dockShadowSheet = 0 Then
        FONT_BuildSheet dockShadowSheet, _RGB(0, 0, 0), _RGB(0, 0, 0)
        _Dest backBuffer
    End If
    FONT_PrintAlpha dockShadowSheet, backBuffer, dktTxt, dktX + 1, dktY + 1, dktA
    FONT_PrintAlpha fontPalette(dktPal), backBuffer, dktTxt, dktX, dktY, dktA
End Sub

Sub DOCK_Draw
    Dim dkdI As Integer, dkdRow As Integer, dkdY As Integer, dkdPal As Integer
    Dim dkdName As String, dkdLv As String, dkdPrice As String, dkdCr As String
    Dim dkdPriceN As Long, dkdCC As Long, dkdX As Integer

    _Dest backBuffer
    If dockBgImg < -1 Then
        _PutImage (0, 0)-(scrW - 1, scrH - 1), dockBgImg, backBuffer
    Else
        Line (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 12), BF
    End If

    DOCK_DrawStatus

    ' see-through panel: dark enough to read white text over the busy art
    Line (DOCK_PX1, DOCK_PY1)-(DOCK_PX2, DOCK_PY2), _RGBA(2, 4, 18, DOCK_PANEL_ALPHA), BF
    Line (DOCK_PX1, DOCK_PY1)-(DOCK_PX2, DOCK_PY2), _RGB(0, 55, 110), B
    Line (DOCK_PX1 + 1, DOCK_PY1 + 1)-(DOCK_PX2 - 1, DOCK_PY2 - 1), _RGB(0, 130, 210), B
    dkdCC = _RGB(0, 210, 255)
    Line (DOCK_PX1, DOCK_PY1)-(DOCK_PX1 + 7, DOCK_PY1), dkdCC : Line (DOCK_PX1, DOCK_PY1)-(DOCK_PX1, DOCK_PY1 + 7), dkdCC
    Line (DOCK_PX2, DOCK_PY1)-(DOCK_PX2 - 7, DOCK_PY1), dkdCC : Line (DOCK_PX2, DOCK_PY1)-(DOCK_PX2, DOCK_PY1 + 7), dkdCC
    Line (DOCK_PX1, DOCK_PY2)-(DOCK_PX1 + 7, DOCK_PY2), dkdCC : Line (DOCK_PX1, DOCK_PY2)-(DOCK_PX1, DOCK_PY2 - 7), dkdCC
    Line (DOCK_PX2, DOCK_PY2)-(DOCK_PX2 - 7, DOCK_PY2), dkdCC : Line (DOCK_PX2, DOCK_PY2)-(DOCK_PX2, DOCK_PY2 - 7), dkdCC
    Line (DOCK_PX1 + 2, DOCK_PY1 + 2)-(DOCK_PX2 - 2, DOCK_PY1 + 20), _RGB(0, 28, 68), BF
    Line (DOCK_PX1 + 2, DOCK_PY1 + 20)-(DOCK_PX2 - 2, DOCK_PY1 + 20), _RGB(0, 100, 180)
    DOCK_Text 11, "UPGRADE DOCK", DOCK_PX1 + 8, DOCK_PY1 + 3, 255
    dkdCr = "$" + LTrim$(Str$(credits))
    DOCK_Text 14, dkdCr, DOCK_PX2 - 7 - Len(dkdCr) * FONT_CHAR_W, DOCK_PY1 + 3, 255
    If planetCurrent >= 1 And planetCurrent <= PLANET_COUNT Then
        DOCK_Text 8, UCase$(Left$(planetNames(planetCurrent), 24)), DOCK_PX1 + 8, DOCK_PY1 + 22, 255
    End If

    For dkdRow = 0 To DOCK_VISIBLE - 1
        dkdI = dockTop + dkdRow
        If dkdI > DOCK_LAUNCH Then Exit For
        dkdY = DOCK_ROW_Y + dkdRow * DOCK_ROW_H
        If dkdI = dockSel Then
            Line (DOCK_PX1 + 4, dkdY - 1)-(DOCK_PX2 - 4, dkdY + 15), _RGBA(0, 60, 130, 220), BF
            Line (DOCK_PX1 + 4, dkdY - 1)-(DOCK_PX2 - 4, dkdY + 15), dkdCC, B
        End If
        If dkdI = DOCK_LAUNCH Then
            If dkdI = dockSel Then dkdPal = 15 Else dkdPal = 10
            DOCK_Text dkdPal, "LAUNCH >>", DOCK_PX1 + 8, dkdY, 255
        Else
            dkdName = UPG_Name$(dkdI)
            dkdPriceN = UPG_Price&(dkdI)
            If dkdI = UPG_RECHARGE Then
                If lives >= shieldMax Then
                    dkdLv = "FULL"
                ElseIf upgLevel(dkdI) >= upgMax(dkdI) Then
                    dkdLv = "DONE"
                Else
                    dkdLv = LTrim$(Str$(UPG_ShieldPct%)) + "%"
                End If
            Else
                dkdLv = LTrim$(Str$(upgLevel(dkdI))) + "/" + LTrim$(Str$(upgMax(dkdI)))
            End If
            If dkdPriceN = 0 Then dkdPrice = "MAX" Else dkdPrice = "$" + LTrim$(Str$(dkdPriceN))
            If dkdI = dockSel Then
                dkdPal = 15
            ElseIf dkdPriceN = 0 Or dkdLv = "FULL" Then
                dkdPal = 8
            Else
                dkdPal = 9
            End If
            DOCK_Text dkdPal, dkdName, DOCK_PX1 + 8, dkdY, 255
            DOCK_Text dkdPal, dkdLv, DOCK_PX1 + 136, dkdY, 255
            If dkdLv = "FULL" Then
                If dkdI <> dockSel Then dkdPal = 8
            ElseIf dkdPriceN > credits Then
                dkdPal = 12
            ElseIf dkdPriceN > 0 Then
                dkdPal = 14
            End If
            dkdX = DOCK_PX2 - 7 - Len(dkdPrice) * FONT_CHAR_W
            DOCK_Text dkdPal, dkdPrice, dkdX, dkdY, 255
        End If
    Next dkdRow
    ' scroll hints: small triangles in the gaps above and below the list, clear of the text
    For dkdI = 0 To 3
        If dockTop > 1 Then Line (DOCK_PX2 - 12 - dkdI, DOCK_ROW_Y - 6 + dkdI)-(DOCK_PX2 - 12 + dkdI, DOCK_ROW_Y - 6 + dkdI), dkdCC
        If dockTop + DOCK_VISIBLE - 1 < DOCK_LAUNCH Then Line (DOCK_PX2 - 12 - dkdI, DOCK_ROW_Y + DOCK_VISIBLE * DOCK_ROW_H + 1 - dkdI)-(DOCK_PX2 - 12 + dkdI, DOCK_ROW_Y + DOCK_VISIBLE * DOCK_ROW_H + 1 - dkdI), dkdCC
    Next dkdI

    dkdY = DOCK_ROW_Y + DOCK_VISIBLE * DOCK_ROW_H + 2
    Line (DOCK_PX1 + 4, dkdY - 2)-(DOCK_PX2 - 4, dkdY - 2), _RGB(0, 100, 180)
    If dockSel = DOCK_LAUNCH Then
        DOCK_Text 15, "LEAVE THE DOCK", DOCK_PX1 + 8, dkdY, 255
        DOCK_Text 14, "ON TO THE NEXT STAGE", DOCK_PX1 + 8, dkdY + 16, 255
    Else
        ' what it does, then what the next level changes
        DOCK_Text 15, UPG_Info$(dockSel), DOCK_PX1 + 8, dkdY, 255
        dkdName = UPG_Next$(dockSel)
        If dkdName = "MAXED" Then dkdPal = 8 Else dkdPal = 14
        DOCK_Text dkdPal, dkdName, DOCK_PX1 + 8, dkdY + 16, 255
    End If
    If dockMsgTimer > 0 Then
        If dockMsgBad Then dkdPal = 12 Else dkdPal = 10
        DOCK_Text dkdPal, dockMsg, DOCK_PX1 + 8, dkdY + 32, 255
    End If
    DOCK_Text 8, "ENTER/A BUY  ESC/B GO", DOCK_PX1 + 8, DOCK_PY2 - 18, 255

    _Dest 0
    _PutImage , backBuffer, 0
End Sub

' Ship status over the art, bottom left (#268): shields, laser and fuel as absolute values
' over the HUD's capacity-length bars. With a capacity upgrade highlighted, its bar shows
' a ghost of the length the next level adds.
Sub DOCK_DrawStatus
    Const DKS_X = 4
    Const DKS_Y = 162
    Line (DKS_X, DKS_Y)-(DKS_X + 90, DKS_Y + 72), _RGBA(2, 4, 18, DOCK_PANEL_ALPHA + 60), BF
    Line (DKS_X, DKS_Y)-(DKS_X + 90, DKS_Y + 72), _RGB(0, 130, 210), B
    DOCK_StatusRow "SH", lives, shieldMax, DKS_X + 4, DKS_Y + 2, 1, UPG_SHIELD
    DOCK_StatusRow "LA", laserEnergy, laserMax, DKS_X + 4, DKS_Y + 25, 2, UPG_LASER
    DOCK_StatusRow "FU", fuelLevel, fuelMax, DKS_X + 4, DKS_Y + 48, 3, UPG_FUEL
End Sub

' One status row: "SH 72/125", then the bar under it (dksKind 1 shield, 2 laser, 3 fuel).
Sub DOCK_StatusRow (dksLbl As String, dksVal As Single, dksMax As Single, dksX As Integer, dksY As Integer, dksKind As Integer, dksUpg As Integer)
    Dim dksGhost As Single
    dksGhost = 0
    If dockSel = dksUpg Then dksGhost = UPG_CapNext!(dksUpg)
    DOCK_Text 15, UPG_StatusStr$(dksLbl, dksVal, dksMax), dksX, dksY, 255
    HUD_Bar dksX, dksY + 15, dksVal, dksMax, dksKind, dksGhost
End Sub
