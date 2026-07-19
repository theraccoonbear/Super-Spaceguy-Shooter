Const DIM_FAR        = 55      ' distance dimming far threshold
Const DIM_NEAR       = 28      ' distance dimming near threshold
Const DIM_AMBIENT    = 0.22    ' minimum brightness at far distance
Const SCORE_ASTEROID = 50      ' points per asteroid kill
Const SCORE_POWERUP  = 500     ' points for powerup collect
Const SHIELD_RESTORE = 30      ' shield added by powerup

Sub GS_PLAYING_Update ()
    Dim gspSkipPhysics As Integer
    Dim hit As Integer
    Dim i As Integer, j As Integer
    Dim gspAstNear As Integer, gspAstI As Integer

    ' ESC during planet/cinematic: skip straight to title (no confirm needed)
    IF gameState = GS_PLANET OR gameState = GS_CINEMATIC THEN
        IF held(E3D_KEY_ESCAPE) AND escWas = 0 THEN
            SEQ_RewindToTitle
            gameState = GS_TITLE
            planetTimer = 0 : cinematicFade = 0 : shipCinVX = 0 : cinematicCamX = 0
            MUS_SetCue "title"
            escWas = held(E3D_KEY_ESCAPE)
            EXIT SUB
        END IF
        escWas = held(E3D_KEY_ESCAPE)
    END IF

    ' ESC confirm dialog (playing only)
    IF gameState = GS_PLAYING THEN
        IF held(E3D_KEY_ESCAPE) AND escWas = 0 THEN
            escConfirm = 1 - escConfirm
            IF escConfirm THEN
                escYWas = _KEYDOWN(89) OR _KEYDOWN(121)
                escNWas = _KEYDOWN(78) OR _KEYDOWN(110)
            END IF
        END IF
        escWas = held(E3D_KEY_ESCAPE)
        IF escConfirm THEN
            IF (_KEYDOWN(89) OR _KEYDOWN(121)) AND escYWas = 0 THEN
                escConfirm = 0 : gameState = GS_TITLE
                SEQ_RewindToTitle
                MUS_SetCue "title"
            END IF
            escYWas = _KEYDOWN(89) OR _KEYDOWN(121)
            IF (_KEYDOWN(78) OR _KEYDOWN(110)) AND escNWas = 0 THEN escConfirm = 0
            escNWas = _KEYDOWN(78) OR _KEYDOWN(110)
            _DEST backBuffer
            UI_DrawPanel scrW\2 - 84, scrH\2 - 30, scrW\2 + 84, scrH\2 + 42, "ABORT MISSION"
            FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "Y   CONFIRM RETREAT", scrH\2 - 2, scrW, 255
            FONT_PrintCenteredAlpha fontPalette(8),  backBuffer, "ESC CANCEL",          scrH\2 + 18, scrW, 255
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
                camF.orbitPhi   = _ATAN2(CAM_OFFSET_Y, CAM_OFFSET_X)
                camF.orbitR     = SQR(CAM_OFFSET_X * CAM_OFFSET_X + CAM_OFFSET_Y * CAM_OFFSET_Y)
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
        IF fireTimer > 0 THEN fireTimer = fireTimer - 0.025
        IF invTimer > 0 THEN invTimer = invTimer - 1
        IF laserEnergy < 100.0 THEN
            laserEnergy = laserEnergy + LASER_REGEN
            IF laserEnergy > 100.0 THEN laserEnergy = 100.0
        END IF
        STAGE_Update

        PLAYER_Update held(E3D_KEY_UP) OR held(E3D_KEY_W), held(E3D_KEY_DOWN) OR held(E3D_KEY_S), held(E3D_KEY_LEFT) OR held(E3D_KEY_A), held(E3D_KEY_RIGHT) OR held(E3D_KEY_D)

        IF gameState = GS_PLAYING THEN
            fuelLevel = fuelLevel - FUEL_DRAIN
            IF isManeuver THEN fuelLevel = fuelLevel - FUEL_DRAIN_BOOST
            IF fuelLevel <= 0 THEN
                fuelLevel = 0
                IF fuelStranded = 0 THEN TELEM_FuelExhausted
                fuelStranded = -1
            END IF
        END IF
        IF godMode THEN
            lives = 100 : laserEnergy = 100.0 : fuelLevel = 100.0 : fuelStranded = 0
        END IF

        IF isManeuver THEN
            thrusterScale = thrusterScale + (0.88 - thrusterScale) * 0.14
        ELSEIF fuelStranded THEN
            thrusterScale = thrusterScale * 0.92
        ELSE
            thrusterScale = thrusterScale + (0.28 - thrusterScale) * 0.06
        END IF

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
                powerups(i).ry  = powerups(i).ry  + powerups(i).dry
                powerups(i).rz  = powerups(i).rz  + powerups(i).drz
                IF powerups(i).px < -5 THEN powerups(i).active = 0

                E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
                powerups(i).px, powerups(i).py, powerups(i).pz, boxLib(MESH_POWERUP), hit
                IF hit THEN
                    powerups(i).active = 0
                    lives = lives + SHIELD_RESTORE
                    IF lives > 100 THEN lives = 100
                    score = score + SCORE_POWERUP
                    SND_Pup
                    TELEM_PowerupCollected
                END IF
            END IF
        NEXT i

        BOSS_Update
        EBULLET_Update
        FX_Update
        E3D_StarfieldUpdate cam.POS.x, cam.POS.y, cam.POS.z
        IF bltActive THEN BELT_Update scrW, scrH

        IF gameOver THEN
            IF score > highScore THEN highScore = score : SETTINGS_Save
            gameOverDelay = 90
            gameState = GS_GAMEOVER
            StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
            MUS_SetCue "gameover"
            SPK_Say sSpkGameOver
            gameOver = 0
        END IF
    END IF

    ' --- render (always runs, even in orbit mode) ---
    PLAYER_CamUpdate
    IF gameState = GS_CINEMATIC THEN
        cam.POS.x = cinematicCamX
    ELSE
        cam.POS.x = player.px - CAM_OFFSET_X
    END IF
    cam.POS.y = camF.lagY + CAM_OFFSET_Y - camF.fwdY * CAM_FWD_SCALE
    cam.POS.z = camF.lagZ               - camF.fwdZ * CAM_FWD_SCALE
    IF gameState = GS_CINEMATIC THEN
        cam.target.x = cinematicCamX + CAM_OFFSET_X + CAM_LEAD_X
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
    IF invTimer = 0 OR (invTimer MOD 6) < 3 THEN
        E3D_SceneAddMeshLit meshLib(MESH_PLAYER), objMat, cam.POS, tt, lightDir
    END IF

    thrusterLight.x = -(0.28 + thrusterScale * 0.85)
    thrusterLight.y = 0.0 : thrusterLight.z = 0.0
    pPos.x = player.px - 0.92 : pPos.y = player.py : pPos.z = player.pz
    E3D_BuildObjectMat pPos, pRot, thrusterScale, objMat
    IF invTimer = 0 OR (invTimer MOD 6) < 3 THEN
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
                E3D_SceneAddMeshLit meshLib(MESH_POWERUP), objMat, cam.POS, tt, lightDir
            END IF
        END IF
    NEXT j

    E3D_SceneFlush vpMat, scrW, scrH

    COMBAT_OverlayDraw

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
