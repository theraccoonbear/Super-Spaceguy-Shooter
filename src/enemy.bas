' enemy.bas — per-frame enemy movement, attitude, trails, fire, and collision
'
' ENEMY_Update : call once per frame in the main game loop (GS_PLAYING).
'
' All persistent state is DIM SHARED in sss.bas.
' Local variable prefix: en*

Const EBULLET_SPEED  = 0.16   ' regular enemy bullet speed
Const EBULLET_CULL   = 8      ' cull when px < player.px - this
Const EFIRE_COOL_MIN = 3.5    ' post-shot cooldown min
Const EFIRE_COOL_VAR = 2.2    ' post-shot cooldown variance
Const EFIRE_RANGE    = 40     ' X-range at which enemies fire
Const EFIRE_LEAD     = 0.65   ' fraction of perfect lead applied to enemy shots (0=dumb, 1=perfect)
Const SCORE_ENEMY         = 100    ' points per enemy kill

Sub ENEMY_Update
    Dim enI As Integer, enJ As Integer, enEJ As Integer
    Dim enOldPY As Single, enOldPZ As Single
    Dim enAttDY As Single, enAttDZ As Single
    Dim enDX As Single, enDY As Single, enDZ As Single, enMag As Single
    Dim enLead As Single
    Dim enTrlR As Integer, enTrlG As Integer, enTrlB As Integer
    Dim enPartR As Integer, enPartG As Integer, enPartB As Integer
    Dim enHit As Integer
    Dim enHomingLerp As Single, enHomingRange As Single
    Dim enBDY As Single, enBDZ As Single

    For enI = 1 To MAX_ENEMIES
        If enemies(enI).active Then
            enemies(enI).px = enemies(enI).px + enemies(enI).vx
            enemies(enI).ry = enemies(enI).ry + enemies(enI).dry

            ' sinusoidal drift far out; home on player when close
            enOldPY = enemies(enI).py
            enOldPZ = enemies(enI).pz
            enHomingLerp  = 0.008 + diffScale * (ENEMY_HOMING_SCALE - 0.008)
            enHomingRange = 30 + diffScale * ENEMY_HOMING_REXT
            If enemies(enI).px < player.px + enHomingRange Then
                enemies(enI).py = enemies(enI).py + (player.py - enemies(enI).py) * enHomingLerp + enemies(enI).vy
                enemies(enI).pz = enemies(enI).pz + (player.pz - enemies(enI).pz) * enHomingLerp + enemies(enI).vz
            Else
                enemies(enI).py = enemies(enI).py + Sin(tt * 1.5 + enI * 1.3) * 0.015 + enemies(enI).vy
                enemies(enI).pz = enemies(enI).pz + Cos(tt * 1.1 + enI * 2.1) * 0.015 + enemies(enI).vz
            End If
            enemies(enI).vy = enemies(enI).vy * 0.88
            enemies(enI).vz = enemies(enI).vz * 0.88
            ' strafe burst
            enemies(enI).strafeCool = enemies(enI).strafeCool - 1
            If enemies(enI).strafeCool <= 0 And diffScale > 0.05 Then
                enemies(enI).vy = (RND - 0.5) * ENEMY_STRAFE_MAG * 2 * diffScale
                enemies(enI).vz = (RND - 0.5) * ENEMY_STRAFE_MAG * 2 * diffScale
                enemies(enI).strafeCool = ENEMY_STRAFE_COOL + Int(RND * 60)
            End If

            ' attitude: bank/pitch from frame-to-frame lateral delta
            enAttDY = enemies(enI).py - enOldPY
            enAttDZ = enemies(enI).pz - enOldPZ
            enemies(enI).rx = enemies(enI).rx + ( (enAttDZ / 0.015) * 20 - enemies(enI).rx) * 0.12
            enemies(enI).rz = enemies(enI).rz + (-(enAttDY / 0.015) * 15 - enemies(enI).rz) * 0.12

            ' contrail: staggered by slot so not all ships emit on the same frame
            If (Int(tt * 40) + enI) Mod 3 = 0 Then
                Select Case enemies(enI).meshIdx
                Case MESH_ENEMY        : enTrlR = 160 : enTrlG =  50 : enTrlB =  35
                Case MESH_ENEMY_ARROW  : enTrlR = 160 : enTrlG =  90 : enTrlB =   0
                Case MESH_ENEMY_HLINE  : enTrlR =  40 : enTrlG = 140 : enTrlB =  55
                Case MESH_ENEMY_VCOL   : enTrlR =  40 : enTrlG = 140 : enTrlB = 155
                Case MESH_ENEMY_PINCER : enTrlR = 155 : enTrlG = 150 : enTrlB =  35
                Case Else              : enTrlR = 120 : enTrlG =  50 : enTrlB = 165
                End Select
                FX_SpawnBurst enemies(enI).px + 0.35, enemies(enI).py, enemies(enI).pz, 1, 0.005, 20, 6, _RGB(enTrlR, enTrlG, enTrlB)
            End If

            ' fire: lead-compensated aim (EFIRE_LEAD fraction of perfect intercept)
            enemyFireTimer(enI) = enemyFireTimer(enI) - 0.025
            If enemyFireTimer(enI) <= 0 And enemies(enI).px > player.px And enemies(enI).px < player.px + EFIRE_RANGE Then
                enDX = player.px - enemies(enI).px
                enDY = player.py - enemies(enI).py
                enDZ = player.pz - enemies(enI).pz
                enMag = SQR(enDX * enDX + enDY * enDY + enDZ * enDZ)
                If enMag > 0.1 Then
                    enLead = (enMag / EBULLET_SPEED) * EFIRE_LEAD
                    enDY = (player.py + playerVY * enLead) - enemies(enI).py
                    enDZ = (player.pz + playerVZ * enLead) - enemies(enI).pz
                    enMag = SQR(enDX * enDX + enDY * enDY + enDZ * enDZ)
                    enDX = enDX / enMag : enDY = enDY / enMag : enDZ = enDZ / enMag
                    For enEJ = 1 To MAX_EBULLETS
                        If ebullets(enEJ).active = 0 Then
                            ebullets(enEJ).active  = -1
                            ebullets(enEJ).meshIdx = enemies(enI).meshIdx
                            ebullets(enEJ).px = enemies(enI).px
                            ebullets(enEJ).py = enemies(enI).py
                            ebullets(enEJ).pz = enemies(enI).pz
                            ebullets(enEJ).vx = enDX * EBULLET_SPEED
                            ebullets(enEJ).vy = enDY * EBULLET_SPEED
                            ebullets(enEJ).vz = enDZ * EBULLET_SPEED
                            ebullets(enEJ).scl = 1.0
                            Exit For
                        End If
                    Next enEJ
                End If
                enemyFireTimer(enI) = (EFIRE_COOL_MIN + RND * EFIRE_COOL_VAR) * (1.0 - diffScale * 0.4)
            End If

            If enemies(enI).px < -5 Then enemies(enI).active = 0 : TELEM_EnemyEscaped

            ' bullet vs enemy
            For enJ = 1 To MAX_BULLETS
                If bullets(enJ).active Then
                    E3D_AABBOverlap enemies(enI).px, enemies(enI).py, enemies(enI).pz, boxLib(enemies(enI).meshIdx), _
                    bullets(enJ).px, bullets(enJ).py, bullets(enJ).pz, boxLib(MESH_BULLET), enHit
                    If enHit Then
                        enemies(enI).vy = 0 : enemies(enI).vz = 0
                        enemies(enI).active = 0
                        bullets(enJ).active = 0
                        telemShotsHit = telemShotsHit + 1
                        score = score + SCORE_ENEMY
                        If debugMode Then DBG_Print "[kill] enemy  score=" + LTrim$(Str$(score))
                        TELEM_EnemyKilled
                        SND_Boom
                        scorePopTimer = 30 : scorePopY = scrH * 0.45 : scorePopVal = SCORE_ENEMY
                        Select Case enemies(enI).meshIdx
                        Case MESH_ENEMY        : enPartR = 255 : enPartG =  80 : enPartB =  60
                        Case MESH_ENEMY_ARROW  : enPartR = 255 : enPartG = 140 : enPartB =   0
                        Case MESH_ENEMY_HLINE  : enPartR =  60 : enPartG = 210 : enPartB =  80
                        Case MESH_ENEMY_VCOL   : enPartR =  60 : enPartG = 220 : enPartB = 235
                        Case MESH_ENEMY_PINCER : enPartR = 235 : enPartG = 225 : enPartB =  50
                        Case Else              : enPartR = 185 : enPartG =  80 : enPartB = 255
                        End Select
                        FX_SpawnBurst enemies(enI).px, enemies(enI).py, enemies(enI).pz, 10, 0.22, 18, 8, _RGB(enPartR, enPartG, enPartB)
                    ElseIf diffScale > 0.1 Then
                        ' near-miss break: bullet passed close without hitting
                        If Abs(bullets(enJ).px - enemies(enI).px) < 3.0 Then
                            enBDY = enemies(enI).py - bullets(enJ).py
                            enBDZ = enemies(enI).pz - bullets(enJ).pz
                            If Abs(enBDY) < ENEMY_NEAR_MISS_RAD And Abs(enBDZ) < ENEMY_NEAR_MISS_RAD Then
                                enemies(enI).vy = enBDY * ENEMY_BREAK_VEL
                                enemies(enI).vz = enBDZ * ENEMY_BREAK_VEL
                            End If
                        End If
                    End If
                End If
            Next enJ

            ' player vs enemy
            E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
            enemies(enI).px, enemies(enI).py, enemies(enI).pz, boxLib(enemies(enI).meshIdx), enHit
            If enHit And invTimer = 0 Then
                enemies(enI).active = 0
                Select Case enemies(enI).meshIdx
                Case MESH_ENEMY        : enPartR = 255 : enPartG =  80 : enPartB =  60
                Case MESH_ENEMY_ARROW  : enPartR = 255 : enPartG = 140 : enPartB =   0
                Case MESH_ENEMY_HLINE  : enPartR =  60 : enPartG = 210 : enPartB =  80
                Case MESH_ENEMY_VCOL   : enPartR =  60 : enPartG = 220 : enPartB = 235
                Case MESH_ENEMY_PINCER : enPartR = 235 : enPartG = 225 : enPartB =  50
                Case Else              : enPartR = 185 : enPartG =  80 : enPartB = 255
                End Select
                SND_Boom
                FX_SpawnBurst enemies(enI).px, enemies(enI).py, enemies(enI).pz, 10, 0.22, 18, 8, _RGB(enPartR, enPartG, enPartB)
                telemDeathCause = "enemy_col"
                PLAYER_TakeDamage DMG_COLLISION, SHAKE_COLLISION, FLASH_COLLISION
            End If
        End If
    Next enI
