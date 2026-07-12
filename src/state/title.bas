Sub GS_TITLE_Update ()
    Dim gstThrobBright As Integer
    tt = tt + 0.025
    _DEST backBuffer
    _PUTIMAGE (0, 0)-(scrW - 1, scrH - 1), titleImg, backBuffer
    LINE (0, 196)-(scrW - 1, scrH - 1), _RGBA(0, 0, 8, 175), BF
    gstThrobBright = INT(170 + 85 * SIN(tt * 5))
    FONT_PrintCenteredAlpha fontPalette(15), backBuffer, "PRESS SPACE TO START", 200, scrW, gstThrobBright
    FONT_PrintAlpha fontPalette(8), backBuffer, "ESC  OPTIONS", 2, scrH - FONT_CHAR_H, 255
    FONT_PrintAlpha fontPalette(8), backBuffer, "v" + VERSION$, scrW - LEN("v" + VERSION$) * FONT_CHAR_W - 2, scrH - FONT_CHAR_H, 255
    IF titleEscConfirm THEN
        UI_DrawPanel scrW\2 - 76, scrH\2 - 52, scrW\2 + 76, scrH\2 + 52, "COMMAND CONSOLE"
        FONT_PrintCenteredAlpha fontPalette(9),  backBuffer, "A   ABOUT",       scrH\2 - 26, scrW, 255
        FONT_PrintCenteredAlpha fontPalette(9),  backBuffer, "S   SETTINGS",    scrH\2 -  6, scrW, 255
        FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "Y   QUIT GAME",   scrH\2 + 14, scrW, 255
        FONT_PrintCenteredAlpha fontPalette(8),  backBuffer, "ESC CANCEL",      scrH\2 + 34, scrW, 255
    END IF
    _DEST 0
    _PUTIMAGE , backBuffer, 0
    IF held(E3D_KEY_ESCAPE) AND escWas = 0 THEN titleEscConfirm = 1 - titleEscConfirm
    escWas = held(E3D_KEY_ESCAPE)
    IF titleEscConfirm THEN
        IF _KEYDOWN(65) OR _KEYDOWN(97) THEN
            ABOUT_Prep : gameState = GS_ABOUT : titleEscConfirm = 0
        END IF
        IF _KEYDOWN(83) OR _KEYDOWN(115) THEN
            gameState = GS_OPTIONS : titleEscConfirm = 0
            optUpWas = -1 : optDnWas = 0 : optLfWas = 0 : optRtWas = 0 : optEscWas = -1 : optAboutWas = _KEYDOWN(65) OR _KEYDOWN(97)
        END IF
        IF _KEYDOWN(89) OR _KEYDOWN(121) THEN SYSTEM
        IF _KEYDOWN(78) OR _KEYDOWN(110) THEN titleEscConfirm = 0
        MUS_Fill 0
        EXIT SUB
    END IF
    MUS_Fill 0
    IF held(E3D_KEY_SPACE) AND spaceWas = 0 THEN GAME_NewGame
    spaceWas = held(E3D_KEY_SPACE)
End Sub
