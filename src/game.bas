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
    camLagY = 0 : camLagZ = 0 : camFwdY = 0 : camFwdZ = 0
    camOrbitMode = 0
    playerVY = 0 : playerVZ = 0
    boss.active = 0 : bossHP = 0 : bossWarnTimer = 0 : bossMoveTimer = 0 : bossState = 0
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