End Sub

Sub EBULLET_Update
    Dim ebI As Integer
    Dim ebHit As Integer
    Dim ebDY As Single, ebDZ As Single

    For ebI = 1 To MAX_EBULLETS
        If ebullets(ebI).active Then
            ebullets(ebI).px = ebullets(ebI).px + ebullets(ebI).vx
            ebullets(ebI).py = ebullets(ebI).py + ebullets(ebI).vy
            ebullets(ebI).pz = ebullets(ebI).pz + ebullets(ebI).vz
            If ebullets(ebI).px < player.px - EBULLET_CULL Then ebullets(ebI).active = 0

            E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
            ebullets(ebI).px, ebullets(ebI).py, ebullets(ebI).pz, boxLib(MESH_EBULLET), ebHit
            If ebHit And invTimer = 0 Then
                ebullets(ebI).active = 0
                telemDeathCause = "ebullet"
                PLAYER_TakeDamage DMG_LASER, SHAKE_LASER, FLASH_LASER
            ElseIf Not ebHit Then
                ' near-miss: fired past player's X plane within a tight lateral window
                If ebullets(ebI).px < player.px And ebullets(ebI).px >= player.px - 0.42 Then
                    ebDY = Abs(ebullets(ebI).py - player.py)
                    ebDZ = Abs(ebullets(ebI).pz - player.pz)
                    If ebDY < 5.0 And ebDZ < 5.0 Then SND_Whoosh 0.5
                End If
            End If
        End If
    Next ebI
End Sub
