' stage.bas — planet arrival, cinematic fly-in, and stage-complete transition
'
' STAGE_Update   : call once per frame in main game loop (after timers, before movement)
' STAGE_DrawPlanet : call once per frame in render section (before scene draw)
'
' All persistent state is DIM SHARED in sss.bas.
' Local variable prefix: st*

Sub STAGE_Update
    Dim stI As Integer

    If planetTimer = 0 Then Exit Sub

    planetTimer = planetTimer + 1
    planetTick  = planetTick + 1
    If planetTick >= 4 Then
        planetTick = 0
        planetSeq  = (planetSeq + 1) Mod 36
    End If
    If planetR < 70.0 Then planetR = planetR + (70.0 - planetR) * 0.006

    ' planetary defenses: wipe remaining enemies at timer 30, no score
    If planetTimer = 30 And planetDefDone = 0 Then
        planetDefDone = -1
        For stI = 1 To MAX_ENEMIES
            If enemies(stI).active Then
                FX_SpawnBurst enemies(stI).px, enemies(stI).py, enemies(stI).pz, 12, 0.28, 20, 10, _RGB(160, 230, 255)
                enemies(stI).active = 0
            End If
        Next stI
    End If

    ' cinematic transition: camera freezes, ship rockets toward planet
    If planetTimer = 120 And gameState = GS_PLANET Then
        gameState    = GS_CINEMATIC
        cinematicCamX = player.px - CAM_OFFSET_X
        shipCinVX    = 0.06
    End If

    If gameState = GS_CINEMATIC Then
        ' decelerate starfield
        For stI = 1 To E3D_sfCount
            E3D_sfVX(stI) = E3D_sfVX(stI) * 0.97
        Next stI
        ' ship accelerates forward away from frozen camera
        shipCinVX = shipCinVX + 0.009
        player.px = player.px + shipCinVX
        ' pronounced rightward bank — ramp is short so sweep starts immediately
        cinPhase = (player.px - cinematicCamX - CAM_OFFSET_X) / 12.0
        If cinPhase > 1.0 Then cinPhase = 1.0
        player.py = player.py + (-3.0 - player.py) * 0.022 * cinPhase
        player.pz = player.pz + (25.0 - player.pz) * 0.035 * cinPhase
        invTimer = 60
        ' fade to black once ship is well ahead of camera
        If player.px > cinematicCamX + CAM_OFFSET_X + 40 Then
            cinematicFade = cinematicFade + 3
            If cinematicFade > 255 Then cinematicFade = 255
        End If
        ' fully faded — reset arena and advance to next crawl
        If cinematicFade >= 255 Then
            lives = 100 : invTimer = 180
            fuelLevel = 100.0 : fuelStranded = 0
            stageScore = score + BOSS_TRIGGER
            player.py = player.py * 0.25 : player.pz = player.pz * 0.25
            camLagY = 0 : camLagZ = 0
            For stI = 1 To MAX_ENEMIES   : enemies(stI).active = 0 : enemyFireTimer(stI) = 0 : Next stI
            For stI = 1 To MAX_BULLETS   : bullets(stI).active = 0  : Next stI
            For stI = 1 To MAX_ASTEROIDS : asteroids(stI).active = 0 : Next stI
            For stI = 1 To MAX_EBULLETS  : ebullets(stI).active = 0  : Next stI
            FX_Clear
            spawnTimer = 0
            bossWarnTimer = 0 : boss.active = 0 : bossHP = 0 : bossMoveTimer = 0 : bossState = 0
            planetTimer = 0 : planetSeq = 0 : planetTick = 0 : planetR = 3.0 : planetDefDone = 0
            cinematicFade = 0 : shipCinVX = 0 : cinematicCamX = 0
            _DEST backBuffer
            Line (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
            SEQ_Advance
        End If
    End If
End Sub

Sub STAGE_DrawPlanet
    Dim stSeqX As Integer, stSeqY As Integer
    Dim stRi As Integer, stAlpha As Integer, stMsgAlpha As Integer

    If planetTimer = 0 Then Exit Sub

    ' planet sprite — fades in and grows after boss defeat
    If planetImages(planetCurrent) <> 0 Then
        stSeqX = (planetSeq Mod 6) * 161
        stSeqY = (planetSeq \ 6) * 161
        stRi   = Int(planetR)
        _PUTIMAGE (scrW\2 - stRi, scrH\2 - 30 - stRi)-(scrW\2 + stRi, scrH\2 - 30 + stRi), _
            planetImages(planetCurrent), backBuffer, (stSeqX, stSeqY)-(stSeqX + 160, stSeqY + 160)
        stAlpha = 240 - planetTimer
        If stAlpha < 0 Then stAlpha = 0
        If stAlpha > 0 Then Line (scrW\2 - stRi, scrH\2 - 30 - stRi)-(scrW\2 + stRi, scrH\2 - 30 + stRi), _RGBA(0, 0, 0, stAlpha), BF
    End If

    ' "Entering [Planet] Airspace" — fades in, holds, fades out
    If planetTimer >= 80 And planetTimer <= 380 Then
        If planetTimer < 120 Then
            stMsgAlpha = Int((planetTimer - 80) / 40.0 * 255)
        ElseIf planetTimer > 320 Then
            stMsgAlpha = Int((380 - planetTimer) / 60.0 * 255)
        Else
            stMsgAlpha = 255
        End If
        If stMsgAlpha > 0 Then
            stRi = Len("Entering " + planetNames(planetNameIdx) + " Airspace") * 4
            Line (scrW\2 - stRi - 4, scrH\2 + 48)-(scrW\2 + stRi + 4, scrH\2 + 66), _RGBA(0, 0, 10, stMsgAlpha * 3 \ 4), BF
            Color _RGBA(140, 210, 255, stMsgAlpha)
            _PrintString (scrW\2 - stRi, scrH\2 + 50), "Entering " + planetNames(planetNameIdx) + " Airspace"
        End If
    End If
End Sub
