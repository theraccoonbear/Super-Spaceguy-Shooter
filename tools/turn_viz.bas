$RESIZE:ON
$SCREENHIDE
$Resize:stretch
$EMBED:'assets/models.e3d':'MODELS'

' DBG_Print stub -- input.bas calls this; we don't need real debug output
Sub DBG_Print(dbgMsg As String)
End Sub

'$INCLUDE:'tool_shell.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/gameplay/behavior.bas'

' ── viz constants ─────────────────────────────────────────────────────────────
Const VZPI = 3.14159265358979
Const VZ_TRAIL_MAX = 600

' ── viz state (prefixed vz to avoid collisions with behavior.bas bsm/bpm vars) ─
Dim Shared vzOrbitTheta As Single
Dim Shared vzOrbitPhi   As Single
Dim Shared vzOrbitR     As Single
Dim Shared vzPaused     As Integer
Dim Shared vzFastMode   As Integer
Dim Shared vzFrame      As Long
Dim Shared vzPrevBX     As Single, vzPrevBY As Single, vzPrevBZ As Single
Dim Shared vzCurTgtRy   As Single
Dim Shared vzTrailPX(1 To VZ_TRAIL_MAX) As Single
Dim Shared vzTrailPY(1 To VZ_TRAIL_MAX) As Single
Dim Shared vzTrailPZ(1 To VZ_TRAIL_MAX) As Single
Dim Shared vzTrailSt(1 To VZ_TRAIL_MAX) As Integer
Dim Shared vzTrailHead  As Integer
Dim Shared vzSpaceWas   As Integer, vzNWas As Integer, vzRWas As Integer
Dim Shared vzFWas       As Integer, vzEscWas As Integer
Dim Shared vz1Was       As Integer, vz2Was As Integer

' ── sim reset ─────────────────────────────────────────────────────────────────
Sub VIZ_SimReset
    player.px = 0 : player.py = 0 : player.pz = 0
    player.rx = 0 : player.ry = 0 : player.rz = 0
    player.scl = 1.0 : player.active = -1 : player.meshIdx = MESH_PLAYER

    boss.px = BOSS_COMBAT_DIST
    boss.py = 0 : boss.pz = 0
    boss.rx = 0 : boss.ry = 0 : boss.rz = 0
    boss.vx = 0 : boss.vy = 0 : boss.vz = 0
    boss.scl = 1.0 : boss.active = -1 : boss.meshIdx = MESH_BOSS
    boss.state = 6 : boss.phase = 1
    boss.arcAngle = 0 : boss.moveTimer = 0 : boss.chargeTimer = 0
    boss.fireTimer = 0 : boss.targetY = 0 : boss.targetZ = 0
    boss.hp = 30 : boss.warnTimer = 0
    bsmTurnDir = 1

    vzOrbitTheta = VZPI * 0.25
    vzOrbitPhi   = 0.5
    vzOrbitR     = 55.0
    vzFrame      = 0 : vzPaused = 0 : vzFastMode = 0
    vzTrailHead  = 0 : vzCurTgtRy = 0
    vzPrevBX = boss.px : vzPrevBY = boss.py : vzPrevBZ = boss.pz

    Dim vzRi As Integer
    For vzRi = 1 To VZ_TRAIL_MAX
        vzTrailPX(vzRi) = 0 : vzTrailPY(vzRi) = 0 : vzTrailPZ(vzRi) = 0
        vzTrailSt(vzRi) = 0
    Next vzRi
End Sub

' ── one sim frame ─────────────────────────────────────────────────────────────
Sub VIZ_Step
    vzFrame = vzFrame + 1
    vzPrevBX = boss.px : vzPrevBY = boss.py : vzPrevBZ = boss.pz

    BOSS_UpdateMovement

    ' state 9 arc completes -> state 0; restart flyover to keep looping
    If boss.state = 0 Then
        boss.state    = 6
        boss.px       = BOSS_COMBAT_DIST
        boss.py       = player.py : boss.pz = player.pz
        boss.chargeTimer = 0
    End If

    ' attitude mirrors boss.bas logic exactly
    Dim vzDX As Single : vzDX = boss.px - vzPrevBX
    Dim vzDY As Single : vzDY = boss.py - vzPrevBY
    Dim vzDZ As Single : vzDZ = boss.pz - vzPrevBZ
    Dim vzTRx As Single, vzTRy As Single, vzTRz As Single
    vzTRx = vzDZ * 90 - vzDX * 15
    If vzTRx >  70 Then vzTRx =  70
    If vzTRx < -70 Then vzTRx = -70
    vzTRy = -vzDZ * 35
    If vzTRy >  28 Then vzTRy =  28
    If vzTRy < -28 Then vzTRy = -28
    vzTRz = vzDY * 60
    If vzTRz >  50 Then vzTRz =  50
    If vzTRz < -50 Then vzTRz = -50
    If boss.state >= 6 And boss.state <= 8 Then
        vzTRy = 180
    ElseIf boss.state = 9 Then
        vzTRy = -_ATAN2(Cos(boss.arcAngle) * BOSS_TURN_RAD_Z * bsmTurnDir, Sin(boss.arcAngle) * BOSS_TURN_RAD_X) * 57.2958
    End If
    vzCurTgtRy = vzTRy
    boss.rx = boss.rx + (vzTRx - boss.rx) * BOSS_ATTITUDE_LERP
    boss.ry = boss.ry + (vzTRy - boss.ry) * BOSS_ATTITUDE_LERP
    boss.rz = boss.rz + (vzTRz - boss.rz) * BOSS_ATTITUDE_LERP

    vzTrailHead = vzTrailHead + 1
    If vzTrailHead > VZ_TRAIL_MAX Then vzTrailHead = 1
    vzTrailPX(vzTrailHead) = boss.px
    vzTrailPY(vzTrailHead) = boss.py
    vzTrailPZ(vzTrailHead) = boss.pz
    vzTrailSt(vzTrailHead) = boss.state

    tt = tt + 1
