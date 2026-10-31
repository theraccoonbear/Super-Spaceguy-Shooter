Const DIM_FAR        = 55      ' distance dimming far threshold
Const DIM_NEAR       = 28      ' distance dimming near threshold
Const DIM_AMBIENT    = 0.22    ' minimum brightness at far distance
Const SCORE_ASTEROID = 50      ' points per asteroid kill

Sub GS_PLAYING_Update ()
    Dim gspSkipPhysics As Integer
    Dim i As Integer, j As Integer
    Dim gspAstNear As Integer, gspAstI As Integer
    Dim spDmg As Integer

    ' ESC confirm dialog: in play and during the planet arrival / cinematic, which it
    ' pauses the same way (nothing below runs while it's open). Input: src/state/pauselogic.bas
    IF gameState = GS_PLAYING OR gameState = GS_PLANET OR gameState = GS_CINEMATIC THEN
        SELECT CASE PAUSE_Input%
            CASE PAUSE_QUIT
                SEQ_QuitRun
                planetTimer = 0 : cinematicFade = 0 : shipCinVX = 0 : cinematicCamX = 0
            CASE PAUSE_CONTROLS
                CONTROLS_Prep gameState : gameState = GS_CONTROLS
            CASE PAUSE_REMAP
                RMP_Open gameState
        END SELECT
        IF pauseShown THEN
            ' prompt column, sized to the widest prompt for the device last used
            Dim gspPx As Integer, gspKW As Integer, gspKi As Integer, gspRy As Integer, gspDev As Integer, gspPal As Integer
            Dim gspK(0 TO 3) As String, gspL(0 TO 3) As String, gspPals(0 TO 3) As Integer
            gspK(0) = UI_Tok$("Y", 0)
            gspK(1) = UI_Tok$("C", E3D_ACT_ROLL)
            gspK(2) = UI_Tok$("K", E3D_ACT_NOVA)
            gspK(3) = UI_Tok$("ESC", E3D_ACT_BACK)
            gspL(0) = "CONFIRM RETREAT" : gspL(1) = "CONTROLS" : gspL(2) = "REMAP CONTROLS" : gspL(3) = "CANCEL"
            gspPals(0) = 14 : gspPals(1) = 9 : gspPals(2) = 9 : gspPals(3) = 8
            gspDev = INP_LastDevice%
            gspKW = 0
            FOR gspKi = 0 TO 3
                IF UI_PromptsW%(gspK(gspKi), gspDev) > gspKW THEN gspKW = UI_PromptsW%(gspK(gspKi), gspDev)
            NEXT gspKi
            gspKW = gspKW + 2 * FONT_CHAR_W
            gspPx = (scrW - gspKW - 15 * FONT_CHAR_W) \ 2
            _DEST backBuffer
            UI_DrawPanel scrW\2 - 104, scrH\2 - 30, scrW\2 + 104, scrH\2 + 70, "ABORT MISSION"
            FOR gspKi = 0 TO 3
                gspRy = scrH\2 - 4 + gspKi * 18
                gspPal = gspPals(gspKi)
                IF gspKi = pauseSel THEN
                    UI_MenuHighlight scrW\2 - 101, gspRy - 2, scrW\2 + 101, gspRy + 14
                    gspPal = 15
                END IF
                UI_PromptsAt gspK(gspKi), gspDev, gspPx, gspRy, gspPal, 255, 0
                FONT_PrintAlpha fontPalette(gspPal), backBuffer, gspL(gspKi), gspPx + gspKW, gspRy, 255
            NEXT gspKi
            _DEST 0
            _PUTIMAGE , backBuffer, 0
            EXIT SUB
        END IF
    END IF

    ' Camera orbit mode (playing only); sets gspSkipPhysics if active this frame
    gspSkipPhysics = 0
    IF gameState = GS_PLAYING THEN
        IF held(E3D_KEY_TAB) AND tabWas = 0 THEN
            camF.orbitMode = 1 - camF.orbitMode
            IF camF.orbitMode THEN
                camF.orbitR     = SQR((cam.POS.x-player.px)*(cam.POS.x-player.px) + (cam.POS.y-player.py)*(cam.POS.y-player.py) + (cam.POS.z-player.pz)*(cam.POS.z-player.pz))
                camF.orbitTheta = _PI(1.0)
                camF.orbitPhi   = _ATAN2(cam.POS.y - player.py, SQR((cam.POS.x-player.px)*(cam.POS.x-player.px) + (cam.POS.z-player.pz)*(cam.POS.z-player.pz)))
            ELSE
                camF.angleLocked = -1
                SETTINGS_Save
            END IF
        END IF
        tabWas = held(E3D_KEY_TAB)
        IF camF.orbitMode THEN
            IF held(E3D_KEY_R) AND rWas = 0 THEN
                camF.orbitTheta = _PI(1.0)
                camF.orbitPhi   = CAM_DEFAULT_PHI
                camF.orbitR     = CAM_DEFAULT_R
                camF.orbitMode  = 0 : camF.angleLocked = 0
                SETTINGS_Save
            END IF
            rWas = held(E3D_KEY_R)
            IF camF.orbitMode THEN
                IF held(E3D_KEY_UP)   THEN camF.orbitPhi = camF.orbitPhi + 0.008
                IF held(E3D_KEY_DOWN) THEN camF.orbitPhi = camF.orbitPhi - 0.008
                IF camF.orbitPhi >  1.5 THEN camF.orbitPhi =  1.5
                IF camF.orbitPhi < -1.5 THEN camF.orbitPhi = -1.5
                IF (camUpWas AND held(E3D_KEY_UP) = 0) OR (camDnWas AND held(E3D_KEY_DOWN) = 0) THEN
                    camF.angleLocked = -1
                    IF debugMode THEN DBG_Print "[cam] phi=" + LTRIM$(STR$(camF.orbitPhi)) + "  r=" + LTRIM$(STR$(camF.orbitR))
                    SETTINGS_Save
                END IF
                camUpWas = held(E3D_KEY_UP) : camDnWas = held(E3D_KEY_DOWN)
                gspSkipPhysics = -1
            END IF
        END IF
    END IF

    ' --- physics (skipped when camera orbit is active) ---
    IF gspSkipPhysics = 0 THEN
        tt = tt + 0.025
        spawnTimer = spawnTimer + 0.025
        IF fireTimer > 0 THEN fireTimer = fireTimer - FIRE_TICK
        IF invTimer > 0 THEN invTimer = invTimer - 1
        IF planetTransitionTimer > 0 THEN
            planetTransitionTimer = planetTransitionTimer - 1
            IF planetTransitionTimer = 0 THEN SEQ_Advance
        END IF
        IF laserEnergy < laserMax THEN
            laserEnergy = laserEnergy + laserRegen
            IF laserEnergy > laserMax THEN laserEnergy = laserMax
        END IF
        STAGE_Update

        IF deathTimer > 0 THEN
            deathTimer = deathTimer - 1
            IF deathTimer = 0 THEN
                IF gameOver THEN
                    IF score > highScore THEN highScore = score : SETTINGS_Save
                    crawlNextState = GS_GAMEOVER
                    CRAWL_Prep SEQ_CRAWL_DEATH, scrH
                    gameState = GS_CRAWL
                    gameOver = 0
                ELSE
                    invTimer = 240
                END IF
            END IF
            FX_Update
            E3D_StarfieldUpdate cam.POS.x, cam.POS.y, cam.POS.z
        ELSE
            PLAYER_Update held(E3D_KEY_UP) OR held(E3D_KEY_W), held(E3D_KEY_DOWN) OR held(E3D_KEY_S), held(E3D_KEY_LEFT) OR held(E3D_KEY_A), held(E3D_KEY_RIGHT) OR held(E3D_KEY_D)

            IF gameState = GS_PLAYING THEN
                fuelLevel = fuelLevel - FUEL_DRAIN
                telemLegFuel = telemLegFuel + FUEL_DRAIN : telemLegFrames = telemLegFrames + 1
                IF isManeuver THEN fuelLevel = fuelLevel - FUEL_DRAIN_BOOST : telemLegFuel = telemLegFuel + FUEL_DRAIN_BOOST
                IF fuelLevel <= 0 THEN
                    fuelLevel = 0
                    IF fuelStranded = 0 THEN TELEM_FuelExhausted
                    fuelStranded = -1
                END IF
            END IF
            IF godMode THEN
                lives = shieldMax : laserEnergy = laserMax : fuelLevel = fuelMax : fuelStranded = 0
            END IF

            IF isManeuver THEN
                thrusterScale = thrusterScale + (0.88 - thrusterScale) * 0.14
            ELSEIF fuelStranded THEN
                thrusterScale = thrusterScale * 0.92
            ELSE
                thrusterScale = thrusterScale + (0.28 - thrusterScale) * 0.06
            END IF

            ABL_Update
            PLAYER_Fire

            IF (INT(tt * 40)) MOD 2 = 0 THEN
                FX_SpawnTrail player.px - 1.1, player.py, player.pz, 2, 0.005, 24, 10, _RGB(80, 140, 255), -0.035, playerVY * 0.3 - 0.008, playerVZ * 0.3
            END IF

            IF levelType = LEVEL_ASTEROID THEN
                IF isManeuver THEN
                    astIdleTimer = 0
                ELSEIF astIdleTimer < 9999 THEN
                    astIdleTimer = astIdleTimer + 1
                END IF
                IF astIdleTimer > 40 THEN
                    gspAstNear = 0
                    FOR gspAstI = 1 TO MAX_ASTEROIDS
                        IF asteroids(gspAstI).active THEN
                            IF asteroids(gspAstI).px > player.px AND asteroids(gspAstI).px < player.px + 35 THEN
                                IF Abs(asteroids(gspAstI).py - player.py) < 5 AND Abs(asteroids(gspAstI).pz - player.pz) < 5 THEN
                                    gspAstNear = -1
                                END IF
                            END IF
                        END IF
                    NEXT gspAstI
                    IF gspAstNear = 0 THEN astForceTarget = -1
                END IF
            END IF
            WAVE_Spawn
            IF cliPup <> "" THEN GAME_DevPups

            FOR i = 1 TO MAX_BULLETS
                IF bullets(i).active THEN
                    bullets(i).px = bullets(i).px + bullets(i).vx
                    bullets(i).py = bullets(i).py + bullets(i).vy
                    bullets(i).pz = bullets(i).pz + bullets(i).vz
                    bullets(i).life = bullets(i).life - 1
                    IF bullets(i).life <= 0 THEN bullets(i).active = 0
                END IF
            NEXT i

            ENEMY_Update

            ASTEROIDS_Update

            FOR i = 1 TO MAX_POWERUPS
                IF powerups(i).active THEN
                    powerups(i).px  = powerups(i).px  + powerups(i).vx
                    powerups(i).rx  = powerups(i).rx  + powerups(i).drx
                    powerups(i).ry  = powerups(i).ry  + powerups(i).dry
                    powerups(i).rz  = powerups(i).rz  + powerups(i).drz
                    IF powerups(i).px < -5 THEN
                        powerups(i).active = 0
                        TELEM_PowerupMissed PUP_KindName$(WAVE_PupKind%(powerups(i).meshIdx))
                    ELSE
                        IF tractorR > 0 THEN ABL_Tractor i
                        IF PUP_Grabbed%(powerups(i).px - player.px, powerups(i).py - player.py, powerups(i).pz - player.pz) THEN GS_PLAYING_PupGrab i
                    END IF
                END IF
            NEXT i

            BOSS_Update
            EBULLET_Update
            spDmg = SPORE_Update%(player.px, player.py, player.pz)
            IF spDmg > 0 AND invTimer = 0 THEN telemDeathCause = "spore" : PLAYER_TakeDamage spDmg, SHAKE_LASER, FLASH_LASER
            spDmg = CUT_Update%(player.px, player.py, player.pz, playerVY, playerVZ)
            IF spDmg > 0 AND invTimer = 0 THEN telemDeathCause = "cut" : PLAYER_TakeDamage spDmg, SHAKE_LASER, FLASH_LASER
            DEV_Update
            DEV_Pull player.py, player.pz, boss.py, boss.pz
            player.py = player.py + devPullY : player.pz = player.pz + devPullZ
            FX_Update
            E3D_StarfieldUpdate cam.POS.x, cam.POS.y, cam.POS.z
            IF bltActive THEN BELT_Update scrW, scrH

            ' gameOver with deathTimer>0 is handled at deathTimer expiry above
            IF gameOver AND deathTimer = 0 THEN
                IF score > highScore THEN highScore = score : SETTINGS_Save
                gameOverDelay = 90
                gameState = GS_GAMEOVER
                StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
                MUS_SetCue "gameover"
                SPK_Say sSpkGameOver
                gameOver = 0
            END IF
        END IF
    END IF

    ' --- render (always runs, even in orbit mode) ---
    PLAYER_CamUpdate
    IF gameState = GS_CINEMATIC THEN
        cam.POS.x = cinematicCamX
    ELSE
        cam.POS.x = player.px - CAM_CHASE_X
    END IF
    cam.POS.y = camF.lagY + CAM_CHASE_Y - camF.fwdY * CAM_FWD_SCALE
    cam.POS.z = camF.lagZ               - camF.fwdZ * CAM_FWD_SCALE
    IF gameState = GS_CINEMATIC THEN
        cam.target.x = cinematicCamX + CAM_CHASE_X + CAM_LEAD_X
        cam.target.y = camF.lagY
        cam.target.z = camF.lagZ
    ELSE
        cam.target.x = player.px + CAM_LEAD_X
        cam.target.y = player.py + camF.fwdY * CAM_LEAD_X
        cam.target.z = player.pz + camF.fwdZ * CAM_LEAD_X
    END IF
    IF (camF.orbitMode OR camF.angleLocked) AND gameState <> GS_CINEMATIC THEN
        cam.POS.x = player.px + camF.orbitR * COS(camF.orbitPhi) * COS(camF.orbitTheta)
        cam.POS.y = player.py + camF.orbitR * SIN(camF.orbitPhi)
        cam.POS.z = player.pz + camF.orbitR * COS(camF.orbitPhi) * SIN(camF.orbitTheta)
    END IF
    E3D_MatLookAt cam, viewMat
    E3D_MatMul projMat, viewMat, vpMat

    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 5, 185), BF
    E3D_StarfieldDraw vpMat, scrW, scrH
    IF bltActive THEN
        Dim gspBltVpX As Single, gspBltVpY As Single, gspBltVpW As Single, gspBltFwd As Single
        gspBltFwd = cam.POS.x + 500.0
        gspBltVpX = gspBltFwd * vpMat.m(0,0) + cam.POS.y * vpMat.m(0,1) + cam.POS.z * vpMat.m(0,2) + vpMat.m(0,3)
        gspBltVpY = gspBltFwd * vpMat.m(1,0) + cam.POS.y * vpMat.m(1,1) + cam.POS.z * vpMat.m(1,2) + vpMat.m(1,3)
        gspBltVpW = gspBltFwd * vpMat.m(3,0) + cam.POS.y * vpMat.m(3,1) + cam.POS.z * vpMat.m(3,2) + vpMat.m(3,3)
        IF gspBltVpW > 0.00001 THEN
            bltCtrX = (gspBltVpX / gspBltVpW + 1.0) * (scrW * 0.5)
            bltCtrY = (1.0 - gspBltVpY / gspBltVpW) * (scrH * 0.5)
        END IF
        BELT_Draw scrW, scrH
    END IF
    STAGE_DrawPlanetBackground
    STAGE_DrawPlanet

    E3D_SceneBegin

    pPos.x = player.px : pPos.y = player.py : pPos.z = player.pz
    pRot.x = player.rx : pRot.y = player.ry : pRot.z = player.rz
    E3D_BuildObjectMat pPos, pRot, player.scl, objMat
    IF deathTimer = 0 AND (invTimer = 0 OR (invTimer MOD 6) < 3) THEN
        E3D_SceneAddMeshLit meshLib(MESH_PLAYER), objMat, cam.POS, tt, lightDir
    END IF

    thrusterLight.x = -(0.28 + thrusterScale * 0.85)
    thrusterLight.y = 0.0 : thrusterLight.z = 0.0
    pPos.x = player.px - 0.92 : pPos.y = player.py : pPos.z = player.pz
    E3D_BuildObjectMat pPos, pRot, thrusterScale, objMat
    IF deathTimer = 0 AND (invTimer = 0 OR (invTimer MOD 6) < 3) THEN
        E3D_SceneAddMeshLit meshLib(MESH_THRUSTER), objMat, cam.POS, tt, thrusterLight
    END IF

    COMBAT_SceneDraw

    ASTEROIDS_Draw

    FOR j = 1 TO MAX_POWERUPS
        IF powerups(j).active THEN
            IF powerups(j).px > cam.POS.x THEN
                pPos.x = powerups(j).px : pPos.y = powerups(j).py : pPos.z = powerups(j).pz
                pRot.x = powerups(j).rx : pRot.y = powerups(j).ry : pRot.z = powerups(j).rz
                E3D_BuildObjectMat pPos, pRot, powerups(j).scl, objMat
                E3D_SceneAddMeshLit meshLib(powerups(j).meshIdx), objMat, cam.POS, tt, pupLight
            END IF
        END IF
    NEXT j

    GS_PLAYING_PupHalos
    E3D_SceneFlush vpMat, scrW, scrH

    COMBAT_OverlayDraw
    GS_PLAYING_PupMarks
    ABL_Draw

    FX_Draw vpMat, scrW, scrH
    HUD_Draw

    IF camF.orbitMode THEN
        _DEST backBuffer
        FONT_PrintAlpha fontPalette(11), backBuffer, "CAMERA MODE", 4, 4 + FONT_CHAR_H + 2, 160
        FONT_PrintAlpha fontPalette(8),  backBuffer, "TAB:CONFIRM  UP/DN:TILT  R:REVERT", 4, 4 + FONT_CHAR_H * 2 + 3, 120
    END IF

    FX_Flash scrW, scrH

    IF cinematicFade > 0 THEN
        _DEST backBuffer
        LINE (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 0, cinematicFade), BF
    END IF

    FX_Shake backBuffer

    IF gameState = GS_PLAYING THEN
        SND_GameFill isManeuver
    ELSE
        MUS_Fill 0
    END IF
