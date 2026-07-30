$RESIZE:ON
$SCREENHIDE
$Resize:stretch
$EMBED:'assets/models.e3d':'MODELS'
$EMBED:'assets/maneuvers.txt':'MANEUVERS'

' DBG_Print stub -- input.bas calls this; we don't need real debug output
Sub DBG_Print(dbgMsg As String)
End Sub

'$INCLUDE:'tool_shell.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/gameplay/behavior.bas'
'$INCLUDE:'../src/gameplay/maneuvers.bas'

' ── viz constants ─────────────────────────────────────────────────────────────
Const VZPI        = 3.14159265358979
Const VZ_TRAIL_MAX = 600
Const VZ_CAM_SPD  = 0.30
Const VZ_LOOK_SPD = 0.025    ' arrow-key look speed (rad/frame)
Const VZ_MOUSE_SPD = 0.0008  ' mouse sensitivity (rad/pixel)
Const VZ_KEY_PGUP = 18688
Const VZ_KEY_PGDN = 20736

' gameplay camera defaults: behind player, looking along +X toward boss
Const VZ_GCAM_X     = -8.0
Const VZ_GCAM_Y     =  3.0
Const VZ_GCAM_Z     =  0.0
Const VZ_GCAM_YAW   = 1.5708    ' VZPI/2 -- faces +X (toward boss)
Const VZ_GCAM_PITCH = 0.22      ' slight downward angle

' ── viz state ─────────────────────────────────────────────────────────────────
Dim Shared vzCamX As Single, vzCamY As Single, vzCamZ As Single
Dim Shared vzCamYaw As Single, vzCamPitch As Single
Dim Shared vzPaused   As Integer
Dim Shared vzFastMode As Integer
Dim Shared vzFrame    As Long
Dim Shared vzPrevBX   As Single, vzPrevBY As Single, vzPrevBZ As Single
Dim Shared vzTrailPX(1 To VZ_TRAIL_MAX) As Single
Dim Shared vzTrailPY(1 To VZ_TRAIL_MAX) As Single
Dim Shared vzTrailPZ(1 To VZ_TRAIL_MAX) As Single
Dim Shared vzTrailSt(1 To VZ_TRAIL_MAX) As Integer
Dim Shared vzTrailHead As Integer
Dim Shared vzSpaceWas As Integer, vzNWas As Integer, vzRWas As Integer
Dim Shared vzFWas     As Integer, vzEscWas As Integer
Dim Shared vz1Was     As Integer, vz2Was   As Integer
Dim Shared vzTabWas   As Integer, vzHWas   As Integer
Dim Shared vzPgUpWas  As Integer, vzPgDnWas As Integer
Dim Shared vzPWas      As Integer, vzVWas      As Integer
Dim Shared vzCWas      As Integer
Dim Shared vzShowHelp  As Integer
Dim Shared vzShowPath  As Integer
Dim Shared vzShowNodes As Integer
Dim Shared vzFollowBoss As Integer

' maneuver block list for TAB cycling
Dim Shared vzBlockNames(0 To 15) As String
Dim Shared vzBlockCount As Integer
Dim Shared vzBlockIdx   As Integer

' ── load the current block into bsmWp* and reset boss+trail (camera unchanged) ─
Sub VIZ_LoadManeuver
    boss.px = player.px + BOSS_COMBAT_DIST
    boss.py = player.py : boss.pz = player.pz
    boss.rx = 0 : boss.ry = 0 : boss.rz = 0
    boss.vx = 0 : boss.vy = 0 : boss.vz = 0
    boss.scl = 1.0 : boss.active = -1 : boss.meshIdx = MESH_BOSS
    boss.state = 6 : boss.phase = 1
    boss.arcAngle = 0 : boss.moveTimer = 0 : boss.chargeTimer = 0
    boss.fireTimer = 0 : boss.targetY = 0 : boss.targetZ = 0
    boss.hp = 30 : boss.warnTimer = 0
    bsmTurnDir = 1
    If vzBlockCount > 0 Then bsmManeuverName = vzBlockNames(vzBlockIdx)
    BOSS_FlyoverInit
    vzFrame = 0 : vzPaused = 0 : vzFastMode = 0 : vzTrailHead = 0
    vzPrevBX = boss.px : vzPrevBY = boss.py : vzPrevBZ = boss.pz
    Dim vzLMi As Integer
    For vzLMi = 1 To VZ_TRAIL_MAX
        vzTrailPX(vzLMi) = 0 : vzTrailPY(vzLMi) = 0 : vzTrailPZ(vzLMi) = 0
        vzTrailSt(vzLMi) = 0
    Next vzLMi
