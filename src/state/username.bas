' username.bas -- callsign entry screen (GS_USERNAME); input in usernamelogic.bas
'
' Keyboard: left/right arrows move cursor; Home/End jump to ends.
' Delete: forward delete at cursor. Backspace: delete before cursor.
' ~X color token pairs are treated as atomic units for cursor movement and render live.
' The input box scrolls when text exceeds UN_BOX_VIS visible chars.
' Editing logic lives in src/2d/textedit.bas (TXE_*).
' Pad (last device used): an arcade letter spinner over the same string -- the character
' under the cursor is highlighted with arrows above and below it.
'
' On confirm (ENTER / pad Start, >= 3 chars), writes telemPlayerName + calls SETTINGS_Save.

Const UN_BOX_VIS = 18  ' visible columns in the input box (one slot reserved for cursor)

Sub GS_USERNAME_Init ()
    unCursorPos = Len(telemPlayerName)
    unScrollOff = 0
    unBlinkN = 0
    unRepDir = 0
End Sub

' One prompt (key name or pad badge) and what it does, side by side.
Sub UN_Hint (uhTok As String, uhDesc As String, uhX As Integer, uhY As Integer, uhPal As Integer, uhA As Integer)
    UI_PromptsAt uhTok, INP_LastDevice%, uhX, uhY, 15, uhA, 0
    FONT_PrintAlpha fontPalette(uhPal), backBuffer, uhDesc, uhX + UI_PromptsW%(uhTok, INP_LastDevice%) + FONT_CHAR_W, uhY, uhA
End Sub

Sub GS_USERNAME_Update ()
    Dim unPX1 As Integer : unPX1 = scrW \ 2 - 130
    Dim unPX2 As Integer : unPX2 = scrW \ 2 + 130
    Dim unPY1 As Integer : unPY1 = scrH \ 2 - 70
    Dim unPY2 As Integer : unPY2 = scrH \ 2 + 70
    Dim unPad As Integer : unPad = (INP_LastDevice% = INP_DEV_PAD)

    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    E3D_StarfieldDraw vpMat, scrW, scrH

    UI_DrawPanel unPX1, unPY1, unPX2, unPY2, "PILOT CALLSIGN"

    Dim unBY As Integer : unBY = scrH \ 2 - 46
    FONT_PrintCenteredAlpha fontPalette(9), backBuffer, "ENTER YOUR CALLSIGN.",           unBY,      scrW, 255
    If unPad Then
        FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "3+ CHARS. UP/DOWN SPINS.", unBY + 16, scrW, 255
    Else
        FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "3+ CHARS. TYPE ~X FOR COLORS.", unBY + 16, scrW, 255
    End If

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
    Dim unSlotX As Integer, unSlotP As Integer, unArI As Integer
    If unPad Then
        ' the spinner slot: the character under the cursor, or the empty slot past the end
        unSlotP = UN_SpinAt%(telemPlayerName, unCursorPos)
        If unSlotP = 0 Then unSlotP = Len(telemPlayerName) + 1
        unSlotX = unTxtX + TXE_VisCol%(telemPlayerName, unScrollOff, unSlotP - 1) * FONT_CHAR_W
        LINE (unSlotX - 1, unBoxY1 + 1)-(unSlotX + FONT_CHAR_W - 1, unBoxY2 - 1), _RGB(0, 10, 30), BF
        For unArI = 0 To 2
            LINE (unSlotX + 3 - unArI, unBoxY1 - 5 + unArI)-(unSlotX + 3 + unArI, unBoxY1 - 5 + unArI), _RGB(255, 210, 60)
            LINE (unSlotX + 3 - unArI, unBoxY2 + 5 - unArI)-(unSlotX + 3 + unArI, unBoxY2 + 5 - unArI), _RGB(255, 210, 60)
        Next unArI
    End If
    unDispStr = "~F" + TXE_ColorAt$(telemPlayerName, unScrollOff) + Mid$(telemPlayerName, unScrollOff + 1)
    FONT_PrintRichAlpha fontPalette(), backBuffer, FONT_RichTrunc$(unDispStr, UN_BOX_VIS), unTxtX, unTxtY, 255
    ' tt doesn't advance on this screen; 60 fps: on 0.5 s, off 0.5 s, solid again after each key
    unBlinkN = unBlinkN + 1
    If unPad = 0 And (unBlinkN \ 30) Mod 2 = 0 Then
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
    If unPad Then
        Dim unCX1 As Integer : unCX1 = scrW \ 2 - 112
        Dim unCX2 As Integer : unCX2 = scrW \ 2 + 12
        FONT_PrintAlpha fontPalette(15), backBuffer, "UP/DN", unCX1, unHY - 2, 255
        FONT_PrintAlpha fontPalette(9), backBuffer, "LETTER", unCX1 + 6 * FONT_CHAR_W, unHY - 2, 255
        UN_Hint UI_Tok$("", E3D_ACT_CONFIRM), "NEXT", unCX2, unHY - 2, 9, 255
        UN_Hint UI_Tok$("", E3D_ACT_BACK), "DELETE", unCX1, unHY + 14, 9, 255
        UN_Hint UI_Tok$("", E3D_ACT_NOVA), "COLOR", unCX2, unHY + 14, 9, 255
        UN_Hint UI_Tok$("", E3D_ACT_PAUSE), "DONE", unCX1, unHY + 30, 9, 255
        UN_Hint UI_Tok$("", E3D_ACT_CAMERA), "SKIP", unCX2, unHY + 30, 8, 200
    Else
        UI_PromptsAt UI_Tok$("ENTER", E3D_ACT_CONFIRM), INP_LastDevice%, unKX, unHY, 15, 255, 0
        FONT_PrintAlpha fontPalette(9),  backBuffer, "OK",      unKX + 9 * FONT_CHAR_W, unHY,      255
        UI_PromptsAt UI_Tok$("ESC", E3D_ACT_BACK), INP_LastDevice%, unKX, unHY + 16, 15, 200, 0
        FONT_PrintAlpha fontPalette(8),  backBuffer, "SKIP",    unKX + 9 * FONT_CHAR_W, unHY + 16, 200
    End If

    _DEST 0
    _PUTIMAGE , backBuffer, 0

    Select Case UN_Input%(telemPlayerName, unCursorPos, UN_MAX_LEN)
        Case UN_DONE  ' min 3 chars
            If Len(telemPlayerName) = 0 Then telemPlayerName = UN_AutoName$
            If Len(telemPlayerName) >= 3 Then
                SETTINGS_Save
                If unFromSettings Then
                    unFromSettings = 0 : TITLE_ReturnTo GS_OPTIONS
                Else
                    LEADIN_Init : gameState = GS_LEADIN
                End If
            End If

        Case UN_SKIP
            If unFromSettings Then
                telemPlayerName = unSavedName
                unFromSettings = 0 : TITLE_ReturnTo GS_OPTIONS
            Else
                telemPlayerName = UN_AutoName$
                SETTINGS_Save
                LEADIN_Init : gameState = GS_LEADIN
            End If

        Case UN_EDIT
            unBlinkN = 0
    End Select

    MUS_Fill 0
End Sub

Function UN_AutoName$ ()
    UN_AutoName$ = "PILOT-" + Right$("000" + LTrim$(Str$(Int(RNG!(RNG_UNIQUE) * 9000) + 1000)), 4)
End Function
