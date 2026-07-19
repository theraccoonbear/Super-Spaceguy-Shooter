' game.bas — new-game initialization
'
' GAME_NewGame : call when the player presses SPACE on the title screen.
'                Resets all game state and transitions to the intro crawl.
'
' All persistent state is DIM SHARED in sss.bas.
' Local variable prefix: gr*

Sub GAME_ResetState
    Dim grI As Integer

    score = 0 : IF settingNerf THEN stageScore = BOSS_TRIGGER_NERF ELSE stageScore = BOSS_TRIGGER
    lives = 100 : shipLives = 3 : laserEnergy = 100.0 : gameOver = 0 : diffTime = 0 : diffScale = 0 : levelNum = 0
    fuelLevel = 100.0 : fuelStranded = 0
    tt = 0 : spawnTimer = 0 : fireTimer = 0 : waveCount = 0 : wavePrev = -1
    scorePopTimer = 0 : fxShakeTimer = 0 : fxFlashTimer = 0 : spawnFlashTimer = 0
    thrusterScale = 0.30 : invTimer = 120 : deathTimer = 0 : escConfirm = 0 : titleEscConfirm = 0
    camF.lagY = 0 : camF.lagZ = 0 : camF.fwdY = 0 : camF.fwdZ = 0
    camF.orbitMode = 0
    playerVY = 0 : playerVZ = 0
    boss.active = 0 : boss.hp = 0 : boss.warnTimer = 0 : boss.moveTimer = 0 : boss.state = 0
    planetTimer = 0 : planetSeq = 0 : planetTick = 0 : planetR = 3.0 : planetDefDone = 0 : planetCurrent = PLANET_COUNT : planetNameIdx = PLANET_COUNT
    cinematicCamX = 0 : shipCinVX = 0 : cinematicFade = 0
    player.px = 0 : player.py = 0 : player.pz = 0
    player.rx = 0 : player.ry = 0 : player.rz = 0
    For grI = 1 To MAX_ENEMIES   : enemies(grI).active = 0   : enemyFireTimer(grI) = 0 : Next grI
    For grI = 1 To MAX_BULLETS   : bullets(grI).active = 0   : Next grI
    For grI = 1 To MAX_ASTEROIDS : asteroids(grI).active = 0 : Next grI
    For grI = 1 To MAX_POWERUPS  : powerups(grI).active = 0  : Next grI
    For grI = 1 To MAX_EBULLETS  : ebullets(grI).active = 0  : Next grI
    FX_Clear
    fxVCRActive = 0
    StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
End Sub

Sub GAME_NewGame
    GAME_ResetState
    TELEM_SessionStart
    If seqIdx >= 0 And seqIdx < seqCount And seqKind(seqIdx) = SEQ_TITLE Then
        SEQ_Advance
    Else
        SEQ_Load _EMBEDDED$("SEQTXT")
        SEQ_Advance
    End If
End Sub

Sub GAME_InitMeshes
    Dim gmiMdl As String
    Dim gmiI   As Integer
    gmiMdl = _EMBEDDED$("MODELS")
    E3D_LoadMesh gmiMdl, "PLAYER",       meshLib(MESH_PLAYER),       boxLib(MESH_PLAYER)
    E3D_LoadMesh gmiMdl, "ENEMY",        meshLib(MESH_ENEMY),        boxLib(MESH_ENEMY)
    E3D_LoadMesh gmiMdl, "ASTEROID",     meshLib(MESH_ASTEROID),     boxLib(MESH_ASTEROID)
    E3D_LoadMesh gmiMdl, "BULLET",       meshLib(MESH_BULLET),       boxLib(MESH_BULLET)
    E3D_LoadMesh gmiMdl, "POWERUP",      meshLib(MESH_POWERUP),      boxLib(MESH_POWERUP)
    E3D_LoadMesh gmiMdl, "ENEMY_ARROW",  meshLib(MESH_ENEMY_ARROW),  boxLib(MESH_ENEMY_ARROW)
    E3D_LoadMesh gmiMdl, "ENEMY_HLINE",  meshLib(MESH_ENEMY_HLINE),  boxLib(MESH_ENEMY_HLINE)
    E3D_LoadMesh gmiMdl, "ENEMY_VCOL",   meshLib(MESH_ENEMY_VCOL),   boxLib(MESH_ENEMY_VCOL)
    E3D_LoadMesh gmiMdl, "ENEMY_PINCER", meshLib(MESH_ENEMY_PINCER), boxLib(MESH_ENEMY_PINCER)
    E3D_LoadMesh gmiMdl, "ENEMY_VWEDGE", meshLib(MESH_ENEMY_VWEDGE), boxLib(MESH_ENEMY_VWEDGE)
    E3D_LoadMesh gmiMdl, "THRUSTER",     meshLib(MESH_THRUSTER),     boxLib(MESH_THRUSTER)
    E3D_LoadMesh gmiMdl, "EBULLET",      meshLib(MESH_EBULLET),      boxLib(MESH_EBULLET)
    E3D_LoadMesh gmiMdl, "BOSS",         meshLib(MESH_BOSS),         boxLib(MESH_BOSS)
    For gmiI = 1 To MESH_COUNT
        E3D_BakeMeshNormals meshLib(gmiI)
    Next gmiI
    For gmiI = MESH_ENEMY To MESH_ENEMY_VWEDGE
        boxLib(gmiI).hx = boxLib(gmiI).hx * HIT_SCALE
        boxLib(gmiI).hy = boxLib(gmiI).hy * HIT_SCALE
        boxLib(gmiI).hz = boxLib(gmiI).hz * HIT_SCALE
    Next gmiI
    lightDir.x = -0.4 : lightDir.y = 0.7 : lightDir.z = -0.5
    player.active  = -1
    player.meshIdx = MESH_PLAYER
    player.scl     = 1.0
    fTypeToMesh(0) = MESH_ENEMY
    fTypeToMesh(1) = MESH_ENEMY_ARROW
    fTypeToMesh(2) = MESH_ENEMY_HLINE
    fTypeToMesh(3) = MESH_ENEMY_VCOL
    fTypeToMesh(4) = MESH_ENEMY_PINCER
    fTypeToMesh(5) = MESH_ENEMY_VWEDGE
    RANDOMIZE TIMER
    StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
End Sub

Sub GAME_Usage(guErr As String)
    Dim guFH As Integer : guFH = FreeFile
    If InStr(_OS$, "WIN") Then
        Open "CON:" For Output As #guFH
    Else
        Open "/dev/stdout" For Output As #guFH
    End If
    If guErr <> "" Then
        Print #guFH, "Error: " + guErr
        Print #guFH, ""
    End If
    Print #guFH, "Super Spaceguy Shooter " + VERSION$
    Print #guFH, ""
    Print #guFH, "Usage: sss [options]"
    Print #guFH, ""
    Print #guFH, "Options:"
    Print #guFH, "  -v, --version          Print version and exit"
    Print #guFH, "  -h, --help             Show this help and exit"
    Print #guFH, "  --scene <name>         Jump to a named scene (skips normal startup)"
    Print #guFH, "  --god                  God mode: shields, health, and laser never deplete"
    Print #guFH, "  --nerf                 Nerf mode: 1 kill triggers boss (was 10), boss has 10 HP (was 30), asteroid field 10% length"
    Print #guFH, "  --debug                Enable debug overlay and stdout event logging"
    Print #guFH, "  --telem                Enable gameplay telemetry logging to sss_telemetry.csv"
    Print #guFH, ""
    Print #guFH, "Scene names:"
    SEQ_PrintScenes guFH
    Close #guFH
    System
End Sub