End Sub

' ── full reset: also resets player and camera to gameplay defaults ─────────────
Sub VIZ_SimReset
    player.px = 0 : player.py = 0 : player.pz = 0
    player.rx = 0 : player.ry = 0 : player.rz = 0
    player.scl = 1.0 : player.active = -1 : player.meshIdx = MESH_PLAYER
    vzCamX = VZ_GCAM_X : vzCamY = VZ_GCAM_Y : vzCamZ = VZ_GCAM_Z
    vzCamYaw = VZ_GCAM_YAW : vzCamPitch = VZ_GCAM_PITCH
    vzShowPath = -1 : vzShowNodes = -1
    VIZ_LoadManeuver
End Sub

' ── one simulation frame ──────────────────────────────────────────────────────
Sub VIZ_Step
    vzFrame = vzFrame + 1
    vzPrevBX = boss.px : vzPrevBY = boss.py : vzPrevBZ = boss.pz

    BOSS_UpdateMovement

    ' flyover completes (state 6 -> 0): restart to loop continuously in the viz
    If boss.state = 0 Then
        boss.px = player.px + BOSS_COMBAT_DIST
        boss.py = player.py : boss.pz = player.pz
        boss.arcAngle = 0
        boss.chargeTimer = 0
        BOSS_FlyoverInit   ' recompute waypoints with updated bsmTurnDir
        boss.state = 6
    End If

    ' orientation = direction of travel, lerped at 0.18 to match actual game
    Dim vzDX As Single : vzDX = boss.px - vzPrevBX
    Dim vzDY As Single : vzDY = boss.py - vzPrevBY
    Dim vzDZ As Single : vzDZ = boss.pz - vzPrevBZ
    Dim vzSpd As Single : vzSpd = Sqr(vzDX*vzDX + vzDY*vzDY + vzDZ*vzDZ)
    If vzSpd > 0.0002 Then
        Dim vzTgtRy As Single : vzTgtRy = _Atan2(vzDZ, -vzDX) * 57.2958
        Dim vzTgtRx As Single : vzTgtRx = boss.rx
        Dim vzHSpd As Single : vzHSpd = Sqr(vzDX*vzDX + vzDZ*vzDZ)
        If vzHSpd > 0.0002 Then vzTgtRx = _Atan2(-vzDY, vzHSpd) * 57.2958
        Dim vzTgtRz As Single : vzTgtRz = -(vzDZ / vzSpd) * 50.0
        ' yaw wrap: always take the short arc across ±180
        Dim vzRyDiff As Single : vzRyDiff = vzTgtRy - boss.ry
        If vzRyDiff >  180 Then vzRyDiff = vzRyDiff - 360
        If vzRyDiff < -180 Then vzRyDiff = vzRyDiff + 360
        boss.ry = boss.ry + vzRyDiff          * 0.18
        boss.rx = boss.rx + (vzTgtRx - boss.rx) * 0.18
        boss.rz = boss.rz + (vzTgtRz - boss.rz) * 0.18
    End If

    vzTrailHead = vzTrailHead + 1
    If vzTrailHead > VZ_TRAIL_MAX Then vzTrailHead = 1
    vzTrailPX(vzTrailHead) = boss.px
    vzTrailPY(vzTrailHead) = boss.py
    vzTrailPZ(vzTrailHead) = boss.pz
    vzTrailSt(vzTrailHead) = boss.state

    tt = tt + 1
End Sub

