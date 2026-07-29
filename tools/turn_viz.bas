$RESIZE:ON
'$INCLUDE:'tool_shell.bas'

' turn_viz.bas -- 2D top-down visualizer for boss flyover turn (states 7-9)
'
' Simulates the state-machine math from behavior.bas / boss.bas in a top-down
' XZ view so you can inspect the path, yaw, AABB clearance, and fire windows
' without launching the full game.
'
' Build: from repo root:
'   ./tools/buildqb tools/turn_viz.bas
' Run:   builds/turn_viz
'
' Controls:
'   SPACE       pause / resume
'   N           step one frame while paused
'   R           reset simulation
'   1 / 2       force turn RIGHT (+Z) or LEFT (-Z)
'   F           toggle fast mode (10x speed)
'   ESC         quit

' ── constants (mirror behavior.bas / boss.bas) ───────────────────────────────
Const BOSS_FLYOVER_REAR   = 20.0
Const BOSS_FLYOVER_FRAMES = 80
Const BOSS_FWD_CHG_SPD    = 0.60
Const BOSS_FWD_CHG_X      = 44.0
Const BOSS_TURN_SPD       = 0.018
Const BOSS_TURN_CX_OFF    = 32.0
Const BOSS_TURN_RAD_X     = 12.0
Const BOSS_TURN_RAD_Z     = 20.0
Const BOSS_COMBAT_DIST    = 20.0
Const BOSS_ATTITUDE_LERP  = 0.07
Const VZPI = 3.14159265358979

' Approximate AABB half-extents (update if you know the real values)
Const VIZ_BOSS_HY  = 2.0
Const VIZ_BOSS_HZ  = 2.5
Const VIZ_PLAYER_HY = 0.8
Const VIZ_PLAYER_HZ = 0.8

' Screen layout
Const VIZ_W = 1100
Const VIZ_H = 720
Const VIZ_PX_SC = 200.0    ' screen X of player (world origin)
Const VIZ_PZ_SC = 360.0    ' screen Y of player (world Z=0)
Const VIZ_SCALE = 10.0     ' pixels per world unit

' ── shared simulation state ───────────────────────────────────────────────────
Dim Shared vizBossX As Single, vizBossZ As Single
Dim Shared vizBossRy As Single
Dim Shared vizBossMoveTimer As Single
Dim Shared vizBossArcAngle As Single
Dim Shared vizBossState As Integer
Dim Shared vizBossFireTimer As Single
Dim Shared vizTurnDir As Integer
Dim Shared vizPrevX As Single, vizPrevZ As Single
Dim Shared vizVx As Single, vizVz As Single
Dim Shared vizTgtRy As Single
Dim Shared vizPlayerX As Single, vizPlayerZ As Single
Dim Shared vizFrame As Integer
Dim Shared vizPaused As Integer
Dim Shared vizFastMode As Integer
Dim Shared vizFireFlash As Integer

Const VIZ_TRAIL_MAX = 400
Dim Shared vizTrailX(1 To VIZ_TRAIL_MAX) As Single
Dim Shared vizTrailZ(1 To VIZ_TRAIL_MAX) As Single
Dim Shared vizTrailState(1 To VIZ_TRAIL_MAX) As Integer
Dim Shared vizTrailFire(1 To VIZ_TRAIL_MAX) As Integer
Dim Shared vizTrailHead As Integer

' coordinate helpers: inlined as macros -- SX(world_x), SZ(world_z)
' SX = VIZ_PX_SC + x * VIZ_SCALE
' SZ = VIZ_PZ_SC - z * VIZ_SCALE

' ── draw helpers ─────────────────────────────────────────────────────────────
Sub VizAABB(acx As Single, acz As Single, ahw As Single, ahh As Single, acol As Long)
    Dim aSX As Single : aSX = VIZ_PX_SC + acx * VIZ_SCALE
    Dim aSZ As Single : aSZ = VIZ_PZ_SC - acz * VIZ_SCALE
    Dim aSW As Single : aSW = ahw * VIZ_SCALE
    Dim aSH As Single : aSH = ahh * VIZ_SCALE
    Line (aSX - aSW, aSZ - aSH)-(aSX + aSW, aSZ + aSH), acol, B
End Sub

