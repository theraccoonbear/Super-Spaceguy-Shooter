' abilities.bas -- in-flight effects of dock upgrades (#268): evasive roll, nova pulse,
' shield regen and the tractor beam. The bookkeeping (charges, cooldowns, regen ticks)
' is in upgrades.bas; this file applies it to the playfield and draws it.
'
' ABL_Update      once per frame in play, after PLAYER_Update
' ABL_Tractor i   per active power-up when the tractor beam is fitted
' ABL_Draw        after COMBAT_OverlayDraw
' Keys: E / pad X = roll, Q / pad Y = nova.
' Local variable prefix: ab*

Const NOVA_FX_FRAMES = 32
Const ABL_HINT_FRAMES = 180   ' how long "NOVA READY - Q / PAD Y" stays up after launch


Sub ABL_Update
    Dim abuDir As Integer, abuNova As Integer, abuRoll As Integer
    UPG_RollTick
    UPG_RegenTick
    If novaFxTimer > 0 Then novaFxTimer = novaFxTimer - 1
    If ablHintTimer > 0 Then ablHintTimer = ablHintTimer - 1
    If gameState <> GS_PLAYING Or deathTimer > 0 Then Exit Sub
    ' first launch after buying an active ability: say which key fires it
    If Len(upgHintPending) > 0 Then
        ablHintText = upgHintPending : upgHintPending = ""
        ablHintTimer = ABL_HINT_FRAMES
    End If

    abuRoll = KEY_Pressed%(E3D_KEY_E) Or KEY_Pressed%(E3D_KEY_PAD_X)
    If abuRoll Then
        abuDir = 0
        If held(E3D_KEY_LEFT) Or held(E3D_KEY_A) Then abuDir = -1
        If held(E3D_KEY_RIGHT) Or held(E3D_KEY_D) Then abuDir = 1
        If abuDir = 0 Then abuDir = Sgn(playerVZ)
        If UPG_RollTry%(abuDir) Then SND_Whoosh 1.5
    End If
    If rollTimer > 0 Then
        FX_SpawnBurst player.px - 0.4, player.py, player.pz, 2, 0.02, 14, 6, _RGB(120, 200, 255)
    End If

    abuNova = KEY_Pressed%(E3D_KEY_Q) Or KEY_Pressed%(E3D_KEY_PAD_Y)
    If abuNova Then
        If UPG_NovaTry% Then ABL_Nova
    End If
End Sub

' Clears every enemy shot and blasts what's within novaRadius: ships and asteroids are
' destroyed, the boss loses novaBossDmg hit points.
Sub ABL_Nova
    Dim abnI As Integer, abnDX As Single, abnDY As Single, abnDZ As Single, abnR2 As Single
    abnR2 = novaRadius * novaRadius
    For abnI = 1 To MAX_EBULLETS
        If ebullets(abnI).active Then
            ebullets(abnI).active = 0
            FX_SpawnBurst ebullets(abnI).px, ebullets(abnI).py, ebullets(abnI).pz, 3, 0.08, 10, 5, _RGB(140, 230, 255)
        End If
    Next abnI
    For abnI = 1 To MAX_ENEMIES
        If enemies(abnI).active Then
            abnDX = enemies(abnI).px - player.px : abnDY = enemies(abnI).py - player.py : abnDZ = enemies(abnI).pz - player.pz
            If abnDX * abnDX + abnDY * abnDY + abnDZ * abnDZ <= abnR2 Then
                enemies(abnI).active = 0
                score = score + SCORE_ENEMY
                TELEM_EnemyKilled
                CR_Add crKill
                FX_SpawnBurst enemies(abnI).px, enemies(abnI).py, enemies(abnI).pz, 12, 0.25, 18, 8, _RGB(160, 230, 255)
            End If
        End If
    Next abnI
    For abnI = 1 To MAX_ASTEROIDS
        If asteroids(abnI).active Then
            abnDX = asteroids(abnI).px - player.px : abnDY = asteroids(abnI).py - player.py : abnDZ = asteroids(abnI).pz - player.pz
            If abnDX * abnDX + abnDY * abnDY + abnDZ * abnDZ <= abnR2 Then
                asteroids(abnI).active = 0
                CR_Add crAstKill
                FX_SpawnBurst asteroids(abnI).px, asteroids(abnI).py, asteroids(abnI).pz, 10, 0.2, 18, 8, _RGB(170, 140, 110)
            End If
        End If
    Next abnI
    If boss.active Then
        abnDX = boss.px - player.px : abnDY = boss.py - player.py : abnDZ = boss.pz - player.pz
        If abnDX * abnDX + abnDY * abnDY + abnDZ * abnDZ <= abnR2 Then
            boss.hp = boss.hp - novaBossDmg
            If boss.hp <= 0 Then BOSS_Defeat
        End If
    End If
    FX_SpawnBurst player.px, player.py, player.pz, 40, 0.5, 22, 8, _RGB(170, 240, 255)
    novaFxTimer = NOVA_FX_FRAMES
    fxShakeTimer = 10   ' no fxFlashTimer: that red flash means "you were hit"
    SND_Boom
