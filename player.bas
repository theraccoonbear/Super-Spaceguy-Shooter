' player.bas — velocity-based flight physics and ship-oriented camera
'
' PLAYER_Update    : call once per frame in the game logic section (before fire/spawning)
' PLAYER_CamUpdate : call once per frame in the render section (before scene draw)
'
' Reads:  held(), gameState, fuelStranded, cinPhase, player, cam, projMat
' Writes: player, playerVY, playerVZ, isManeuver,
'         camLagY, camLagZ, camFwdY, camFwdZ, cam, viewMat, vpMat
'
' Local variable prefix: plr* (physics)  plc* (camera)

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

Sub PLAYER_CamUpdate
    Dim plcFwdTgtY As Single, plcFwdTgtZ As Single

    ' positional lag: camera position tracks player Y/Z with smoothing
    If gameState <> GS_CINEMATIC Then
        camLagY = camLagY + (player.py - camLagY) * CAM_LAG_RATE
        camLagZ = camLagZ + (player.pz - camLagZ) * CAM_LAG_RATE
    End If

    ' orientation lag: smooth forward direction from velocity (slower than position lag)
    plcFwdTgtY = playerVY / PLAYER_MAX_VEL
    plcFwdTgtZ = playerVZ / PLAYER_MAX_VEL
    camFwdY = camFwdY + (plcFwdTgtY - camFwdY) * CAM_FWD_RATE
    camFwdZ = camFwdZ + (plcFwdTgtZ - camFwdZ) * CAM_FWD_RATE

    ' cam.POS and cam.target are set in sss.bas after this call — nested UDT field
    ' writes from included-file Subs don't update the global, same as UDT array gotcha.
End Sub
