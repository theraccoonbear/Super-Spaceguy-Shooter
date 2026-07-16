' player.bas — velocity-based flight physics and ship-oriented camera
'
' PLAYER_Update    : call once per frame in the game logic section (before fire/spawning)
' PLAYER_CamUpdate : call once per frame in the render section (before scene draw)
'
' Reads:  held(), gameState, fuelStranded, cinPhase, player, cam, projMat
' Writes: player, playerVY, playerVZ, isManeuver,
'         camF.lagY, camF.lagZ, camF.fwdY, camF.fwdZ, cam, viewMat, vpMat
'
' Local variable prefix: plr* (physics)  plc* (camera)

Const PLAYER_ACCEL     = 0.14    ' velocity lerp rate (controls both accel and drag)
Const PLAYER_MAX_VEL   = 0.12    ' max lateral velocity per frame
Const ATTITUDE_LERP    = 0.09    ' ship tilt/roll settle rate
Const BULLET_SPEED     = 0.35    ' player bullet X velocity
Const FIRE_COOLDOWN    = 0.18    ' seconds between shots
Const LASER_COST       = 5.0     ' laser energy drained per shot (%)
Const AIM_ASSIST       = 0.30    ' fraction of aim error corrected toward nearest enemy in cone
Const LASER_REGEN      = 0.30    ' laser energy per frame (~18%/sec at 60fps)
Const FUEL_DRAIN       = 0.0185  ' base drain per frame (~90 sec at 60fps)
Const FUEL_DRAIN_BOOST = 0.006   ' extra drain per frame when thrusting
Const BULLET_RANGE     = 110     ' cull player bullet beyond player.px + this
Const BULLET_TRAIL_LEN = 2.0     ' world-unit length of bolt body (rear to tip along nose)
Const DMG_COLLISION    = 17      ' shield damage from collision
Const DMG_ASTEROID     = 100     ' asteroid collision: always fatal
Const DMG_LASER        = 5       ' shield damage from enemy bullet
Const SHAKE_COLLISION  = 7       ' shakeTimer on collision
Const FLASH_COLLISION  = 4       ' flashTimer on collision
Const SHAKE_LASER      = 2       ' shakeTimer on laser hit
Const FLASH_LASER      = 1       ' flashTimer on laser hit

Sub PLAYER_Update(plrUp As Integer, plrDown As Integer, plrLeft As Integer, plrRight As Integer)
    Dim plrTgtVY As Single, plrTgtVZ As Single
    Dim plrTgtRx As Single, plrTgtRy As Single, plrTgtRz As Single
    Dim plrNorm As Single

    ' input -> target velocity
    plrTgtVY = 0 : plrTgtVZ = 0
    If gameState = GS_PLAYING And Not fuelStranded Then
        If plrUp    Then plrTgtVY =  PLAYER_MAX_VEL
        If plrDown  Then plrTgtVY = -PLAYER_MAX_VEL
        If plrLeft  Then plrTgtVZ = -PLAYER_MAX_VEL
        If plrRight Then plrTgtVZ =  PLAYER_MAX_VEL
    End If

    ' lerp velocity toward target (PLAYER_ACCEL drives both accel and drag)
    playerVY = playerVY + (plrTgtVY - playerVY) * PLAYER_ACCEL
    playerVZ = playerVZ + (plrTgtVZ - playerVZ) * PLAYER_ACCEL

    ' update position from velocity
    If gameState = GS_PLAYING And Not fuelStranded Then
        player.py = player.py + playerVY
        player.pz = player.pz + playerVZ
    End If

    ' isManeuver: ship is meaningfully in motion (drives fuel drain + thruster FX)
    If Abs(playerVY) > 0.005 Or Abs(playerVZ) > 0.005 Then
        isManeuver = -1
    Else
        isManeuver = 0
    End If

    ' attitude: derived from velocity direction, not raw key state
    plrTgtRx = 0 : plrTgtRy = 0 : plrTgtRz = 0
    If gameState = GS_CINEMATIC Then
        plrTgtRx =  32 * cinPhase
        plrTgtRy = -12 * cinPhase
    ElseIf Not fuelStranded Then
        plrNorm = PLAYER_MAX_VEL
        plrTgtRx =  (playerVZ / plrNorm) * 22   ' bank into left/right
        plrTgtRy = -(playerVZ / plrNorm) * 7    ' yaw nudge
        plrTgtRz =  (playerVY / plrNorm) * 15   ' pitch up/down
    End If
    player.rx = player.rx + (plrTgtRx - player.rx) * ATTITUDE_LERP
    player.ry = player.ry + (plrTgtRy - player.ry) * ATTITUDE_LERP
    player.rz = player.rz + (plrTgtRz - player.rz) * ATTITUDE_LERP
End Sub

