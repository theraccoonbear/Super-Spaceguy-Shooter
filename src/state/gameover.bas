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
    ' leftover credits were cashed in at the death (CR_CashOut): count the bonus up into the score
    Dim gsgBonus As Long, gsgFrac As Single
    gsgFrac = (90 - gameOverDelay) / 45
    IF gsgFrac < 0 THEN gsgFrac = 0
    IF gsgFrac > 1 THEN gsgFrac = 1
    gsgBonus = INT(crBonusPts * gsgFrac)
    Dim gsgY As Integer, gsgStep As Integer, gsgTitle As String
    IF runStranded THEN gsgTitle = "STRANDED" ELSE gsgTitle = "GAME OVER"
    IF crBonusCredits > 0 THEN
        UI_DrawPanel scrW \ 2 - 88, scrH \ 2 - 62, scrW \ 2 + 88, scrH \ 2 + 62, gsgTitle
        FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "CREDITS BONUS +" + LTRIM$(STR$(gsgBonus)), scrH \ 2 - 38, scrW, 255
        gsgY = scrH \ 2 - 20 : gsgStep = 18
    ELSE
        UI_DrawPanel scrW \ 2 - 88, scrH \ 2 - 54, scrW \ 2 + 88, scrH \ 2 + 54, gsgTitle
        gsgY = scrH \ 2 - 28 : gsgStep = 20
    END IF
    FONT_PrintCenteredAlpha fontPalette(9),  backBuffer, "SCORE:  " + LTRIM$(STR$(score - crBonusPts + gsgBonus)), gsgY, scrW, 255
    IF score >= highScore THEN
        FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "BEST:   " + LTRIM$(STR$(highScore)), gsgY + gsgStep, scrW, 255
    ELSE
        FONT_PrintCenteredAlpha fontPalette(8),  backBuffer, "BEST:   " + LTRIM$(STR$(highScore)), gsgY + gsgStep, scrW, 255
    END IF
    Dim gsgRank As Integer : gsgRank = LBRD_Rank%(score)
    IF gsgRank > 0 THEN
        FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "RANK:   #" + LTRIM$(STR$(gsgRank)), gsgY + gsgStep * 2, scrW, 255
    ELSEIF lbrdCount > 0 THEN
        FONT_PrintCenteredAlpha fontPalette(8),  backBuffer, "RANK:   --", gsgY + gsgStep * 2, scrW, 200
    END IF
    IF gameOverDelay <= 0 THEN
        gsgThrobBright = INT(170 + 85 * SIN(tt * 5))
        UI_PromptsCentered "PRESS " + UI_Tok$("SPACE", E3D_ACT_FIRE) + " TO PLAY", gsgY + gsgStep * 3, 15, gsgThrobBright
        IF held(E3D_KEY_SPACE) AND spaceWas = 0 THEN gameState = GS_TITLE : SEQ_RewindToTitle : MUS_SetCue "title"
    END IF
    spaceWas = held(E3D_KEY_SPACE)
    _DEST 0
    _PUTIMAGE , backBuffer, 0
    MUS_Fill 0
End Sub
