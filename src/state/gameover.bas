Sub GS_GAMEOVER_Update ()
    Dim gsgThrobBright As Integer
    tt = tt + 0.025
    cam.POS.x = -CAM_OFFSET_X : cam.POS.y = CAM_OFFSET_Y : cam.POS.z = 0
    cam.target.x = CAM_LEAD_X : cam.target.y = 0 : cam.target.z = 0
    E3D_MatLookAt cam, viewMat
    E3D_MatMul projMat, viewMat, vpMat
    E3D_StarfieldUpdate cam.POS.x, cam.POS.y, cam.POS.z
    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    E3D_StarfieldDraw vpMat, scrW, scrH
    gameOverDelay = gameOverDelay - 1
    UI_DrawPanel scrW \ 2 - 88, scrH \ 2 - 44, scrW \ 2 + 88, scrH \ 2 + 44, "GAME OVER"
    FONT_PrintCenteredAlpha fontPalette(9),  backBuffer, "SCORE:  " + LTRIM$(STR$(score)), scrH \ 2 - 18, scrW, 255
    IF score >= highScore THEN
        FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "BEST:   " + LTRIM$(STR$(highScore)), scrH \ 2 + 2, scrW, 255
    ELSE
        FONT_PrintCenteredAlpha fontPalette(8),  backBuffer, "BEST:   " + LTRIM$(STR$(highScore)), scrH \ 2 + 2, scrW, 255
    END IF
    IF gameOverDelay <= 0 THEN
        gsgThrobBright = INT(170 + 85 * SIN(tt * 5))
        FONT_PrintCenteredAlpha fontPalette(15), backBuffer, "PRESS SPACE TO PLAY", scrH \ 2 + 22, scrW, gsgThrobBright
        IF held(E3D_KEY_SPACE) AND spaceWas = 0 THEN gameState = GS_TITLE : SEQ_RewindToTitle : MUS_SetCue "title"
    END IF
    spaceWas = held(E3D_KEY_SPACE)
    _DEST 0
    _PUTIMAGE , backBuffer, 0
    MUS_Fill 0
End Sub
