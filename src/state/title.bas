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
    IF ctrlDev > 0 THEN
        FONT_PrintAlpha fontPalette(8), backBuffer, "ESC/BACK  OPTIONS", 2, scrH - FONT_CHAR_H, 255
    ELSE
        FONT_PrintAlpha fontPalette(8), backBuffer, "ESC  OPTIONS", 2, scrH - FONT_CHAR_H, 255
    END IF
    FONT_PrintAlpha fontPalette(8), backBuffer, "v" + VERSION$, scrW - LEN("v" + VERSION$) * FONT_CHAR_W - 2, scrH - FONT_CHAR_H, 255
    IF titleEscConfirm THEN
        Dim gstKX As Integer, gstSelY As Integer
        UI_DrawPanel scrW\2 - 76, scrH\2 - 72, scrW\2 + 76, scrH\2 + 66, "COMMAND CONSOLE"
        gstSelY = scrH\2 - 46 + titleConSel * 18
        LINE (scrW\2 - 66, gstSelY - 3)-(scrW\2 + 66, gstSelY + 11), _RGBA(0, 40, 100, 180), BF
        LINE (scrW\2 - 66, gstSelY - 3)-(scrW\2 + 66, gstSelY + 11), _RGB(0, 100, 180), B
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
        FONT_PrintAlpha fontPalette(9),  backBuffer, "N/ESC CANCEL", gstKX, scrH\2 + 44, 255
        FONT_PrintAlpha fontPalette(15), backBuffer, "N",            gstKX, scrH\2 + 44, 255
        FONT_PrintAlpha fontPalette(15), backBuffer, "ESC",          gstKX + 2 * FONT_CHAR_W, scrH\2 + 44, 255
    END IF
    _DEST 0
    _PUTIMAGE , backBuffer, 0
    ' gamepad Start also sets ESCAPE; on the title it means "play", not "open console" (Back opens it)
    IF (held(E3D_KEY_ESCAPE) AND escWas = 0 AND held(E3D_KEY_PAD_START) = 0) OR KEY_Pressed%(E3D_KEY_PAD_SELECT) THEN
        titleEscConfirm = 1 - titleEscConfirm : titleConSel = 0
    END IF
    escWas = held(E3D_KEY_ESCAPE)
    IF titleEscConfirm THEN
        Dim gstPick As Integer
        IF KEY_Pressed%(E3D_KEY_UP) THEN titleConSel = (titleConSel + 5) MOD 6
        IF KEY_Pressed%(E3D_KEY_DOWN) THEN titleConSel = (titleConSel + 1) MOD 6
        gstPick = -1
        IF KEY_Confirm% THEN gstPick = titleConSel
        IF KEY_Down%(65) OR KEY_Down%(97) THEN gstPick = 0
        IF KEY_Down%(67) OR KEY_Down%(99) THEN gstPick = 1
        IF KEY_Down%(83) OR KEY_Down%(115) THEN gstPick = 2
        IF KEY_Down%(76) OR KEY_Down%(108) THEN gstPick = 3
        IF KEY_Down%(81) OR KEY_Down%(113) THEN gstPick = 4
        IF KEY_Down%(78) OR KEY_Down%(110) OR KEY_Pressed%(E3D_KEY_PAD_B) THEN gstPick = 5
        SELECT CASE gstPick
            CASE 0
                ABOUT_Prep GS_TITLE : gameState = GS_ABOUT : titleEscConfirm = 0
            CASE 1
                CONTROLS_Prep GS_TITLE : gameState = GS_CONTROLS
            CASE 2
                gameState = GS_OPTIONS : titleEscConfirm = 0
                optUpWas = -1 : optDnWas = 0 : optLfWas = 0 : optRtWas = 0 : optEscWas = -1 : optAboutWas = KEY_Down%(65) OR KEY_Down%(97)
            CASE 3
                gameState = GS_LEADERBOARD : titleEscConfirm = 0
            CASE 4
                SYSTEM
            CASE 5
                titleEscConfirm = 0
        END SELECT
        ' keep the start-game debounce current, so a P or Start held while the console closes doesn't start a game
        pWas = held(E3D_KEY_P) OR held(E3D_KEY_PAD_START)
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
