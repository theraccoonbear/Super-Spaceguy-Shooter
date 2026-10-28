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

Sub DOCK_Draw
    Dim dkdI As Integer, dkdRow As Integer, dkdY As Integer, dkdPal As Integer
    Dim dkdName As String, dkdLv As String, dkdPrice As String, dkdCr As String
    Dim dkdPriceN As Long, dkdCC As Long, dkdX As Integer, dkdU As Integer

    _Dest backBuffer
    If dockBgImg < -1 Then
        _PutImage (0, 0)-(scrW - 1, scrH - 1), dockBgImg, backBuffer
    Else
        Line (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 12), BF
    End If

    DOCK_DrawStatus

    UI_Panel DOCK_PX1, DOCK_PY1, DOCK_PX2, DOCK_PY2
    dkdCC = _RGB(0, 210, 255)
    Line (DOCK_PX1 + 2, DOCK_PY1 + 2)-(DOCK_PX2 - 2, DOCK_PY1 + 20), _RGB(0, 28, 68), BF
    Line (DOCK_PX1 + 2, DOCK_PY1 + 20)-(DOCK_PX2 - 2, DOCK_PY1 + 20), _RGB(0, 100, 180)
    UI_Text 11, "UPGRADE DOCK", DOCK_PX1 + 8, DOCK_PY1 + 3, 255
    dkdCr = "$" + LTrim$(Str$(credits))
    UI_Text 14, dkdCr, DOCK_PX2 - 7 - Len(dkdCr) * FONT_CHAR_W, DOCK_PY1 + 3, 255
    If planetCurrent >= 1 And planetCurrent <= PLANET_COUNT Then
        UI_Text 8, UCase$(Left$(planetNames(planetCurrent), 24)), DOCK_PX1 + 8, DOCK_PY1 + 22, 255
    End If

    For dkdRow = 0 To DOCK_VISIBLE - 1
        dkdI = dockTop + dkdRow
        If dkdI > DOCK_LAUNCH Then Exit For
        dkdY = DOCK_ROW_Y + dkdRow * DOCK_ROW_H
        If dkdI = dockSel Then
            UI_MenuHighlight DOCK_PX1 + 4, dkdY - 1, DOCK_PX2 - 4, dkdY + 15
        End If
        If dkdI = DOCK_LAUNCH Then
            If dkdI = dockSel Then dkdPal = 15 Else dkdPal = 10
            UI_Text dkdPal, "LAUNCH >>", DOCK_PX1 + 8, dkdY, 255
        ElseIf DOCK_SupplyOf%(dkdI) > 0 Then
            DOCK_DrawSupplyRow dkdI, dkdY
        Else
            dkdU = dkdI - DOCK_UPG0
            dkdName = UPG_Name$(dkdU)
            dkdPriceN = UPG_Price&(dkdU)
            dkdLv = LTrim$(Str$(upgLevel(dkdU))) + "/" + LTrim$(Str$(upgMax(dkdU)))
            If dkdPriceN = 0 Then dkdPrice = "MAX" Else dkdPrice = "$" + LTrim$(Str$(dkdPriceN))
            If dkdI = dockSel Then
                dkdPal = 15
            ElseIf dkdPriceN = 0 Then
                dkdPal = 8
            Else
                dkdPal = 9
            End If
            UI_Text dkdPal, dkdName, DOCK_PX1 + 8, dkdY, 255
            UI_Text dkdPal, dkdLv, DOCK_PX1 + 136, dkdY, 255
            If dkdPriceN > credits Then
                dkdPal = 12
            ElseIf dkdPriceN > 0 Then
                dkdPal = 14
            End If
            dkdX = DOCK_PX2 - 7 - Len(dkdPrice) * FONT_CHAR_W
            UI_Text dkdPal, dkdPrice, dkdX, dkdY, 255
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
        UI_Text 15, "LEAVE THE DOCK", DOCK_PX1 + 8, dkdY, 255
        UI_Text 14, "ON TO THE NEXT STAGE", DOCK_PX1 + 8, dkdY + 16, 255
    ElseIf DOCK_SupplyOf%(dockSel) > 0 Then
        DOCK_DrawSupplyInfo DOCK_SupplyOf%(dockSel), dkdY
    Else
        ' what it does, then what the next level changes
        UI_Text 15, UPG_Info$(dockSel - DOCK_UPG0), DOCK_PX1 + 8, dkdY, 255
        dkdName = UPG_Next$(dockSel - DOCK_UPG0)
        If dkdName = "MAXED" Then dkdPal = 8 Else dkdPal = 14
        UI_Text dkdPal, dkdName, DOCK_PX1 + 8, dkdY + 16, 255
    End If
    If dockMsgTimer > 0 Then
        If dockMsgBad Then dkdPal = 12 Else dkdPal = 10
        UI_Text dkdPal, dockMsg, DOCK_PX1 + 8, dkdY + 32, 255
    End If
    UI_PromptsAt UI_Tok$("ENTER", E3D_ACT_CONFIRM) + " BUY  " + UI_Tok$("ESC", E3D_ACT_BACK) + " GO", INP_LastDevice%, DOCK_PX1 + 8, DOCK_PY2 - 18, 8, 255, -1

    _Dest 0
    _PutImage , backBuffer, 0
