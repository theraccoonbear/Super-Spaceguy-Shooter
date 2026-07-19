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
    Dim hdHiStr As String

    _DEST backBuffer

    ' crosshair and target locks — combat only
    If gameState = GS_PLAYING And levelType <> LEVEL_ASTEROID Then
        ' project aim point along ship nose — full E3D rotation Rx*Ry*Rz applied to forward (1,0,0)
        Dim hdRx As Single, hdRy As Single, hdRz As Single
        Dim hdAimPX As Single, hdAimPY As Single, hdAimPZ As Single
        Dim hdCPjX As Single, hdCPjY As Single, hdCPjW As Single
        Dim hdCSX As Single, hdCSY As Single
        hdRx = player.rx * _PI / 180.0
        hdRy = player.ry * _PI / 180.0
        hdRz = player.rz * _PI / 180.0
        hdAimPX = player.px + COS(hdRz)*COS(hdRy) * 20
        hdAimPY = player.py + (COS(hdRx)*SIN(hdRz)*COS(hdRy) + SIN(hdRx)*SIN(hdRy)) * 20
        hdAimPZ = player.pz + (SIN(hdRx)*SIN(hdRz)*COS(hdRy) - COS(hdRx)*SIN(hdRy)) * 20
        hdCPjX = hdAimPX * vpMat.m(0,0) + hdAimPY * vpMat.m(0,1) + hdAimPZ * vpMat.m(0,2) + vpMat.m(0,3)
        hdCPjY = hdAimPX * vpMat.m(1,0) + hdAimPY * vpMat.m(1,1) + hdAimPZ * vpMat.m(1,2) + vpMat.m(1,3)
        hdCPjW = hdAimPX * vpMat.m(3,0) + hdAimPY * vpMat.m(3,1) + hdAimPZ * vpMat.m(3,2) + vpMat.m(3,3)
        If hdCPjW > 0.001 Then
            hdCSX = (hdCPjX / hdCPjW + 1.0) * (scrW * 0.5)
            hdCSY = (1.0 - hdCPjY / hdCPjW) * (scrH * 0.5)
        Else
            hdCSX = scrW * 0.5 : hdCSY = scrH * 0.5
        End If
        LINE (hdCSX - 7, hdCSY)-(hdCSX - 3, hdCSY), _RGB(100, 255, 100)
        LINE (hdCSX + 3, hdCSY)-(hdCSX + 7, hdCSY), _RGB(100, 255, 100)
        LINE (hdCSX, hdCSY - 5)-(hdCSX, hdCSY - 2), _RGB(100, 255, 100)
        LINE (hdCSX, hdCSY + 2)-(hdCSX, hdCSY + 5), _RGB(100, 255, 100)

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
                            COLOR _RGB(255, 165, 40)
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
                        COLOR _RGB(255, 60, 60)
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
    FONT_PrintAlpha fontPalette(9), backBuffer, "SCORE: " + LTRIM$(STR$(score)), 4, 4, 255
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

    FONT_PrintAlpha fontPalette(9), backBuffer, "SH", scrW - 150, 4, 255
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

    FONT_PrintAlpha fontPalette(9), backBuffer, "LA", scrW - 100, 4, 255
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

    FONT_PrintAlpha fontPalette(9), backBuffer, "FU", scrW - 50, 4, 255
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
        FONT_PrintAlpha fontPalette(14), backBuffer, "BOSS", scrW\2 - 88, scrH - 18, 255
        hdBossHPBar = INT((boss.hp / BOSS_MAX_HP) * 100)
        LINE (scrW/2 - 52, scrH - 14)-(scrW/2 + 52, scrH - 5), _RGB(15, 20, 30), BF
        If hdBossHPBar > 0 Then
            LINE (scrW/2 - 51, scrH - 13)-(scrW/2 - 51 + hdBossHPBar, scrH - 6), _RGB(220, 40, 40), BF
            LINE (scrW/2 - 51, scrH - 13)-(scrW/2 - 51 + hdBossHPBar, scrH - 12), _RGB(255, 110, 110), BF
        End If
        LINE (scrW/2 - 52, scrH - 14)-(scrW/2 + 52, scrH - 5), _RGB(70, 90, 100), B
    End If

    ' boss warning flash
    If boss.warnTimer > 0 And boss.active = 0 Then
        If (boss.warnTimer Mod 18) < 9 Then
            FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "! WARNING !", scrH\2 - 10, scrW, 255
            FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "BOSS INCOMING", scrH\2 + 8, scrW, 255
        End If
    End If

    ' score pop — floats upward, fades
    If scorePopTimer > 0 Then
        hdPartFade = scorePopTimer / 30.0
        Dim hdPopAlpha As Integer
        hdPopAlpha = INT(hdPartFade * 255)
        If hdPopAlpha > 255 Then hdPopAlpha = 255
        FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "+" + LTRIM$(STR$(scorePopVal)), INT(scorePopY), scrW, hdPopAlpha
        scorePopY = scorePopY - 0.5
        scorePopTimer = scorePopTimer - 1
    End If

    ' hi score — lower-right, always visible during play
    hdHiStr = "HI: " + LTRIM$(STR$(highScore))
    FONT_PrintAlpha fontPalette(8), backBuffer, hdHiStr, scrW - LEN(hdHiStr) * FONT_CHAR_W - 2, scrH - FONT_CHAR_H, 255

    ' parsec-to-destination gauge — asteroid field only
    If levelType = LEVEL_ASTEROID Then
        Dim hdPPct As Single, hdPPSC As Integer, hdPFill As Integer
        Dim hdPClr As Long, hdPStr As String, hdPX As Integer
        hdPPct = 1.0 - (tt - astFieldStart) / astFieldDuration
        If hdPPct < 0.0 Then hdPPct = 0.0
        If hdPPct > 1.0 Then hdPPct = 1.0
        hdPPSC = INT(hdPPct * ASTFIELD_PARSECS)
        hdPStr = LTRIM$(STR$(hdPPSC)) + " PSC"
        hdPX = scrW\2 - 56
        FONT_PrintAlpha fontPalette(11), backBuffer, hdPStr, hdPX, scrH - 16, 255
        hdPFill = INT(hdPPct * 50)
        LINE (scrW\2 + 4, scrH - 14)-(scrW\2 + 56, scrH - 5), _RGB(15, 20, 30), BF
        If hdPFill > 0 Then
            hdPClr = _RGB(60, 160, 255)
            LINE (scrW\2 + 5, scrH - 13)-(scrW\2 + 5 + hdPFill, scrH - 6), hdPClr, BF
            LINE (scrW\2 + 5, scrH - 13)-(scrW\2 + 5 + hdPFill, scrH - 12), _RGB(140, 210, 255), BF
        End If
        LINE (scrW\2 + 4, scrH - 14)-(scrW\2 + 56, scrH - 5), _RGB(70, 90, 100), B
    End If

    ' invincibility lead-in
    If invTimer > 0 And gameState = GS_PLAYING Then
        hdThrobBright = INT(160 + 95 * SIN(tt * 10))
        FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "GET READY", scrH * 2 \ 3, scrW, hdThrobBright
    End If

End Sub