Sub VizArrow(arCX As Single, arCZ As Single, arAngleDeg As Single, arCol As Long)
    Dim arRad As Single : arRad = arAngleDeg * (VZPI / 180.0)
    Dim arNdx As Single : arNdx = -Cos(-arRad)
    Dim arNdz As Single : arNdz = Sin(-arRad)
    Dim arSX As Single : arSX = VIZ_PX_SC + arCX * VIZ_SCALE
    Dim arSZ As Single : arSZ = VIZ_PZ_SC - arCZ * VIZ_SCALE
    Dim arEx As Single : arEx = arSX + arNdx * 18
    Dim arEz As Single : arEz = arSZ + arNdz * 18
    Line (arSX, arSZ)-(arEx, arEz), arCol
    Dim arP2X As Single : arP2X = arEx - arNdx * 5 + arNdz * 4
    Dim arP2Z As Single : arP2Z = arEz - arNdz * 5 - arNdx * 4
    Dim arP3X As Single : arP3X = arEx - arNdx * 5 - arNdz * 4
    Dim arP3Z As Single : arP3Z = arEz - arNdz * 5 + arNdx * 4
    Line (arEx, arEz)-(arP2X, arP2Z), arCol
    Line (arEx, arEz)-(arP3X, arP3Z), arCol
End Sub

' ── simulation reset ─────────────────────────────────────────────────────────
Sub VizReset()
    vizPlayerX = 0.0 : vizPlayerZ = 0.0
    vizBossX = vizPlayerX - BOSS_FLYOVER_REAR
    vizBossZ = vizPlayerZ
    vizBossRy = 180.0
    vizBossMoveTimer = BOSS_FLYOVER_FRAMES
    vizBossArcAngle = 0.0
    vizBossState = 7
    vizBossFireTimer = 0.3
    vizTrailHead = 0
    vizFrame = 0
    vizFireFlash = 0
    Dim vri As Integer
    For vri = 1 To VIZ_TRAIL_MAX
        vizTrailX(vri) = 0 : vizTrailZ(vri) = 0
        vizTrailState(vri) = 0 : vizTrailFire(vri) = 0
    Next vri
End Sub

' ── one simulation step ───────────────────────────────────────────────────────
Sub VizStep()
    vizFrame = vizFrame + 1
    vizPrevX = vizBossX : vizPrevZ = vizBossZ

    Dim vstFlyOff As Single
    Dim vstTgtX As Single, vstTgtZ As Single
    Dim vstFired As Integer : vstFired = 0

    Select Case vizBossState
    Case 7  ' rear dwell
        vizBossZ = vizBossZ + (vizPlayerZ - vizBossZ) * 0.05
        vizBossMoveTimer = vizBossMoveTimer - 1
        If vizBossMoveTimer <= 0 Then
            vizBossArcAngle = VZPI
            vizBossState = 8
        End If
        vizBossFireTimer = vizBossFireTimer - 0.025
        If vizBossFireTimer <= 0 Then vstFired = -1 : vizBossFireTimer = 1.5

    Case 8  ' forward charge -- fly ABOVE player; fire only after overtaking
        vstFlyOff = VIZ_BOSS_HY + VIZ_PLAYER_HY + 1.0   ' Y clearance (not shown in top-down, but noted)
        vizBossZ = vizBossZ + (vizPlayerZ - vizBossZ) * 0.06
        vizBossX = vizBossX + BOSS_FWD_CHG_SPD
        If vizBossX >= vizPlayerX + BOSS_FWD_CHG_X Then
            vizBossX = vizPlayerX + BOSS_FWD_CHG_X
            vizBossArcAngle = 0
            vizBossFireTimer = 0.5
            vizBossState = 9
        End If
        If vizBossX > vizPlayerX Then
            vizBossFireTimer = vizBossFireTimer - 0.025
            If vizBossFireTimer <= 0 Then vstFired = -1 : vizBossFireTimer = 1.2
        End If

    Case 9  ' dramatic turn
        vizBossArcAngle = vizBossArcAngle + BOSS_TURN_SPD
        vstTgtX = vizPlayerX + BOSS_TURN_CX_OFF + Cos(vizBossArcAngle) * BOSS_TURN_RAD_X
        vstTgtZ = vizPlayerZ + Sin(vizBossArcAngle) * BOSS_TURN_RAD_Z * vizTurnDir
        vizBossX = vizBossX + (vstTgtX - vizBossX) * 0.14
        vizBossZ = vizBossZ + (vstTgtZ - vizBossZ) * 0.14
        If vizBossArcAngle >= VZPI Then
            vizBossX = vizPlayerX + BOSS_COMBAT_DIST
            vizBossZ = vizPlayerZ
            vizTurnDir = vizTurnDir * -1
            If vizTurnDir = 0 Then vizTurnDir = 1
            vizBossMoveTimer = BOSS_FLYOVER_FRAMES
            vizBossFireTimer = 0.3
            vizBossState = 7
        End If
    End Select

    vizVx = vizBossX - vizPrevX
    vizVz = vizBossZ - vizPrevZ

    If vizBossState >= 7 And vizBossState <= 8 Then
        vizTgtRy = 180
    ElseIf vizBossState = 9 Then
        vizTgtRy = -_ATAN2(Cos(vizBossArcAngle) * BOSS_TURN_RAD_Z * vizTurnDir, Sin(vizBossArcAngle) * BOSS_TURN_RAD_X) * (180.0 / VZPI)
    Else
        vizTgtRy = -vizVz * 35
        If vizTgtRy > 28 Then vizTgtRy = 28
        If vizTgtRy < -28 Then vizTgtRy = -28
    End If
    vizBossRy = vizBossRy + (vizTgtRy - vizBossRy) * BOSS_ATTITUDE_LERP

    vizTrailHead = vizTrailHead + 1
    If vizTrailHead > VIZ_TRAIL_MAX Then vizTrailHead = 1
    vizTrailX(vizTrailHead) = vizBossX
    vizTrailZ(vizTrailHead) = vizBossZ
    vizTrailState(vizTrailHead) = vizBossState
    vizTrailFire(vizTrailHead) = vstFired
    If vstFired Then vizFireFlash = 8
    If vizFireFlash > 0 Then vizFireFlash = vizFireFlash - 1
