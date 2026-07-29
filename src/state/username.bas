' username.bas -- callsign entry screen (GS_USERNAME)
'
' Left/right arrows move cursor; Home/End jump to ends.
' Delete: forward delete at cursor. Backspace: delete before cursor.
' ~X color token pairs are treated as atomic units for cursor movement.
' The input box scrolls when text exceeds UN_BOX_VIS raw chars.
'
' On confirm (ENTER, >= 3 chars), writes telemPlayerName + calls SETTINGS_Save.

Const UN_BOX_VIS = 18  ' raw chars visible in input box (one slot reserved for cursor)

Sub GS_USERNAME_Init ()
    unCursorPos = Len(telemPlayerName)
    unScrollOff = 0
End Sub

Sub GS_USERNAME_Update ()
    Dim unPX1 As Integer : unPX1 = scrW \ 2 - 130
    Dim unPX2 As Integer : unPX2 = scrW \ 2 + 130
    Dim unPY1 As Integer : unPY1 = scrH \ 2 - 70
    Dim unPY2 As Integer : unPY2 = scrH \ 2 + 70

    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    E3D_StarfieldDraw vpMat, scrW, scrH

    UI_DrawPanel unPX1, unPY1, unPX2, unPY2, "PILOT CALLSIGN"

    Dim unBY As Integer : unBY = scrH \ 2 - 46
    FONT_PrintCenteredAlpha fontPalette(9), backBuffer, "ENTER YOUR CALLSIGN.",           unBY,      scrW, 255
    FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "3+ CHARS. TYPE ~X FOR COLORS.", unBY + 16, scrW, 255

    ' input box
    Dim unBoxX1 As Integer : unBoxX1 = scrW \ 2 - 78
    Dim unBoxX2 As Integer : unBoxX2 = scrW \ 2 + 78
    Dim unBoxY1 As Integer : unBoxY1 = scrH \ 2 - 8
    Dim unBoxY2 As Integer : unBoxY2 = scrH \ 2 + 8
    LINE (unBoxX1, unBoxY1)-(unBoxX2, unBoxY2), _RGB(0, 40, 90), BF
    LINE (unBoxX1, unBoxY1)-(unBoxX2, unBoxY2), _RGB(0, 80, 160), B

    ' clamp cursor and scroll
    If unCursorPos < 0 Then unCursorPos = 0
    If unCursorPos > Len(telemPlayerName) Then unCursorPos = Len(telemPlayerName)
    If unCursorPos < unScrollOff Then unScrollOff = unCursorPos
    If unCursorPos > unScrollOff + UN_BOX_VIS - 1 Then unScrollOff = unCursorPos - (UN_BOX_VIS - 1)
    If unScrollOff < 0 Then unScrollOff = 0

    ' render text slice + inline cursor
    Dim unSlice As String    : unSlice    = Mid$(telemPlayerName, unScrollOff + 1, UN_BOX_VIS)
    Dim unVisCur As Integer  : unVisCur   = unCursorPos - unScrollOff
    Dim unCurCh As String    : unCurCh    = " "
    If Int(tt * 2) Mod 2 = 0 Then unCurCh = "_"
    Dim unDispStr As String
    unDispStr = Left$(unSlice, unVisCur) + unCurCh + Mid$(unSlice, unVisCur + 1)
    FONT_PrintAlpha fontPalette(15), backBuffer, unDispStr, unBoxX1 + 2, scrH \ 2 - 4, 255

    ' scroll indicators at box edges
    If unScrollOff > 0 Then
        FONT_PrintAlpha fontPalette(9), backBuffer, Chr$(17), unBoxX1 + 2, scrH \ 2 - 4, 160
    End If
    If unScrollOff + UN_BOX_VIS < Len(telemPlayerName) Then
        FONT_PrintAlpha fontPalette(9), backBuffer, Chr$(16), unBoxX2 - FONT_CHAR_W - 2, scrH \ 2 - 4, 160
    End If

    ' key hints
    Dim unHY As Integer : unHY = scrH \ 2 + 22
    Dim unKX As Integer : unKX = scrW \ 2 - 44
    FONT_PrintAlpha fontPalette(15), backBuffer, "ENTER", unKX,                   unHY,      255
    FONT_PrintAlpha fontPalette(9),  backBuffer, "OK",    unKX + 7 * FONT_CHAR_W, unHY,      255
    FONT_PrintAlpha fontPalette(15), backBuffer, "ESC",   unKX,                   unHY + 16, 200
    FONT_PrintAlpha fontPalette(8),  backBuffer, "SKIP",  unKX + 5 * FONT_CHAR_W, unHY + 16, 200

    _DEST 0
    _PUTIMAGE , backBuffer, 0

    ' --- key handling ---
    Dim unKey As Long    : unKey      = _KEYHIT
    Dim unMoveStep As Integer         ' reused for token-aware stepping
    Dim unMoveH    As Integer         ' reused for hex-digit check

    Select Case unKey
        Case 13, 32  ' ENTER / SPACE -- confirm (min 3 chars)
            If Len(telemPlayerName) = 0 Then telemPlayerName = UN_AutoName$
            If Len(telemPlayerName) >= 3 Then
                SETTINGS_Save
                If unFromSettings Then
                    unFromSettings = 0 : gameState = GS_OPTIONS
                Else
                    LEADIN_Init : gameState = GS_LEADIN
                End If
            End If

        Case 27  ' ESC
            If unFromSettings Then
                telemPlayerName = unSavedName
                unFromSettings = 0 : gameState = GS_OPTIONS
            Else
                telemPlayerName = UN_AutoName$
                SETTINGS_Save
                LEADIN_Init : gameState = GS_LEADIN
            End If

        Case 19200  ' left arrow
            If unCursorPos > 0 Then
                unMoveStep = 1
                If unCursorPos >= 2 Then
                    If Mid$(telemPlayerName, unCursorPos - 1, 1) = Chr$(126) Then
                        unMoveH = Asc(UCase$(Mid$(telemPlayerName, unCursorPos, 1)))
                        If (unMoveH >= 48 And unMoveH <= 57) Or (unMoveH >= 65 And unMoveH <= 70) Then
                            unMoveStep = 2
                        End If
                    End If
                End If
                unCursorPos = unCursorPos - unMoveStep
            End If

        Case 19712  ' right arrow
            If unCursorPos < Len(telemPlayerName) Then
                unMoveStep = 1
                If unCursorPos + 2 <= Len(telemPlayerName) Then
                    If Mid$(telemPlayerName, unCursorPos + 1, 1) = Chr$(126) Then
                        unMoveH = Asc(UCase$(Mid$(telemPlayerName, unCursorPos + 2, 1)))
                        If (unMoveH >= 48 And unMoveH <= 57) Or (unMoveH >= 65 And unMoveH <= 70) Then
                            unMoveStep = 2
                        End If
                    End If
                End If
                unCursorPos = unCursorPos + unMoveStep
            End If

        Case 18176  ' Home
            unCursorPos = 0

        Case 20224  ' End
            unCursorPos = Len(telemPlayerName)

        Case 8  ' backspace -- delete char(s) before cursor
            If unCursorPos > 0 Then
                unMoveStep = 1
                If unCursorPos >= 2 Then
                    If Mid$(telemPlayerName, unCursorPos - 1, 1) = Chr$(126) Then
                        unMoveH = Asc(UCase$(Mid$(telemPlayerName, unCursorPos, 1)))
                        If (unMoveH >= 48 And unMoveH <= 57) Or (unMoveH >= 65 And unMoveH <= 70) Then
                            unMoveStep = 2
                        End If
                    End If
                End If
                telemPlayerName = Left$(telemPlayerName, unCursorPos - unMoveStep) _
                                + Mid$(telemPlayerName, unCursorPos + 1)
                unCursorPos = unCursorPos - unMoveStep
            End If

        Case 21248  ' Delete -- forward delete at cursor
            If unCursorPos < Len(telemPlayerName) Then
                unMoveStep = 1
                If unCursorPos + 2 <= Len(telemPlayerName) Then
                    If Mid$(telemPlayerName, unCursorPos + 1, 1) = Chr$(126) Then
                        unMoveH = Asc(UCase$(Mid$(telemPlayerName, unCursorPos + 2, 1)))
                        If (unMoveH >= 48 And unMoveH <= 57) Or (unMoveH >= 65 And unMoveH <= 70) Then
                            unMoveStep = 2
                        End If
                    End If
                End If
                telemPlayerName = Left$(telemPlayerName, unCursorPos) _
                                + Mid$(telemPlayerName, unCursorPos + unMoveStep + 1)
            End If

        Case Else
            If unKey >= 32 And unKey <= 126 Then  ' printable ASCII
                If Len(telemPlayerName) < UN_MAX_LEN Then
                    telemPlayerName = Left$(telemPlayerName, unCursorPos) _
                                    + Chr$(unKey) _
                                    + Mid$(telemPlayerName, unCursorPos + 1)
                    unCursorPos = unCursorPos + 1
                End If
            End If
    End Select

    MUS_Fill 0
End Sub

Function UN_AutoName$ ()
    UN_AutoName$ = "PILOT-" + Right$("000" + LTrim$(Str$(Int(RND * 9000) + 1000)), 4)
End Function
