' username.bas -- callsign entry screen (GS_USERNAME)
'
' Left/right arrows move cursor; Home/End jump to ends.
' Delete: forward delete at cursor. Backspace: delete before cursor.
' ~X color token pairs are treated as atomic units for cursor movement and render live.
' The input box scrolls when text exceeds UN_BOX_VIS visible chars.
' Editing logic lives in src/2d/textedit.bas (TXE_*).
'
' On confirm (ENTER, >= 3 chars), writes telemPlayerName + calls SETTINGS_Save.

Const UN_BOX_VIS = 18  ' visible columns in the input box (one slot reserved for cursor)

Sub GS_USERNAME_Init ()
    unCursorPos = Len(telemPlayerName)
    unScrollOff = 0
    unBlinkN = 0
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

    ' text from the scroll offset, in the color in force there, plus an overlaid cursor
    If unCursorPos < 0 Then unCursorPos = 0
    If unCursorPos > Len(telemPlayerName) Then unCursorPos = Len(telemPlayerName)
    unScrollOff = TXE_Scroll%(telemPlayerName, unCursorPos, unScrollOff, UN_BOX_VIS)
    Dim unTxtX As Integer : unTxtX = unBoxX1 + 2
    Dim unTxtY As Integer : unTxtY = scrH \ 2 - 4
    Dim unDispStr As String
    unDispStr = "~F" + TXE_ColorAt$(telemPlayerName, unScrollOff) + Mid$(telemPlayerName, unScrollOff + 1)
    FONT_PrintRichAlpha fontPalette(), backBuffer, FONT_RichTrunc$(unDispStr, UN_BOX_VIS), unTxtX, unTxtY, 255
    ' tt doesn't advance on this screen; 60 fps: on 0.5 s, off 0.5 s, solid again after each key
    unBlinkN = unBlinkN + 1
    If (unBlinkN \ 30) Mod 2 = 0 Then
        FONT_PrintAlpha fontPalette(15), backBuffer, "_", unTxtX + TXE_VisCol%(telemPlayerName, unScrollOff, unCursorPos) * FONT_CHAR_W, unTxtY, 255
    End If

    ' scroll indicators just outside the box edges
    If TXE_VisCol%(telemPlayerName, 0, unScrollOff) > 0 Then
        FONT_PrintAlpha fontPalette(9), backBuffer, "<", unBoxX1 - FONT_CHAR_W - 1, unTxtY, 200
    End If
    If TXE_VisCol%(telemPlayerName, unScrollOff, Len(telemPlayerName)) > UN_BOX_VIS Then
        FONT_PrintAlpha fontPalette(9), backBuffer, ">", unBoxX2 + 2, unTxtY, 200
    End If

    ' key hints
    Dim unHY As Integer : unHY = scrH \ 2 + 22
    Dim unKX As Integer : unKX = scrW \ 2 - 44
    FONT_PrintAlpha fontPalette(15), backBuffer, "ENTER/A", unKX,                   unHY,      255
    FONT_PrintAlpha fontPalette(9),  backBuffer, "OK",      unKX + 9 * FONT_CHAR_W, unHY,      255
    FONT_PrintAlpha fontPalette(15), backBuffer, "ESC/B",   unKX,                   unHY + 16, 200
    FONT_PrintAlpha fontPalette(8),  backBuffer, "SKIP",    unKX + 9 * FONT_CHAR_W, unHY + 16, 200

    _DEST 0
    _PUTIMAGE , backBuffer, 0

    ' --- key handling ---
    Dim unKey As Long    : unKey      = KEY_Hit&
    Dim unKeyUsed As Integer
    If KEY_Pressed%(E3D_KEY_PAD_A) Then unKey = 13
    If KEY_Pressed%(E3D_KEY_PAD_B) Then unKey = 27

    Select Case unKey
        Case 13, 32  ' ENTER / SPACE -- confirm (min 3 chars)
            If Len(telemPlayerName) = 0 Then telemPlayerName = UN_AutoName$
            If Len(telemPlayerName) >= 3 Then
                SETTINGS_Save
                If unFromSettings Then
                    unFromSettings = 0 : TITLE_ReturnTo GS_OPTIONS
                Else
                    LEADIN_Init : gameState = GS_LEADIN
                End If
            End If

        Case 27  ' ESC
            If unFromSettings Then
                telemPlayerName = unSavedName
                unFromSettings = 0 : TITLE_ReturnTo GS_OPTIONS
            Else
                telemPlayerName = UN_AutoName$
                SETTINGS_Save
                LEADIN_Init : gameState = GS_LEADIN
            End If

        Case Else
            unKeyUsed = TXE_Key%(telemPlayerName, unCursorPos, unKey, UN_MAX_LEN)
            If unKeyUsed Then unBlinkN = 0
    End Select

    MUS_Fill 0
End Sub

Function UN_AutoName$ ()
    UN_AutoName$ = "PILOT-" + Right$("000" + LTrim$(Str$(Int(RNG!(RNG_UNIQUE) * 9000) + 1000)), 4)
End Function
