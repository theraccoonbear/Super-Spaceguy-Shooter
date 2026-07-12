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
    lives = 100 : shipLives = 3 : laserEnergy = 100.0 : gameOver = 0 : diffTime = 0 : diffScale = 0
    fuelLevel = 100.0 : fuelStranded = 0
    tt = 0 : spawnTimer = 0 : fireTimer = 0 : waveCount = 0 : wavePrev = -1
    scorePopTimer = 0 : fxShakeTimer = 0 : fxFlashTimer = 0 : spawnFlashTimer = 0
    thrusterScale = 0.30 : invTimer = 120 : escConfirm = 0 : titleEscConfirm = 0
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
    Print #guFH, "  --nerf                 Nerf mode: 1 kill triggers boss (was 10), boss has 10 HP (was 30)"
    Print #guFH, "  --debug                Enable debug overlay and stdout event logging"
    Print #guFH, "  --telem                Enable gameplay telemetry logging to sss_telemetry.csv"
    Print #guFH, ""
    Print #guFH, "Scene names:"
    Print #guFH, "  title                  Title screen (default)"
    Print #guFH, "  crawl0                 Intro crawl"
    Print #guFH, "  crawl1..6              Chapter crawls"
    Print #guFH, "  playing1..6            Gameplay stages"
    Print #guFH, "  boss1..6               Stage with boss pre-triggered on frame 1"
    Close #guFH
    System
End Sub
