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

' Render orientation for states 5/6 (transition/flyover) -- built directly from
' a forward/up/right basis, not Euler angles (see BOSS_Update, E3D_BuildObjectMatBasis).
Dim Shared bssRendFwdX As Single, bssRendFwdY As Single, bssRendFwdZ As Single
Dim Shared bssRendUpX  As Single, bssRendUpY  As Single, bssRendUpZ  As Single
Dim Shared bssRendRgtX As Single, bssRendRgtY As Single, bssRendRgtZ As Single

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

    ' boss.phase is set at spawn (1) and advanced only by phase triggers
    ' (trigger: <t>, phase, <n> in the current maneuver -- see behavior.bas
    ' Case 6); no longer HP-derived.
    bssOldPhase = boss.phase

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

    ' initial approach: close spawn distance down to combat range before the first flyover pass
    If boss.state = 0 Then
        If boss.px > player.px + BOSS_COMBAT_DIST Then
            Dim bssApproachRateD As Double
            SpEfPhaseApproachRate CDbl(boss.vx), CDbl(boss.phase), bssApproachRateD
            boss.px = boss.px + CSng(bssApproachRateD)
        End If
    End If

    ' intent-driven multi-axis movement (behavior.bas)
    bssPrevX = boss.px : bssPrevY = boss.py : bssPrevZ = boss.pz
    BOSS_UpdateMovement
    bssVX = boss.px - bssPrevX
    bssVY = boss.py - bssPrevY
    bssVZ = boss.pz - bssPrevZ

    ' attitude: roll/yaw from Z velocity, pitch from Y velocity; X charge adds nose-down tilt.
    ' ExprForge-generated (SpEfVelocityAttitude) -- ships the same clamp behavior as before.
    Dim bssVaRxD As Double, bssVaRyD As Double, bssVaRzD As Double
    SpEfVelocityAttitude CDbl(bssVX), CDbl(bssVY), CDbl(bssVZ), bssVaRxD, bssVaRyD, bssVaRzD
    bssTgtRx = CSng(bssVaRxD)
    bssTgtRy = CSng(bssVaRyD)
    bssTgtRz = CSng(bssVaRzD)
    ' flyover + transition: render orientation is built directly from a
    ' forward/up/right basis (bssRendFwd/Up/Rgt, consumed by combat.bas's
    ' E3D_BuildObjectMatBasis) instead of Euler angles. Rx*Ry*Rz composition
    ' cannot represent banking at arbitrary yaw -- at high yaw, neither pitch
    ' (Rx) nor roll (Rz) can tilt the model, so it pitches when it should bank.
    ' tools/turn_viz.bas's VIZ_BuildBossObjMat (commit 46547c9) found and fixed
    ' this for a debug tool; this ports the same fix to the real renderer.
    ' boss.rx/ry/rz are left to SpEfVelocityAttitude's small-tilt approximation
    ' (above) during states 5/6 -- unused for rendering then, but keeps a sane
    ' value for state 0 to resume lerping from once the pass ends.
    If boss.state = 6 Or boss.state = 5 Then
        Dim bssFwdX As Single, bssFwdY As Single, bssFwdZ As Single
        Dim bssBaseRX As Single, bssBaseRY As Single, bssBaseRZ As Single
        Dim bssBaseUX As Single, bssBaseUY As Single, bssBaseUZ As Single

        If bsmOrientMode = 1 Then
            ' Fixed-target facing: forward is the direction to the target, and
            ' roll comes from a frame built on THAT direction, not the path
            ' tangent's transport frame (bsmFlFRX/Y/Z) -- that frame rotates
            ' with the path tangent, which can point anywhere relative to a
            ' fixed target, producing an unrelated, wildly varying roll.
            SpShipFacing boss.px, boss.py, boss.pz, _
                         bsmFlTnX, bsmFlTnY, bsmFlTnZ, _
                         bsmOrientMode, _
                         player.px + bsmTargetX, player.py + bsmTargetY, player.pz + bsmTargetZ, _
                         bssFwdX, bssFwdY, bssFwdZ
            Dim bssMkRxD As Double, bssMkRyD As Double, bssMkRzD As Double
            Dim bssMkUxD As Double, bssMkUyD As Double, bssMkUzD As Double
            SpEfMkFrame CDbl(bssFwdX), CDbl(bssFwdY), CDbl(bssFwdZ), _
                        bssMkRxD, bssMkRyD, bssMkRzD, bssMkUxD, bssMkUyD, bssMkUzD
            bssBaseRX = CSng(bssMkRxD) : bssBaseRY = CSng(bssMkRyD) : bssBaseRZ = CSng(bssMkRzD)
            bssBaseUX = CSng(bssMkUxD) : bssBaseUY = CSng(bssMkUyD) : bssBaseUZ = CSng(bssMkUzD)
        Else
            ' Path-follow: forward is the spline tangent, roll comes from the
            ' persistent parallel-transport frame (BOSS_UpdateTransportFrame).
            bssFwdX = bsmFlTnX : bssFwdY = bsmFlTnY : bssFwdZ = bsmFlTnZ
            bssBaseRX = bsmFlFRX : bssBaseRY = bsmFlFRY : bssBaseRZ = bsmFlFRZ
            bssBaseUX = bsmFlFUX : bssBaseUY = bsmFlFUY : bssBaseUZ = bsmFlFUZ
        End If

        ' Authored craftRoll (state 6 only -- see behavior.bas's SpEvalRollAt):
        ' rotate the (U,R) pair around the forward axis by the interpolated
        ' craftRoll angle, exactly like TrailForge's rolledU/rolledR.
        Dim bssCRDeg As Single : bssCRDeg = 0
        If boss.state = 6 Then bssCRDeg = bsmFlCR
        Dim bssRUxD As Double, bssRUyD As Double, bssRUzD As Double
        Dim bssRRxD As Double, bssRRyD As Double, bssRRzD As Double
        SpEfRollFrame CDbl(bssBaseUX), CDbl(bssBaseUY), CDbl(bssBaseUZ), _
                      CDbl(bssBaseRX), CDbl(bssBaseRY), CDbl(bssBaseRZ), _
                      CDbl(bssCRDeg), bssRUxD, bssRUyD, bssRUzD, bssRRxD, bssRRyD, bssRRzD

        ' Canonical mapping (forward/up/right, no sign-flips here) -- the BOSS
        ' mesh's actual local-axis mismatch (nose at local -X, confirmed via
        ' tools/turn_viz.bas's VIZ_BuildBossObjMat, and verified numerically
        ' against the mesh's own dark-belly-colored faces, an authored "this
        ' is the bottom" marker) is corrected ONCE at load time instead, via
        ' the "axisfix" line in assets/models.e3d (E3D_LoadMesh). See
        ' E3D_BuildObjectMatBasis for the matrix this feeds.
        bssRendFwdX = bssFwdX : bssRendFwdY = bssFwdY : bssRendFwdZ = bssFwdZ
        bssRendUpX  = CSng(bssRUxD) : bssRendUpY = CSng(bssRUyD) : bssRendUpZ = CSng(bssRUzD)
        bssRendRgtX = CSng(bssRRxD) : bssRendRgtY = CSng(bssRRyD) : bssRendRgtZ = CSng(bssRRzD)
    End If
    Dim bssAttLerp As Single : bssAttLerp = BOSS_ATTITUDE_LERP
    If boss.state = 6 Or boss.state = 5 Then bssAttLerp = 0.18  ' faster tracking during spline flight/transition
    boss.rx = boss.rx + (bssTgtRx - boss.rx) * bssAttLerp
    boss.ry = boss.ry + (bssTgtRy - boss.ry) * bssAttLerp
    boss.rz = boss.rz + (bssTgtRz - boss.rz) * bssAttLerp

    ' fire patterns: suppressed during dive (6), dramatic turn (9), and fwd charge approach (8 before overtake)
    boss.fireTimer = boss.fireTimer - 0.025
    ' fire: suppress during flyover except when boss is behind player (rear-fire zone)
    If boss.fireTimer <= 0 And (boss.state <> 6 Or boss.px < player.px) Then
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
            If boss.state = 0 Then BOSS_PickMode

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
            If boss.state = 0 Then BOSS_PickMode

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
            If boss.state = 0 Then BOSS_PickMode
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