End Sub

' Power-up i is caught: give it (src/gameplay/powerups.bas), then the pop, gauge flash, sound and log.
Sub GS_PLAYING_PupGrab (gpgI As Integer)
    Dim gpgKind As Integer, gpgAmt As Single, gpgN As String
    gpgKind = WAVE_PupKind%(powerups(gpgI).meshIdx)
    powerups(gpgI).active = 0
    gpgAmt = PUP_Apply!(gpgKind, levelNum)
    gpgN = LTRIM$(STR$(INT(gpgAmt + 0.5)))
    pupPopTimer = 50 : pupPopY = scrH * 0.55
    IF pupOverflowPts > 0 THEN
        pupPopTxt = "FULL +" + LTRIM$(STR$(pupOverflowPts)) : pupPopPal = 14
    ELSE
        SELECT CASE gpgKind
            CASE PUP_SHIELD : pupPopTxt = "+" + gpgN + " SH" : pupPopPal = 10 : hudFlashKind = 1 : hudFlashTimer = 48
            CASE PUP_FUEL   : pupPopTxt = "+" + gpgN + " FU" : pupPopPal = 6  : hudFlashKind = 3 : hudFlashTimer = 48
            CASE ELSE       : pupPopTxt = "+" + gpgN : pupPopPal = 14
        END SELECT
    END IF
    SND_Pup
    TELEM_PowerupCollected PUP_KindName$(gpgKind), gpgAmt
