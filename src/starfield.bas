Const E3D_SF_MAX = 400

Dim Shared E3D_sfCount As Integer
Dim Shared E3D_sfX(1 To E3D_SF_MAX)   As Single
Dim Shared E3D_sfY(1 To E3D_SF_MAX)   As Single
Dim Shared E3D_sfZ(1 To E3D_SF_MAX)   As Single
Dim Shared E3D_sfVX(1 To E3D_SF_MAX)  As Single
Dim Shared E3D_sfClr(1 To E3D_SF_MAX) As Long
Dim Shared E3D_sfRY(1 To E3D_SF_MAX)  As Single   ' per-star lateral recycle range
Dim Shared E3D_sfRZ(1 To E3D_SF_MAX)  As Single
Dim Shared E3D_sfLastCamY As Single
Dim Shared E3D_sfLastCamZ As Single

' Reset the starfield and record the starting camera position.
Sub E3D_StarfieldInit (camY As Single, camZ As Single)
    E3D_sfCount    = 0
    E3D_sfLastCamY = camY
    E3D_sfLastCamZ = camZ
End Sub

' Append a layer of stars spread around the current camera position.
' bright: 0 = dim/far, 1 = medium, 2 = bright/near
Sub E3D_StarfieldAddLayer (camX As Single, camY As Single, camZ As Single, count As Integer, rangeX As Single, rangeY As Single, rangeZ As Single, spdMin As Single, spdMax As Single, bright As Integer)
    Dim colors(0 To 2) As Long
    Dim i As Integer, n As Integer
    Select Case bright
        Case 0
            colors(0) = _RGB( 45,  45,  60)
            colors(1) = _RGB( 65,  65,  80)
            colors(2) = _RGB( 85,  85, 105)
        Case 1
            colors(0) = _RGB(100, 100, 120)
            colors(1) = _RGB(150, 150, 170)
            colors(2) = _RGB(195, 195, 215)
        Case Else
            colors(0) = _RGB(190, 190, 210)
            colors(1) = _RGB(225, 225, 240)
            colors(2) = _RGB(255, 255, 255)
    End Select
    For i = 1 To count
        If E3D_sfCount < E3D_SF_MAX Then
            E3D_sfCount = E3D_sfCount + 1
            n = E3D_sfCount
            E3D_sfX(n)   = camX + Rnd * rangeX
            E3D_sfY(n)   = camY + Rnd * rangeY - rangeY * 0.5
            E3D_sfZ(n)   = camZ + Rnd * rangeZ - rangeZ * 0.5
            E3D_sfVX(n)  = -(spdMin + Rnd * (spdMax - spdMin))
            E3D_sfRY(n)  = rangeY
            E3D_sfRZ(n)  = rangeZ
            E3D_sfClr(n) = colors(Int(Rnd * 3))
        End If
    Next i
End Sub

' Scroll stars in X; shift all Y/Z by the camera's movement delta so the
' field tracks the player laterally — gives the "infinite space" feel.
Sub E3D_StarfieldUpdate (camX As Single, camY As Single, camZ As Single)
    Dim i As Integer
    Dim dY As Single, dZ As Single
    Dim ry As Single, rz As Single
    dY = camY - E3D_sfLastCamY
    dZ = camZ - E3D_sfLastCamZ
    E3D_sfLastCamY = camY
    E3D_sfLastCamZ = camZ
    For i = 1 To E3D_sfCount
        E3D_sfX(i) = E3D_sfX(i) + E3D_sfVX(i)
        E3D_sfY(i) = E3D_sfY(i) + dY
        E3D_sfZ(i) = E3D_sfZ(i) + dZ
        If E3D_sfX(i) < camX - 2 Then
            ry = E3D_sfRY(i)
            rz = E3D_sfRZ(i)
            E3D_sfX(i) = camX + 20 + Rnd * 30
            E3D_sfY(i) = camY + Rnd * ry - ry * 0.5
            E3D_sfZ(i) = camZ + Rnd * rz - rz * 0.5
        End If
    Next i
End Sub

' Project and draw all stars into the current _Dest surface.
Sub E3D_StarfieldDraw (vpMat As E3D_Matrix4, scrW As Single, scrH As Single)
    Dim i As Integer
    Dim svx As Single, svy As Single, svw As Single
    Dim ssx As Single, ssy As Single
    For i = 1 To E3D_sfCount
        svx = E3D_sfX(i) * vpMat.m(0,0) + E3D_sfY(i) * vpMat.m(0,1) + E3D_sfZ(i) * vpMat.m(0,2) + vpMat.m(0,3)
        svy = E3D_sfX(i) * vpMat.m(1,0) + E3D_sfY(i) * vpMat.m(1,1) + E3D_sfZ(i) * vpMat.m(1,2) + vpMat.m(1,3)
        svw = E3D_sfX(i) * vpMat.m(3,0) + E3D_sfY(i) * vpMat.m(3,1) + E3D_sfZ(i) * vpMat.m(3,2) + vpMat.m(3,3)
        If svw > 0.00001 Then
            ssx = (svx / svw + 1.0) * (scrW * 0.5)
            ssy = (1.0 - svy / svw) * (scrH * 0.5)
            If ssx >= 0 And ssx < scrW Then
                If ssy >= 0 And ssy < scrH Then
                    PSet (ssx, ssy), E3D_sfClr(i)
                End If
            End If
        End If
    Next i
End Sub

Sub StarfieldReset(srX As Single, srY As Single, srZ As Single)
    E3D_StarfieldInit srY, srZ
    E3D_StarfieldAddLayer srX, srY, srZ, 200, 50, 50, 40, 0.010, 0.020, 0
    E3D_StarfieldAddLayer srX, srY, srZ,  60, 40, 30, 25, 0.035, 0.070, 1
    E3D_StarfieldAddLayer srX, srY, srZ,  15, 25, 15, 12, 0.100, 0.180, 2
End Sub