End Sub

' A supply row (#277): name, then on the selected row the amount between LEFT / RIGHT
' arrows, and its live cost (red when the credits don't cover it); FULL once nothing is missing.
Sub DOCK_DrawSupplyRow (dsrRow As Integer, dsrY As Integer)
    Dim dsrK As Integer, dsrPal As Integer, dsrAmt As String, dsrCost As Long, dsrTxt As String
    Dim dsrX As Integer, dsrI As Integer, dsrCC As Long, dsrSel As Integer
    dsrK = DOCK_SupplyOf%(dsrRow)
    dsrSel = (dsrRow = dockSel)
    If dsrSel Then
        dsrPal = 15
    ElseIf SUP_Missing%(dsrK) = 0 Then
        dsrPal = 8
    Else
        dsrPal = 9
    End If
    If dsrK = SUP_FUEL Then dsrTxt = "REFUEL" Else dsrTxt = "SHIELDS"
    UI_Text dsrPal, dsrTxt, DOCK_PX1 + 8, dsrY, 255
    If SUP_Missing%(dsrK) = 0 Then
        UI_Text 8, "FULL", DOCK_PX2 - 7 - 4 * FONT_CHAR_W, dsrY, 255
        Exit Sub
    End If
    dsrAmt = "+" + LTrim$(Str$(dockAmt(dsrK)))
    dsrX = DOCK_PX1 + 100
    UI_Text dsrPal, dsrAmt, dsrX, dsrY, 255
    If dsrSel Then
        dsrCC = _RGB(0, 210, 255)
        For dsrI = 0 To 3
            Line (dsrX - 8 + dsrI, dsrY + 7 - dsrI)-(dsrX - 8 + dsrI, dsrY + 7 + dsrI), dsrCC
            Line (dsrX + Len(dsrAmt) * FONT_CHAR_W + 5 - dsrI, dsrY + 7 - dsrI)-(dsrX + Len(dsrAmt) * FONT_CHAR_W + 5 - dsrI, dsrY + 7 + dsrI), dsrCC
        Next dsrI
    End If
    dsrCost = SUP_Cost&(dsrK, dockAmt(dsrK), levelNum)
    If dsrCost > credits Then dsrPal = 12 Else dsrPal = 14
    dsrTxt = "$" + LTrim$(Str$(dsrCost))
    UI_Text dsrPal, dsrTxt, DOCK_PX2 - 7 - Len(dsrTxt) * FONT_CHAR_W, dsrY, 255
End Sub

