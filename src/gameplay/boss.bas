' boss.bas -- boss trigger, fire patterns, collision, and death sequence
'
' BOSS_Update : call once per frame in the main game loop (GS_PLAYING).
'               Calls BOSS_UpdateMovement / BOSS_SetEvasion from behavior.bas.
'
' All persistent state is DIM SHARED in sss.bas.
' Local variable prefix: bss*

Const BOSS_SPAWN_DIST    = 55    ' boss spawns this far ahead of player
Const BOSS_FIRE_INIT     = 2.5   ' fire interval at boss spawn (before phase lock-in)
Const BOSS_FIRE1         = 2.2   ' phase 1 fire interval
Const BOSS_FIRE2         = 1.5   ' phase 2 fire interval
Const BOSS_FIRE3         = 0.9   ' phase 3 fire interval
Const BOSS_SHOT1         = 0.26  ' phase 1 laser speed
Const BOSS_SHOT2         = 0.30  ' phase 2 laser speed
Const BOSS_SHOT3         = 0.35  ' phase 3 laser speed
Const BOSS_DIM_FLOOR     = 0.35  ' minimum lighting factor for boss (keeps it visible at range)
Const BOSS_DEATH_PARTS   = 35    ' particle count on boss death
Const BOSS_ATTITUDE_LERP = 0.07  ' attitude settle rate (< player 0.09 = heavier feel)

