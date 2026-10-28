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
        Dim lbdRank   As String
        Dim lbdNameX  As Integer : lbdNameX  = scrW \ 2 - 96
        Dim lbdScoreX As Integer : lbdScoreX = scrW \ 2 + 20
        Dim lbdClr    As Long
        Dim lbdRowY   As Integer
        For lbdI = 1 To lbrdCount
            lbdRowY = lbdY + (lbdI - 1) * 16
            If lbdI = 1 Then
                lbdClr = fontPalette(14)  ' gold
            ElseIf lbdI <= 3 Then
                lbdClr = fontPalette(15)  ' bright white
            Else
                lbdClr = fontPalette(9)   ' blue-gray
            End If
            lbdRank = LTrim$(Str$(lbdI)) + "."  ' right-aligned so "10." clears the name column
            FONT_PrintAlpha    fontPalette(8), backBuffer, lbdRank, lbdNameX - 2 - Len(lbdRank) * FONT_CHAR_W, lbdRowY, 200
            FONT_PrintRichAlpha fontPalette(), backBuffer, LBRD_DisplayName$(lbdI, lbrdName(lbdI)), lbdNameX, lbdRowY, 255
            FONT_PrintAlpha    lbdClr,         backBuffer, LTrim$(Str$(lbrdScore(lbdI))), lbdScoreX, lbdRowY, 255
        Next lbdI
    End If

    Dim lbdThrobBright As Integer : lbdThrobBright = Int(170 + 85 * Sin(tt * 5))
    UI_PromptsCentered "PRESS " + UI_Tok$("SPACE", E3D_ACT_FIRE) + " TO RETURN", lbdPY2 - 18, 15, lbdThrobBright

    _DEST 0
    _PUTIMAGE , backBuffer, 0

    ' presses, not holds: the A that picked LEADERBOARD on the console is still down here.
    ' SPACE's slot also carries pad A, ESC's pad Start.
    If KEY_Pressed%(E3D_KEY_SPACE) Or KEY_Back% Then TITLE_ReturnTo GS_TITLE

    MUS_Fill 0
End Sub
