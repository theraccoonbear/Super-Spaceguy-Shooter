' wave.bas — per-frame difficulty scaling and enemy/asteroid/powerup spawning
'
' Call WAVE_Spawn once per frame from the main game loop.
' It handles the difficulty ramp, formation wave selection, and all object placement.
' All persistent state is DIM SHARED in sss.bas.
'
' Local variable prefix: wv*  (QB64-PE hoists Sub locals to module scope;
' all names must be unique across the compilation unit.)

Const SPAWN_INTERVAL_BASE = 7.0    ' base spawn interval (seconds)
Const SPAWN_INTERVAL_MIN  = 2.0    ' difficulty reduces interval by up to this
Const SPAWN_DIST_MIN      = 70     ' spawn ahead of player: min distance
Const SPAWN_DIST_VAR      = 30     ' spawn ahead of player: variance
Const SPAWN_SPREAD_Y      = 18     ' ±Y spawn spread
Const SPAWN_SPREAD_Z      = 22     ' ±Z spawn spread
Const DIFF_SPEED_SCALE    = 0.6    ' how much difficulty boosts enemy speed
Const EFIRE_INIT_MIN      = 2.5    ' enemy initial fire timer min (seconds)
Const EFIRE_INIT_VAR      = 2.0    ' enemy initial fire timer variance
Const ASTFIELD_INTERVAL   = 1.8    ' tt-ticks between asteroid patterns
Const ASTFIELD_LIFE       = 220    ' frames each asteroid lives; long enough to cross from far spawn