' ── world-to-screen projection ─────────────────────────────────────────────────
Sub VIZ_Project(vprWX As Single, vprWY As Single, vprWZ As Single, vprSX As Single, vprSY As Single, vprVis As Integer)
    Dim vprCX As Single, vprCY As Single, vprCW As Single
    vprCX = vprWX*vpMat.m(0,0) + vprWY*vpMat.m(0,1) + vprWZ*vpMat.m(0,2) + vpMat.m(0,3)
    vprCY = vprWX*vpMat.m(1,0) + vprWY*vpMat.m(1,1) + vprWZ*vpMat.m(1,2) + vpMat.m(1,3)
    vprCW = vprWX*vpMat.m(3,0) + vprWY*vpMat.m(3,1) + vprWZ*vpMat.m(3,2) + vpMat.m(3,3)
    If vprCW > 0.00001 Then
        vprSX  = (vprCX/vprCW + 1.0) * scrW * 0.5
        vprSY  = (1.0 - vprCY/vprCW) * scrH * 0.5
        vprVis = -1
    Else
        vprVis = 0
    End If
End Sub

' ── draw the static Catmull-Rom spline through the loaded waypoints ────────────
Sub VIZ_DrawSplinePath
    If bsmWpCount < 2 Then Exit Sub
    Dim vdspT As Single, vdspStep As Single, vdspN As Integer
    Dim vdspSeg As Integer
    Dim vdspFu As Single, vdspFu2 As Single, vdspFu3 As Single
    Dim vdspI0 As Integer, vdspI1 As Integer, vdspI2 As Integer, vdspI3 As Integer
    Dim vdspW0 As Single, vdspW1 As Single, vdspW2 As Single, vdspW3 As Single
    Dim vdspWX As Single, vdspWY As Single, vdspWZ As Single
    Dim vdspSX As Single, vdspSY As Single, vdspVis As Integer
    Dim vdspPX As Single, vdspPY As Single, vdspPVis As Integer

    vdspStep = (bsmWpCount - 1) / 200.0
    vdspT = 0 : vdspPVis = 0
    For vdspN = 0 To 200
        vdspSeg = Int(vdspT)
        If vdspSeg >= bsmWpCount - 1 Then vdspSeg = bsmWpCount - 2
        vdspFu  = vdspT - vdspSeg
        vdspFu2 = vdspFu * vdspFu
        vdspFu3 = vdspFu2 * vdspFu
        vdspI0 = vdspSeg - 1 : If vdspI0 < 0 Then vdspI0 = 0
        vdspI1 = vdspSeg
        vdspI2 = vdspSeg + 1 : If vdspI2 >= bsmWpCount Then vdspI2 = bsmWpCount - 1
        vdspI3 = vdspSeg + 2 : If vdspI3 >= bsmWpCount Then vdspI3 = bsmWpCount - 1
        vdspW0 = -vdspFu3 + 2*vdspFu2 - vdspFu
        vdspW1 =  3*vdspFu3 - 5*vdspFu2 + 2
        vdspW2 = -3*vdspFu3 + 4*vdspFu2 + vdspFu
        vdspW3 = vdspFu3 - vdspFu2
        vdspWX = player.px + 0.5*(bsmWpX(vdspI0)*vdspW0 + bsmWpX(vdspI1)*vdspW1 + bsmWpX(vdspI2)*vdspW2 + bsmWpX(vdspI3)*vdspW3)
        vdspWY = player.py + 0.5*(bsmWpY(vdspI0)*vdspW0 + bsmWpY(vdspI1)*vdspW1 + bsmWpY(vdspI2)*vdspW2 + bsmWpY(vdspI3)*vdspW3)
        vdspWZ = player.pz + 0.5*(bsmWpZ(vdspI0)*vdspW0 + bsmWpZ(vdspI1)*vdspW1 + bsmWpZ(vdspI2)*vdspW2 + bsmWpZ(vdspI3)*vdspW3)
        VIZ_Project vdspWX, vdspWY, vdspWZ, vdspSX, vdspSY, vdspVis
        If vdspVis And vdspPVis Then
            Line (vdspPX, vdspPY)-(vdspSX, vdspSY), _RGBA(0, 220, 200, 160)
        End If
        vdspPX = vdspSX : vdspPY = vdspSY : vdspPVis = vdspVis
        vdspT = vdspT + vdspStep
    Next vdspN
End Sub

