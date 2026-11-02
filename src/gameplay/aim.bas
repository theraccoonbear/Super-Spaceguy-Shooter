' aim.bas -- which way a shot leaves a ship (#199). No rendering or game state here, so tests can
' drive it with plain numbers:
'
'   AIM_Nose rx,ry,rz, nx,ny,nz            unit vector a ship's model +X axis points along, from its
'                                          attitude in degrees (the order E3D_BuildObjectMat uses)
'   AIM_Blend ax,ay,az, nx,ny,nz, b, ox,oy,oz
'                                          player: direction between the aimed shot (a) and the nose
'                                          (n); b = 0 returns a untouched, b = 1 the nose
'   ok = AIM_Arc%(nx,ny,nz, tx,ty,tz, arcDeg, ox,oy,oz)
'                                          enemy / boss: nose n, unit direction t to the target. ok is
'                                          0 (hold fire) when the angle between them is over arcDeg;
'                                          otherwise o is t turned toward the nose so it is never more
'                                          than arcDeg / 2 off the nose. arcDeg <= 0 or >= 360 means no
'                                          limit: o is t untouched, ok is -1
'   ok = AIM_Set%(blend, arcDeg)           the two config values (assets/config/waves.ini)
'
' Local variable prefix: aim*

Dim Shared aimNoseBlend As Single   ' player_nose_blend: 0 = today's aim
Dim Shared aimArcDeg As Single      ' enemy_fire_arc_deg: 0 (stored for 360 and up) = no limit
Dim Shared aimLoadErr As String

Function AIM_Set% (aimsBlend As Single, aimsArc As Single)
    AIM_Set% = 0
    aimLoadErr = ""
    If aimsBlend < 0 Or aimsBlend > 1 Then aimLoadErr = "config/waves.ini player_nose_blend must be 0 to 1" : Exit Function
    If aimsArc < 0 Then aimLoadErr = "config/waves.ini enemy_fire_arc_deg must be 0 or more (0 and 360 or more = no limit)" : Exit Function
    aimNoseBlend = aimsBlend
    If aimsArc >= 360 Then aimArcDeg = 0 Else aimArcDeg = aimsArc
    AIM_Set% = -1
End Function

Sub AIM_Nose (aimNRx As Single, aimNRy As Single, aimNRz As Single, aimNX As Single, aimNY As Single, aimNZ As Single)
    Dim aimNCx As Single, aimNSx As Single, aimNCy As Single, aimNSy As Single, aimNCz As Single, aimNSz As Single
    aimNCx = Cos(aimNRx * _Pi / 180.0) : aimNSx = Sin(aimNRx * _Pi / 180.0)
    aimNCy = Cos(aimNRy * _Pi / 180.0) : aimNSy = Sin(aimNRy * _Pi / 180.0)
    aimNCz = Cos(aimNRz * _Pi / 180.0) : aimNSz = Sin(aimNRz * _Pi / 180.0)
    aimNX = aimNCz * aimNCy
    aimNY = aimNCx * aimNSz + aimNSx * aimNCz * aimNSy
    aimNZ = aimNSx * aimNSz - aimNCx * aimNCz * aimNSy
End Sub

Sub AIM_Blend (aimAx As Single, aimAy As Single, aimAz As Single, aimBnx As Single, aimBny As Single, aimBnz As Single, aimBb As Single, aimOx As Single, aimOy As Single, aimOz As Single)
    Dim aimBx As Single, aimBy As Single, aimBz As Single, aimBm As Single
    If aimBb <= 0 Then aimOx = aimAx : aimOy = aimAy : aimOz = aimAz : Exit Sub
    aimBx = aimAx + (aimBnx - aimAx) * aimBb
    aimBy = aimAy + (aimBny - aimAy) * aimBb
    aimBz = aimAz + (aimBnz - aimAz) * aimBb
    aimBm = Sqr(aimBx * aimBx + aimBy * aimBy + aimBz * aimBz)
    If aimBm < 0.000001 Then
        aimOx = aimBnx : aimOy = aimBny : aimOz = aimBnz
    Else
        aimOx = aimBx / aimBm : aimOy = aimBy / aimBm : aimOz = aimBz / aimBm
    End If
End Sub

Function AIM_Arc% (aimNx As Single, aimNy As Single, aimNz As Single, aimTx As Single, aimTy As Single, aimTz As Single, aimArc As Single, aimOx As Single, aimOy As Single, aimOz As Single)
    Dim aimD As Single, aimAng As Single, aimHalf As Single
    Dim aimPx As Single, aimPy As Single, aimPz As Single, aimPm As Single
    aimOx = aimTx : aimOy = aimTy : aimOz = aimTz
    AIM_Arc% = -1
    If aimArc <= 0 Or aimArc >= 360 Then Exit Function
    aimD = aimNx * aimTx + aimNy * aimTy + aimNz * aimTz
    If aimD > 1 Then aimD = 1
    If aimD < -1 Then aimD = -1
    aimAng = _Acos(aimD) * 180.0 / _Pi
    If aimAng > aimArc Then AIM_Arc% = 0 : Exit Function
    aimHalf = aimArc / 2
    If aimAng <= aimHalf Then Exit Function
    aimPx = aimTx - aimNx * aimD : aimPy = aimTy - aimNy * aimD : aimPz = aimTz - aimNz * aimD
    aimPm = Sqr(aimPx * aimPx + aimPy * aimPy + aimPz * aimPz)
    If aimPm < 0.000001 Then aimOx = aimNx : aimOy = aimNy : aimOz = aimNz : Exit Function
    aimHalf = aimHalf * _Pi / 180.0
    aimOx = aimNx * Cos(aimHalf) + aimPx / aimPm * Sin(aimHalf)
    aimOy = aimNy * Cos(aimHalf) + aimPy / aimPm * Sin(aimHalf)
    aimOz = aimNz * Cos(aimHalf) + aimPz / aimPm * Sin(aimHalf)
End Function