Sub WAVE_Spawn
    Dim wvOK       As Integer
    Dim wvCount    As Integer, wvMember As Integer
    Dim wvType     As Integer
    Dim wvPoolSize As Integer
    Dim wvCX As Single, wvCY As Single, wvCZ As Single, wvVX As Single
    Dim wvDX(0 To 4) As Single, wvDY(0 To 4) As Single, wvDZ(0 To 4) As Single
    Dim wvI As Integer
    Dim wvTypeName As String
    Dim wvAstProg As Single, wvAstInterval As Single, wvAstElapsed As Single

    diffTime  = diffTime + 0.025
    diffScale = diffTime / DIFF_RAMP_DURATION
    If diffScale > 1.0 Then diffScale = 1.0

    ' --- asteroid field level: pattern-based spawning, no enemies ---
    If levelType = LEVEL_ASTEROID Then
        If tt - astFieldStart >= ASTFIELD_DURATION And gameState = GS_PLAYING Then
            Dim wvFuelBonus As Long
            wvFuelBonus = INT(fuelLevel * 5)
            If wvFuelBonus > 0 Then
                score = score + wvFuelBonus
                scorePopVal = wvFuelBonus
                scorePopTimer = 45
                scorePopY = scrH * 0.4
            End If
            gameState     = GS_PLANET
            planetTimer   = 1
            MUS_SetCue "planet"
            planetCurrent = (planetCurrent Mod PLANET_COUNT) + 1
            planetNameIdx = (planetNameIdx Mod PLANET_COUNT) + 1
        End If
        wvAstElapsed = tt - astFieldStart
        If wvAstElapsed < 3.0 Then
            spawnTimer = 0  ' hold — empty space
        ElseIf wvAstElapsed < 12.0 Then
            ' approach phase: spawn far so asteroids appear as distant 2D blobs first
            If spawnTimer > 3.5 And gameState = GS_PLAYING Then
                spawnTimer = 0
                astSpawnXBias = 200.0 * (1.0 - (wvAstElapsed - 3.0) / 9.0)
                WAVE_SpawnAsteroidField
                astSpawnXBias = 0.0
            End If
        Else
            ' normal progressive density
            wvAstProg = wvAstElapsed / ASTFIELD_DURATION
            If wvAstProg > 1.0 Then wvAstProg = 1.0
            wvAstInterval = 3.0
            If wvAstProg > 0.67 And wvAstProg <= 0.82 Then
                wvAstInterval = 3.0 - ((wvAstProg - 0.67) / 0.15) * 2.0
            ElseIf wvAstProg > 0.82 Then
                wvAstInterval = 1.0 + ((wvAstProg - 0.82) / 0.18) * 3.0
            End If
            If spawnTimer > wvAstInterval And gameState = GS_PLAYING Then
                spawnTimer = 0
                WAVE_SpawnAsteroidField
            End If
        End If
        Exit Sub
    End If

    wvOK = (gameState = GS_PLAYING And boss.active = 0 And boss.warnTimer = 0)
    If spawnTimer > (SPAWN_INTERVAL_BASE - diffScale * SPAWN_INTERVAL_MIN) And wvOK Then
        spawnTimer = 0

        ' formation type pool grows each level: harder types unlock as stages progress
        Select Case levelNum
        Case 1   : wvPoolSize = 4  ' solo, arrow, hline, vcol
        Case 2   : wvPoolSize = 5  ' + pincer
        Case Else: wvPoolSize = 6  ' + vwedge
        End Select

        ' run 1-2 of the same formation type, then switch
        If waveCount <= 0 Then
            Do
                waveType = Int(RND * wvPoolSize)
            Loop While waveType = wavePrev
            wavePrev  = waveType
            waveCount = 1
        End If
        wvType    = waveType
        waveCount = waveCount - 1

        ' per-type size and level threshold for 3rd member
        Select Case wvType
        Case 0 : wvCount = 1 : wvTypeName = "solo"
        Case 1 : wvCount = 2 : wvTypeName = "arrow"  : If levelNum >= 3 Then wvCount = 3
        Case 2 : wvCount = 2 : wvTypeName = "hline"  : If levelNum >= 2 Then wvCount = 3
        Case 3 : wvCount = 2 : wvTypeName = "vcol"   : If levelNum >= 3 Then wvCount = 3
        Case 4 : wvCount = 2 : wvTypeName = "pincer" : If levelNum >= 5 Then wvCount = 3 : wvDX(2) = 0 : wvDY(2) = 0 : wvDZ(2) = 0
        Case Else : wvCount = 2 : wvTypeName = "vwedge" : If levelNum >= 4 Then wvCount = 3
        End Select
        If debugMode Then DBG_Print "[wave] " + wvTypeName + "  n=" + LTrim$(Str$(wvCount)) + "  score=" + LTrim$(Str$(score))

        wvCX = player.px + SPAWN_DIST_MIN + RND * SPAWN_DIST_VAR
        wvCY = player.py + (RND * (SPAWN_SPREAD_Y * 2)) - SPAWN_SPREAD_Y
        wvCZ = player.pz + (RND * (SPAWN_SPREAD_Z * 2)) - SPAWN_SPREAD_Z
        ' per-type speed: solo=slow, pincer/vwedge=fast
        Select Case wvType
        Case 0    : wvVX = -(0.06 + RND * 0.04)
        Case 1    : wvVX = -(0.09 + RND * 0.05)
        Case 2    : wvVX = -(0.07 + RND * 0.04)
        Case 3    : wvVX = -(0.09 + RND * 0.04)
        Case 4    : wvVX = -(0.13 + RND * 0.05)
        Case Else : wvVX = -(0.14 + RND * 0.06)
        End Select
        wvVX = wvVX * (1.0 + diffScale * DIFF_SPEED_SCALE)
        spawnFlashPX = wvCX : spawnFlashPY = wvCY : spawnFlashPZ = wvCZ
        spawnFlashTimer = 9

        Select Case wvType
        Case 0  ' solo
            wvDX(0) = 0 : wvDY(0) =  0 : wvDZ(0) =   0
        Case 1  ' arrow — tip leads, wings stagger back
            wvDX(0) = 0 : wvDY(0) =  0 : wvDZ(0) =   0
            wvDX(1) = 6 : wvDY(1) =  4 : wvDZ(1) =   7
            wvDX(2) = 6 : wvDY(2) = -4 : wvDZ(2) =  -7
        Case 2  ' horizontal line — sweeps across Z
            wvDX(0) = 0 : wvDY(0) =  0 : wvDZ(0) =  -8
            wvDX(1) = 0 : wvDY(1) =  0 : wvDZ(1) =   0
            wvDX(2) = 0 : wvDY(2) =  0 : wvDZ(2) =   8
        Case 3  ' vertical column — stacked in Y
            wvDX(0) = 0 : wvDY(0) = -9 : wvDZ(0) =   0
            wvDX(1) = 0 : wvDY(1) =  0 : wvDZ(1) =   0
            wvDX(2) = 0 : wvDY(2) =  9 : wvDZ(2) =   0
        Case 4  ' pincer — cross paths from opposite corners
            wvDX(0) = 0 : wvDY(0) =  12 : wvDZ(0) = -16
            wvDX(1) = 0 : wvDY(1) = -12 : wvDZ(1) =  16
        Case 5  ' V-wedge — tip arrives first, wings stagger back
            wvDX(0) = 0 : wvDY(0) =  0 : wvDZ(0) =   0
            wvDX(1) = 6 : wvDY(1) =  5 : wvDZ(1) =   9
            wvDX(2) = 6 : wvDY(2) = -5 : wvDZ(2) =  -9
        End Select

        For wvMember = 0 To wvCount - 1
            For wvI = 1 To MAX_ENEMIES
                If enemies(wvI).active = 0 Then
                    enemies(wvI).active  = -1
                    enemies(wvI).meshIdx = fTypeToMesh(wvType)
                    enemies(wvI).px = wvCX + wvDX(wvMember)
                    enemies(wvI).py = wvCY + wvDY(wvMember)
                    enemies(wvI).pz = wvCZ + wvDZ(wvMember)
                    enemies(wvI).vx = wvVX
                    enemies(wvI).vy = 0
                    enemies(wvI).vz = 0
                    enemies(wvI).dry = 0
                    enemies(wvI).scl = 0.9 + RND * 0.4
                    enemies(wvI).strafeCool = ENEMY_STRAFE_COOL + Int(RND * 60)
                    enemyFireTimer(wvI) = EFIRE_INIT_MIN + RND * EFIRE_INIT_VAR
                    Exit For
                End If
            Next wvI
        Next wvMember

        ' one asteroid per combat wave
        For wvI = 1 To MAX_ASTEROIDS
            If asteroids(wvI).active = 0 Then
                asteroids(wvI).active  = -1
                asteroids(wvI).meshIdx = MESH_ASTEROID
                asteroids(wvI).px  = player.px + 45 + RND * 20
                asteroids(wvI).py  = player.py + (RND * 140) - 70
                asteroids(wvI).pz  = player.pz + (RND * 180) - 90
                asteroids(wvI).vx         = -(0.04 + RND * 0.05)
                asteroids(wvI).vy         = 0
                asteroids(wvI).vz         = 0
                asteroids(wvI).drx        = (RND - 0.5) * 2
                asteroids(wvI).dry        = (RND - 0.5) * 2
                asteroids(wvI).drz        = (RND - 0.5) * 2
                asteroids(wvI).scl        = 0.7 + RND * 0.9
                asteroids(wvI).life       = 0  ' combat: expire by px < -5 only
                asteroids(wvI).strafeCool = Int(RND * 6)
                Exit For
            End If
        Next wvI

        ' powerup (rare)
        If Int(RND * 6) = 0 Then
            For wvI = 1 To MAX_POWERUPS
                If powerups(wvI).active = 0 Then
                    powerups(wvI).active  = -1
                    powerups(wvI).meshIdx = MESH_POWERUP
                    powerups(wvI).px  =  26 + RND * 6
                    powerups(wvI).py  = player.py + (RND * 80)  - 40
                    powerups(wvI).pz  = player.pz + (RND * 100) - 50
                    powerups(wvI).vx  = -0.05
                    powerups(wvI).dry = 2.0
                    powerups(wvI).drz = 1.5
                    powerups(wvI).scl = 1.0
                    Exit For
                End If
            Next wvI
        End If
    End If
