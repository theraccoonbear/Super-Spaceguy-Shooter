' hud.bas — in-game HUD rendering
'
' Call HUD_Draw once per frame after the scene is drawn to backBuffer.
' All state it reads/writes is DIM SHARED in sss.bas.
'
' Local variable prefix: hd*  (QB64-PE hoists Sub locals to module scope;
' all names must be unique across the compilation unit.)

Sub HUD_Draw
    Dim hdI As Integer, hdJ As Integer
    Dim hdTR As Integer
    Dim hdTSX As Single, hdTSY As Single
    Dim hdPjX As Single, hdPjY As Single, hdPjW As Single
    Dim hdShieldPct As Single, hdShieldFill As Integer, hdShieldClr As Long
    Dim hdLaserFill As Integer, hdLaserClr As Long
    Dim hdFuelFill As Integer, hdFuelClr As Long
    Dim hdBossHPBar As Integer
    Dim hdPartFade As Single
    Dim hdThrobBright As Integer

    _DEST backBuffer

    ' crosshair and target locks — gameplay only
    If gameState = GS_PLAYING Then
        ' trajectory cone: project 4 points along bullet path at increasing X depth
        Dim hdDist(0 To 3) As Single : hdDist(0) = 10 : hdDist(1) = 25 : hdDist(2) = 50 : hdDist(3) = 90
        Dim hdDotPX As Single, hdDotSX As Single, hdDotSY As Single, hdDotArm As Integer
        Dim hdDotClr As Long
        For hdI = 0 To 3
            hdDotPX = player.px + hdDist(hdI)
            hdPjX = hdDotPX * vpMat.m(0,0) + player.py * vpMat.m(0,1) + player.pz * vpMat.m(0,2) + vpMat.m(0,3)
            hdPjY = hdDotPX * vpMat.m(1,0) + player.py * vpMat.m(1,1) + player.pz * vpMat.m(1,2) + vpMat.m(1,3)
            hdPjW = hdDotPX * vpMat.m(3,0) + player.py * vpMat.m(3,1) + player.pz * vpMat.m(3,2) + vpMat.m(3,3)
            If hdPjW > 0.001 Then
                hdDotSX = (hdPjX / hdPjW + 1.0) * (scrW * 0.5)
                hdDotSY = (1.0 - hdPjY / hdPjW) * (scrH * 0.5)
                hdDotArm = 3 - hdI
                Select Case hdI
                    Case 0 : hdDotClr = _RGB(90, 230, 90)
                    Case 1 : hdDotClr = _RGB(70, 190, 70)
                    Case 2 : hdDotClr = _RGB(55, 155, 55)
                    Case 3 : hdDotClr = _RGB(40, 115, 40)
                End Select
                If hdDotArm > 0 Then
                    LINE (hdDotSX - hdDotArm, hdDotSY)-(hdDotSX + hdDotArm, hdDotSY), hdDotClr
                    LINE (hdDotSX, hdDotSY - hdDotArm)-(hdDotSX, hdDotSY + hdDotArm), hdDotClr
                Else
                    PSET (hdDotSX, hdDotSY), hdDotClr
                End If
            End If
        Next hdI

        If hdLockFlashTimer > 0 Then hdLockFlashTimer = hdLockFlashTimer - 1

        hdTR = 10
        For hdI = 1 To MAX_ENEMIES
            If enemies(hdI).active And enemies(hdI).px > player.px Then
                If Abs(player.py - enemies(hdI).py) < 3.5 And Abs(player.pz - enemies(hdI).pz) < 3.5 Then
                    hdPjX = enemies(hdI).px * vpMat.m(0,0) + enemies(hdI).py * vpMat.m(0,1) + enemies(hdI).pz * vpMat.m(0,2) + vpMat.m(0,3)
                    hdPjY = enemies(hdI).px * vpMat.m(1,0) + enemies(hdI).py * vpMat.m(1,1) + enemies(hdI).pz * vpMat.m(1,2) + vpMat.m(1,3)
                    hdPjW = enemies(hdI).px * vpMat.m(3,0) + enemies(hdI).py * vpMat.m(3,1) + enemies(hdI).pz * vpMat.m(3,2) + vpMat.m(3,3)
                    If hdPjW > 0.001 Then
                        hdTSX = (hdPjX / hdPjW + 1.0) * (scrW * 0.5)
                        hdTSY = (1.0 - hdPjY / hdPjW) * (scrH * 0.5)
                        If hdTSX >= hdTR And hdTSX < scrW - hdTR And hdTSY >= hdTR And hdTSY < scrH - hdTR Then
                            If hdLockFlashTimer > 0 Then COLOR _RGB(255, 255, 200) Else COLOR _RGB(255, 165, 40)
                            LINE (hdTSX - hdTR, hdTSY - hdTR)-(hdTSX - hdTR\2, hdTSY - hdTR)
                            LINE (hdTSX - hdTR, hdTSY - hdTR)-(hdTSX - hdTR, hdTSY - hdTR\2)
                            LINE (hdTSX + hdTR\2, hdTSY - hdTR)-(hdTSX + hdTR, hdTSY - hdTR)
                            LINE (hdTSX + hdTR, hdTSY - hdTR)-(hdTSX + hdTR, hdTSY - hdTR\2)
                            LINE (hdTSX - hdTR, hdTSY + hdTR\2)-(hdTSX - hdTR, hdTSY + hdTR)
                            LINE (hdTSX - hdTR, hdTSY + hdTR)-(hdTSX - hdTR\2, hdTSY + hdTR)
                            LINE (hdTSX + hdTR, hdTSY + hdTR\2)-(hdTSX + hdTR, hdTSY + hdTR)
                            LINE (hdTSX + hdTR\2, hdTSY + hdTR)-(hdTSX + hdTR, hdTSY + hdTR)
                        End If
                    End If
                End If
            End If
        Next hdI

        ' boss lock bracket (larger)
        If boss.active Then
            If Abs(player.py - boss.py) < 5.0 And Abs(player.pz - boss.pz) < 5.0 Then
                hdPjX = boss.px * vpMat.m(0,0) + boss.py * vpMat.m(0,1) + boss.pz * vpMat.m(0,2) + vpMat.m(0,3)
                hdPjY = boss.px * vpMat.m(1,0) + boss.py * vpMat.m(1,1) + boss.pz * vpMat.m(1,2) + vpMat.m(1,3)
                hdPjW = boss.px * vpMat.m(3,0) + boss.py * vpMat.m(3,1) + boss.pz * vpMat.m(3,2) + vpMat.m(3,3)
                If hdPjW > 0.001 Then
                    hdTSX = (hdPjX / hdPjW + 1.0) * (scrW * 0.5)
                    hdTSY = (1.0 - hdPjY / hdPjW) * (scrH * 0.5)
                    hdTR = 18
                    If hdTSX >= hdTR And hdTSX < scrW - hdTR And hdTSY >= hdTR And hdTSY < scrH - hdTR Then
                        If hdLockFlashTimer > 0 Then COLOR _RGB(255, 220, 220) Else COLOR _RGB(255, 60, 60)
                        LINE (hdTSX - hdTR, hdTSY - hdTR)-(hdTSX - hdTR\2, hdTSY - hdTR)
                        LINE (hdTSX - hdTR, hdTSY - hdTR)-(hdTSX - hdTR, hdTSY - hdTR\2)
                        LINE (hdTSX + hdTR\2, hdTSY - hdTR)-(hdTSX + hdTR, hdTSY - hdTR)
                        LINE (hdTSX + hdTR, hdTSY - hdTR)-(hdTSX + hdTR, hdTSY - hdTR\2)
                        LINE (hdTSX - hdTR, hdTSY + hdTR\2)-(hdTSX - hdTR, hdTSY + hdTR)
                        LINE (hdTSX - hdTR, hdTSY + hdTR)-(hdTSX - hdTR\2, hdTSY + hdTR)
                        LINE (hdTSX + hdTR, hdTSY + hdTR\2)-(hdTSX + hdTR, hdTSY + hdTR)
                        LINE (hdTSX + hdTR\2, hdTSY + hdTR)-(hdTSX + hdTR, hdTSY + hdTR)
                    End If
                End If
            End If
        End If
    End If

    ' score
    FONT_Print fontPalette(9), backBuffer, "SCORE: " + LTRIM$(STR$(score)), 4, 4

    ' ship life icons — bottom-left corner
    For hdJ = 1 To 3
        If hdJ <= shipLives Then
            LINE (3 + (hdJ-1)*10, scrH - 12)-(9 + (hdJ-1)*10, scrH - 4), _RGB(60, 155, 230), BF
            LINE (3 + (hdJ-1)*10, scrH - 12)-(9 + (hdJ-1)*10, scrH - 4), _RGB(140, 210, 255), B
        Else
            LINE (3 + (hdJ-1)*10, scrH - 12)-(9 + (hdJ-1)*10, scrH - 4), _RGB(18, 26, 40), BF
            LINE (3 + (hdJ-1)*10, scrH - 12)-(9 + (hdJ-1)*10, scrH - 4), _RGB(38, 52, 70), B
        End If
    Next hdJ

    ' gauges: SH [=] LA [=] FU [=]
    hdShieldPct = lives / 100.0
    If hdShieldPct > 1.0 Then hdShieldPct = 1.0
    If hdShieldPct < 0.0 Then hdShieldPct = 0.0
    hdShieldFill = INT(hdShieldPct * 28)
    hdLaserFill  = INT((laserEnergy / 100.0) * 28)
    hdFuelFill   = INT((fuelLevel   / 100.0) * 28)

    FONT_Print fontPalette(9), backBuffer, "SH", scrW - 150, 4
    LINE (scrW - 134, 8)-(scrW - 104, 14), _RGB(15, 20, 30), BF
    If hdShieldFill > 0 Then
        If lives > 60 Then
            hdShieldClr = _RGB(50, 210, 60)
        ElseIf lives > 30 Then
            hdShieldClr = _RGB(235, 190, 15)
        Else
            hdShieldClr = _RGB(240, 50, 35)
        End If
        LINE (scrW - 133, 9)-(scrW - 133 + hdShieldFill, 13), hdShieldClr, BF
        LINE (scrW - 133, 9)-(scrW - 133 + hdShieldFill, 10), _RGB(180, 255, 190), BF
    End If
    LINE (scrW - 134, 8)-(scrW - 104, 14), _RGB(70, 90, 100), B

    FONT_Print fontPalette(9), backBuffer, "LA", scrW - 100, 4
    LINE (scrW - 84, 8)-(scrW - 54, 14), _RGB(15, 20, 30), BF
    If hdLaserFill > 0 Then
        If laserEnergy > 30 Then
            hdLaserClr = _RGB(60, 180, 255)
        Else
            hdLaserClr = _RGB(255, 140, 20)
        End If
        LINE (scrW - 83, 9)-(scrW - 83 + hdLaserFill, 13), hdLaserClr, BF
        LINE (scrW - 83, 9)-(scrW - 83 + hdLaserFill, 10), _RGB(200, 235, 255), BF
    End If
    LINE (scrW - 84, 8)-(scrW - 54, 14), _RGB(70, 90, 100), B

    FONT_Print fontPalette(9), backBuffer, "FU", scrW - 50, 4
    LINE (scrW - 34, 8)-(scrW - 4, 14), _RGB(15, 20, 30), BF
    If hdFuelFill > 0 Then
        If fuelLevel > 40 Then
            hdFuelClr = _RGB(230, 180, 30)
        Else
            hdFuelClr = _RGB(255, 80, 20)
        End If
        LINE (scrW - 33, 9)-(scrW - 33 + hdFuelFill, 13), hdFuelClr, BF
        LINE (scrW - 33, 9)-(scrW - 33 + hdFuelFill, 10), _RGB(255, 230, 130), BF
    End If
    LINE (scrW - 34, 8)-(scrW - 4, 14), _RGB(70, 90, 100), B

    ' boss HP bar
    If boss.active Then
        FONT_Print fontPalette(14), backBuffer, "BOSS", scrW\2 - 88, scrH - 18
        hdBossHPBar = INT((bossHP / BOSS_MAX_HP) * 100)
        LINE (scrW/2 - 52, scrH - 14)-(scrW/2 + 52, scrH - 5), _RGB(15, 20, 30), BF
        If hdBossHPBar > 0 Then
            LINE (scrW/2 - 51, scrH - 13)-(scrW/2 - 51 + hdBossHPBar, scrH - 6), _RGB(220, 40, 40), BF
            LINE (scrW/2 - 51, scrH - 13)-(scrW/2 - 51 + hdBossHPBar, scrH - 12), _RGB(255, 110, 110), BF
        End If
        LINE (scrW/2 - 52, scrH - 14)-(scrW/2 + 52, scrH - 5), _RGB(70, 90, 100), B
    End If

    ' boss warning flash
    If bossWarnTimer > 0 And boss.active = 0 Then
        If (bossWarnTimer Mod 18) < 9 Then
            FONT_PrintCentered fontPalette(14), backBuffer, "! WARNING !", scrH\2 - 10, scrW
            FONT_PrintCentered fontPalette(14), backBuffer, "BOSS INCOMING", scrH\2 + 8, scrW
        End If
    End If

    ' score pop — floats upward, fades
    If scorePopTimer > 0 Then
        hdPartFade = scorePopTimer / 30.0
        COLOR _RGB(INT(255 * hdPartFade), INT(255 * hdPartFade), INT(80 * hdPartFade))
        _PRINTSTRING (scrW / 2 - 10, scorePopY), "+" + LTRIM$(STR$(scorePopVal))
        scorePopY = scorePopY - 0.5
        scorePopTimer = scorePopTimer - 1
    End If

    ' invincibility lead-in
    If invTimer > 0 And gameState = GS_PLAYING Then
        hdThrobBright = INT(160 + 95 * SIN(tt * 10))
        COLOR _RGB(hdThrobBright, hdThrobBright, 80)
        _PRINTSTRING (scrW / 2 - 32, scrH / 2 - 8), "GET READY"
    End If

    ' pause overlay
    If pauseFlag Then
        hdThrobBright = INT(160 + 95 * SIN(tt * 7))
        COLOR _RGB(hdThrobBright, hdThrobBright, 255)
        _PRINTSTRING (scrW / 2 - 20, scrH / 2 - 8), "PAUSE"
        COLOR _RGB(120, 120, 180)
        _PRINTSTRING (scrW / 2 - 20, scrH / 2 + 8), "P=RESUME"
    End If
End Sub