' ── draw waypoint nodes as labeled circles ─────────────────────────────────────
Sub VIZ_DrawNodes
    If bsmWpCount < 1 Then Exit Sub
    Dim vdnI As Integer
    Dim vdnSX As Single, vdnSY As Single, vdnVis As Integer
    Dim vdnWX As Single, vdnWY As Single, vdnWZ As Single
    For vdnI = 0 To bsmWpCount - 1
        vdnWX = player.px + bsmWpX(vdnI)
        vdnWY = player.py + bsmWpY(vdnI)
        vdnWZ = player.pz + bsmWpZ(vdnI)
        VIZ_Project vdnWX, vdnWY, vdnWZ, vdnSX, vdnSY, vdnVis
        If vdnVis Then
            Circle (vdnSX, vdnSY), 5, _RGB(255, 200, 0)
            Circle (vdnSX, vdnSY), 4, _RGB(255, 200, 0)
            Color _RGB(255, 200, 0)
            _PrintString (vdnSX + 6, vdnSY - 4), LTrim$(Str$(vdnI))
        End If
    Next vdnI
End Sub

' ── render one frame ──────────────────────────────────────────────────────────
Sub VIZ_Draw
    Dim vdFX As Single, vdFY As Single, vdFZ As Single
    vdFX = Sin(vzCamYaw) * Cos(vzCamPitch)
    vdFY = -Sin(vzCamPitch)
    vdFZ = -Cos(vzCamYaw) * Cos(vzCamPitch)

    E3D_MakeCamera cam, vzCamX, vzCamY, vzCamZ, _
        vzCamX + vdFX, vzCamY + vdFY, vzCamZ + vdFZ, GAME_FOV
    E3D_MatLookAt cam, viewMat
    E3D_MatMul projMat, viewMat, vpMat

    _DEST backBuffer
    Line (0, 0)-(scrW-1, scrH-1), _RGB(0, 0, 8), BF

    E3D_SceneBegin

    ' player ship at origin
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

    ' static spline path in teal/cyan
    If vzShowPath Then VIZ_DrawSplinePath

    ' simulation trail dots, colored by boss X relative to player
    Dim vdTi As Integer
    For vdTi = 1 To VZ_TRAIL_MAX
        If vzTrailSt(vdTi) > 0 Then
            Dim vdTC As Long
            If vzTrailPX(vdTi) < player.px Then
                vdTC = _RGBA(60, 80, 255, 200)   ' behind player
            ElseIf vzTrailPX(vdTi) < player.px + 25 Then
                vdTC = _RGBA(255, 220, 30, 200)  ' overhead zone
            Else
                vdTC = _RGBA(200, 60, 220, 200)  ' far ahead / banking arc
            End If
            Dim vdTSX As Single, vdTSY As Single, vdTVis As Integer
            VIZ_Project vzTrailPX(vdTi), vzTrailPY(vdTi), vzTrailPZ(vdTi), vdTSX, vdTSY, vdTVis
            If vdTVis Then PSet (vdTSX, vdTSY), vdTC
        End If
    Next vdTi

    ' waypoint nodes -- prominent circles with index labels
    If vzShowNodes Then VIZ_DrawNodes

    ' player screen marker
    Dim vdPSX As Single, vdPSY As Single, vdPVis As Integer
    VIZ_Project player.px, player.py, player.pz, vdPSX, vdPSY, vdPVis
    If vdPVis Then
        Circle (vdPSX, vdPSY), 6, _RGB(0, 240, 80)
        Circle (vdPSX, vdPSY), 5, _RGB(0, 240, 80)
        Color _RGB(0, 240, 80)
        _PrintString (vdPSX - 8, vdPSY - 14), "YOU"
    End If

    ' block name -- top center
    Dim vdBlkName As String
    If vzBlockCount > 0 Then vdBlkName = vzBlockNames(vzBlockIdx) Else vdBlkName = "?"
    Dim vdBlkX As Integer : vdBlkX = (scrW - Len(vdBlkName) * 8) \ 2
    Color _RGB(255, 240, 80)
    _PrintString (vdBlkX, 2), vdBlkName

    ' telemetry strip: top-left, 14px line spacing
    Color _RGB(180, 180, 180)
    Dim vdSN As String
    If boss.state = 6 Then vdSN = "6 FLY" Else vdSN = LTrim$(Str$(boss.state))
    Dim vdDirS As String
    If bsmTurnDir > 0 Then vdDirS = "+1 R" Else vdDirS = "-1 L"
    _PrintString (2, 16), "ST:" + vdSN
    _PrintString (2, 30), "T:" + Left$(Str$(boss.arcAngle + 1000), 6)
    _PrintString (2, 44), "DIR" + vdDirS
    _PrintString (2, 58), "F:" + LTrim$(Str$(vzFrame))
    If vzPaused    Then _PrintString (2,  72), "PAUSED"
    If vzFastMode  Then _PrintString (50, 72), "FAST"
    If vzFollowBoss Then
        Color _RGB(80, 200, 255)
        _PrintString (2, 86), "FOLLOW"
    End If

    ' help toggle hint at bottom right
    Color _RGB(80, 80, 80)
    _PrintString (scrW - 48, scrH - 10), "[H] help"

    ' block cycling hint
    Dim vdCycHint As String
    If vzBlockCount > 1 Then
        vdCycHint = LTrim$(Str$(vzBlockIdx + 1)) + "/" + LTrim$(Str$(vzBlockCount))
        _PrintString (2, scrH - 10), "TAB " + vdCycHint
    End If

    ' ── help popup ────────────────────────────────────────────────────────────
    If vzShowHelp Then
        Dim vdHX As Integer : vdHX = 20
        Dim vdHY As Integer : vdHY = 20
        Dim vdHW As Integer : vdHW = 280
        Dim vdHH As Integer : vdHH = 180
        Line (vdHX, vdHY)-(vdHX + vdHW, vdHY + vdHH), _RGBA(0, 0, 0, 220), BF
        Line (vdHX, vdHY)-(vdHX + vdHW, vdHY + vdHH), _RGB(100, 100, 100), B
        Color _RGB(255, 240, 80)
        _PrintString (vdHX + 8, vdHY + 6), "CONTROLS"
        Color _RGB(200, 200, 200)
        Dim vdHLY As Integer : vdHLY = vdHY + 22
        _PrintString (vdHX + 8, vdHLY),      "W/S          fly forward / back"
        _PrintString (vdHX + 8, vdHLY + 14), "A/D          strafe left / right"
        _PrintString (vdHX + 8, vdHLY + 28), "Q/E          elevator down / up"
        _PrintString (vdHX + 8, vdHLY + 42), "PgDn/PgUp    elevator down / up"
        _PrintString (vdHX + 8, vdHLY + 56), "arrows       look"
        _PrintString (vdHX + 8, vdHLY + 70), "mouse drag   look"
        _PrintString (vdHX + 8, vdHLY + 84),  "TAB / Sh-TAB next / prev maneuver"
        _PrintString (vdHX + 8, vdHLY + 98),  "1 / 2        turn direction +/-"
        _PrintString (vdHX + 8, vdHLY + 112), "C            follow boss camera"
        _PrintString (vdHX + 8, vdHLY + 126), "SPC=pause  N=step  F=fast"
        _PrintString (vdHX + 8, vdHLY + 140), "P=path  V=nodes  R=reset  ESC=quit"
    End If

    _DEST 0
    _PutImage , backBuffer, 0
    _Display
