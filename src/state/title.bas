Sub GS_TITLE_Update ()
    Dim gstThrobBright As Integer
    ' a pad with no built-in layout and no saved bindings: first-run setup (#266)
    IF padSetupDue AND ctrlDev > 0 AND iscActive = 0 AND titleEscConfirm = 0 THEN
        padSetupDue = 0 : launchOpen = 0
        RMP_OpenWizard GS_TITLE
        EXIT SUB
    END IF
    tt = tt + 0.025
    _DEST backBuffer
    _PUTIMAGE (0, 0)-(scrW - 1, scrH - 1), titleImg, backBuffer
    LINE (0, 196)-(scrW - 1, scrH - 1), _RGBA(0, 0, 8, 175), BF
    gstThrobBright = INT(170 + 85 * SIN(tt * 5))
    UI_PromptsCentered "PRESS " + UI_Tok$("P", E3D_ACT_PAUSE) + " TO PLAY", 200, 15, gstThrobBright
    IF DLV_Chosen$ <> DLV_Default$ AND titleEscConfirm = 0 AND crTallyTimer <= 0 THEN
        Dim gstDiff As String
        gstDiff = "DIFFICULTY: " + DLV_Name$(DLV_Chosen$)
        UI_Panel scrW \ 2 - LEN(gstDiff) * FONT_CHAR_W \ 2 - 6, 172, scrW \ 2 + LEN(gstDiff) * FONT_CHAR_W \ 2 + 5, 193
        UI_TextCentered 14, gstDiff, 175, 255
    END IF
    UI_Prompts UI_Tok$("ESC", E3D_ACT_CAMERA) + "  OPTIONS", 2, scrH - FONT_CHAR_H, 8, 255
    FONT_PrintAlpha fontPalette(8), backBuffer, "v" + VERSION$, scrW - LEN("v" + VERSION$) * FONT_CHAR_W - 2, scrH - FONT_CHAR_H, 255
    IF titleEscConfirm THEN
        Dim gstKX As Integer, gstSelY As Integer, gstBY As Integer
        gstBY = scrH\2 - 9   ' the console grew a row: it moves up half of it, clear of PRESS P TO PLAY
        UI_DrawPanel scrW\2 - 76, gstBY - 72, scrW\2 + 76, gstBY + 84, "COMMAND CONSOLE"
        gstSelY = gstBY - 46 + titleConSel * 18
        UI_MenuHighlight scrW\2 - 66, gstSelY - 3, scrW\2 + 66, gstSelY + 11
        ' labels, then (keyboard) each hotkey letter overwritten in bright; the pad has only its cancel button
        gstKX = scrW\2 - 44
        FONT_PrintAlpha fontPalette(9),  backBuffer, "ABOUT",       gstKX, gstBY - 46, 255
        FONT_PrintAlpha fontPalette(9),  backBuffer, "CONTROLS",    gstKX, gstBY - 28, 255
        FONT_PrintAlpha fontPalette(9),  backBuffer, "SETTINGS",    gstKX, gstBY - 10, 255
        FONT_PrintAlpha fontPalette(9),  backBuffer, "LEADERBOARD", gstKX, gstBY +  8, 255
        FONT_PrintAlpha fontPalette(9),  backBuffer, "TUTORIAL",    gstKX, gstBY + 26, 255
        FONT_PrintAlpha fontPalette(9),  backBuffer, "QUIT GAME",   gstKX, gstBY + 44, 255
        IF INP_LastDevice% = INP_DEV_PAD THEN
            UI_PromptsAt UI_Tok$("", E3D_ACT_BACK) + " CANCEL", INP_DEV_PAD, gstKX, gstBY + 62, 9, 255, 0
        ELSE
            FONT_PrintAlpha fontPalette(15), backBuffer, "A",            gstKX, gstBY - 46, 255
            FONT_PrintAlpha fontPalette(15), backBuffer, "C",            gstKX, gstBY - 28, 255
            FONT_PrintAlpha fontPalette(15), backBuffer, "S",            gstKX, gstBY - 10, 255
            FONT_PrintAlpha fontPalette(15), backBuffer, "L",            gstKX, gstBY +  8, 255
            FONT_PrintAlpha fontPalette(15), backBuffer, "T",            gstKX, gstBY + 26, 255
            FONT_PrintAlpha fontPalette(15), backBuffer, "Q",            gstKX, gstBY + 44, 255
            FONT_PrintAlpha fontPalette(9),  backBuffer, "N/ESC CANCEL", gstKX, gstBY + 62, 255
            FONT_PrintAlpha fontPalette(15), backBuffer, "N",            gstKX, gstBY + 62, 255
            FONT_PrintAlpha fontPalette(15), backBuffer, "ESC",          gstKX + 2 * FONT_CHAR_W, gstBY + 62, 255
        END IF
    END IF
    IF titleEscConfirm = 0 THEN HUD_RunTally
    IF launchOpen THEN
        Dim gstLY As Integer, gstLP As String
        UI_DrawPanel scrW\2 - 80, scrH\2 - 48, scrW\2 + 80, scrH\2 + 40, "LAUNCH NOW?"
        gstLY = scrH\2 - 20 + launchSel * 18
        UI_MenuHighlight scrW\2 - 66, gstLY - 3, scrW\2 + 66, gstLY + 11
        UI_TextCentered 9, "YES", scrH\2 - 20, 255
        UI_TextCentered 9, "NO",  scrH\2 - 2,  255
        gstLP = UI_Tok$("ENTER", E3D_ACT_CONFIRM) + " GO  " + UI_Tok$("ESC", E3D_ACT_BACK) + " BACK"
        UI_PromptsAt gstLP, INP_LastDevice%, (scrW - UI_PromptsW%(gstLP, INP_LastDevice%)) \ 2, scrH\2 + 20, 8, 255, 0
    END IF
    _DEST 0
    _PUTIMAGE , backBuffer, 0
    ' gamepad Start also sets ESCAPE; on the title it means "play", not "open console" (Back opens it)
    IF launchOpen = 0 AND ((held(E3D_KEY_ESCAPE) AND escWas = 0 AND held(E3D_KEY_PAD_START) = 0) OR KEY_Pressed%(E3D_KEY_PAD_SELECT)) THEN
        titleEscConfirm = 1 - titleEscConfirm : titleConSel = 0
        IF titleEscConfirm = 0 THEN uiSfx = SND_UI_BACK
    END IF
    escWas = held(E3D_KEY_ESCAPE)
    IF titleEscConfirm THEN
        Dim gstPick As Integer
        gstPick = MENU_Input%(titleConSel, 7)
        IF KEY_Down%(65) OR KEY_Down%(97) THEN gstPick = 0
        IF KEY_Down%(67) OR KEY_Down%(99) THEN gstPick = 1
        IF KEY_Down%(83) OR KEY_Down%(115) THEN gstPick = 2
        IF KEY_Down%(76) OR KEY_Down%(108) THEN gstPick = 3
        IF KEY_Down%(84) OR KEY_Down%(116) THEN gstPick = 4
        IF KEY_Down%(81) OR KEY_Down%(113) THEN gstPick = 5
        IF KEY_Down%(78) OR KEY_Down%(110) OR KEY_Pressed%(E3D_KEY_PAD_B) THEN gstPick = 6
        IF gstPick >= 0 AND gstPick <= 5 THEN uiSfx = SND_UI_OK
        IF gstPick = 6 THEN uiSfx = SND_UI_BACK
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
                titleEscConfirm = 0 : tutGated = 0
                IF GAME_StartTutorial% = 0 THEN GAME_Usage(seqLastError)
            CASE 5
                GAME_Quit
            CASE 6
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
    ' The first start press opens LAUNCH NOW? (launchlogic.bas); nothing starts a run until it is confirmed.
    IF LAUNCH_Input%(held(E3D_KEY_P) OR held(E3D_KEY_PAD_START)) = LAUNCH_YES THEN TUT_StartFromTitle
End Sub
