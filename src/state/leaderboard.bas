' leaderboard.bas -- top-10 display screen (GS_LEADERBOARD)
'
' SPACE / ESC  return to title screen

Sub GS_LEADERBOARD_Update ()
    Dim lbdPX1 As Integer : lbdPX1 = scrW \ 2 - 130
    Dim lbdPX2 As Integer : lbdPX2 = scrW \ 2 + 130
    Dim lbdPY1 As Integer : lbdPY1 = scrH \ 2 - 106
    Dim lbdPY2 As Integer : lbdPY2 = scrH \ 2 + 106

    tt = tt + 0.025
    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    E3D_StarfieldDraw vpMat, scrW, scrH

    UI_DrawPanel lbdPX1, lbdPY1, lbdPX2, lbdPY2, "TOP PILOTS"

    Dim lbdY As Integer : lbdY = scrH \ 2 - 88
    Dim lbdI As Integer

    If lbrdCount = 0 Then
        FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "NO SCORES YET.", lbdY + 60, scrW, 255
    Else
        Dim lbdRankX  As Integer : lbdRankX  = scrW \ 2 - 118
        Dim lbdNameX  As Integer : lbdNameX  = scrW \ 2 - 96
        Dim lbdScoreX As Integer : lbdScoreX = scrW \ 2 + 20
        For lbdI = 1 To lbrdCount
            Dim lbdRowY As Integer : lbdRowY = lbdY + (lbdI - 1) * 16
            Dim lbdClr  As Long
            If lbdI = 1 Then
                lbdClr = fontPalette(14)  ' gold tint for #1
            ElseIf lbdI <= 3 Then
                lbdClr = fontPalette(15)  ' bright for top 3
            Else
                lbdClr = fontPalette(9)
            End If
            FONT_PrintAlpha fontPalette(8), backBuffer, LTrim$(Str$(lbdI)) + ".", lbdRankX, lbdRowY, 200
            FONT_PrintAlpha lbdClr,         backBuffer, lbrdName(lbdI),           lbdNameX, lbdRowY, 255
            FONT_PrintAlpha lbdClr,         backBuffer, LTrim$(Str$(lbrdScore(lbdI))), lbdScoreX, lbdRowY, 255
        Next lbdI
    End If

    Dim lbdThrobBright As Integer : lbdThrobBright = Int(170 + 85 * Sin(tt * 5))
    FONT_PrintCenteredAlpha fontPalette(15), backBuffer, "PRESS SPACE TO RETURN", lbdPY2 - 18, scrW, lbdThrobBright

    _DEST 0
    _PUTIMAGE , backBuffer, 0

    Dim lbdKey As Long : lbdKey = _KEYHIT
    If lbdKey = 32 Or lbdKey = 27 Then gameState = GS_TITLE

    MUS_Fill 0
End Sub