End Sub

' The kind's colour (gold points, green shield, orange fuel) at alpha gpcA.
Function GS_PLAYING_PupClr& (gpcKind As Integer, gpcA As Integer)
    Dim gpcAl As Integer
    gpcAl = gpcA
    IF gpcAl < 0 THEN gpcAl = 0
    IF gpcAl > 255 THEN gpcAl = 255
    SELECT CASE gpcKind
        CASE PUP_SHIELD : GS_PLAYING_PupClr& = _RGBA32(80, 255, 140, gpcAl)
        CASE PUP_FUEL   : GS_PLAYING_PupClr& = _RGBA32(255, 140, 30, gpcAl)
        CASE ELSE       : GS_PLAYING_PupClr& = _RGBA32(255, 215, 40, gpcAl)
    END SELECT
End Function

' A pulsing glow behind each power-up, drawn before the scene so the model sits on top of it.
Sub GS_PLAYING_PupHalos
    Dim gphI As Integer, gphK As Integer, gphKind As Integer, gphOk As Integer, gphOk2 As Integer
    Dim gphSX As Single, gphSY As Single, gphEX As Single, gphEY As Single, gphR As Single, gphP As Single, gphFade As Single
    _DEST backBuffer
    FOR gphI = 1 TO MAX_POWERUPS
        IF powerups(gphI).active THEN
            IF powerups(gphI).px > cam.POS.x + 1 THEN
                COMBAT_Project powerups(gphI).px, powerups(gphI).py, powerups(gphI).pz, gphSX, gphSY, gphOk
                COMBAT_Project powerups(gphI).px, powerups(gphI).py + 1.1, powerups(gphI).pz, gphEX, gphEY, gphOk2
                IF gphOk AND gphOk2 THEN
                    gphKind = WAVE_PupKind%(powerups(gphI).meshIdx)
                    gphP = 0.5 + 0.5 * SIN(tt * 7 + gphI)
                    gphR = ABS(gphSY - gphEY) * (0.9 + 0.2 * gphP)
                    gphFade = (powerups(gphI).px - player.px) / 10
                    IF gphFade > 1 THEN gphFade = 1
                    IF gphR < 3 THEN gphR = 3
                    IF gphR < 150 THEN
                        FOR gphK = 0 TO 2
                            CIRCLE (gphSX, gphSY), gphR - gphK * gphR * 0.18, GS_PLAYING_PupClr&(gphKind, INT((30 + gphK * 20 + gphP * 30) * gphFade))
                        NEXT gphK
                    END IF
                END IF
            END IF
        END IF
    NEXT gphI