End Sub

' ── main ─────────────────────────────────────────────────────────────────────
scrW = 320 : scrH = 240
Screen _NewImage(scrW, scrH, 32)
backBuffer = _NewImage(scrW, scrH, 32)
TOOL_Init "Boss Flyover Visualizer"
MNV_Init _EMBEDDED$("MANEUVERS")

' enumerate block names from data file
MNV_ListBlocks vzBlockNames(), vzBlockCount
vzBlockIdx = 0
bsmManeuverName = "flyover"
If vzBlockCount > 0 Then bsmManeuverName = vzBlockNames(0)

lightDir.x = -0.4 : lightDir.y = 0.7 : lightDir.z = -0.5

Dim vzMdl As String
vzMdl = _EMBEDDED$("MODELS")
E3D_LoadMesh vzMdl, "PLAYER", meshLib(MESH_PLAYER), boxLib(MESH_PLAYER)
E3D_LoadMesh vzMdl, "BOSS",   meshLib(MESH_BOSS),   boxLib(MESH_BOSS)
E3D_BakeMeshNormals meshLib(MESH_PLAYER)
E3D_BakeMeshNormals meshLib(MESH_BOSS)

E3D_MakeCamera cam, 0, 20, 30, 0, 0, 0, GAME_FOV
E3D_MatPerspective cam, scrW / scrH, projMat

_MouseHide
VIZ_SimReset
_SCREENSHOW