Sub BOSS_Update
    Dim bssDX As Single, bssDY As Single, bssDZ As Single, bssSpd As Single
    Dim bssEJ As Integer, bssJ As Integer
    Dim bssShots As Integer
    Dim bssHit As Integer
    Dim bssPrevY As Single, bssPrevZ As Single
    Dim bssVY As Single, bssVZ As Single
    Dim bssTgtRx As Single, bssTgtRy As Single, bssTgtRz As Single
    Dim bssOldPhase As Integer
    Dim bssMusCue As String, bssSpeechKey As String
    Dim bssAtk As Integer
    Dim bssLeftE As Integer, bssLeftP As Integer, bssClear As Integer

    ' combat phase complete: clear the field (waves.ini wave_clear), then advance to the boss or planet
    If gameState = GS_PLAYING And boss.active = 0 And boss.warnTimer = 0 And SEQ_StageCleared% And planetTransitionTimer = 0 Then
        stageClearT = stageClearT + 1
        bssLeftE = 0 : bssLeftP = 0
        For bssJ = 1 To MAX_ENEMIES
            If enemies(bssJ).active Then bssLeftE = bssLeftE + 1
        Next bssJ
        For bssJ = 1 To MAX_POWERUPS
            If powerups(bssJ).active Then bssLeftP = bssLeftP + 1
        Next bssJ
        bssClear = WVT_ClearDone%(stageClearT, bssLeftE, bssLeftP, scorePopTimer)
        If bssClear = WVT_CLEAR_FORCE Then
            For bssJ = 1 To MAX_ENEMIES : enemies(bssJ).active = 0 : Next bssJ
            For bssJ = 1 To MAX_POWERUPS : powerups(bssJ).active = 0 : Next bssJ
        End If
        If bssClear <> WVT_CLEAR_WAIT Then
            If debugMode Then DBG_Print "[clear] done after" + Str$(stageClearT) + " frames  forced=" + LTrim$(Str$(bssClear = WVT_CLEAR_FORCE))
            stageClearT = 0
            planetTransitionTimer = 1
        End If
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
            bossMaxHP = BHP_MaxHP%(bossCfgHp, settingNerf)
            boss.hp = bossMaxHP
            bossShieldT = 0
            boss.phase       = 1
            boss.fireTimer   = BOSS_FIRE_INIT * dlvFBossFire
            boss.moveTimer   = 0
            boss.targetY     = player.py
            boss.targetZ     = player.pz
            boss.state       = 0
            boss.chargeTimer = BOSS_CHARGE_CD1
            boss.arcAngle    = RNG!(RNG_GAME) * 6.28318
            If bossMusCnt > 0 And Len(bossMusList$(0)) > 0 Then MUS_SetCue bossMusList$(0)
            telemBossPhaseLog = 0
            TELEM_BossReached
        End If
    End If

    If boss.active = 0 Then Exit Sub

    ' phase thresholds
    bssOldPhase = boss.phase
    boss.phase = BHP_Phase%(boss.hp, bossMaxHP)
    If bossShieldT > 0 Then bossShieldT = bossShieldT - 1

    ' phase transition: music tick and speech; the boss stays shielded until the callout ends
    If boss.phase <> bssOldPhase Then
        TELEM_BossPhase boss.phase
        telemBossPhaseLog = boss.phase
        Dim bssPhaseIdx As Integer : bssPhaseIdx = boss.phase - 1
        If bssPhaseIdx < bossMusCnt Then
            bssMusCue = bossMusList$(bssPhaseIdx)
            If Len(bssMusCue) > 0 Then MUS_SetCue bssMusCue
        End If
        bossShieldT = BHP_ShieldFrames&(0)
        If bssPhaseIdx < bossSpeechCnt Then
            bssSpeechKey = bossSpeechList$(bssPhaseIdx)
            If Len(bssSpeechKey) > 0 Then
                SPK_Say GTEXT_Get$(bssSpeechKey)
                bossShieldT = BHP_ShieldFrames&(SPK_QueueSamples&)
            End If
        End If
    ElseIf boss.phase <> telemBossPhaseLog Then
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

    ' fire patterns: one attack per volley from the boss's attack= pool (attacks.bas);
    ' a running cut chain holds the next volley so attacks never overlap
    ATK_Tick
    If CUT_Busy% = 0 Then boss.fireTimer = boss.fireTimer - 0.025
    If boss.fireTimer <= 0 Then
        Select Case boss.phase
        Case 1 : bssSpd = BOSS_SHOT1
        Case 2 : bssSpd = BOSS_SHOT2
        Case Else : bssSpd = BOSS_SHOT3
        End Select
        IMP_AimLead boss.px, boss.py, boss.pz, player.px, player.py, player.pz, playerVY + devPullY, playerVZ + devPullZ, bssSpd, bssDX, bssDY, bssDZ

        bssAtk = ATK_Pick%(bossAttackList$(), bossAttackCnt, RNG!(RNG_GAME))
        If DEV_Busy% Then bssAtk = ATK_LASER  ' devour keeps firing lasers, nothing else
        ATK_Fired bssAtk
        If bssAtk <> ATK_LASER Then
            If bssAtk = ATK_SPORE Then BOSS_SporeVolley
            If bssAtk = ATK_CUT Then CUT_Start boss.phase, (RNG!(RNG_GAME) < 0.5), player.px, player.py, player.pz, playerVY, playerVZ
            If bssAtk = ATK_DEVOUR Then DEV_Start boss.phase
            Select Case boss.phase
            Case 1 : boss.fireTimer = BOSS_FIRE1 * dlvFBossFire
            Case 2 : boss.fireTimer = BOSS_FIRE2 * dlvFBossFire
            Case Else : boss.fireTimer = BOSS_FIRE3 * dlvFBossFire
            End Select
            BOSS_SetEvasion boss.phase
        Else
            Select Case boss.phase
            Case 1  ' 3-shot Y fan
                bssShots = 0
                For bssEJ = 1 To MAX_EBULLETS
                    If ebullets(bssEJ).active = 0 And bssShots < 3 Then
                        ebullets(bssEJ).active  = -1
                        ebullets(bssEJ).meshIdx = MESH_BOSS
                        ebullets(bssEJ).px = boss.px : ebullets(bssEJ).py = boss.py : ebullets(bssEJ).pz = boss.pz
                        ebullets(bssEJ).vx = bssDX * BOSS_SHOT1
                        ebullets(bssEJ).vy = bssDY * BOSS_SHOT1 + (bssShots - 1) * 0.07
                        ebullets(bssEJ).vz = bssDZ * BOSS_SHOT1
                        ebullets(bssEJ).scl = 1.0
                        bssShots = bssShots + 1
                    End If
                Next bssEJ
                boss.fireTimer = BOSS_FIRE1 * dlvFBossFire
                BOSS_SetEvasion boss.phase
    
            Case 2  ' 5-shot aimed cross
                bssShots = 0
                For bssEJ = 1 To MAX_EBULLETS
                    If ebullets(bssEJ).active = 0 And bssShots < 5 Then
                        ebullets(bssEJ).active  = -1
                        ebullets(bssEJ).meshIdx = MESH_BOSS
                        ebullets(bssEJ).px = boss.px : ebullets(bssEJ).py = boss.py : ebullets(bssEJ).pz = boss.pz
                        ebullets(bssEJ).vx = bssDX * BOSS_SHOT2
                        Select Case bssShots
                        Case 0 : ebullets(bssEJ).vy = bssDY * BOSS_SHOT2        : ebullets(bssEJ).vz = bssDZ * BOSS_SHOT2
                        Case 1 : ebullets(bssEJ).vy = bssDY * BOSS_SHOT2 - 0.11 : ebullets(bssEJ).vz = bssDZ * BOSS_SHOT2
                        Case 2 : ebullets(bssEJ).vy = bssDY * BOSS_SHOT2 + 0.11 : ebullets(bssEJ).vz = bssDZ * BOSS_SHOT2
                        Case 3 : ebullets(bssEJ).vy = bssDY * BOSS_SHOT2        : ebullets(bssEJ).vz = bssDZ * BOSS_SHOT2 - 0.11
                        Case 4 : ebullets(bssEJ).vy = bssDY * BOSS_SHOT2        : ebullets(bssEJ).vz = bssDZ * BOSS_SHOT2 + 0.11
                        End Select
                        ebullets(bssEJ).scl = 1.0
                        bssShots = bssShots + 1
                    End If
                Next bssEJ
                boss.fireTimer = BOSS_FIRE2 * dlvFBossFire
                BOSS_SetEvasion boss.phase
    
            Case 3  ' 7-shot diagonal fan, fast
                bssShots = 0
                For bssEJ = 1 To MAX_EBULLETS
                    If ebullets(bssEJ).active = 0 And bssShots < 7 Then
                        ebullets(bssEJ).active  = -1
                        ebullets(bssEJ).meshIdx = MESH_BOSS
                        ebullets(bssEJ).px = boss.px : ebullets(bssEJ).py = boss.py : ebullets(bssEJ).pz = boss.pz
                        ebullets(bssEJ).vx = bssDX * BOSS_SHOT3
                        ebullets(bssEJ).vy = bssDY * BOSS_SHOT3 + (bssShots - 3) * 0.07
                        ebullets(bssEJ).vz = bssDZ * BOSS_SHOT3 + (bssShots - 3) * 0.07
                        ebullets(bssEJ).scl = 1.0
                        bssShots = bssShots + 1
                    End If
                Next bssEJ
                boss.fireTimer = BOSS_FIRE3 * dlvFBossFire
                BOSS_SetEvasion boss.phase
            End Select
        End If
    End If

    ' player vs boss body collision
    E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
    boss.px, boss.py, boss.pz, boxLib(MESH_BOSS), bssHit
    If bssHit And invTimer = 0 Then
        telemDeathCause = "boss_col"
        PLAYER_TakeHit DLV_Dmg%(DMG_COLLISION), SHAKE_COLLISION, FLASH_COLLISION
    End If

    ' player bullets vs boss
    For bssJ = 1 To MAX_BULLETS
        If bullets(bssJ).active Then
            E3D_AABBOverlap boss.px, boss.py, boss.pz, boxLib(MESH_BOSS), _
            bullets(bssJ).px, bullets(bssJ).py, bullets(bssJ).pz, boxLib(MESH_BULLET), bssHit
            If bssHit Then
                bullets(bssJ).active = 0
                telemShotsHit = telemShotsHit + 1
                If bossShieldT > 0 Then
                    FX_SpawnBurst bullets(bssJ).px, bullets(bssJ).py, bullets(bssJ).pz, 4, 0.12, 10, 5, _RGB(140, 230, 255)
                    _Continue
                End If
                BOSS_Hit 1
                fxShakeTimer = 2
                SND_Boom
                If boss.hp <= 0 Then
                    BOSS_Defeat
                    ' the boss is gone: a second bullet landing this same frame must not run
                    ' the defeat (score, telemetry, stage transition) again (#168)
                    Exit For
                End If
            End If
        End If
    Next bssJ
