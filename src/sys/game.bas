' game.bas — new-game initialization
'
' GAME_NewGame : call when the player presses SPACE on the title screen.
'                Resets all game state and transitions to the intro crawl.
'
' All persistent state is DIM SHARED in sss.bas.
' Local variable prefix: gr*

Sub GAME_ResetState
    Dim grI As Integer

    DLV_Begin
    GAME_LoadTuning
    UPG_Reset
    CR_ResetRun
    credits = cliCredits
    ablHintTimer = 0
    score = 0 : stageKills = 0 : IF settingNerf THEN stageKillTarget = BOSS_TRIGGER_NERF ELSE stageKillTarget = BOSS_TRIGGER
    lives = shieldMax : shipLives = 3 : laserEnergy = laserMax : gameOver = 0 : diffTime = 0 : diffScale = 0 : levelNum = 0
    If cliShips > 0 Then shipLives = cliShips
    If cliShields > 0 Then lives = cliShields
    If lives > shieldMax Then lives = shieldMax
    fuelLevel = fuelMax : fuelStranded = 0 : runStranded = 0
    If cliFuel > 0 And cliFuel < fuelMax Then fuelLevel = cliFuel
    telemLegFuel = 0 : telemLegFrames = 0
    tt = 0 : spawnTimer = 0 : fireTimer = 0 : waveCount = 0 : wavePrev = -1 : stageClearT = 0 : bossShieldT = 0
    scorePopTimer = 0 : fxShakeTimer = 0 : fxFlashTimer = 0 : spawnFlashTimer = 0
    pupPopTimer = 0 : hudFlashTimer = 0
    thrusterScale = 0.30 : invTimer = 120 : deathTimer = 0 : escConfirm = 0 : titleEscConfirm = 0 : launchOpen = 0
    lbrdPollDone = 0
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
    SPORE_Clear
    CUT_Clear
    DEV_Clear
    ATK_Clear
    FX_Clear
    fxVCRActive = 0
    StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
End Sub

' Every config loader, at the difficulty level in use (DLV_Use / DLV_Begin first).
Sub GAME_LoadTuning
    If UPG_Load% = 0 Then GAME_Usage upgLoadErr
    If SUP_Load% = 0 Then GAME_Usage supLoadErr
    If PUP_Load% = 0 Then GAME_Usage pupLoadErr
    If WVT_Load% = 0 Then GAME_Usage wvtLoadErr
    If BHP_Load% = 0 Then GAME_Usage bhpLoadErr
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
    E3D_LoadMesh gmiMdl, "PUP_SHIELD",   meshLib(MESH_PUP_SHIELD),   boxLib(MESH_PUP_SHIELD)
    E3D_LoadMesh gmiMdl, "ENEMY_ARROW",  meshLib(MESH_ENEMY_ARROW),  boxLib(MESH_ENEMY_ARROW)
    E3D_LoadMesh gmiMdl, "ENEMY_HLINE",  meshLib(MESH_ENEMY_HLINE),  boxLib(MESH_ENEMY_HLINE)
    E3D_LoadMesh gmiMdl, "ENEMY_VCOL",   meshLib(MESH_ENEMY_VCOL),   boxLib(MESH_ENEMY_VCOL)
    E3D_LoadMesh gmiMdl, "ENEMY_PINCER", meshLib(MESH_ENEMY_PINCER), boxLib(MESH_ENEMY_PINCER)
    E3D_LoadMesh gmiMdl, "ENEMY_VWEDGE", meshLib(MESH_ENEMY_VWEDGE), boxLib(MESH_ENEMY_VWEDGE)
    E3D_LoadMesh gmiMdl, "THRUSTER",     meshLib(MESH_THRUSTER),     boxLib(MESH_THRUSTER)
    E3D_LoadMesh gmiMdl, "EBULLET",      meshLib(MESH_EBULLET),      boxLib(MESH_EBULLET)
    E3D_LoadMesh gmiMdl, "BOSS",         meshLib(MESH_BOSS),         boxLib(MESH_BOSS)
    E3D_LoadMesh gmiMdl, "PUP_FUEL",     meshLib(MESH_PUP_FUEL),     boxLib(MESH_PUP_FUEL)
    E3D_LoadMesh gmiMdl, "PUP_POINTS",   meshLib(MESH_PUP_POINTS),   boxLib(MESH_PUP_POINTS)
    For gmiI = 1 To MESH_COUNT
        E3D_BakeMeshNormals meshLib(gmiI)
    Next gmiI
    For gmiI = MESH_ENEMY To MESH_ENEMY_VWEDGE
        boxLib(gmiI).hx = boxLib(gmiI).hx * HIT_SCALE
        boxLib(gmiI).hy = boxLib(gmiI).hy * HIT_SCALE
        boxLib(gmiI).hz = boxLib(gmiI).hz * HIT_SCALE
    Next gmiI
    lightDir.x = -0.4 : lightDir.y = 0.7 : lightDir.z = -0.5
    pupLight.x = -0.8 : pupLight.y = 0.55 : pupLight.z = -0.2
    player.active  = -1
    player.meshIdx = MESH_PLAYER
    player.scl     = 1.0
    fTypeToMesh(0) = MESH_ENEMY
    fTypeToMesh(1) = MESH_ENEMY_ARROW
    fTypeToMesh(2) = MESH_ENEMY_HLINE
    fTypeToMesh(3) = MESH_ENEMY_VCOL
    fTypeToMesh(4) = MESH_ENEMY_PINCER
    fTypeToMesh(5) = MESH_ENEMY_VWEDGE
    StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
