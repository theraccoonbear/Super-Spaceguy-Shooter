Sub GS_PLAYING_Update ()
    Dim gspSkipPhysics As Integer

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
        IF held(E3D_KEY_ESCAPE) AND escWas = 0 THEN escConfirm = 1 - escConfirm
        escWas = held(E3D_KEY_ESCAPE)
        IF escConfirm THEN
            IF _KEYDOWN(89) OR _KEYDOWN(121) THEN
                escConfirm = 0 : gameState = GS_TITLE
                SEQ_RewindToTitle
                MUS_SetCue "title"
            END IF
            IF _KEYDOWN(78) OR _KEYDOWN(110) THEN escConfirm = 0
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
            camOrbitMode = 1 - camOrbitMode
            IF camOrbitMode THEN
                camOrbitR     = SQR((cam.POS.x-player.px)*(cam.POS.x-player.px) + (cam.POS.y-player.py)*(cam.POS.y-player.py) + (cam.POS.z-player.pz)*(cam.POS.z-player.pz))
                camOrbitTheta = _ATAN2(cam.POS.z - player.pz, cam.POS.x - player.px)
                camOrbitPhi   = _ATAN2(cam.POS.y - player.py, SQR((cam.POS.x-player.px)*(cam.POS.x-player.px) + (cam.POS.z-player.pz)*(cam.POS.z-player.pz)))
            ELSE
                camAngleLocked = -1
                SETTINGS_Save
            END IF
        END IF
        tabWas = held(E3D_KEY_TAB)
        IF camOrbitMode THEN
            IF held(E3D_KEY_R) AND rWas = 0 THEN
                camOrbitTheta = _PI(1.0)
                camOrbitPhi   = _ATAN2(CAM_OFFSET_Y, CAM_OFFSET_X)
                camOrbitR     = SQR(CAM_OFFSET_X * CAM_OFFSET_X + CAM_OFFSET_Y * CAM_OFFSET_Y)
                camOrbitMode  = 0 : camAngleLocked = 0
                SETTINGS_Save
            END IF
            rWas = held(E3D_KEY_R)
            IF camOrbitMode THEN
                IF held(E3D_KEY_UP)   THEN camOrbitPhi = camOrbitPhi + 0.008
                IF held(E3D_KEY_DOWN) THEN camOrbitPhi = camOrbitPhi - 0.008
                IF camOrbitPhi >  1.5 THEN camOrbitPhi =  1.5
                IF camOrbitPhi < -1.5 THEN camOrbitPhi = -1.5
                IF (camUpWas AND held(E3D_KEY_UP) = 0) OR (camDnWas AND held(E3D_KEY_DOWN) = 0) THEN
                    camAngleLocked = -1
                    IF debugMode THEN DBG_Print "[cam] phi=" + LTRIM$(STR$(camOrbitPhi)) + "  r=" + LTRIM$(STR$(camOrbitR))
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

        FOR i = 1 TO MAX_ASTEROIDS
            IF asteroids(i).active THEN
                asteroids(i).px  = asteroids(i).px  + asteroids(i).vx
                asteroids(i).rx  = asteroids(i).rx  + asteroids(i).drx
                asteroids(i).ry  = asteroids(i).ry  + asteroids(i).dry
                asteroids(i).rz  = asteroids(i).rz  + asteroids(i).drz
                IF asteroids(i).px < player.px + 25 THEN
                    asteroids(i).py = asteroids(i).py + (player.py - asteroids(i).py) * 0.004
                    asteroids(i).pz = asteroids(i).pz + (player.pz - asteroids(i).pz) * 0.004
                END IF
                IF asteroids(i).px < -5 THEN asteroids(i).active = 0

                FOR j = 1 TO MAX_BULLETS
                    IF bullets(j).active THEN
                        E3D_AABBOverlap asteroids(i).px, asteroids(i).py, asteroids(i).pz, boxLib(MESH_ASTEROID), _
                        bullets(j).px, bullets(j).py, bullets(j).pz, boxLib(MESH_BULLET), hit
                        IF hit THEN
                            asteroids(i).active = 0
                            bullets(j).active = 0
                            score = score + SCORE_ASTEROID
                            SND_Boom
                            scorePopTimer = 30 : scorePopY = scrH * 0.45 : scorePopVal = SCORE_ASTEROID
                            FX_SpawnBurst asteroids(i).px, asteroids(i).py, asteroids(i).pz, 8, 0.18, 15, 7, _RGB(120 + INT(RND * 40), 100 + INT(RND * 30), 75 + INT(RND * 20))
                        END IF
                    END IF
                NEXT j

                E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
                asteroids(i).px, asteroids(i).py, asteroids(i).pz, boxLib(MESH_ASTEROID), hit
                IF hit AND invTimer = 0 THEN
                    asteroids(i).active = 0
                    SND_Boom
                    FX_SpawnBurst asteroids(i).px, asteroids(i).py, asteroids(i).pz, 8, 0.18, 15, 7, _RGB(120 + INT(RND * 40), 100 + INT(RND * 30), 75 + INT(RND * 20))
                    PLAYER_TakeDamage DMG_COLLISION, SHAKE_COLLISION, FLASH_COLLISION
                END IF
            END IF
        NEXT i

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

        IF gameOver THEN
            IF score > highScore THEN highScore = score : SETTINGS_Save
            gameOverDelay = 90
            gameState = GS_GAMEOVER
            StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
            MUS_SetCue "gameover"
            SPK_Say sSpkGameOver$
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
    cam.POS.y = camLagY + CAM_OFFSET_Y - camFwdY * CAM_FWD_SCALE
    cam.POS.z = camLagZ               - camFwdZ * CAM_FWD_SCALE
    IF gameState = GS_CINEMATIC THEN
        cam.target.x = cinematicCamX + CAM_OFFSET_X + CAM_LEAD_X
        cam.target.y = camLagY
        cam.target.z = camLagZ
    ELSE
        cam.target.x = player.px + CAM_LEAD_X
        cam.target.y = player.py + camFwdY * CAM_LEAD_X
        cam.target.z = player.pz + camFwdZ * CAM_LEAD_X
    END IF
    IF (camOrbitMode OR camAngleLocked) AND gameState <> GS_CINEMATIC THEN
        cam.POS.x = player.px + camOrbitR * COS(camOrbitPhi) * COS(camOrbitTheta)
        cam.POS.y = player.py + camOrbitR * SIN(camOrbitPhi)
        cam.POS.z = player.pz + camOrbitR * COS(camOrbitPhi) * SIN(camOrbitTheta)
    END IF
    E3D_MatLookAt cam, viewMat
    E3D_MatMul projMat, viewMat, vpMat

    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 5, 185), BF
    E3D_StarfieldDraw vpMat, scrW, scrH
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

    FOR j = 1 TO MAX_ENEMIES
        IF enemies(j).active THEN
            IF enemies(j).px > cam.POS.x THEN
                pPos.x = enemies(j).px : pPos.y = enemies(j).py : pPos.z = enemies(j).pz
                pRot.x = enemies(j).rx : pRot.y = enemies(j).ry : pRot.z = enemies(j).rz
                E3D_BuildObjectMat pPos, pRot, enemies(j).scl, objMat
                eDist = enemies(j).px - player.px
                IF eDist > DIM_FAR THEN
                    eDimF = DIM_AMBIENT
                ELSEIF eDist > DIM_NEAR THEN
                    eDimF = DIM_AMBIENT + (eDist - DIM_NEAR) * ((1.0 - DIM_AMBIENT) / (DIM_FAR - DIM_NEAR))
                ELSE
                    eDimF = 1.0
                END IF
                eLitDir.x = lightDir.x * eDimF
                eLitDir.y = lightDir.y * eDimF
                eLitDir.z = lightDir.z * eDimF
                E3D_SceneAddMeshLit meshLib(enemies(j).meshIdx), objMat, cam.POS, tt, eLitDir
            END IF
        END IF
    NEXT j

    FOR j = 1 TO MAX_ASTEROIDS
        IF asteroids(j).active THEN
            IF asteroids(j).px > cam.POS.x THEN
                pPos.x = asteroids(j).px : pPos.y = asteroids(j).py : pPos.z = asteroids(j).pz
                pRot.x = asteroids(j).rx : pRot.y = asteroids(j).ry : pRot.z = asteroids(j).rz
                E3D_BuildObjectMat pPos, pRot, asteroids(j).scl, objMat
                E3D_SceneAddMeshLit meshLib(MESH_ASTEROID), objMat, cam.POS, tt, lightDir
            END IF
        END IF
    NEXT j

    IF boss.active THEN
        pPos.x = boss.px : pPos.y = boss.py : pPos.z = boss.pz
        pRot.x = boss.rx : pRot.y = boss.ry : pRot.z = boss.rz
        E3D_BuildObjectMat pPos, pRot, boss.scl, objMat
        eDist = boss.px - player.px
        IF eDist > DIM_FAR THEN
            eDimF = 0.35
        ELSEIF eDist > DIM_NEAR THEN
            eDimF = 0.35 + (eDist - DIM_NEAR) * (0.65 / (DIM_FAR - DIM_NEAR))
        ELSE
            eDimF = 1.0
        END IF
        eLitDir.x = lightDir.x * eDimF
        eLitDir.y = lightDir.y * eDimF
        eLitDir.z = lightDir.z * eDimF
        E3D_SceneAddMeshLit meshLib(MESH_BOSS), objMat, cam.POS, tt, eLitDir
    END IF

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

    _DEST backBuffer
    FOR j = 1 TO MAX_BULLETS
        IF bullets(j).active THEN
            pjX  = bullets(j).px * vpMat.m(0,0) + bullets(j).py * vpMat.m(0,1) + bullets(j).pz * vpMat.m(0,2) + vpMat.m(0,3)
            pjY  = bullets(j).px * vpMat.m(1,0) + bullets(j).py * vpMat.m(1,1) + bullets(j).pz * vpMat.m(1,2) + vpMat.m(1,3)
            pjW  = bullets(j).px * vpMat.m(3,0) + bullets(j).py * vpMat.m(3,1) + bullets(j).pz * vpMat.m(3,2) + vpMat.m(3,3)
            pjBX = bullets(j).px - bullets(j).vx * (BULLET_TRAIL_LEN / BULLET_SPEED)
            pjBY = bullets(j).py - bullets(j).vy * (BULLET_TRAIL_LEN / BULLET_SPEED)
            pjBZ = bullets(j).pz - bullets(j).vz * (BULLET_TRAIL_LEN / BULLET_SPEED)
            pjX2 = pjBX * vpMat.m(0,0) + pjBY * vpMat.m(0,1) + pjBZ * vpMat.m(0,2) + vpMat.m(0,3)
            pjY2 = pjBX * vpMat.m(1,0) + pjBY * vpMat.m(1,1) + pjBZ * vpMat.m(1,2) + vpMat.m(1,3)
            pjW2 = pjBX * vpMat.m(3,0) + pjBY * vpMat.m(3,1) + pjBZ * vpMat.m(3,2) + vpMat.m(3,3)
            IF pjW > 0.0001 AND pjW2 > 0.0001 THEN
                pjX  = (pjX  / pjW  + 1.0) * scrW * 0.5
                pjY  = (1.0 - pjY  / pjW)  * scrH * 0.5
                pjX2 = (pjX2 / pjW2 + 1.0) * scrW * 0.5
                pjY2 = (1.0 - pjY2 / pjW2) * scrH * 0.5
                IF pjX >= 0 AND pjX < scrW AND pjY >= 0 AND pjY < scrH THEN
                    pjFade = bullets(j).life / (BULLET_RANGE / BULLET_SPEED)
                    IF pjFade > 1.0 THEN pjFade = 1.0
                    LINE (INT(pjX2), INT(pjY2))-(INT(pjX), INT(pjY)), _RGB(INT(210*pjFade), INT(215*pjFade), INT(60*pjFade))
                    PSET (INT(pjX), INT(pjY)), _RGB(INT(240*pjFade), INT(245*pjFade), INT(140*pjFade))
                END IF
            END IF
        END IF
    NEXT j

    FOR j = 1 TO MAX_EBULLETS
        IF ebullets(j).active THEN
            pjX = ebullets(j).px * vpMat.m(0,0) + ebullets(j).py * vpMat.m(0,1) + ebullets(j).pz * vpMat.m(0,2) + vpMat.m(0,3)
            pjY = ebullets(j).px * vpMat.m(1,0) + ebullets(j).py * vpMat.m(1,1) + ebullets(j).pz * vpMat.m(1,2) + vpMat.m(1,3)
            pjW = ebullets(j).px * vpMat.m(3,0) + ebullets(j).py * vpMat.m(3,1) + ebullets(j).pz * vpMat.m(3,2) + vpMat.m(3,3)
            IF pjW > 0.0001 THEN
                pjX = (pjX / pjW + 1.0) * scrW * 0.5
                pjY = (1.0 - pjY / pjW) * scrH * 0.5
                IF pjX >= 4 AND pjX < scrW - 4 AND pjY >= 3 AND pjY < scrH - 3 THEN
                    SELECT CASE ebullets(j).meshIdx
                    CASE MESH_BOSS         : ebClr = _RGB(255, 200,   0)
                    CASE MESH_ENEMY        : ebClr = _RGB(255,  80,  60)
                    CASE MESH_ENEMY_ARROW  : ebClr = _RGB(220,  35,  65)
                    CASE MESH_ENEMY_HLINE  : ebClr = _RGB( 80, 140, 255)
                    CASE MESH_ENEMY_VCOL   : ebClr = _RGB(180,  65, 255)
                    CASE MESH_ENEMY_PINCER : ebClr = _RGB(255,  45, 190)
                    CASE ELSE              : ebClr = _RGB(185,  80, 255)
                    END SELECT
                    LINE (pjX - 4, pjY)-(pjX + 4, pjY), ebClr
                    LINE (pjX, pjY - 2)-(pjX, pjY + 2), ebClr
                    PSET (pjX, pjY), _RGB(255, 255, 255)
                END IF
            END IF
        END IF
    NEXT j

    _DEST backBuffer
    IF spawnFlashTimer > 0 THEN
        pjX = spawnFlashPX * vpMat.m(0,0) + spawnFlashPY * vpMat.m(0,1) + spawnFlashPZ * vpMat.m(0,2) + vpMat.m(0,3)
        pjY = spawnFlashPX * vpMat.m(1,0) + spawnFlashPY * vpMat.m(1,1) + spawnFlashPZ * vpMat.m(1,2) + vpMat.m(1,3)
        pjW = spawnFlashPX * vpMat.m(3,0) + spawnFlashPY * vpMat.m(3,1) + spawnFlashPZ * vpMat.m(3,2) + vpMat.m(3,3)
        IF pjW > 0.0001 THEN
            pjX = (pjX / pjW + 1.0) * scrW * 0.5
            pjY = (1.0 - pjY / pjW) * scrH * 0.5
            IF pjX >= 3 AND pjX < scrW - 3 AND pjY >= 3 AND pjY < scrH - 3 THEN
                partR = spawnFlashTimer * 26
                LINE (pjX - 4, pjY)-(pjX + 4, pjY), _RGB(partR, partR, partR)
                LINE (pjX, pjY - 4)-(pjX, pjY + 4), _RGB(partR, partR, partR)
            END IF
        END IF
        spawnFlashTimer = spawnFlashTimer - 1
    END IF

    FX_Draw vpMat, scrW, scrH
    HUD_Draw

    IF camOrbitMode THEN
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
