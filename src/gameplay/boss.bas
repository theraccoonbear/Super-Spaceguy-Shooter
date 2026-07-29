' boss.bas -- boss trigger, fire patterns, collision, and death sequence
'
' BOSS_Update : call once per frame in the main game loop (GS_PLAYING).
'               Calls BOSS_UpdateMovement / BOSS_PickMode from behavior.bas.
'
' All persistent state is DIM SHARED in sss.bas.
' Local variable prefix: bss*

Const BOSS_SPAWN_DIST    = 55    ' boss spawns this far ahead of player
Const BOSS_FIRE_INIT     = 2.5   ' fire interval at boss spawn (before phase lock-in)
Const BOSS_FIRE1         = 2.2   ' phase 1 fire interval
Const BOSS_FIRE2         = 1.5   ' phase 2 fire interval
Const BOSS_FIRE3         = 0.9   ' phase 3 fire interval
Const BOSS_DIM_FLOOR     = 0.35  ' minimum lighting factor for boss (keeps it visible at range)
Const BOSS_DEATH_PARTS   = 35    ' particle count on boss death
Const BOSS_ATTITUDE_LERP = 0.07  ' attitude settle rate (< player 0.09 = heavier feel)

Sub BOSS_Update
    Dim bssDX As Single, bssDY As Single, bssDZ As Single, bssDMag As Single
    Dim bssEJ As Integer, bssJ As Integer, bssP As Integer, bssPK As Integer
    Dim bssShots As Integer
    Dim bssHit As Integer
    Dim bssPrevX As Single, bssPrevY As Single, bssPrevZ As Single
    Dim bssVX As Single, bssVY As Single, bssVZ As Single
    Dim bssTgtRx As Single, bssTgtRy As Single, bssTgtRz As Single
    Dim bssOldPhase As Integer
    Dim bssMusCue As String, bssSpeechKey As String

    ' combat phase complete: hold off one second so the kill explosion plays out, then advance
    If gameState = GS_PLAYING And boss.active = 0 And boss.warnTimer = 0 And score >= stageScore And planetTransitionTimer = 0 Then
        planetTransitionTimer = 75
    End If

    If boss.warnTimer > 0 Then
        boss.warnTimer = boss.warnTimer - 1
        If boss.warnTimer = 0 And gameState = GS_PLAYING Then
            If debugMode Then DBG_Print "[boss] spawned  score=" + LTrim$(Str$(score)) + "  aabb=" + LTrim$(Str$(boxLib(MESH_BOSS).hx)) + "x" + LTrim$(Str$(boxLib(MESH_BOSS).hy)) + "x" + LTrim$(Str$(boxLib(MESH_BOSS).hz)) + "  verts=" + LTrim$(Str$(meshLib(MESH_BOSS).vCount))
            boss.active  = -1
            boss.meshIdx = MESH_BOSS
            bsmTurnDir   = 1
            boss.px = player.px + BOSS_SPAWN_DIST
            boss.py = player.py
            boss.pz = player.pz
            boss.vx = -0.05
            boss.scl = 1.0
            If settingNerf Then boss.hp = BOSS_MAX_HP_NERF Else boss.hp = BOSS_MAX_HP
            boss.phase       = 1
            boss.fireTimer   = BOSS_FIRE_INIT
            boss.moveTimer   = 0
            boss.targetY     = player.py
            boss.targetZ     = player.pz
            boss.state       = 0
            boss.chargeTimer = BOSS_CHARGE_CD1
            boss.arcAngle    = Rnd * 6.28318
            If bossMusCnt > 0 And Len(bossMusList$(0)) > 0 Then MUS_SetCue bossMusList$(0)
            telemBossPhaseLog = 0
            TELEM_BossReached
        End If
    End If

    If boss.active = 0 Then Exit Sub

    ' phase thresholds
    bssOldPhase = boss.phase
    If boss.hp > 20 Then
        boss.phase = 1
    ElseIf boss.hp > 10 Then
        boss.phase = 2
    Else
        boss.phase = 3
    End If

    ' phase transition: music tick and speech
    If boss.phase <> bssOldPhase Then
        TELEM_BossPhase boss.phase
        telemBossPhaseLog = boss.phase
        Dim bssPhaseIdx As Integer : bssPhaseIdx = boss.phase - 1
        If bssPhaseIdx < bossMusCnt Then
            bssMusCue = bossMusList$(bssPhaseIdx)
            If Len(bssMusCue) > 0 Then MUS_SetCue bssMusCue
        End If
        If bssPhaseIdx < bossSpeechCnt Then
            bssSpeechKey = bossSpeechList$(bssPhaseIdx)
            If Len(bssSpeechKey) > 0 Then SPK_Say GTEXT_Get$(bssSpeechKey)
        End If
    ElseIf boss.phase <> telemBossPhaseLog Then
        TELEM_BossPhase boss.phase
        telemBossPhaseLog = boss.phase
    End If

    ' initial approach: close to combat range (hunt/evade/arc only; charge/flyover handle own X)
    If boss.state = 0 Or boss.state = 1 Or boss.state = 4 Then
        If boss.px > player.px + BOSS_COMBAT_DIST Then
            boss.px = boss.px + boss.vx * (1.0 + (boss.phase - 1) * 0.4)
        End If
    End If

    ' intent-driven multi-axis movement (behavior.bas)
    bssPrevX = boss.px : bssPrevY = boss.py : bssPrevZ = boss.pz
    BOSS_UpdateMovement
    bssVX = boss.px - bssPrevX
    bssVY = boss.py - bssPrevY
    bssVZ = boss.pz - bssPrevZ

    ' attitude: roll/yaw from Z velocity, pitch from Y velocity; X charge adds nose-down tilt
    bssTgtRx = bssVZ * 90 - bssVX * 15 : If bssTgtRx > 70 Then bssTgtRx = 70 : If bssTgtRx < -70 Then bssTgtRx = -70
    bssTgtRy = -bssVZ * 35              : If bssTgtRy > 28 Then bssTgtRy = 28 : If bssTgtRy < -28 Then bssTgtRy = -28
    bssTgtRz = bssVY * 60              : If bssTgtRz > 50 Then bssTgtRz = 50 : If bssTgtRz < -50 Then bssTgtRz = -50
    ' flyover yaw: 180 while behind/charging fwd; arc-tangent-based during dramatic turn
    If boss.state >= 6 And boss.state <= 8 Then
        bssTgtRy = 180   ' facing same direction as player: dive, rear-fire, fwd charge
    ElseIf boss.state = 9 Then
        ' yaw = heading direction of the arc tangent; -atan2 maps the convention: ry=0 faces player (-X)
        bssTgtRy = -_ATAN2(COS(boss.arcAngle) * BOSS_TURN_RAD_Z * bsmTurnDir, SIN(boss.arcAngle) * BOSS_TURN_RAD_X) * 57.2958
    End If
    boss.rx = boss.rx + (bssTgtRx - boss.rx) * BOSS_ATTITUDE_LERP
    boss.ry = boss.ry + (bssTgtRy - boss.ry) * BOSS_ATTITUDE_LERP
    boss.rz = boss.rz + (bssTgtRz - boss.rz) * BOSS_ATTITUDE_LERP

    ' fire patterns: suppressed during dive (6), dramatic turn (9), and fwd charge approach (8 before overtake)
    boss.fireTimer = boss.fireTimer - 0.025
    If boss.fireTimer <= 0 And boss.state <> 6 And boss.state <> 9 And (boss.state <> 8 Or boss.px > player.px) Then
        bssDX = player.px - boss.px
        bssDY = player.py - boss.py
        bssDZ = player.pz - boss.pz
        bssDMag = SQR(bssDX * bssDX + bssDY * bssDY + bssDZ * bssDZ)
        If bssDMag > 0.1 Then bssDX = bssDX/bssDMag : bssDY = bssDY/bssDMag : bssDZ = bssDZ/bssDMag

        Select Case boss.phase
        Case 1  ' 3-shot Y fan
            bssShots = 0
            For bssEJ = 1 To MAX_EBULLETS
                If ebullets(bssEJ).active = 0 And bssShots < 3 Then
                    ebullets(bssEJ).active  = -1
                    ebullets(bssEJ).meshIdx = MESH_BOSS
                    ebullets(bssEJ).px = boss.px : ebullets(bssEJ).py = boss.py : ebullets(bssEJ).pz = boss.pz
                    ebullets(bssEJ).vx = bssDX * 0.26
                    ebullets(bssEJ).vy = bssDY * 0.26 + (bssShots - 1) * 0.07
                    ebullets(bssEJ).vz = bssDZ * 0.26
                    ebullets(bssEJ).scl = 1.0
                    bssShots = bssShots + 1
                End If
            Next bssEJ
            boss.fireTimer = BOSS_FIRE1
            If boss.state = 0 Or boss.state = 1 Or boss.state = 4 Then BOSS_PickMode boss.phase

        Case 2  ' 5-shot aimed cross
            bssShots = 0
            For bssEJ = 1 To MAX_EBULLETS
                If ebullets(bssEJ).active = 0 And bssShots < 5 Then
                    ebullets(bssEJ).active  = -1
                    ebullets(bssEJ).meshIdx = MESH_BOSS
                    ebullets(bssEJ).px = boss.px : ebullets(bssEJ).py = boss.py : ebullets(bssEJ).pz = boss.pz
                    ebullets(bssEJ).vx = bssDX * 0.30
                    Select Case bssShots
                    Case 0 : ebullets(bssEJ).vy = bssDY * 0.30        : ebullets(bssEJ).vz = bssDZ * 0.30
                    Case 1 : ebullets(bssEJ).vy = bssDY * 0.30 - 0.11 : ebullets(bssEJ).vz = bssDZ * 0.30
                    Case 2 : ebullets(bssEJ).vy = bssDY * 0.30 + 0.11 : ebullets(bssEJ).vz = bssDZ * 0.30
                    Case 3 : ebullets(bssEJ).vy = bssDY * 0.30        : ebullets(bssEJ).vz = bssDZ * 0.30 - 0.11
                    Case 4 : ebullets(bssEJ).vy = bssDY * 0.30        : ebullets(bssEJ).vz = bssDZ * 0.30 + 0.11
                    End Select
                    ebullets(bssEJ).scl = 1.0
                    bssShots = bssShots + 1
                End If
            Next bssEJ
            boss.fireTimer = BOSS_FIRE2
            If boss.state = 0 Or boss.state = 1 Or boss.state = 4 Then BOSS_PickMode boss.phase

        Case 3  ' 7-shot diagonal fan, fast
            bssShots = 0
            For bssEJ = 1 To MAX_EBULLETS
                If ebullets(bssEJ).active = 0 And bssShots < 7 Then
                    ebullets(bssEJ).active  = -1
                    ebullets(bssEJ).meshIdx = MESH_BOSS
                    ebullets(bssEJ).px = boss.px : ebullets(bssEJ).py = boss.py : ebullets(bssEJ).pz = boss.pz
                    ebullets(bssEJ).vx = bssDX * 0.35
                    ebullets(bssEJ).vy = bssDY * 0.35 + (bssShots - 3) * 0.07
                    ebullets(bssEJ).vz = bssDZ * 0.35 + (bssShots - 3) * 0.07
                    ebullets(bssEJ).scl = 1.0
                    bssShots = bssShots + 1
                End If
            Next bssEJ
            boss.fireTimer = BOSS_FIRE3
            If boss.state = 0 Or boss.state = 1 Or boss.state = 4 Then BOSS_PickMode boss.phase
        End Select
    End If

    ' player vs boss body collision
    E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
    boss.px, boss.py, boss.pz, boxLib(MESH_BOSS), bssHit
    If bssHit And invTimer = 0 Then
        telemDeathCause = "boss_col"
        PLAYER_TakeDamage DMG_COLLISION, SHAKE_COLLISION, FLASH_COLLISION
    End If

    ' player bullets vs boss
    For bssJ = 1 To MAX_BULLETS
        If bullets(bssJ).active Then
            E3D_AABBOverlap boss.px, boss.py, boss.pz, boxLib(MESH_BOSS), _
            bullets(bssJ).px, bullets(bssJ).py, bullets(bssJ).pz, boxLib(MESH_BULLET), bssHit
            If bssHit Then
                bullets(bssJ).active = 0
                telemShotsHit = telemShotsHit + 1
                boss.hp = boss.hp - 1
                fxShakeTimer = 2
                SND_Boom
                If boss.hp <= 0 Then
                    If debugMode Then DBG_Print "[boss] defeated  score=" + LTrim$(Str$(score))
                    TELEM_BossDefeated
                    boss.active  = 0
                    planetTransitionTimer = 75
                    score = score + 2000
                    scorePopTimer = 40 : scorePopY = scrH * 0.38 : scorePopVal = 2000
                    bssPK = 0
                    For bssP = 1 To FX_MAX_PARTICLES
                        If fxPartActive(bssP) = 0 And bssPK < BOSS_DEATH_PARTS Then
                            fxPartActive(bssP) = -1
                            fxPartPX(bssP) = boss.px + (RND - 0.5) * 5
                            fxPartPY(bssP) = boss.py + (RND - 0.5) * 5
                            fxPartPZ(bssP) = boss.pz + (RND - 0.5) * 5
                            fxPartVX(bssP) = (RND - 0.5) * 0.40
                            fxPartVY(bssP) = (RND - 0.5) * 0.40
                            fxPartVZ(bssP) = (RND - 0.5) * 0.40
                            fxPartLife(bssP) = 35 + Int(RND * 25)
                            fxPartClr(bssP)  = _RGB(255, Int(RND * 140) + 60, 0)
                            bssPK = bssPK + 1
                        End If
                    Next bssP
                    MUS_SetCue "game"
                End If
            End If
        End If
    Next bssJ
End Sub