End Sub

' ── world -> screen projection using current vpMat ─────────────────────────────
Sub VIZ_Project(vprWX As Single, vprWY As Single, vprWZ As Single, vprSX As Single, vprSY As Single, vprVis As Integer)
    Dim vprCX As Single, vprCY As Single, vprCW As Single
    vprCX = vprWX * vpMat.m(0,0) + vprWY * vpMat.m(0,1) + vprWZ * vpMat.m(0,2) + vpMat.m(0,3)
    vprCY = vprWX * vpMat.m(1,0) + vprWY * vpMat.m(1,1) + vprWZ * vpMat.m(1,2) + vpMat.m(1,3)
    vprCW = vprWX * vpMat.m(3,0) + vprWY * vpMat.m(3,1) + vprWZ * vpMat.m(3,2) + vpMat.m(3,3)
    If vprCW > 0.00001 Then
        vprSX  = (vprCX / vprCW + 1.0) * scrW * 0.5
        vprSY  = (1.0 - vprCY / vprCW) * scrH * 0.5
        vprVis = -1
    Else
        vprVis = 0
    End If
End Sub

' ── render one frame ──────────────────────────────────────────────────────────
Sub VIZ_Draw
    ' place orbit camera around player origin
    Dim vdCX As Single, vdCY As Single, vdCZ As Single
    vdCX = player.px + vzOrbitR * Cos(vzOrbitPhi) * Sin(vzOrbitTheta)
    vdCY = player.py + vzOrbitR * Sin(vzOrbitPhi)
    vdCZ = player.pz + vzOrbitR * Cos(vzOrbitPhi) * Cos(vzOrbitTheta)
    E3D_MakeCamera cam, vdCX, vdCY, vdCZ, player.px, player.py, player.pz, GAME_FOV
    E3D_MatLookAt cam, viewMat
    E3D_MatMul projMat, viewMat, vpMat

    _DEST backBuffer
    Line (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 8), BF

    E3D_SceneBegin

    ' player ship
    pPos.x = player.px : pPos.y = player.py : pPos.z = player.pz
    pRot.x = player.rx : pRot.y = player.ry : pRot.z = player.rz
    E3D_BuildObjectMat pPos, pRot, player.scl, objMat
    E3D_SceneAddMeshLit meshLib(MESH_PLAYER), objMat, cam.pos, tt, lightDir

    ' boss ship
    Dim vdBPos As E3D_Coord, vdBRot As E3D_Coord
    vdBPos.x = boss.px : vdBPos.y = boss.py : vdBPos.z = boss.pz
    vdBRot.x = boss.rx : vdBRot.y = boss.ry : vdBRot.z = boss.rz
    E3D_BuildObjectMat vdBPos, vdBRot, boss.scl, objMat
    E3D_SceneAddMeshLit meshLib(MESH_BOSS), objMat, cam.pos, tt, lightDir

    E3D_SceneFlush vpMat, scrW, scrH

    ' trail dots projected into screen space
    Dim vdTi As Integer
    For vdTi = 1 To VZ_TRAIL_MAX
        If vzTrailSt(vdTi) > 0 Then
            Dim vdTC As Long
            Select Case vzTrailSt(vdTi)
            Case 6  : vdTC = _RGBA(255, 80,  0,   180)
            Case 7  : vdTC = _RGBA(60,  80,  255, 180)
            Case 8  : vdTC = _RGBA(255, 220, 30,  180)
            Case 9  : vdTC = _RGBA(200, 60,  220, 200)
            Case Else : vdTC = _RGBA(80, 80, 80, 120)
            End Select
            Dim vdTSX As Single, vdTSY As Single, vdTVis As Integer
            VIZ_Project vzTrailPX(vdTi), vzTrailPY(vdTi), vzTrailPZ(vdTi), vdTSX, vdTSY, vdTVis
            If vdTVis Then PSet (vdTSX, vdTSY), vdTC
        End If
    Next vdTi

    ' HUD overlay
    Dim vdSN As String
    Select Case boss.state
    Case 6  : vdSN = "6 DIVE"
    Case 7  : vdSN = "7 REAR"
    Case 8  : vdSN = "8 FWD"
    Case 9  : vdSN = "9 TURN"
    Case Else : vdSN = LTrim$(Str$(boss.state))
    End Select
    Dim vdDirS As String
    If bsmTurnDir > 0 Then vdDirS = "+1 R" Else vdDirS = "-1 L"

    Color _RGB(200, 200, 200)
    _PrintString (2, 2),  "ST: " + vdSN
    _PrintString (2, 12), "ARC:" + Left$(Str$(boss.arcAngle + 1000), 6)
    _PrintString (2, 22), "RY: " + Left$(Str$(boss.ry + 1000), 7)
    _PrintString (2, 32), "DIR:" + vdDirS
    _PrintString (2, 42), "F:  " + LTrim$(Str$(vzFrame))
    If vzPaused   Then _PrintString (2, 54), "PAUSED"
    If vzFastMode Then _PrintString (60, 54), "FAST"

    Color _RGB(100, 100, 100)
    _PrintString (2, scrH - 10), "ARR=cam SPC=pause R=reset 1/2=dir F=fast -/+=zoom"

    _DEST 0
    _PutImage , backBuffer, 0
    _Display