Dim vzSpNow As Integer, vzNNow As Integer, vzRNow As Integer
Dim vzFNow As Integer, vzEscNow As Integer
Dim vz1Now As Integer, vz2Now As Integer
Dim vzTabNow As Integer, vzHNow As Integer
Dim vzPgUpNow As Integer, vzPgDnNow As Integer
Dim vzPNow As Integer, vzVNow As Integer
Dim vzCNow As Integer
Dim vzFwdX As Single, vzFwdY As Single, vzFwdZ As Single
Dim vzRgtX As Single, vzRgtZ As Single
Dim vzFLi As Integer
Dim vzMX As Long, vzMY As Long

Do
    ' ── key state ──────────────────────────────────────────────────────
    vzSpNow   = _KeyDown(E3D_KEY_SPACE)
    vzNNow    = _KeyDown(Asc("n"))
    vzRNow    = _KeyDown(Asc("r"))
    vzFNow    = _KeyDown(Asc("f"))
    vzEscNow  = _KeyDown(E3D_KEY_ESCAPE)
    vz1Now    = _KeyDown(Asc("1"))
    vz2Now    = _KeyDown(Asc("2"))
    vzTabNow  = _KeyDown(E3D_KEY_TAB)
    vzHNow    = _KeyDown(Asc("h"))
    vzPgUpNow = _KeyDown(VZ_KEY_PGUP)
    vzPgDnNow = _KeyDown(VZ_KEY_PGDN)
    vzPNow    = _KeyDown(Asc("p"))
    vzVNow    = _KeyDown(Asc("v"))
    vzCNow    = _KeyDown(Asc("c"))

    ' ── mouse look (left-button drag only) ────────────────────────────
    vzMX = 0 : vzMY = 0
    Do While _MouseInput
        vzMX = vzMX + _MouseMovementX
        vzMY = vzMY + _MouseMovementY
    Loop
    If _MouseButton(1) Then
        vzCamYaw   = vzCamYaw   + vzMX * VZ_MOUSE_SPD
        vzCamPitch = vzCamPitch + vzMY * VZ_MOUSE_SPD
    End If
    If vzCamPitch >  1.5 Then vzCamPitch =  1.5
    If vzCamPitch < -1.5 Then vzCamPitch = -1.5

    ' ── arrow-key look ─────────────────────────────────────────────────
    If _KeyDown(E3D_KEY_LEFT)  Then vzCamYaw   = vzCamYaw   - VZ_LOOK_SPD
    If _KeyDown(E3D_KEY_RIGHT) Then vzCamYaw   = vzCamYaw   + VZ_LOOK_SPD
    If _KeyDown(E3D_KEY_UP)    Then vzCamPitch = vzCamPitch - VZ_LOOK_SPD
    If _KeyDown(E3D_KEY_DOWN)  Then vzCamPitch = vzCamPitch + VZ_LOOK_SPD
    If vzCamPitch >  1.5 Then vzCamPitch =  1.5
    If vzCamPitch < -1.5 Then vzCamPitch = -1.5

    ' ── WASD fly + elevator (free-cam only) ───────────────────────────
    If vzFollowBoss = 0 Then
        vzFwdX = Sin(vzCamYaw) * Cos(vzCamPitch)
        vzFwdY = -Sin(vzCamPitch)
        vzFwdZ = -Cos(vzCamYaw) * Cos(vzCamPitch)
        vzRgtX = Cos(vzCamYaw)
        vzRgtZ = Sin(vzCamYaw)
        If _KeyDown(119) Then   ' W forward
            vzCamX = vzCamX + vzFwdX * VZ_CAM_SPD
            vzCamY = vzCamY + vzFwdY * VZ_CAM_SPD
            vzCamZ = vzCamZ + vzFwdZ * VZ_CAM_SPD
        End If
        If _KeyDown(115) Then   ' S back
            vzCamX = vzCamX - vzFwdX * VZ_CAM_SPD
            vzCamY = vzCamY - vzFwdY * VZ_CAM_SPD
            vzCamZ = vzCamZ - vzFwdZ * VZ_CAM_SPD
        End If
        If _KeyDown(97) Then    ' A strafe left
            vzCamX = vzCamX - vzRgtX * VZ_CAM_SPD
            vzCamZ = vzCamZ - vzRgtZ * VZ_CAM_SPD
        End If
        If _KeyDown(100) Then   ' D strafe right
            vzCamX = vzCamX + vzRgtX * VZ_CAM_SPD
            vzCamZ = vzCamZ + vzRgtZ * VZ_CAM_SPD
        End If
        If _KeyDown(113) Or vzPgDnNow Then vzCamY = vzCamY - VZ_CAM_SPD  ' Q/PgDn down
        If _KeyDown(101) Or vzPgUpNow Then vzCamY = vzCamY + VZ_CAM_SPD  ' E/PgUp up
    End If

    ' ── edge-triggered sim controls ────────────────────────────────────
    If vzSpNow And vzSpaceWas = 0 Then vzPaused   = Not vzPaused
    If vzNNow  And vzNWas    = 0 And vzPaused Then VIZ_Step
    If vzFNow  And vzFWas    = 0 Then vzFastMode  = Not vzFastMode
    If vzHNow  And vzHWas    = 0 Then vzShowHelp  = Not vzShowHelp
    If vzPNow  And vzPWas    = 0 Then vzShowPath   = Not vzShowPath
    If vzVNow  And vzVWas    = 0 Then vzShowNodes  = Not vzShowNodes
    If vzCNow  And vzCWas    = 0 Then vzFollowBoss = Not vzFollowBoss
    If vzRNow  And vzRWas    = 0 Then VIZ_SimReset
    If vz1Now  And vz1Was    = 0 Then bsmTurnDir = 1
    If vz2Now  And vz2Was    = 0 Then bsmTurnDir = -1
    If vzEscNow And vzEscWas = 0 Then System

    ' TAB / SHIFT+TAB: cycle through maneuver blocks
    If vzTabNow And vzTabWas = 0 And vzBlockCount > 1 Then
        If _KeyDown(100304) Or _KeyDown(100303) Then  ' shift held = go back
            vzBlockIdx = vzBlockIdx - 1
            If vzBlockIdx < 0 Then vzBlockIdx = vzBlockCount - 1
        Else
            vzBlockIdx = vzBlockIdx + 1
            If vzBlockIdx >= vzBlockCount Then vzBlockIdx = 0
        End If
        bsmManeuverName = vzBlockNames(vzBlockIdx)
        VIZ_LoadManeuver
    End If

    vzSpaceWas = vzSpNow  : vzNWas   = vzNNow    : vzRWas   = vzRNow
    vzFWas     = vzFNow   : vzEscWas = vzEscNow
    vz1Was     = vz1Now   : vz2Was   = vz2Now
    vzTabWas   = vzTabNow : vzHWas   = vzHNow
    vzPWas     = vzPNow   : vzVWas   = vzVNow
    vzCWas     = vzCNow

    ' ── sim advance ────────────────────────────────────────────────────
    If vzPaused = 0 Then
        If vzFastMode Then
            For vzFLi = 1 To 10
                VIZ_Step
            Next vzFLi
        Else
            VIZ_Step
        End If
    End If

    ' ── follow-boss camera override ────────────────────────────────────
    If vzFollowBoss Then
        ' position 12 units behind the boss (opposite its nose direction)
        Dim vzBFwdX As Single : vzBFwdX = -Cos(boss.ry * VZPI / 180.0)
        Dim vzBFwdZ As Single : vzBFwdZ =  Sin(boss.ry * VZPI / 180.0)
        vzCamX = boss.px - vzBFwdX * 12.0
        vzCamY = boss.py + 3.0
        vzCamZ = boss.pz - vzBFwdZ * 12.0
        ' point camera at boss
        Dim vzFCDX As Single : vzFCDX = boss.px - vzCamX
        Dim vzFCDY As Single : vzFCDY = boss.py - vzCamY
        Dim vzFCDZ As Single : vzFCDZ = boss.pz - vzCamZ
        Dim vzFCHL As Single : vzFCHL = Sqr(vzFCDX * vzFCDX + vzFCDZ * vzFCDZ)
        If vzFCHL > 0.001 Then
            vzCamYaw   = _Atan2(vzFCDX, -vzFCDZ)
            vzCamPitch = _Atan2(-vzFCDY, vzFCHL)
        End If
    End If

    VIZ_Draw
    _Limit 60
Loop
