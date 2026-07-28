' username.bas -- one-time display name entry screen (GS_USERNAME)
'
' Player types a name (max 12 printable ASCII chars).
' ENTER / SPACE  confirm and continue
' ESC            skip; auto-name is assigned (PILOT-XXXX)
'
' On exit always writes telemPlayerName and calls SETTINGS_Save,
' then transitions to GS_LEADIN.

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
    FONT_PrintCenteredAlpha fontPalette(9),  backBuffer, "ENTER YOUR CALLSIGN.",           unBY,      scrW, 255
    FONT_PrintCenteredAlpha fontPalette(8),  backBuffer, "3-12 CHARS. APPEARS ON BOARDS.", unBY + 16, scrW, 255

    ' input box
    Dim unBoxX1 As Integer : unBoxX1 = scrW \ 2 - 78
    Dim unBoxX2 As Integer : unBoxX2 = scrW \ 2 + 78
    Dim unBoxY1 As Integer : unBoxY1 = scrH \ 2 - 8
    Dim unBoxY2 As Integer : unBoxY2 = scrH \ 2 + 8
    LINE (unBoxX1, unBoxY1)-(unBoxX2, unBoxY2), _RGB(0, 40, 90), BF
    LINE (unBoxX1, unBoxY1)-(unBoxX2, unBoxY2), _RGB(0, 80, 160), B

    Dim unCursor As String
    If Int(tt * 2) Mod 2 = 0 Then unCursor = "_" Else unCursor = " "
    Dim unDisplay As String : unDisplay = telemPlayerName + unCursor
    FONT_PrintCenteredAlpha fontPalette(15), backBuffer, unDisplay, scrH \ 2 - 4, scrW, 255

    ' key hints
    Dim unHY As Integer : unHY = scrH \ 2 + 22
    Dim unKX As Integer : unKX = scrW \ 2 - 44
    FONT_PrintAlpha fontPalette(15), backBuffer, "ENTER", unKX,                       unHY,      255
    FONT_PrintAlpha fontPalette(9),  backBuffer, "OK",    unKX + 7 * FONT_CHAR_W,     unHY,      255
    FONT_PrintAlpha fontPalette(15), backBuffer, "ESC",   unKX,                       unHY + 16, 200
    FONT_PrintAlpha fontPalette(8),  backBuffer, "SKIP",  unKX + 5 * FONT_CHAR_W,     unHY + 16, 200

    _DEST 0
    _PUTIMAGE , backBuffer, 0

    Dim unKey As Long : unKey = _KEYHIT
    Select Case unKey
        Case 13, 32  ' ENTER or SPACE -- confirm (requires >= 3 chars or empty for auto-name)
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
                telemPlayerName = unSavedName  ' cancel: restore old name
                unFromSettings = 0 : gameState = GS_OPTIONS
            Else
                telemPlayerName = UN_AutoName$  ' first-time flow: auto-assign
                SETTINGS_Save
                LEADIN_Init : gameState = GS_LEADIN
            End If

        Case 8  ' backspace
            If Len(telemPlayerName) > 0 Then
                telemPlayerName = Left$(telemPlayerName, Len(telemPlayerName) - 1)
            End If

        Case Else
            If unKey >= 32 And unKey <= 126 Then  ' printable ASCII
                If Len(telemPlayerName) < UN_MAX_LEN Then
                    telemPlayerName = telemPlayerName + Chr$(unKey)
                End If
            End If
    End Select

    MUS_Fill 0
End Sub

Function UN_AutoName$ ()
    UN_AutoName$ = "PILOT-" + Right$("000" + LTrim$(Str$(Int(RND * 9000) + 1000)), 4)
End Function