End Sub

' Spawn one asteroid field pattern (called every ASTFIELD_INTERVAL seconds).
' Cycles through 4 patterns: dense cloud, Y-corridor, staggered wave, cluster pack.
' Local prefix: wvaf* (names must be unique across the compilation unit)
Sub WAVE_SpawnAsteroidField
    Static wvafPat As Integer
    Dim wvafI As Integer, wvafJ As Integer, wvafN As Integer
    Dim wvafCX As Single, wvafCY As Single, wvafCZ As Single
    Dim wvafGap As Single
    Dim wvafXO(0 To 7) As Single, wvafYO(0 To 7) As Single, wvafZO(0 To 7) As Single
    Dim wvafVY As Single, wvafVZ As Single, wvafScl As Single, wvafTint As Integer, wvafErratic As Integer

    wvafCX = player.px + 150 + RND * 30 + astSpawnXBias
    If astForceTarget Then
        wvafCY    = player.py + (RND * 3) - 1.5
        wvafCZ    = player.pz + (RND * 3) - 1.5
        astForceTarget = 0
        astIdleTimer   = 0
    Else
        wvafCY = player.py + (RND * 5) - 2.5
        wvafCZ = player.pz + (RND * 5) - 2.5
    End If
    wvafN  = 0

    Select Case wvafPat
    Case 0  ' dense cloud: asteroids huddled close to the flight corridor
        wvafXO(0) =  0 : wvafYO(0) =  0 : wvafZO(0) =  0
        wvafXO(1) =  5 : wvafYO(1) =  4 : wvafZO(1) =  3
        wvafXO(2) =  5 : wvafYO(2) = -4 : wvafZO(2) = -3
        wvafXO(3) = 10 : wvafYO(3) =  2 : wvafZO(3) = -4
        wvafXO(4) = 10 : wvafYO(4) = -2 : wvafZO(4) =  4
        wvafXO(5) = 15 : wvafYO(5) = -1 : wvafZO(5) =  5
        wvafXO(6) =  3 : wvafYO(6) =  3 : wvafZO(6) = -5
        wvafXO(7) =  8 : wvafYO(7) = -3 : wvafZO(7) =  2
        wvafN = 8

    Case 1  ' Y corridor: tighter walls above/below, 2 stragglers threading the gap
        wvafGap = player.py + (RND * 10) - 5
        wvafCY  = wvafGap
        ' upper wall
        wvafXO(0) =  0 : wvafYO(0) =  7 : wvafZO(0) = -8
        wvafXO(1) =  7 : wvafYO(1) =  9 : wvafZO(1) =  0
        wvafXO(2) = 14 : wvafYO(2) =  7 : wvafZO(2) =  8
        ' lower wall
        wvafXO(3) =  0 : wvafYO(3) = -7 : wvafZO(3) = -8
        wvafXO(4) =  7 : wvafYO(4) = -9 : wvafZO(4) =  0
        wvafXO(5) = 14 : wvafYO(5) = -7 : wvafZO(5) =  8
        ' gap stragglers
        wvafXO(6) = 18 : wvafYO(6) =  2 : wvafZO(6) =  4
        wvafXO(7) =  4 : wvafYO(7) = -2 : wvafZO(7) = -4
        wvafN = 8

    Case 2  ' staggered wave: alternating Y through the tunnel, moderate Z spread
        wvafXO(0) =  0 : wvafYO(0) =  7 : wvafZO(0) = -12
        wvafXO(1) =  7 : wvafYO(1) = -7 : wvafZO(1) = -6
        wvafXO(2) = 14 : wvafYO(2) =  7 : wvafZO(2) =  0
        wvafXO(3) = 21 : wvafYO(3) = -7 : wvafZO(3) =  6
        wvafXO(4) = 28 : wvafYO(4) =  7 : wvafZO(4) =  12
        wvafXO(5) = 35 : wvafYO(5) = -7 : wvafZO(5) = -12
        wvafXO(6) = 42 : wvafYO(6) =  7 : wvafZO(6) =  6
        wvafXO(7) = 14 : wvafYO(7) =  7 : wvafZO(7) = -6
        wvafN = 8

    Case 3  ' cluster pack: 4 pairs threading through Z, tight Y
        wvafXO(0) =  0 : wvafYO(0) =  4 : wvafZO(0) = -12
        wvafXO(1) =  8 : wvafYO(1) = -4 : wvafZO(1) = -10
        wvafXO(2) =  0 : wvafYO(2) =  4 : wvafZO(2) =   0
        wvafXO(3) =  8 : wvafYO(3) = -4 : wvafZO(3) =   2
        wvafXO(4) =  0 : wvafYO(4) =  4 : wvafZO(4) =  12
        wvafXO(5) =  8 : wvafYO(5) = -4 : wvafZO(5) =  10
        wvafXO(6) = 16 : wvafYO(6) =  4 : wvafZO(6) = -6
        wvafXO(7) = 20 : wvafYO(7) = -4 : wvafZO(7) =   9
        wvafN = 8
    End Select

    For wvafJ = 0 To wvafN - 1
        ' per-asteroid trajectory: most drift slightly, 1-in-10 are erratic cross-cutters
        If Int(RND * 10) = 0 Then
            wvafVY = (RND - 0.5) * 0.35
            wvafVZ = (RND - 0.5) * 0.35
            wvafErratic = -1
        Else
            wvafVY = (RND - 0.5) * 0.06
            wvafVZ = (RND - 0.5) * 0.06
            wvafErratic = 0
        End If
        If Int(RND * 5) = 0 Then
            wvafScl = 3.0 + RND * 1.5
        Else
            wvafScl = 0.5 + RND * 1.6
        End If
        wvafTint = Int(RND * 6)
        For wvafI = 1 To MAX_ASTEROIDS
            If asteroids(wvafI).active = 0 Then
                asteroids(wvafI).active     = -1
                asteroids(wvafI).meshIdx    = MESH_ASTEROID
                asteroids(wvafI).px         = wvafCX + wvafXO(wvafJ)
                If wvafErratic Then asteroids(wvafI).px = asteroids(wvafI).px + 50
                asteroids(wvafI).py         = wvafCY + wvafYO(wvafJ)
                asteroids(wvafI).pz         = wvafCZ + wvafZO(wvafJ)
                If Int(RND * 6) = 0 Then
                    asteroids(wvafI).vx = -(1.2 + RND * 0.3)
                Else
                    asteroids(wvafI).vx = -(0.45 + RND * 0.25)
                End If
                asteroids(wvafI).vy         = wvafVY
                asteroids(wvafI).vz         = wvafVZ
                asteroids(wvafI).drx        = (RND - 0.5) * 2
                asteroids(wvafI).dry        = (RND - 0.5) * 2
                asteroids(wvafI).drz        = (RND - 0.5) * 2
                asteroids(wvafI).scl        = wvafScl
                asteroids(wvafI).life = 0  ' expire by position (px < player.px-20), not timer
                asteroids(wvafI).strafeCool = wvafTint
                Exit For
            End If
        Next wvafI
    Next wvafJ

    If debugMode Then DBG_Print "[astfield] pat=" + LTrim$(Str$(wvafPat)) + "  n=" + LTrim$(Str$(wvafN)) + "  t=" + LTrim$(Str$(tt - astFieldStart))
    wvafPat = (wvafPat + 1) Mod 4
End Sub