End Sub

' ── draw the full scene ───────────────────────────────────────────────────────
Sub VizDraw()
    TOOL_Cls _RGB(10, 10, 20)

    Line (VIZ_W - 260, 0)-(VIZ_W - 1, VIZ_H - 1), _RGB(20, 20, 35), BF
    Line (VIZ_W - 260, 0)-(VIZ_W - 1, VIZ_H - 1), _RGB(60, 60, 90), B

    _PrintString (10, 10), "BOSS FLYOVER VISUALIZER  [top-down: X right, Z up]"
    _PrintString (10, 28), "SPACE=pause  N=step  R=reset  1/2=force dir  F=fast  ESC=quit"

    Dim dsGi As Integer
    For dsGi = -6 To 6
        Dim dsGx As Single : dsGx = VIZ_PX_SC + dsGi * 10 * VIZ_SCALE
        Dim dsGz As Single : dsGz = VIZ_PZ_SC - dsGi * 10 * VIZ_SCALE
        Line (dsGx, 0)-(dsGx, VIZ_H), _RGB(30, 30, 50)
        Line (0, dsGz)-(VIZ_W - 270, dsGz), _RGB(30, 30, 50)
    Next dsGi
    Line (VIZ_PX_SC - 70*VIZ_SCALE, VIZ_PZ_SC)-(VIZ_PX_SC + 70*VIZ_SCALE, VIZ_PZ_SC), _RGB(50, 50, 70)
    Line (VIZ_PX_SC, VIZ_PZ_SC + 40*VIZ_SCALE)-(VIZ_PX_SC, VIZ_PZ_SC - 40*VIZ_SCALE), _RGB(50, 50, 70)
    _PrintString (VIZ_PX_SC + 65*VIZ_SCALE + 2, VIZ_PZ_SC - 8), "X"
    _PrintString (VIZ_PX_SC + 2, VIZ_PZ_SC - 38*VIZ_SCALE - 8), "Z"

    ' combat range ring
    Dim dsCi As Integer
    Dim dsPrevCSX As Single, dsPrevCSZ As Single
    For dsCi = 0 To 360 Step 5
        Dim dsAng As Single : dsAng = dsCi * (VZPI / 180.0)
        Dim dsCpWX As Single : dsCpWX = vizPlayerX + Cos(dsAng) * BOSS_COMBAT_DIST
        Dim dsCpWZ As Single : dsCpWZ = vizPlayerZ + Sin(dsAng) * BOSS_COMBAT_DIST
        Dim dsCpSX As Single : dsCpSX = VIZ_PX_SC + dsCpWX * VIZ_SCALE
        Dim dsCpSZ As Single : dsCpSZ = VIZ_PZ_SC - dsCpWZ * VIZ_SCALE
        If dsCi > 0 Then Line (dsPrevCSX, dsPrevCSZ)-(dsCpSX, dsCpSZ), _RGB(40, 55, 40)
        dsPrevCSX = dsCpSX : dsPrevCSZ = dsCpSZ
    Next dsCi

    ' AABB clearance boundary (Z axis)
    Dim dsClrZ As Single : dsClrZ = VIZ_BOSS_HZ + VIZ_PLAYER_HZ + 0.5
    Line (VIZ_PX_SC - 5*VIZ_SCALE, VIZ_PZ_SC - dsClrZ*VIZ_SCALE)-(VIZ_PX_SC + (BOSS_FWD_CHG_X+5)*VIZ_SCALE, VIZ_PZ_SC - dsClrZ*VIZ_SCALE), _RGBA(180, 60, 60, 120)
    Line (VIZ_PX_SC - 5*VIZ_SCALE, VIZ_PZ_SC + dsClrZ*VIZ_SCALE)-(VIZ_PX_SC + (BOSS_FWD_CHG_X+5)*VIZ_SCALE, VIZ_PZ_SC + dsClrZ*VIZ_SCALE), _RGBA(180, 60, 60, 120)

    ' player
    VizAABB vizPlayerX, vizPlayerZ, VIZ_PLAYER_HZ, VIZ_PLAYER_HY, _RGB(60, 200, 80)
    _PrintString (VIZ_PX_SC + vizPlayerX*VIZ_SCALE + 5, VIZ_PZ_SC - vizPlayerZ*VIZ_SCALE - 6), "PLAYER"

    ' trail
    Dim dsTi As Integer
    For dsTi = 1 To VIZ_TRAIL_MAX
        If vizTrailX(dsTi) <> 0 Or vizTrailZ(dsTi) <> 0 Then
            Dim dsTCol As Long
            Select Case vizTrailState(dsTi)
            Case 7 : dsTCol = _RGBA(80, 80, 255, 160)
            Case 8
                If vizTrailX(dsTi) > vizPlayerX Then
                    dsTCol = _RGBA(255, 120, 0, 180)
                Else
                    dsTCol = _RGBA(255, 220, 0, 120)
                End If
            Case 9 : dsTCol = _RGBA(200, 80, 200, 180)
            Case Else : dsTCol = _RGBA(60, 60, 60, 80)
            End Select
            Dim dsTSX As Single : dsTSX = VIZ_PX_SC + vizTrailX(dsTi) * VIZ_SCALE
            Dim dsTSZ As Single : dsTSZ = VIZ_PZ_SC - vizTrailZ(dsTi) * VIZ_SCALE
            If vizTrailFire(dsTi) Then
                Circle (dsTSX, dsTSZ), 5, _RGB(255, 255, 0)
            Else
                PSet (dsTSX, dsTSZ), dsTCol
            End If
        End If
    Next dsTi

    ' boss
    Dim dsBCol As Long
    If vizFireFlash > 0 Then dsBCol = _RGB(255, 255, 80) Else dsBCol = _RGB(200, 200, 255)
    VizAABB vizBossX, vizBossZ, VIZ_BOSS_HZ, VIZ_BOSS_HY, dsBCol
    VizArrow vizBossX, vizBossZ, vizBossRy, _RGB(255, 80, 80)

    ' info panel
    Dim dsIPX As Integer : dsIPX = VIZ_W - 252
    Dim dsIPY As Integer : dsIPY = 16
    Dim dsStName As String
    Select Case vizBossState
    Case 7 : dsStName = "7 REAR-FIRE"
    Case 8 : dsStName = "8 FWD-CHARGE"
    Case 9 : dsStName = "9 DRAMATIC-TURN"
    Case Else : dsStName = Str$(vizBossState)
    End Select
    _PrintString (dsIPX, dsIPY), "State:     " + dsStName : dsIPY = dsIPY + 18
    _PrintString (dsIPX, dsIPY), "Frame:     " + LTrim$(Str$(vizFrame)) : dsIPY = dsIPY + 18
    _PrintString (dsIPX, dsIPY), "arcAngle:  " + Left$(Str$(vizBossArcAngle), 7) : dsIPY = dsIPY + 18
    _PrintString (dsIPX, dsIPY), "bossX-plr: " + Left$(Str$(vizBossX - vizPlayerX), 7) : dsIPY = dsIPY + 18
    _PrintString (dsIPX, dsIPY), "bossZ-plr: " + Left$(Str$(vizBossZ - vizPlayerZ), 7) : dsIPY = dsIPY + 18
    _PrintString (dsIPX, dsIPY), "bossRy:    " + Left$(Str$(vizBossRy), 7) + " deg" : dsIPY = dsIPY + 18
    _PrintString (dsIPX, dsIPY), "tgtRy:     " + Left$(Str$(vizTgtRy), 7) + " deg" : dsIPY = dsIPY + 18
    _PrintString (dsIPX, dsIPY), "vx:        " + Left$(Str$(vizVx), 8) : dsIPY = dsIPY + 18
    _PrintString (dsIPX, dsIPY), "vz:        " + Left$(Str$(vizVz), 8) : dsIPY = dsIPY + 18
    dsIPY = dsIPY + 8
    Dim dsTDirLabel As String
    If vizTurnDir > 0 Then dsTDirLabel = "+1 (RIGHT/+Z)" Else dsTDirLabel = "-1 (LEFT/-Z)"
    _PrintString (dsIPX, dsIPY), "TurnDir:   " + dsTDirLabel : dsIPY = dsIPY + 18
    dsIPY = dsIPY + 8
    If vizPaused Then _PrintString (dsIPX, dsIPY), "** PAUSED **" : dsIPY = dsIPY + 18
    If vizFastMode Then _PrintString (dsIPX, dsIPY), "** FAST x10 **" : dsIPY = dsIPY + 18
    dsIPY = dsIPY + 12
    _PrintString (dsIPX, dsIPY), "Legend:" : dsIPY = dsIPY + 18
    Line (dsIPX, dsIPY + 6)-(dsIPX + 12, dsIPY + 6), _RGB(80, 80, 255) : _PrintString (dsIPX + 16, dsIPY), "State 7 rear" : dsIPY = dsIPY + 18
    Line (dsIPX, dsIPY + 6)-(dsIPX + 12, dsIPY + 6), _RGB(255, 220, 0) : _PrintString (dsIPX + 16, dsIPY), "State 8 approach" : dsIPY = dsIPY + 18
    Line (dsIPX, dsIPY + 6)-(dsIPX + 12, dsIPY + 6), _RGB(255, 120, 0) : _PrintString (dsIPX + 16, dsIPY), "State 8 post-overtake" : dsIPY = dsIPY + 18
    Line (dsIPX, dsIPY + 6)-(dsIPX + 12, dsIPY + 6), _RGB(200, 80, 200) : _PrintString (dsIPX + 16, dsIPY), "State 9 dramatic turn" : dsIPY = dsIPY + 18
    Circle (dsIPX + 6, dsIPY + 6), 5, _RGB(255, 255, 0) : _PrintString (dsIPX + 16, dsIPY), "Fire event" : dsIPY = dsIPY + 18
    Line (dsIPX, dsIPY + 6)-(dsIPX + 12, dsIPY + 6), _RGB(255, 80, 80) : _PrintString (dsIPX + 16, dsIPY), "Nose arrow" : dsIPY = dsIPY + 18
    dsIPY = dsIPY + 8
    Line (dsIPX, dsIPY + 6)-(dsIPX + 60, dsIPY + 6), _RGBA(180, 60, 60, 120) : _PrintString (dsIPX + 64, dsIPY), "AABB clr zone"

    _Display