End Sub

Sub GAME_Usage(guErr As String)
    Dim guFH As Integer : guFH = FreeFile
    If InStr(_OS$, "WIN") Then
        _Console On
        _Dest _Console
    Else
        Open "/dev/stdout" For Append As #guFH
    End If
    If guErr <> "" Then
        CLI_Emit guFH, "Error: " + guErr
        CLI_Emit guFH, ""
    End If
    CLI_Emit guFH, "Super Spaceguy Shooter " + VERSION$
    CLI_Emit guFH, ""
    CLI_Emit guFH, "Usage: sss [options]"
    CLI_Emit guFH, ""
    CLI_Emit guFH, "Options:"
    CLI_Emit guFH, "  -v, --version          Print version and exit"
    CLI_Emit guFH, "  -h, --help             Show this help and exit"
    ' --debug still works in a release build, for bug reports, but isn't advertised (#275)
    $IF RELEASEBUILD = 1 THEN
    CLI_Emit guFH, "  --no-telem             Disable gameplay telemetry for this session"
    $ELSE
    CLI_Emit guFH, "  --scene <name>         Jump to a named scene (skips normal startup)"
    CLI_Emit guFH, "  --crawls               Crawl browser: list, play and time every named crawl"
    CLI_Emit guFH, "  --god                  God mode: shields, health, and laser never deplete"
    CLI_Emit guFH, "  --nerf                 Nerf mode: 1 kill triggers boss (was 10), boss has 10 HP (was 30), asteroid field 10% length"
    CLI_Emit guFH, "  --difficulty <level>   Play every run at this level (" + DLV_List$ + "), whatever Settings says"
    CLI_Emit guFH, "  --debug                Enable debug overlay and stdout event logging"
    CLI_Emit guFH, "  --no-telem             Disable gameplay telemetry for this session"
    CLI_Emit guFH, "  --input-script <file>  Play from a script instead of the keyboard (see src/sys/inputscript.bas)"
    CLI_Emit guFH, "  --script-override      Let flags here differ from the input script's #! header (this line wins)"
    CLI_Emit guFH, "  --leaderboard-file <file>  Show this saved top_scores JSON on the leaderboard (no network)"
    CLI_Emit guFH, "  --frames N             Quit after N frames (60 per second)"
    CLI_Emit guFH, "  --realtime             Keep 60 frames per second in --input-script runs (for recordings)"
    CLI_Emit guFH, "  --seed N               Fixed random seed, so a scripted run repeats exactly"
    CLI_Emit guFH, "  --credits N            Start every run with N credits (whole number, 0 or more; for trying the upgrade dock)"
    CLI_Emit guFH, "  --ships N              Start every run with N ships (testing)"
    CLI_Emit guFH, "  --shields N            Start every run with N shield points (testing)"
    CLI_Emit guFH, "  --fuel N               Start every run with N fuel (testing: a stranded dock)"
    CLI_Emit guFH, "  --pup K,K,K            Place power-ups (shield, fuel, points) when play starts: in your path, beside it, off-screen"
    CLI_Emit guFH, "  --screenshot-at N,N    Save frames N,... as shot-N.png in the launch folder"
    CLI_Emit guFH, ""
    CLI_Emit guFH, "Scene names:"
    SEQ_PrintScenes guFH
    $END IF
    If InStr(_OS$, "WIN") = 0 Then Close #guFH
    If guErr <> "" Then System 1 Else System 0
End Sub

' --screenshot-at: save this frame as shot-<gameFrame>.png in the launch folder when
' it's one of the requested frames.
Sub GAME_MaybeScreenshot
    Dim gmsI As Integer
    For gmsI = 1 To cliShotN
        If cliShotAt(gmsI) = gameFrame Then
            _SaveImage _StartDir$ + "/shot-" + LTrim$(Str$(gameFrame)) + ".png", _Display
            Exit Sub
        End If
    Next gmsI
End Sub

' --pup (dev): on the first frame of play, place the listed kinds -- the first in the ship's
' path, the second just beside it, the third far off to the left (off-screen) -- then forget them.
Sub GAME_DevPups
    $IF RELEASEBUILD = 1 THEN
    $ELSE
    Dim gdpV As String, gdpPos As Integer, gdpN As Integer, gdpK As Integer
    Dim gdpX(1 To 3) As Single, gdpY(1 To 3) As Single, gdpZ(1 To 3) As Single
    If cliPup = "" Or gameState <> GS_PLAYING Then Exit Sub
    gdpX(1) = 6 : gdpY(1) = 0   : gdpZ(1) = 0
    gdpX(2) = 8 : gdpY(2) = 2.5 : gdpZ(2) = -2.5
    gdpX(3) = 20 : gdpY(3) = 2  : gdpZ(3) = 30
    gdpV = cliPup : cliPup = ""
    Do While gdpV <> "" And gdpN < 3
        gdpPos = InStr(gdpV, ",")
        If gdpPos = 0 Then gdpPos = Len(gdpV) + 1
        gdpN = gdpN + 1
        gdpK = gdpN
        powerups(gdpK).active = -1
        powerups(gdpK).meshIdx = WAVE_PupMesh%(PUP_KindOf%(Left$(gdpV, gdpPos - 1)))
        powerups(gdpK).px = player.px + gdpX(gdpN)
        powerups(gdpK).py = player.py + gdpY(gdpN)
        powerups(gdpK).pz = player.pz + gdpZ(gdpN)
        powerups(gdpK).vx = -pupSpeed
        powerups(gdpK).rx = 0 : powerups(gdpK).ry = 0 : powerups(gdpK).rz = 0
        powerups(gdpK).drx = 0 : powerups(gdpK).dry = 0 : powerups(gdpK).drz = 0
        If powerups(gdpK).meshIdx = MESH_PUP_POINTS Then powerups(gdpK).drx = 3.0 Else powerups(gdpK).dry = 2.0 : powerups(gdpK).rz = 15
        powerups(gdpK).scl = 1.0
        gdpV = Mid$(gdpV, gdpPos + 1)
    Loop
    $END IF
End Sub
