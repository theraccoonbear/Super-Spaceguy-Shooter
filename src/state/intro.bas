Sub GS_INTRO_Update ()
    Dim gsiThrobBright As Integer
    tt = tt + 0.025
    introTimer = introTimer + 1
    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    IF emperorImg <> 0 THEN
        _PUTIMAGE (10, 0)-(309, scrH - 1), emperorImg, backBuffer
        BACKDROP_Draw "emperor", 10, 0, 309, scrH - 1
    END IF
    LINE (0, scrH - 38)-(scrW - 1, scrH - 1), _RGBA(0, 0, 8, 210), BF
    FONT_PrintCenteredAlpha fontPalette(14), backBuffer, emperorName, scrH - 34, scrW, 255
    IF introTimer > 60 THEN
        gsiThrobBright = INT(160 + 95 * SIN(tt * 5))
        UI_PromptsCentered UI_Tok$("ENTER", E3D_ACT_CONFIRM) + " CONTINUE  " + UI_Tok$("ESC", E3D_ACT_BACK) + " BACK", scrH - 14, 15, gsiThrobBright
    END IF
    IF introTimer < 40 THEN
        LINE (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 0, 255 - introTimer * 6), BF
    END IF
    _DEST 0
    _PUTIMAGE , backBuffer, 0
    IF KEY_Back% THEN
        SEQ_RewindToTitle
        gameState = GS_TITLE : introTimer = 0 : MUS_SetCue "title"
    END IF
    escWas = held(E3D_KEY_ESCAPE)
    IF KEY_Proceed% AND introTimer > 45 THEN
        introTimer = 0 : SEQ_Advance
    END IF
    spaceWas = held(E3D_KEY_SPACE)
    MUS_Fill 0
End Sub