End Sub

' ── main ─────────────────────────────────────────────────────────────────────
Screen _NewImage(VIZ_W, VIZ_H, 32)
TOOL_Init "Boss Flyover Turn Visualizer"

vizTurnDir = 1
VizReset

Dim mlSpaceWas As Integer, mlNWas As Integer, mlRWas As Integer
Dim mlF1Was As Integer, mlF2Was As Integer, mlFWas As Integer, mlEscWas As Integer

Do
    Dim mlSpaceNow As Integer : mlSpaceNow = _KeyDown(32)
    Dim mlNNow As Integer     : mlNNow     = _KeyDown(Asc("n"))
    Dim mlRNow As Integer     : mlRNow     = _KeyDown(Asc("r"))
    Dim mlF1Now As Integer    : mlF1Now    = _KeyDown(Asc("1"))
    Dim mlF2Now As Integer    : mlF2Now    = _KeyDown(Asc("2"))
    Dim mlFNow As Integer     : mlFNow     = _KeyDown(Asc("f"))
    Dim mlEscNow As Integer   : mlEscNow   = _KeyDown(27)

    If mlSpaceNow And Not mlSpaceWas Then vizPaused = Not vizPaused
    If mlNNow And Not mlNWas And vizPaused Then VizStep
    If mlRNow And Not mlRWas Then VizReset
    If mlF1Now And Not mlF1Was Then vizTurnDir = 1
    If mlF2Now And Not mlF2Was Then vizTurnDir = -1
    If mlFNow And Not mlFWas Then vizFastMode = Not vizFastMode
    If mlEscNow And Not mlEscWas Then System

    mlSpaceWas = mlSpaceNow : mlNWas = mlNNow : mlRWas = mlRNow
    mlF1Was = mlF1Now : mlF2Was = mlF2Now : mlFWas = mlFNow : mlEscWas = mlEscNow

    If vizPaused = 0 Then
        If vizFastMode Then
            Dim mlFi As Integer
            For mlFi = 1 To 10
                VizStep
            Next mlFi
        Else
            VizStep
        End If
    End If

    VizDraw
    _Limit 60
Loop