Sub PLAYER_Fire
    Dim plfI As Integer, plfAaI As Integer
    Dim plfRx As Single, plfRy As Single, plfRz As Single
    Dim plfNx As Single, plfNy As Single, plfNz As Single
    Dim plfAaDX As Single, plfAaDY As Single, plfAaDZ As Single, plfAaDist As Single
    Dim plfAaBest As Single, plfAaNY As Single, plfAaNZ As Single

    If held(E3D_KEY_SPACE) = 0 Or invTimer > 0 Or gameState <> GS_PLAYING Then Exit Sub
    If fireTimer > 0 Or laserEnergy < LASER_COST Then Exit Sub

    For plfI = 1 To MAX_BULLETS
        If bullets(plfI).active = 0 Then
            bullets(plfI).active  = -1
            bullets(plfI).meshIdx = MESH_BULLET
            plfRx = player.rx * _PI / 180.0
            plfRy = player.ry * _PI / 180.0
            plfRz = player.rz * _PI / 180.0
            plfNx = COS(plfRz) * COS(plfRy)
            plfNy = COS(plfRx)*SIN(plfRz)*COS(plfRy) + SIN(plfRx)*SIN(plfRy)
            plfNz = SIN(plfRx)*SIN(plfRz)*COS(plfRy) - COS(plfRx)*SIN(plfRy)
            bullets(plfI).px = player.px + plfNx * (BULLET_TRAIL_LEN + 1.0)
            bullets(plfI).py = player.py + plfNy * (BULLET_TRAIL_LEN + 1.0)
            bullets(plfI).pz = player.pz + plfNz * (BULLET_TRAIL_LEN + 1.0)
            ' aim assist: nudge toward nearest enemy within ~20 deg forward cone
            plfAaBest = 1e9
            For plfAaI = 1 To MAX_ENEMIES
                If enemies(plfAaI).active Then
                    plfAaDX = enemies(plfAaI).px - player.px
                    plfAaDY = enemies(plfAaI).py - player.py
                    plfAaDZ = enemies(plfAaI).pz - player.pz
                    plfAaDist = SQR(plfAaDX*plfAaDX + plfAaDY*plfAaDY + plfAaDZ*plfAaDZ)
                    If plfAaDist > 0.1 And plfAaDX > 0 Then
                        If (plfAaDX / plfAaDist) > 0.94 Then  ' cos(20°) ≈ 0.94
                            If plfAaDist < plfAaBest Then
                                plfAaBest = plfAaDist
                                plfAaNY = plfAaDY / plfAaDist
                                plfAaNZ = plfAaDZ / plfAaDist
                            End If
                        End If
                    End If
                End If
            Next plfAaI
            If plfAaBest < 1e9 Then
                plfNy = plfNy + (plfAaNY - plfNy) * AIM_ASSIST
                plfNz = plfNz + (plfAaNZ - plfNz) * AIM_ASSIST
            End If
            bullets(plfI).vx   = plfNx * BULLET_SPEED
            bullets(plfI).vy   = plfNy * BULLET_SPEED
            bullets(plfI).vz   = plfNz * BULLET_SPEED
            bullets(plfI).life = BULLET_RANGE / BULLET_SPEED
            bullets(plfI).scl  = 1.0
            fireTimer   = FIRE_COOLDOWN
            laserEnergy = laserEnergy - LASER_COST
            SND_Shoot
            telemShotsFired = telemShotsFired + 1
            Exit For
        End If
    Next plfI
End Sub

Sub PLAYER_CamUpdate
    Dim plcFwdTgtY As Single, plcFwdTgtZ As Single

    ' positional lag: camera position tracks player Y/Z with smoothing
    If gameState <> GS_CINEMATIC Then
        camF.lagY = camF.lagY + (player.py - camF.lagY) * CAM_LAG_RATE
        camF.lagZ = camF.lagZ + (player.pz - camF.lagZ) * CAM_LAG_RATE
    End If

    ' orientation lag: smooth forward direction from velocity (slower than position lag)
    plcFwdTgtY = playerVY / PLAYER_MAX_VEL
    plcFwdTgtZ = playerVZ / PLAYER_MAX_VEL
    camF.fwdY = camF.fwdY + (plcFwdTgtY - camF.fwdY) * CAM_FWD_RATE
    camF.fwdZ = camF.fwdZ + (plcFwdTgtZ - camF.fwdZ) * CAM_FWD_RATE

    ' cam.POS and cam.target are set in sss.bas after this call — nested UDT field
    ' writes from included-file Subs don't update the global, same as UDT array gotcha.
End Sub

Sub PLAYER_TakeDamage(ptDmg As Integer, ptShake As Integer, ptFlash As Integer)
    lives = lives - ptDmg
    fxShakeTimer = ptShake : fxFlashTimer = ptFlash
    SND_Hit
    TELEM_PlayerDamaged
    If lives <= 0 Then
        shipLives = shipLives - 1
        If shipLives <= 0 Then
            gameOver = -1
            SND_Death
            TELEM_PlayerDeath
            TELEM_SessionEnd
        Else
            lives = 100 : invTimer = 240 : fuelLevel = 100.0 : fuelStranded = 0
        End If
    End If
End Sub
