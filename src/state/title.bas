Sub GS_TITLE_Update ()
    Dim gstThrobBright As Integer
    tt = tt + 0.025
    _DEST backBuffer
    _PUTIMAGE (0, 0)-(scrW - 1, scrH - 1), titleImg, backBuffer
    LINE (0, 196)-(scrW - 1, scrH - 1), _RGBA(0, 0, 8, 175), BF
    gstThrobBright = INT(170 + 85 * SIN(tt * 5))
    IF ctrlDev > 0 THEN
        FONT_PrintCenteredAlpha fontPalette(15), backBuffer, "PRESS P OR START TO PLAY", 200, scrW, gstThrobBright
    ELSE
        FONT_PrintCenteredAlpha fontPalette(15), backBuffer, "PRESS P TO PLAY", 200, scrW, gstThrobBright
    END IF
    FONT_PrintAlpha fontPalette(8), backBuffer, "ESC  OPTIONS", 2, scrH - FONT_CHAR_H, 255
    FONT_PrintAlpha fontPalette(8), backBuffer, "v" + VERSION$, scrW - LEN("v" + VERSION$) * FONT_CHAR_W - 2, scrH - FONT_CHAR_H, 255
    IF titleEscConfirm THEN
        Dim gstKX As Integer
        UI_DrawPanel scrW\2 - 76, scrH\2 - 72, scrW\2 + 76, scrH\2 + 66, "COMMAND CONSOLE"
        ' key column: dim full label first, then overwrite hotkey in bright
        gstKX = scrW\2 - 44
        FONT_PrintAlpha fontPalette(9),  backBuffer, "ABOUT",       gstKX, scrH\2 - 46, 255
        FONT_PrintAlpha fontPalette(15), backBuffer, "A",           gstKX, scrH\2 - 46, 255
        FONT_PrintAlpha fontPalette(9),  backBuffer, "CONTROLS",    gstKX, scrH\2 - 28, 255
        FONT_PrintAlpha fontPalette(15), backBuffer, "C",           gstKX, scrH\2 - 28, 255
        FONT_PrintAlpha fontPalette(9),  backBuffer, "SETTINGS",    gstKX, scrH\2 - 10, 255
        FONT_PrintAlpha fontPalette(15), backBuffer, "S",           gstKX, scrH\2 - 10, 255
        FONT_PrintAlpha fontPalette(9),  backBuffer, "LEADERBOARD", gstKX, scrH\2 +  8, 255
        FONT_PrintAlpha fontPalette(15), backBuffer, "L",           gstKX, scrH\2 +  8, 255
        FONT_PrintAlpha fontPalette(9),  backBuffer, "QUIT GAME",   gstKX, scrH\2 + 26, 255
        FONT_PrintAlpha fontPalette(15), backBuffer, "Q",           gstKX, scrH\2 + 26, 255
        FONT_PrintAlpha fontPalette(9),  backBuffer, "ESC CANCEL",  gstKX, scrH\2 + 44, 255
        FONT_PrintAlpha fontPalette(15), backBuffer, "ESC",         gstKX, scrH\2 + 44, 255
    END IF
    _DEST 0
    _PUTIMAGE , backBuffer, 0
    ' gamepad Start also sets ESCAPE; on the title it means "play", not "open console"
    IF held(E3D_KEY_ESCAPE) AND escWas = 0 AND held(E3D_KEY_PAD_START) = 0 THEN titleEscConfirm = 1 - titleEscConfirm
    escWas = held(E3D_KEY_ESCAPE)
    IF titleEscConfirm THEN
        IF KEY_Down%(65) OR KEY_Down%(97) THEN
            ABOUT_Prep GS_TITLE : gameState = GS_ABOUT : titleEscConfirm = 0
        END IF
        IF KEY_Down%(67) OR KEY_Down%(99) THEN
            CONTROLS_Prep GS_TITLE : gameState = GS_CONTROLS
        END IF
        IF KEY_Down%(83) OR KEY_Down%(115) THEN
            gameState = GS_OPTIONS : titleEscConfirm = 0
            optUpWas = -1 : optDnWas = 0 : optLfWas = 0 : optRtWas = 0 : optEscWas = -1 : optAboutWas = KEY_Down%(65) OR KEY_Down%(97)
        END IF
        IF KEY_Down%(76) OR KEY_Down%(108) THEN
            gameState = GS_LEADERBOARD : titleEscConfirm = 0
        END IF
        IF KEY_Down%(81) OR KEY_Down%(113) THEN SYSTEM
        IF KEY_Down%(78) OR KEY_Down%(110) THEN titleEscConfirm = 0
        MUS_Fill 0
        EXIT SUB
    END IF
    MUS_Fill 0
    ' Deliberately NOT space here -- space is held/mashed constantly elsewhere
    ' (firing, skipping crawls/cinematics) and made it too easy to accidentally
    ' start a new game from the title screen. P is not bound to anything else.
    ' Gamepad Start for the same reason (A is the fire button).
    IF (held(E3D_KEY_P) OR held(E3D_KEY_PAD_START)) AND pWas = 0 THEN GAME_NewGame
    pWas = held(E3D_KEY_P) OR held(E3D_KEY_PAD_START)
End Sub
