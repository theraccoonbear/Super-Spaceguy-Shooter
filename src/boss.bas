' boss.bas — boss trigger, fire patterns, collision, and death sequence
'
' BOSS_Update : call once per frame in the main game loop (GS_PLAYING).
'               Calls BOSS_UpdateMovement / BOSS_SetEvasion from behavior.bas.
'
' All persistent state is DIM SHARED in sss.bas.
' Local variable prefix: bss*

Const BOSS_SPAWN_DIST  = 55     ' boss spawns this far ahead of player
Const BOSS_COMBAT_DIST = 20     ' boss holds at this X distance
Const BOSS_WARN_FRAMES = 120    ' warning frames before boss spawns
Const BOSS_FIRE_INIT   = 2.5    ' fire interval at boss spawn (before phase lock-in)
Const BOSS_FIRE1       = 2.2    ' phase 1 fire interval
Const BOSS_FIRE2       = 1.5    ' phase 2 fire interval
Const BOSS_FIRE3       = 0.9    ' phase 3 fire interval
Const BOSS_DIM_FLOOR   = 0.35   ' minimum lighting factor for boss (keeps it visible at range)
Const BOSS_DEATH_PARTS = 35     ' particle count on boss death
Const BOSS_ATTITUDE_LERP = 0.07   ' attitude settle rate (< player 0.09 = heavier feel)

Sub BOSS_Update
    Dim bssDX As Single, bssDY As Single, bssDZ As Single, bssDMag As Single
    Dim bssEJ As Integer, bssJ As Integer, bssP As Integer, bssPK As Integer
    Dim bssShots As Integer
    Dim bssHit As Integer
    Dim bssPrevY As Single, bssPrevZ As Single
    Dim bssVY As Single, bssVZ As Single
    Dim bssTgtRx As Single, bssTgtRy As Single, bssTgtRz As Single

    ' trigger when score threshold reached
    If gameState = GS_PLAYING And boss.active = 0 And boss.warnTimer = 0 And score >= stageScore Then
        If levelHasBoss = 0 Then
            ' no boss on this level — go straight to planet
            gameState     = GS_PLANET
            planetTimer   = 1
            MUS_SetCue "planet"
            planetCurrent = (planetCurrent Mod PLANET_COUNT) + 1
            planetNameIdx = (planetNameIdx Mod PLANET_COUNT) + 1
        Else
            boss.warnTimer = BOSS_WARN_FRAMES
            SPK_Say GTEXT_Get$("speech_boss_warning")
        End If
    End If

    If boss.warnTimer > 0 Then
        boss.warnTimer = boss.warnTimer - 1
        If boss.warnTimer = 0 And gameState = GS_PLAYING Then
            If debugMode Then DBG_Print "[boss] spawned  score=" + LTrim$(Str$(score)) + "  aabb=" + LTrim$(Str$(boxLib(MESH_BOSS).hx)) + "x" + LTrim$(Str$(boxLib(MESH_BOSS).hy)) + "x" + LTrim$(Str$(boxLib(MESH_BOSS).hz)) + "  verts=" + LTrim$(Str$(meshLib(MESH_BOSS).vCount))
            boss.active  = -1
            boss.meshIdx = MESH_BOSS
            boss.px = player.px + BOSS_SPAWN_DIST
            boss.py = player.py
            boss.pz = player.pz
            boss.vx = -0.05
            boss.scl = 1.0
            If settingNerf Then boss.hp = BOSS_MAX_HP_NERF Else boss.hp = BOSS_MAX_HP
            boss.phase    = 1
            boss.fireTimer = BOSS_FIRE_INIT
            boss.moveTimer = 0
            boss.targetY  = player.py
            boss.targetZ  = player.pz
            boss.state    = 0
            MUS_SetCue "boss"
            telemBossPhaseLog = 0
            TELEM_BossReached
        End If
    End If

    If Not boss.active Then Exit Sub

    ' phase thresholds
    If boss.hp > 20 Then
        boss.phase = 1
    ElseIf boss.hp > 10 Then
        boss.phase = 2
    Else
        boss.phase = 3
    End If
    If boss.phase <> telemBossPhaseLog Then
        TELEM_BossPhase boss.phase
        telemBossPhaseLog = boss.phase
    End If

    ' X approach: close to combat range, speed scales with phase
    If boss.px > player.px + BOSS_COMBAT_DIST Then
        boss.px = boss.px + boss.vx * (1.0 + (boss.phase - 1) * 0.4)
    End If

    ' intent-driven lateral movement (behavior.bas)
    bssPrevY = boss.py : bssPrevZ = boss.pz
    BOSS_UpdateMovement
    ' attitude: roll/yaw from Z velocity, pitch from Y velocity
    bssVY = boss.py - bssPrevY
    bssVZ = boss.pz - bssPrevZ
    bssTgtRx = bssVZ * 90 : If bssTgtRx > 70 Then bssTgtRx = 70 : If bssTgtRx < -70 Then bssTgtRx = -70
    bssTgtRy = -bssVZ * 35 : If bssTgtRy > 28 Then bssTgtRy = 28 : If bssTgtRy < -28 Then bssTgtRy = -28
    bssTgtRz = bssVY * 60 : If bssTgtRz > 50 Then bssTgtRz = 50 : If bssTgtRz < -50 Then bssTgtRz = -50
    boss.rx = boss.rx + (bssTgtRx - boss.rx) * BOSS_ATTITUDE_LERP
    boss.ry = boss.ry + (bssTgtRy - boss.ry) * BOSS_ATTITUDE_LERP
    boss.rz = boss.rz + (bssTgtRz - boss.rz) * BOSS_ATTITUDE_LERP

    ' fire patterns
    boss.fireTimer = boss.fireTimer - 0.025
    If boss.fireTimer <= 0 Then
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
            BOSS_SetEvasion boss.phase

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
            BOSS_SetEvasion boss.phase

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
            BOSS_SetEvasion boss.phase
        End Select
    End If

    ' player vs boss body
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
                    gameState    = GS_PLANET
                    planetTimer  = 1
                    MUS_SetCue "planet"
                    ' note: stage.bas lerps player.py/pz to 0 over the GS_PLANET window
                    planetCurrent = (planetCurrent Mod PLANET_COUNT) + 1
                    planetNameIdx = (planetNameIdx Mod PLANET_COUNT) + 1
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