' The two info lines under the list for a supply row: the unit price, then for fuel what the
' next jump needs (red while the amount shown wouldn't cover it) and for shields the result.
Sub DOCK_DrawSupplyInfo (dsiK As Integer, dsiY As Integer)
    Dim dsiNeed As Single, dsiPal As Integer, dsiTxt As String, dsiAfter As Long
    If dsiK = SUP_FUEL Then
        UI_Text 15, DOCK_Money$(SUP_UnitPrice!(SUP_FUEL, levelNum)) + "/U", DOCK_PX1 + 8, dsiY, 255
        dsiNeed = SUP_LegNeed!
        If dsiNeed <= 0 Then
            UI_Text 8, "NO JUMP AHEAD", DOCK_PX1 + 8, dsiY + 16, 255
        Else
            If fuelLevel + dockAmt(SUP_FUEL) < dsiNeed Then dsiPal = 12 Else dsiPal = 14
            UI_Text dsiPal, "NEXT JUMP NEEDS " + LTrim$(Str$(-Int(-dsiNeed))) + " FU", DOCK_PX1 + 8, dsiY + 16, 255
        End If
    Else
        UI_Text 15, DOCK_Money$(SUP_UnitPrice!(SUP_SHIELD, levelNum)) + "/U  FLAT RATE", DOCK_PX1 + 8, dsiY, 255
        If SUP_Missing%(SUP_SHIELD) = 0 Then
            UI_Text 8, "SHIELDS FULL", DOCK_PX1 + 8, dsiY + 16, 255
        Else
            dsiAfter = lives + dockAmt(SUP_SHIELD)
            If dsiAfter > shieldMax Then dsiAfter = shieldMax
            dsiTxt = "SHIELD " + LTrim$(Str$(lives)) + " > " + LTrim$(Str$(dsiAfter))
            UI_Text 14, dsiTxt, DOCK_PX1 + 8, dsiY + 16, 255
        End If
    End If
End Sub

' 2.8 -> "$2.80"
Function DOCK_Money$ (dkmV As Single)
    Dim dkmC As Long, dkmF As String
    dkmC = Int(dkmV * 100 + 0.5)
    dkmF = LTrim$(Str$(dkmC Mod 100))
    If Len(dkmF) < 2 Then dkmF = "0" + dkmF
    DOCK_Money$ = "$" + LTrim$(Str$(dkmC \ 100)) + "." + dkmF
End Function

' Ship status over the art, bottom left (#268): shields, laser and fuel as absolute values
' over the HUD's capacity-length bars. With a capacity upgrade highlighted, its bar shows
' a ghost of the length the next level adds; with a supply row highlighted, a ghost of the
' amount being bought (#277). The fuel bar has a tick at what the next jump needs.
Sub DOCK_DrawStatus
    Const DKS_X = 4
    Const DKS_Y = 162
    UI_Panel DKS_X, DKS_Y, DKS_X + 90, DKS_Y + 72
    DOCK_StatusRow "SH", lives, shieldMax, DKS_X + 4, DKS_Y + 2, 1, UPG_SHIELD, SUP_SHIELD
    DOCK_StatusRow "LA", laserEnergy, laserMax, DKS_X + 4, DKS_Y + 25, 2, UPG_LASER, 0
    DOCK_StatusRow "FU", fuelLevel, fuelMax, DKS_X + 4, DKS_Y + 48, 3, UPG_FUEL, SUP_FUEL
End Sub

' One status row: "SH 72/125", then the bar under it (dksKind 1 shield, 2 laser, 3 fuel;
' dksSup the supply it is, 0 for none).
Sub DOCK_StatusRow (dksLbl As String, dksVal As Single, dksMax As Single, dksX As Integer, dksY As Integer, dksKind As Integer, dksUpg As Integer, dksSup As Integer)
    Dim dksGhost As Single, dksF0 As Integer, dksF1 As Integer, dksNeed As Single, dksTx As Integer
    dksGhost = 0
    If dockSel - DOCK_UPG0 = dksUpg Then dksGhost = UPG_CapNext!(dksUpg)
    UI_Text 15, UPG_StatusStr$(dksLbl, dksVal, dksMax), dksX, dksY, 255
    HUD_Bar dksX, dksY + 15, dksVal, dksMax, dksKind, dksGhost
    If dksSup = 0 Then Exit Sub
    If DOCK_SupplyOf%(dockSel) = dksSup And dockAmt(dksSup) > 0 Then
        dksF0 = UPG_BarFill%(dksVal, dksMax)
        dksF1 = UPG_BarFill%(dksVal + dockAmt(dksSup), dksMax)
        If dksF1 > dksF0 Then Line (dksX + 2 + dksF0, dksY + 16)-(dksX + 1 + dksF1, dksY + 20), _RGBA(0, 210, 255, 150), BF
    End If
    If dksSup = SUP_FUEL Then
        dksNeed = SUP_LegNeed!
        If dksNeed > 0 Then
            dksTx = dksX + 1 + UPG_BarFill%(dksNeed, dksMax)
            Line (dksTx, dksY + 14)-(dksTx, dksY + 22), _RGB(255, 255, 255)
        End If
    End If
End Sub
