' aim_test.bas -- which way a shot leaves a ship (src/gameplay/aim.bas, #199)
'
' Drives the real module with plain numbers: the nose against the engine's own object matrix,
' the player's blend (0 = the aimed direction exactly, 1 = the nose, between = unit length),
' and the enemy / boss firing arc (360 = the target direction exactly, a narrow arc clamps to
' half the arc off the nose, a target outside the arc = hold fire).
'
' Build: ./tools/buildqb tests/aim_test.bas
' Run:   builds/aim_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

Sub DBG_Print (atdDbg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/gameplay/aim.bas'

Dim Shared atPassed As Integer, atFailed As Integer

Sub AT_Assert (ataCond As Integer, ataName As String)
    If ataCond Then
        Print "PASS  " + ataName
        atPassed = atPassed + 1
    Else
        Print "FAIL  " + ataName
        atFailed = atFailed + 1
    End If
End Sub

Function AT_Near% (atnA As Single, atnB As Single)
    AT_Near% = (Abs(atnA - atnB) < 0.0001)
End Function

Function AT_Len! (atlX As Single, atlY As Single, atlZ As Single)
    AT_Len! = Sqr(atlX * atlX + atlY * atlY + atlZ * atlZ)
End Function

Function AT_AngleDeg! (atgAX As Single, atgAY As Single, atgAZ As Single, atgBX As Single, atgBY As Single, atgBZ As Single)
    Dim atgD As Single
    atgD = atgAX * atgBX + atgAY * atgBY + atgAZ * atgBZ
    If atgD > 1 Then atgD = 1
    If atgD < -1 Then atgD = -1
    AT_AngleDeg! = _Acos(atgD) * 180.0 / _Pi
End Function


Dim aaX As Single, aaY As Single, aaZ As Single
Dim nnX As Single, nnY As Single, nnZ As Single
Dim ooX As Single, ooY As Single, ooZ As Single
Dim ttX As Single, ttY As Single, ttZ As Single
Dim mxPos As E3D_Coord, mxRot As E3D_Coord, mxOne As E3D_Coord, mxOut As E3D_Coord, mxM As E3D_Matrix4
Dim atI As Integer, atOk As Integer
Dim atRx(7) As Single, atRy(7) As Single, atRz(7) As Single
For atI = 0 To 7
    Read atRx(atI), atRy(atI), atRz(atI)
Next atI
Data 0,0,0, 30,10,-50, -45,25,15, 70,-28,33, 10,40,-70, -20,-60,20, 90,5,45, 15,15,15

Print "=== aim_test ==="

' nose: same as the engine's object matrix applied to the model's +X axis
mxPos.x = 0 : mxPos.y = 0 : mxPos.z = 0
mxOne.x = 1 : mxOne.y = 0 : mxOne.z = 0
atOk = -1
For atI = 0 To 7
    mxRot.x = atRx(atI)
    mxRot.y = atRy(atI)
    mxRot.z = atRz(atI)
    E3D_BuildObjectMat mxPos, mxRot, 1, mxM
    E3D_MatTransformCoord mxOne, mxM, mxOut
    AIM_Nose mxRot.x, mxRot.y, mxRot.z, nnX, nnY, nnZ
    If AT_Near%(nnX, mxOut.x) = 0 Or AT_Near%(nnY, mxOut.y) = 0 Or AT_Near%(nnZ, mxOut.z) = 0 Then atOk = 0
Next atI
AT_Assert atOk, "nose matches the engine's object matrix for 8 attitudes"
AIM_Nose 0, 0, 0, nnX, nnY, nnZ
AT_Assert AT_Near%(nnX, 1) And AT_Near%(nnY, 0) And AT_Near%(nnZ, 0), "level ship points along +X"

' blend
aaX = 0.8 : aaY = 0.3 : aaZ = -0.1      ' deliberately not unit length, like the player's aim
nnX = 0.6 : nnY = -0.8 : nnZ = 0
AIM_Blend aaX, aaY, aaZ, nnX, nnY, nnZ, 0, ooX, ooY, ooZ
AT_Assert ooX = aaX And ooY = aaY And ooZ = aaZ, "blend 0 returns the aim exactly"
AIM_Blend aaX, aaY, aaZ, nnX, nnY, nnZ, 1, ooX, ooY, ooZ
AT_Assert AT_Near%(ooX, 0.6) And AT_Near%(ooY, -0.8) And AT_Near%(ooZ, 0), "blend 1 returns the nose"
AIM_Blend aaX, aaY, aaZ, nnX, nnY, nnZ, 0.5, ooX, ooY, ooZ
AT_Assert AT_Near%(AT_Len!(ooX, ooY, ooZ), 1), "blend 0.5 is unit length"
AT_Assert AT_Near%(ooX, 0.7 / AT_Len!(0.7, -0.25, -0.05)) And AT_Near%(ooY, -0.25 / AT_Len!(0.7, -0.25, -0.05)), "blend 0.5 is the normalised midpoint"
AIM_Blend aaX, aaY, aaZ, aaX, aaY, aaZ, 0, aaX, aaY, aaZ
AT_Assert AT_Near%(aaX, 0.8) And AT_Near%(aaY, 0.3), "blend 0 in place leaves the aim alone"
nnX = 1 : nnY = 0 : nnZ = 0
AIM_Blend -1, 0, 0, nnX, nnY, nnZ, 0.5, ooX, ooY, ooZ
AT_Assert AT_Near%(ooX, 1) And AT_Near%(ooY, 0), "opposite aim and nose at 0.5 fall back to the nose"

' arc: nose along -X, target 30 degrees off in Y
nnX = -1 : nnY = 0 : nnZ = 0
ttX = -Cos(30 * _Pi / 180) : ttY = Sin(30 * _Pi / 180) : ttZ = 0
atOk = AIM_Arc%(nnX, nnY, nnZ, ttX, ttY, ttZ, 360, ooX, ooY, ooZ)
AT_Assert atOk And ooX = ttX And ooY = ttY And ooZ = ttZ, "arc 360 fires exactly at the target"
atOk = AIM_Arc%(nnX, nnY, nnZ, ttX, ttY, ttZ, 720, ooX, ooY, ooZ)
AT_Assert atOk And ooX = ttX And ooY = ttY And ooZ = ttZ, "arc above 360 fires exactly at the target"
atOk = AIM_Arc%(nnX, nnY, nnZ, ttX, ttY, ttZ, 0, ooX, ooY, ooZ)
AT_Assert atOk And ooX = ttX And ooY = ttY And ooZ = ttZ, "arc 0 means no limit"
atOk = AIM_Arc%(nnX, nnY, nnZ, ttX, ttY, ttZ, 120, ooX, ooY, ooZ)
AT_Assert atOk And ooX = ttX And ooY = ttY And ooZ = ttZ, "target inside half the arc is aimed at exactly"
atOk = AIM_Arc%(nnX, nnY, nnZ, ttX, ttY, ttZ, 40, ooX, ooY, ooZ)
AT_Assert atOk, "target 30 off, arc 40: fires"
AT_Assert AT_Near%(AT_AngleDeg!(ooX, ooY, ooZ, nnX, nnY, nnZ), 20), "shot clamped to half the arc (20) off the nose"
AT_Assert AT_Near%(AT_AngleDeg!(ooX, ooY, ooZ, ttX, ttY, ttZ), 10), "and still turned toward the target"
AT_Assert AT_Near%(AT_Len!(ooX, ooY, ooZ), 1) And AT_Near%(ooZ, 0) And ooY > 0, "unit length, in the nose-target plane"
atOk = AIM_Arc%(nnX, nnY, nnZ, ttX, ttY, ttZ, 29, ooX, ooY, ooZ)
AT_Assert atOk = 0, "target 30 off, arc 29: holds fire"
atOk = AIM_Arc%(nnX, nnY, nnZ, ttX, ttY, ttZ, 30, ooX, ooY, ooZ)
AT_Assert atOk <> 0 And AT_Near%(AT_AngleDeg!(ooX, ooY, ooZ, nnX, nnY, nnZ), 15), "target on the arc edge fires, 15 off the nose"
ttX = 1 : ttY = 0 : ttZ = 0
atOk = AIM_Arc%(nnX, nnY, nnZ, ttX, ttY, ttZ, 90, ooX, ooY, ooZ)
AT_Assert atOk = 0, "target behind the ship: holds fire"
atOk = AIM_Arc%(nnX, nnY, nnZ, ttX, ttY, ttZ, 360, ooX, ooY, ooZ)
AT_Assert atOk <> 0 And ooX = 1, "target behind the ship at arc 360: fires as before"
ttX = -Cos(30 * _Pi / 180) : ttY = 0 : ttZ = -Sin(30 * _Pi / 180)
atOk = AIM_Arc%(nnX, nnY, nnZ, ttX, ttY, ttZ, 40, ooX, ooY, ooZ)
AT_Assert atOk <> 0 And AT_Near%(AT_AngleDeg!(ooX, ooY, ooZ, nnX, nnY, nnZ), 20) And ooZ < 0 And AT_Near%(ooY, 0), "clamps the same way sideways"

' config
atOk = AIM_Set%(0.6, 60)
AT_Assert atOk <> 0 And AT_Near%(aimNoseBlend, 0.6) And aimArcDeg = 60, "config: blend 0.6, arc 60 accepted"
atOk = AIM_Set%(0, 360)
AT_Assert atOk <> 0 And aimNoseBlend = 0 And aimArcDeg = 0, "config: defaults give blend 0 and no arc limit"
atOk = AIM_Set%(1.5, 360)
AT_Assert atOk = 0 And Len(aimLoadErr) > 0, "config: blend above 1 rejected"
atOk = AIM_Set%(0, -5)
AT_Assert atOk = 0, "config: negative arc rejected"

Print ""
Print "=== " + LTrim$(Str$(atPassed + atFailed)) + " tests: " + LTrim$(Str$(atPassed)) + " passed, " + LTrim$(Str$(atFailed)) + " failed ==="
If atFailed > 0 Then System 1 Else System 0
