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

    Dim lbdY As Integer : lbdY = scrH \ 2 - 82  ' 4px below title bar (UI_TITLE_H=20, was -88 which overlapped)
    Dim lbdI As Integer

    If lbrdCount = 0 Then
        FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "NO SCORES YET.", lbdY + 60, scrW, 255
    Else
        Dim lbdRankX  As Integer : lbdRankX  = scrW \ 2 - 118
        Dim lbdNameX  As Integer : lbdNameX  = scrW \ 2 - 96
        Dim lbdScoreX As Integer : lbdScoreX = scrW \ 2 + 20
        Dim lbdClr    As Long
        Dim lbdRowY   As Integer
        Dim lbdPfx    As String
        For lbdI = 1 To lbrdCount
            lbdRowY = lbdY + (lbdI - 1) * 16
            If lbdI = 1 Then
                lbdClr = fontPalette(14) : lbdPfx = "~E"  ' gold
            ElseIf lbdI <= 3 Then
                lbdClr = fontPalette(15) : lbdPfx = "~F"  ' bright white
            Else
                lbdClr = fontPalette(9)  : lbdPfx = "~9"  ' blue-gray
            End If
            FONT_PrintAlpha    fontPalette(8), backBuffer, LTrim$(Str$(lbdI)) + ".", lbdRankX, lbdRowY, 200
            FONT_PrintRichAlpha fontPalette(), backBuffer, lbdPfx + FONT_RichTrunc$(lbrdName(lbdI), 14), lbdNameX, lbdRowY, 255
            FONT_PrintAlpha    lbdClr,         backBuffer, LTrim$(Str$(lbrdScore(lbdI))), lbdScoreX, lbdRowY, 255
        Next lbdI
    End If

    Dim lbdThrobBright As Integer : lbdThrobBright = Int(170 + 85 * Sin(tt * 5))
    FONT_PrintCenteredAlpha fontPalette(15), backBuffer, "PRESS SPACE TO RETURN", lbdPY2 - 18, scrW, lbdThrobBright

    _DEST 0
    _PUTIMAGE , backBuffer, 0

    Static lbdSpaceWas As Integer
    Static lbdEscWas   As Integer
    Dim lbdSpc As Integer : lbdSpc = _KEYDOWN(32)
    Dim lbdEsc As Integer : lbdEsc = _KEYDOWN(27)
    If (lbdSpc And lbdSpaceWas = 0) Or (lbdEsc And lbdEscWas = 0) Then gameState = GS_TITLE
    lbdSpaceWas = lbdSpc
    lbdEscWas   = lbdEsc

    MUS_Fill 0
End Sub