End Sub

' Pulls power-up abI sideways toward the ship when it's ahead and within tractorR.
Sub ABL_Tractor (abtI As Integer)
    Dim abtDX As Single, abtDY As Single, abtDZ As Single
    abtDX = powerups(abtI).px - player.px
    abtDY = player.py - powerups(abtI).py
    abtDZ = player.pz - powerups(abtI).pz
    If PUP_InTractor%(abtDX, abtDY, abtDZ, tractorR) = 0 Then Exit Sub
    powerups(abtI).py = powerups(abtI).py + abtDY * tractorPull
    powerups(abtI).pz = powerups(abtI).pz + abtDZ * tractorPull
End Sub

Sub ABL_Draw
    Dim abdSX As Single, abdSY As Single, abdEX As Single, abdEY As Single
    Dim abdOk As Integer, abdOk2 As Integer, abdR As Single, abdF As Single, abdK As Integer, abdI As Integer
    _Dest backBuffer
    If ablHintTimer > 0 Then ABL_DrawHint
    ' nova: a ring racing out to the blast radius, fading as it goes
    If novaFxTimer > 0 Then
        abdF = 1 - novaFxTimer / NOVA_FX_FRAMES
        If novaFxTimer > NOVA_FX_FRAMES - 5 Then
            Line (0, 0)-(scrW - 1, scrH - 1), _RGBA(170, 240, 255, (novaFxTimer - NOVA_FX_FRAMES + 5) * 30), BF
        End If
        COMBAT_Project player.px, player.py, player.pz, abdSX, abdSY, abdOk
        COMBAT_Project player.px, player.py + novaRadius * abdF, player.pz, abdEX, abdEY, abdOk2
        If abdOk And abdOk2 Then
            abdR = Abs(abdSY - abdEY)
            If abdR > 400 Then abdR = 400
            For abdK = 0 To 3
                Circle (abdSX, abdSY), abdR - abdK * 2, _RGBA(170, 240, 255, Int((1 - abdF) * (220 - abdK * 45)))
            Next abdK
        End If
    End If
    ' tractor beam: a faint line to each power-up it's holding
    If tractorR > 0 Then
        For abdI = 1 To MAX_POWERUPS
            If powerups(abdI).active Then
                If PUP_InTractor%(powerups(abdI).px - player.px, powerups(abdI).py - player.py, powerups(abdI).pz - player.pz, tractorR) Then
                    COMBAT_Project player.px, player.py, player.pz, abdSX, abdSY, abdOk
                    COMBAT_Project powerups(abdI).px, powerups(abdI).py, powerups(abdI).pz, abdEX, abdEY, abdOk2
                    If abdOk And abdOk2 Then Line (abdSX, abdSY)-(abdEX, abdEY), _RGBA(120, 255, 160, 90)
                End If
            End If
        Next abdI
    End If
End Sub

' The launch hint: one centred line per newly bought ability, fading out at the end.
Sub ABL_DrawHint
    Dim abhA As Integer, abhLine As String, abhP As Integer, abhQ As Integer, abhY As Integer
    abhA = 255
    If ablHintTimer < 40 Then abhA = Int(255 * ablHintTimer / 40)
    abhY = 44 : abhP = 1
    Do While abhP <= Len(ablHintText)
        abhQ = InStr(abhP, ablHintText, Chr$(10))
        If abhQ = 0 Then abhQ = Len(ablHintText) + 1
        abhLine = Mid$(ablHintText, abhP, abhQ - abhP)
        Line (scrW \ 2 - Len(abhLine) * 4 - 5, abhY - 2)-(scrW \ 2 + Len(abhLine) * 4 + 4, abhY + 16), _RGBA(0, 10, 30, abhA * 3 \ 4), BF
        FONT_PrintCenteredAlpha fontPalette(11), backBuffer, abhLine, abhY, scrW, abhA
        abhY = abhY + 20
        abhP = abhQ + 1
    Loop
End Sub