End Sub

' Takes bshDmg hit points off the boss (bosshp.bas: none while shielded, never past the next
' phase's start). Reaching a new phase shields it at once, so the rest of this frame's shots
' bounce off too; BOSS_Update stretches the shield over the phase callout next frame.
Sub BOSS_Hit (bshDmg As Integer)
    Dim bshOld As Integer
    bshOld = boss.hp
    boss.hp = BHP_Damage%(boss.hp, bossMaxHP, bshDmg, bossShieldT)
    If boss.hp > 0 And BHP_Phase%(boss.hp, bossMaxHP) <> BHP_Phase%(bshOld, bossMaxHP) Then bossShieldT = BHP_ShieldFrames&(0)
End Sub

' The boss is beaten (by lasers or a nova pulse): score, credits, telemetry, the stage transition.
Sub BOSS_Defeat
    Dim bsdP As Integer, bsdPK As Integer
    If debugMode Then DBG_Print "[boss] defeated  score=" + LTrim$(Str$(score))
    TELEM_BossDefeated
    boss.active  = 0
    planetTransitionTimer = 75
    SPORE_Clear  ' no lingering clouds or cuts once the boss is dead
    CUT_Clear
    DEV_Clear
    score = score + 2000
    scorePopTimer = 40 : scorePopY = scrH * 0.38 : scorePopVal = 2000
    bsdPK = 0
    For bsdP = 1 To FX_MAX_PARTICLES
        If fxPartActive(bsdP) = 0 And bsdPK < BOSS_DEATH_PARTS Then
            fxPartActive(bsdP) = -1
            fxPartPX(bsdP) = boss.px + (RNG!(RNG_FX) - 0.5) * 5
            fxPartPY(bsdP) = boss.py + (RNG!(RNG_FX) - 0.5) * 5
            fxPartPZ(bsdP) = boss.pz + (RNG!(RNG_FX) - 0.5) * 5
            fxPartVX(bsdP) = (RNG!(RNG_FX) - 0.5) * 0.40
            fxPartVY(bsdP) = (RNG!(RNG_FX) - 0.5) * 0.40
            fxPartVZ(bsdP) = (RNG!(RNG_FX) - 0.5) * 0.40
            fxPartLife(bsdP) = 35 + Int(RNG!(RNG_FX) * 25)
            fxPartClr(bsdP)  = _RGB(255, Int(RNG!(RNG_FX) * 140) + 60, 0)
            bsdPK = bsdPK + 1
        End If
    Next bsdP
    MUS_SetCue "game"
    CR_Add crBoss
End Sub

' Attack A, spore bloom (#26): launches spore clouds at where the player is now, one per
' boss phase reached (1, 2, 3).
Sub BOSS_SporeVolley
    Dim bsvN As Integer, bsvSide As Single
    bsvN = boss.phase
    If RNG!(RNG_GAME) < 0.5 Then bsvSide = -1 Else bsvSide = 1
    SPORE_Spawn boss.px, boss.py, boss.pz, player.px, player.py, player.pz
    If bsvN >= 2 Then SPORE_Spawn boss.px, boss.py, boss.pz, player.px, player.py + 3.2 * bsvSide, player.pz
    If bsvN >= 3 Then SPORE_Spawn boss.px, boss.py, boss.pz, player.px, player.py, player.pz + 3.2 * bsvSide
End Sub