End Sub

' ── main ─────────────────────────────────────────────────────────────────────
scrW = 320 : scrH = 240
Screen _NewImage(scrW, scrH, 32)
backBuffer = _NewImage(scrW, scrH, 32)
TOOL_Init "Boss Flyover Visualizer"

lightDir.x = -0.4 : lightDir.y = 0.7 : lightDir.z = -0.5

Dim vzMdl As String
vzMdl = _EMBEDDED$("MODELS")
E3D_LoadMesh vzMdl, "PLAYER", meshLib(MESH_PLAYER), boxLib(MESH_PLAYER)
E3D_LoadMesh vzMdl, "BOSS",   meshLib(MESH_BOSS),   boxLib(MESH_BOSS)
E3D_BakeMeshNormals meshLib(MESH_PLAYER)
E3D_BakeMeshNormals meshLib(MESH_BOSS)

E3D_MakeCamera cam, 0, 20, 30, 0, 0, 0, GAME_FOV
E3D_MatPerspective cam, scrW / scrH, projMat

VIZ_SimReset
_SCREENSHOW

Dim vzSpNow As Integer, vzNNow As Integer, vzRNow As Integer
Dim vzFNow As Integer, vzEscNow As Integer
Dim vz1Now As Integer, vz2Now As Integer
Dim vzPlusNow As Integer, vzMinusNow As Integer
Dim vzFLi As Integer

Do
    vzSpNow    = _KeyDown(E3D_KEY_SPACE)
    vzNNow     = _KeyDown(Asc("n"))
    vzRNow     = _KeyDown(Asc("r"))
    vzFNow     = _KeyDown(Asc("f"))
    vzEscNow   = _KeyDown(E3D_KEY_ESCAPE)
    vz1Now     = _KeyDown(Asc("1"))
    vz2Now     = _KeyDown(Asc("2"))
    vzPlusNow  = _KeyDown(43) Or _KeyDown(61)
    vzMinusNow = _KeyDown(45)

    If _KeyDown(E3D_KEY_LEFT)  Then vzOrbitTheta = vzOrbitTheta - 0.02
    If _KeyDown(E3D_KEY_RIGHT) Then vzOrbitTheta = vzOrbitTheta + 0.02
    If _KeyDown(E3D_KEY_UP)    Then vzOrbitPhi = vzOrbitPhi + 0.02
    If _KeyDown(E3D_KEY_DOWN)  Then vzOrbitPhi = vzOrbitPhi - 0.02
    If vzOrbitPhi >  1.5 Then vzOrbitPhi =  1.5
    If vzOrbitPhi < -1.5 Then vzOrbitPhi = -1.5
    If vzPlusNow  Then vzOrbitR = vzOrbitR - 0.5
    If vzMinusNow Then vzOrbitR = vzOrbitR + 0.5
    If vzOrbitR <   5 Then vzOrbitR =   5
    If vzOrbitR > 200 Then vzOrbitR = 200

    If vzSpNow  And vzSpaceWas = 0 Then vzPaused   = Not vzPaused
    If vzNNow   And vzNWas    = 0 And vzPaused Then VIZ_Step
    If vzRNow   And vzRWas    = 0 Then VIZ_SimReset
    If vz1Now   And vz1Was    = 0 Then bsmTurnDir = 1
    If vz2Now   And vz2Was    = 0 Then bsmTurnDir = -1
    If vzFNow   And vzFWas    = 0 Then vzFastMode  = Not vzFastMode
    If vzEscNow And vzEscWas  = 0 Then System

    vzSpaceWas = vzSpNow : vzNWas = vzNNow   : vzRWas = vzRNow
    vzFWas     = vzFNow  : vzEscWas = vzEscNow
    vz1Was     = vz1Now  : vz2Was = vz2Now

    If vzPaused = 0 Then
        If vzFastMode Then
            For vzFLi = 1 To 10
                VIZ_Step
            Next vzFLi
        Else
            VIZ_Step
        End If
    End If

    VIZ_Draw
    _Limit 60
Loop
