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
        Case DOCK_MOVED : SND_Blip 660
        Case DOCK_BOUGHT : SND_Pup
        Case DOCK_NOFUNDS, DOCK_MAXED, DOCK_FULL : SND_Hit
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
    Dim dkdPriceN As Long, dkdCC As Long, dkdX As Integer

    _Dest backBuffer
    If dockBgImg < -1 Then
        _PutImage (0, 0)-(scrW - 1, scrH - 1), dockBgImg, backBuffer
    Else
        Line (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 12), BF
    End If

    ' see-through panel: dark enough to read white text over the busy art
    Line (DOCK_PX1, DOCK_PY1)-(DOCK_PX2, DOCK_PY2), _RGBA(2, 4, 18, 200), BF
    Line (DOCK_PX1, DOCK_PY1)-(DOCK_PX2, DOCK_PY2), _RGB(0, 55, 110), B
    Line (DOCK_PX1 + 1, DOCK_PY1 + 1)-(DOCK_PX2 - 1, DOCK_PY2 - 1), _RGB(0, 130, 210), B
    dkdCC = _RGB(0, 210, 255)
    Line (DOCK_PX1, DOCK_PY1)-(DOCK_PX1 + 7, DOCK_PY1), dkdCC : Line (DOCK_PX1, DOCK_PY1)-(DOCK_PX1, DOCK_PY1 + 7), dkdCC
    Line (DOCK_PX2, DOCK_PY1)-(DOCK_PX2 - 7, DOCK_PY1), dkdCC : Line (DOCK_PX2, DOCK_PY1)-(DOCK_PX2, DOCK_PY1 + 7), dkdCC
    Line (DOCK_PX1, DOCK_PY2)-(DOCK_PX1 + 7, DOCK_PY2), dkdCC : Line (DOCK_PX1, DOCK_PY2)-(DOCK_PX1, DOCK_PY2 - 7), dkdCC
    Line (DOCK_PX2, DOCK_PY2)-(DOCK_PX2 - 7, DOCK_PY2), dkdCC : Line (DOCK_PX2, DOCK_PY2)-(DOCK_PX2, DOCK_PY2 - 7), dkdCC
    Line (DOCK_PX1 + 2, DOCK_PY1 + 2)-(DOCK_PX2 - 2, DOCK_PY1 + 20), _RGB(0, 28, 68), BF
    Line (DOCK_PX1 + 2, DOCK_PY1 + 20)-(DOCK_PX2 - 2, DOCK_PY1 + 20), _RGB(0, 100, 180)
    FONT_PrintAlpha fontPalette(11), backBuffer, "UPGRADE DOCK", DOCK_PX1 + 8, DOCK_PY1 + 3, 255
    dkdCr = "$" + LTrim$(Str$(credits))
    FONT_PrintAlpha fontPalette(14), backBuffer, dkdCr, DOCK_PX2 - 7 - Len(dkdCr) * FONT_CHAR_W, DOCK_PY1 + 3, 255
    If planetCurrent >= 1 And planetCurrent <= PLANET_COUNT Then
        FONT_PrintAlpha fontPalette(8), backBuffer, UCase$(Left$(planetNames(planetCurrent), 24)), DOCK_PX1 + 8, DOCK_PY1 + 22, 255
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
            FONT_PrintAlpha fontPalette(dkdPal), backBuffer, "LAUNCH >>", DOCK_PX1 + 8, dkdY, 255
        Else
            dkdName = UPG_Name$(dkdI)
            dkdPriceN = UPG_Price&(dkdI)
            If dkdI = UPG_REPAIR Then
                If upgLevel(dkdI) >= upgMax(dkdI) Then dkdLv = "DONE" Else dkdLv = ""
            Else
                dkdLv = LTrim$(Str$(upgLevel(dkdI))) + "/" + LTrim$(Str$(upgMax(dkdI)))
            End If
            If dkdPriceN = 0 Then dkdPrice = "MAX" Else dkdPrice = "$" + LTrim$(Str$(dkdPriceN))
            If dkdI = dockSel Then
                dkdPal = 15
            ElseIf dkdPriceN = 0 Then
                dkdPal = 8
            Else
                dkdPal = 9
            End If
            FONT_PrintAlpha fontPalette(dkdPal), backBuffer, dkdName, DOCK_PX1 + 8, dkdY, 255
            FONT_PrintAlpha fontPalette(dkdPal), backBuffer, dkdLv, DOCK_PX1 + 136, dkdY, 255
            If dkdPriceN > credits Then
                dkdPal = 12
            ElseIf dkdPriceN > 0 Then
                dkdPal = 14
            End If
            dkdX = DOCK_PX2 - 7 - Len(dkdPrice) * FONT_CHAR_W
            FONT_PrintAlpha fontPalette(dkdPal), backBuffer, dkdPrice, dkdX, dkdY, 255
        End If
    Next dkdRow
    ' scroll hints
    If dockTop > 1 Then FONT_PrintAlpha fontPalette(11), backBuffer, "^", DOCK_PX2 - 12, DOCK_ROW_Y - 14, 200
    If dockTop + DOCK_VISIBLE - 1 < DOCK_LAUNCH Then FONT_PrintAlpha fontPalette(11), backBuffer, "v", DOCK_PX2 - 12, DOCK_ROW_Y + DOCK_VISIBLE * DOCK_ROW_H - 3, 200

    dkdY = DOCK_ROW_Y + DOCK_VISIBLE * DOCK_ROW_H + 2
    Line (DOCK_PX1 + 4, dkdY - 2)-(DOCK_PX2 - 4, dkdY - 2), _RGB(0, 100, 180)
    If dockSel = DOCK_LAUNCH Then
        FONT_PrintAlpha fontPalette(9), backBuffer, "ON TO THE NEXT STAGE", DOCK_PX1 + 8, dkdY, 255
    Else
        FONT_PrintAlpha fontPalette(9), backBuffer, UPG_Desc$(dockSel), DOCK_PX1 + 8, dkdY, 255
    End If
    If dockMsgTimer > 0 Then
        If dockMsgBad Then dkdPal = 12 Else dkdPal = 10
        FONT_PrintAlpha fontPalette(dkdPal), backBuffer, dockMsg, DOCK_PX1 + 8, dkdY + 16, 255
    End If
    FONT_PrintAlpha fontPalette(8), backBuffer, "ENTER/A BUY  ESC/B GO", DOCK_PX1 + 8, DOCK_PY2 - 18, 255

    _Dest 0
    _PutImage , backBuffer, 0
End Sub
