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
Const ASTFIELD_DURATION   = 90.0   ' seconds to survive the asteroid field
Const ASTFIELD_INTERVAL   = 4.0    ' seconds between asteroid patterns
Const ASTFIELD_LIFE       = 480    ' frames each asteroid lives (~12s at 40fps)

Sub WAVE_Spawn
    Dim wvOK       As Integer
    Dim wvCount    As Integer, wvMember As Integer
    Dim wvType     As Integer
    Dim wvPoolSize As Integer
    Dim wvCX As Single, wvCY As Single, wvCZ As Single, wvVX As Single
    Dim wvDX(0 To 4) As Single, wvDY(0 To 4) As Single, wvDZ(0 To 4) As Single
    Dim wvI As Integer
    Dim wvTypeName As String

    diffTime  = diffTime + 0.025
    diffScale = diffTime / DIFF_RAMP_DURATION
    If diffScale > 1.0 Then diffScale = 1.0

    ' --- asteroid field level: pattern-based spawning, no enemies ---
    If levelType = LEVEL_ASTEROID Then
        If tt - astFieldStart >= ASTFIELD_DURATION And gameState = GS_PLAYING Then
            gameState     = GS_PLANET
            planetTimer   = 1
            MUS_SetCue "planet"
            planetCurrent = (planetCurrent Mod PLANET_COUNT) + 1
            planetNameIdx = (planetNameIdx Mod PLANET_COUNT) + 1
        End If
        If spawnTimer > ASTFIELD_INTERVAL And gameState = GS_PLAYING Then
            spawnTimer = 0
            WAVE_SpawnAsteroidField
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
                asteroids(wvI).vx  = -(0.04 + RND * 0.05)
                asteroids(wvI).drx = (RND - 0.5) * 2
                asteroids(wvI).dry = (RND - 0.5) * 2
                asteroids(wvI).drz = (RND - 0.5) * 2
                asteroids(wvI).scl = 0.7 + RND * 0.9
                asteroids(wvI).life = 0  ' combat: expire by px < -5 only
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

    wvafCX = player.px + 65 + RND * 25
    wvafCY = player.py + (RND * 18) - 9
    wvafCZ = player.pz + (RND * 22) - 11
    wvafN  = 0

    Select Case wvafPat
    Case 0  ' dense cloud: 5 asteroids huddled in a tight sphere
        wvafXO(0) =  0 : wvafYO(0) =  0 : wvafZO(0) =  0
        wvafXO(1) =  5 : wvafYO(1) =  7 : wvafZO(1) =  5
        wvafXO(2) =  5 : wvafYO(2) = -7 : wvafZO(2) = -5
        wvafXO(3) = 10 : wvafYO(3) =  4 : wvafZO(3) = -7
        wvafXO(4) = 10 : wvafYO(4) = -4 : wvafZO(4) =  7
        wvafN = 5

    Case 1  ' Y corridor: two walls above/below a random gap
        wvafGap = player.py + (RND * 18) - 9
        wvafCY  = wvafGap
        ' upper wall
        wvafXO(0) =  0 : wvafYO(0) =  12 : wvafZO(0) = -14
        wvafXO(1) =  7 : wvafYO(1) =  16 : wvafZO(1) =   0
        wvafXO(2) = 14 : wvafYO(2) =  12 : wvafZO(2) =  14
        ' lower wall
        wvafXO(3) =  0 : wvafYO(3) = -12 : wvafZO(3) = -14
        wvafXO(4) =  7 : wvafYO(4) = -16 : wvafZO(4) =   0
        wvafXO(5) = 14 : wvafYO(5) = -12 : wvafZO(5) =  14
        wvafN = 6

    Case 2  ' staggered wave: alternating Y, spread across Z and staggered in X
        wvafXO(0) =  0 : wvafYO(0) =  13 : wvafZO(0) = -22
        wvafXO(1) =  7 : wvafYO(1) = -13 : wvafZO(1) = -11
        wvafXO(2) = 14 : wvafYO(2) =  13 : wvafZO(2) =   0
        wvafXO(3) = 21 : wvafYO(3) = -13 : wvafZO(3) =  11
        wvafXO(4) = 28 : wvafYO(4) =  13 : wvafZO(4) =  22
        wvafN = 5

    Case 3  ' cluster pack: 3 pairs spread across Z, each pair offset in Y
        wvafXO(0) =  0 : wvafYO(0) =  7 : wvafZO(0) = -22
        wvafXO(1) =  8 : wvafYO(1) = -7 : wvafZO(1) = -18
        wvafXO(2) =  0 : wvafYO(2) =  7 : wvafZO(2) =   0
        wvafXO(3) =  8 : wvafYO(3) = -7 : wvafZO(3) =   4
        wvafXO(4) =  0 : wvafYO(4) =  7 : wvafZO(4) =  22
        wvafXO(5) =  8 : wvafYO(5) = -7 : wvafZO(5) =  18
        wvafN = 6
    End Select

    For wvafJ = 0 To wvafN - 1
        For wvafI = 1 To MAX_ASTEROIDS
            If asteroids(wvafI).active = 0 Then
                asteroids(wvafI).active  = -1
                asteroids(wvafI).meshIdx = MESH_ASTEROID
                asteroids(wvafI).px  = wvafCX + wvafXO(wvafJ)
                asteroids(wvafI).py  = wvafCY + wvafYO(wvafJ)
                asteroids(wvafI).pz  = wvafCZ + wvafZO(wvafJ)
                asteroids(wvafI).vx  = -(0.06 + RND * 0.04)
                asteroids(wvafI).drx = (RND - 0.5) * 2
                asteroids(wvafI).dry = (RND - 0.5) * 2
                asteroids(wvafI).drz = (RND - 0.5) * 2
                asteroids(wvafI).scl = 0.8 + RND * 0.6
                asteroids(wvafI).life = ASTFIELD_LIFE
                Exit For
            End If
        Next wvafI
    Next wvafJ

    If debugMode Then DBG_Print "[astfield] pat=" + LTrim$(Str$(wvafPat)) + "  n=" + LTrim$(Str$(wvafN)) + "  t=" + LTrim$(Str$(tt - astFieldStart))
    wvafPat = (wvafPat + 1) Mod 4
End Sub
