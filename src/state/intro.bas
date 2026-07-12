Sub GS_INTRO_Update ()
    Dim gsiThrobBright As Integer
    tt = tt + 0.025
    introTimer = introTimer + 1
    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    IF emperorImg <> 0 THEN
        _PUTIMAGE (10, 0)-(309, scrH - 1), emperorImg, backBuffer
    END IF
    LINE (0, scrH - 38)-(scrW - 1, scrH - 1), _RGBA(0, 0, 8, 210), BF
    FONT_PrintCenteredAlpha fontPalette(14), backBuffer, emperorName, scrH - 34, scrW, 255
    IF introTimer > 60 THEN
        gsiThrobBright = INT(160 + 95 * SIN(tt * 5))
        FONT_PrintCenteredAlpha fontPalette(15), backBuffer, "PRESS SPACE", scrH - 14, scrW, gsiThrobBright
    END IF
    IF introTimer < 40 THEN
        LINE (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 0, 255 - introTimer * 6), BF
    END IF
    _DEST 0
    _PUTIMAGE , backBuffer, 0
    IF held(E3D_KEY_ESCAPE) AND escWas = 0 THEN
        SEQ_RewindToTitle
        gameState = GS_TITLE : introTimer = 0 : MUS_SetCue "title"
    END IF
    escWas = held(E3D_KEY_ESCAPE)
    IF held(E3D_KEY_SPACE) AND spaceWas = 0 AND introTimer > 45 THEN
        introTimer = 0 : SEQ_Advance
    END IF
    spaceWas = held(E3D_KEY_SPACE)
    MUS_Fill 0
End Sub
