' wave.bas — per-frame difficulty scaling and enemy/asteroid/powerup spawning
'
' Call WAVE_Spawn once per frame from the main game loop.
' It handles the difficulty ramp, formation wave selection, and all object placement.
' All persistent state is DIM SHARED in sss.bas.
'
' Local variable prefix: wv*  (QB64-PE hoists Sub locals to module scope;
' all names must be unique across the compilation unit.)

Sub WAVE_Spawn
    Dim wvOK     As Integer
    Dim wvCount  As Integer, wvMember As Integer
    Dim wvType   As Integer
    Dim wvCX As Single, wvCY As Single, wvCZ As Single, wvVX As Single
    Dim wvDX(0 To 4) As Single, wvDY(0 To 4) As Single, wvDZ(0 To 4) As Single
    Dim wvI As Integer
    Dim wvTypeName As String

    diffTime  = diffTime + 0.025
    diffScale = diffTime / DIFF_RAMP_DURATION
    If diffScale > 1.0 Then diffScale = 1.0

    wvOK = (gameState = GS_PLAYING And boss.active = 0 And bossWarnTimer = 0)
    If spawnTimer > (SPAWN_INTERVAL_BASE - diffScale * SPAWN_INTERVAL_MIN) And wvOK Then
        spawnTimer = 0

        ' run 1-2 of the same formation type, then switch
        If waveCount <= 0 Then
            Do
                waveType = Int(RND * 6)
            Loop While waveType = wavePrev
            wavePrev  = waveType
            waveCount = 1
        End If
        wvType    = waveType
        waveCount = waveCount - 1
        Select Case wvType
        Case 0 : wvCount = 1 : wvTypeName = "solo"
        Case 1 : wvCount = 2 : wvTypeName = "arrow"
        Case 2 : wvCount = 2 : wvTypeName = "hline"
        Case 3 : wvCount = 2 : wvTypeName = "vcol"
        Case 4 : wvCount = 2 : wvTypeName = "pincer"
        Case Else : wvCount = 2 : wvTypeName = "vwedge"
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
                    enemies(wvI).dry = 0
                    enemies(wvI).scl = 0.9 + RND * 0.4
                    enemyFireTimer(wvI) = EFIRE_INIT_MIN + RND * EFIRE_INIT_VAR
                    Exit For
                End If
            Next wvI
        Next wvMember

        ' asteroid (spawn less frequently)
        If Int(RND * 3) = 0 Then
            For wvI = 1 To MAX_ASTEROIDS
                If asteroids(wvI).active = 0 Then
                    asteroids(wvI).active  = -1
                    asteroids(wvI).meshIdx = MESH_ASTEROID
                    asteroids(wvI).px = player.px + 45 + RND * 20
                    asteroids(wvI).py = player.py + (RND * 140) - 70
                    asteroids(wvI).pz = player.pz + (RND * 180) - 90
                    asteroids(wvI).vx = -(0.04 + RND * 0.05)
                    asteroids(wvI).drx = (RND - 0.5) * 2
                    asteroids(wvI).dry = (RND - 0.5) * 2
                    asteroids(wvI).drz = (RND - 0.5) * 2
                    asteroids(wvI).scl = 0.7 + RND * 0.9
                    Exit For
                End If
            Next wvI
        End If

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