End Sub

' Over the scene: a crossing reticle where each power-up will pass the ship (the last
' pup_marker_frames frames, closing in to the grab radius), and an edge arrow for one off-screen.
Sub GS_PLAYING_PupMarks
    Dim gpmI As Integer, gpmKind As Integer, gpmOk As Integer, gpmOk2 As Integer, gpmA As Integer
    Dim gpmDX As Single, gpmFr As Single, gpmF As Single, gpmR As Single
    Dim gpmSX As Single, gpmSY As Single, gpmEX As Single, gpmEY As Single, gpmPx As Single
    Dim gpmUX As Single, gpmUY As Single, gpmLen As Single, gpmT As Single, gpmT2 As Single
    IF gameState <> GS_PLAYING THEN EXIT SUB
    _DEST backBuffer
    FOR gpmI = 1 TO MAX_POWERUPS
        IF powerups(gpmI).active THEN
            gpmKind = WAVE_PupKind%(powerups(gpmI).meshIdx)
            gpmDX = powerups(gpmI).px - player.px
            gpmFr = gpmDX / pupSpeed
            IF gpmDX > -pupGrabDX AND gpmFr <= pupMarkerFrames AND pupMarkerFrames > 0 THEN
                gpmF = gpmFr / pupMarkerFrames
                IF gpmF < 0 THEN gpmF = 0
                gpmR = pupGrabR * (1 + 0.3 * gpmF)
                COMBAT_Project player.px, powerups(gpmI).py, powerups(gpmI).pz, gpmSX, gpmSY, gpmOk
                COMBAT_Project player.px, powerups(gpmI).py + gpmR, powerups(gpmI).pz, gpmEX, gpmEY, gpmOk2
                IF gpmOk AND gpmOk2 THEN
                    gpmPx = ABS(gpmSY - gpmEY)
                    IF gpmPx >= 2 AND gpmPx < 300 THEN
                        gpmA = 60 + INT(160 * (1 - gpmF))
                        CIRCLE (gpmSX, gpmSY), gpmPx, GS_PLAYING_PupClr&(gpmKind, gpmA)
                        CIRCLE (gpmSX, gpmSY), gpmPx + 1, GS_PLAYING_PupClr&(gpmKind, gpmA \ 3)
                        LINE (gpmSX - gpmPx - 3, gpmSY)-(gpmSX - gpmPx + 2, gpmSY), GS_PLAYING_PupClr&(gpmKind, gpmA)
                        LINE (gpmSX + gpmPx - 2, gpmSY)-(gpmSX + gpmPx + 3, gpmSY), GS_PLAYING_PupClr&(gpmKind, gpmA)
                        LINE (gpmSX, gpmSY - gpmPx - 3)-(gpmSX, gpmSY - gpmPx + 2), GS_PLAYING_PupClr&(gpmKind, gpmA)
                        LINE (gpmSX, gpmSY + gpmPx - 2)-(gpmSX, gpmSY + gpmPx + 3), GS_PLAYING_PupClr&(gpmKind, gpmA)
                    END IF
                END IF
            END IF
            IF gpmDX > -pupGrabDX THEN
                COMBAT_Project powerups(gpmI).px, powerups(gpmI).py, powerups(gpmI).pz, gpmSX, gpmSY, gpmOk
                IF gpmOk THEN
                    IF gpmSX < 0 OR gpmSX >= scrW OR gpmSY < 0 OR gpmSY >= scrH THEN
                        gpmUX = gpmSX - scrW / 2 : gpmUY = gpmSY - scrH / 2
                        gpmLen = SQR(gpmUX * gpmUX + gpmUY * gpmUY)
                        IF gpmLen > 0.001 THEN
                            gpmUX = gpmUX / gpmLen : gpmUY = gpmUY / gpmLen
                            gpmT = 1E+09 : gpmT2 = 1E+09
                            IF ABS(gpmUX) > 0.001 THEN gpmT = (scrW / 2 - 12) / ABS(gpmUX)
                            IF ABS(gpmUY) > 0.001 THEN gpmT2 = (scrH / 2 - 12) / ABS(gpmUY)
                            IF gpmT2 < gpmT THEN gpmT = gpmT2
                            gpmEX = scrW / 2 + gpmUX * gpmT : gpmEY = scrH / 2 + gpmUY * gpmT
                            gpmA = 150 + INT(100 * (0.5 + 0.5 * SIN(tt * 10)))
                            COMBAT_Chevron gpmEX - gpmUX * 8, gpmEY - gpmUY * 8, gpmUX, gpmUY, 0, GS_PLAYING_PupClr&(gpmKind, gpmA)
                            COMBAT_Chevron gpmEX - gpmUX * 8, gpmEY - gpmUY * 8, gpmUX, gpmUY, -4, GS_PLAYING_PupClr&(gpmKind, gpmA \ 2)
                        END IF
                    END IF
                END IF
            END IF
        END IF
    NEXT gpmI
End Sub
