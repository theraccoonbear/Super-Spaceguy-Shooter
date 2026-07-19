Const E3D_SF_MAX  = 400
Const BELT_MAX    = 100

Dim Shared bltCount                    As Integer
Dim Shared bltActive                   As Integer
Dim Shared bltAngle(1 To BELT_MAX)     As Single   ' radial direction from screen center
Dim Shared bltDepth(1 To BELT_MAX)     As Single   ' current radius from center (pixels)
Dim Shared bltDSpd(1 To BELT_MAX)      As Single   ' depth growth per frame
Dim Shared bltSz(1 To BELT_MAX)        As Integer  ' size tier 0-3 (also controls speed)
Dim Shared bltClr(1 To BELT_MAX)       As Long
Dim Shared bltMaxD                     As Single   ' screen half-diagonal
Dim Shared bltCtrX                     As Single   ' belt vanishing point screen X (set by playing.bas)
Dim Shared bltCtrY                     As Single   ' belt vanishing point screen Y

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

' Belt parallax: earthen pebbles that radiate outward from the screen center,
' exactly like the starfield but in the 2D projection plane.
' Bigger size tier = faster speed = closer debris.
Sub BELT_Init(bliW As Single, bliH As Single)
    Dim bliI As Integer, bliR As Single
    Dim bliColors(0 To 4) As Long
    bliColors(0) = _RGB( 70,  55,  40)
    bliColors(1) = _RGB( 55,  38,  22)
    bliColors(2) = _RGB( 60,  60,  60)
    bliColors(3) = _RGB( 78,  42,  28)
    bliColors(4) = _RGB( 45,  45,  50)
    bltMaxD   = SQR(bliW * bliW * 0.25 + bliH * bliH * 0.25)
    bltCtrX   = bliW * 0.5
    bltCtrY   = bliH * 0.5
    bltCount  = 0
    bltActive = -1
    For bliI = 1 To BELT_MAX
        bliR = RND
        If bliR < 0.40 Then
            bltSz(bliI) = 0
        ElseIf bliR < 0.70 Then
            bltSz(bliI) = 1
        ElseIf bliR < 0.88 Then
            bltSz(bliI) = 2
        Else
            bltSz(bliI) = 3
        End If
        bltAngle(bliI) = RND * _PI(2)
        bltDepth(bliI) = RND * bltMaxD     ' scatter so they don't all flash from center at once
        Select Case bltSz(bliI)
        Case 0 : bltDSpd(bliI) = 0.15 + RND * 0.20
        Case 1 : bltDSpd(bliI) = 0.30 + RND * 0.25
        Case 2 : bltDSpd(bliI) = 0.55 + RND * 0.35
        Case Else : bltDSpd(bliI) = 1.0 + RND * 0.6
        End Select
        bltClr(bliI) = bliColors(Int(RND * 5))
        bltCount     = bltCount + 1
    Next bliI
End Sub

Sub BELT_Update(bluW As Single, bluH As Single)
    Dim bluI As Integer
    For bluI = 1 To bltCount
        bltDepth(bluI) = bltDepth(bluI) + bltDSpd(bluI)
        If bltDepth(bluI) > bltMaxD * 1.05 Then
            bltAngle(bluI) = RND * _PI(2)
            bltDepth(bluI) = RND * 4
        End If
    Next bluI
End Sub

Sub BELT_Draw(bldW As Single, bldH As Single)
    Dim bldI As Integer, bldX As Integer, bldY As Integer
    Dim bldCX As Single, bldCY As Single, bldC As Long
    Dim bldDF As Single, bldR As Integer
    Dim bldYY As Integer, bldXW As Integer
    bldCX = bltCtrX
    bldCY = bltCtrY
    For bldI = 1 To bltCount
        bldX = Int(bldCX + COS(bltAngle(bldI)) * bltDepth(bldI))
        bldY = Int(bldCY + SIN(bltAngle(bldI)) * bltDepth(bldI))
        If bldX >= 0 And bldX < bldW And bldY >= 0 And bldY < bldH Then
            bldC  = bltClr(bldI)
            bldDF = bltDepth(bldI) / bltMaxD
            bldR  = Int(bltSz(bldI) * bldDF * 1.8 + 0.1)
            Select Case bldR
            Case 0
                PSet (bldX, bldY), bldC
            Case 1
                PSet (bldX, bldY), bldC
                PSet (bldX + 1, bldY), bldC : PSet (bldX - 1, bldY), bldC
                PSet (bldX, bldY + 1), bldC : PSet (bldX, bldY - 1), bldC
            Case Else
                ' scanline fill: vastly faster than Circle+Paint flood fill
                For bldYY = -bldR To bldR
                    bldXW = Int(Sqr(bldR * bldR - bldYY * bldYY) + 0.5)
                    Line (bldX - bldXW, bldY + bldYY)-(bldX + bldXW, bldY + bldYY), bldC
                Next bldYY
            End Select
        End If
    Next bldI
End Sub

Sub StarfieldReset(srX As Single, srY As Single, srZ As Single)
    E3D_StarfieldInit srY, srZ
    E3D_StarfieldAddLayer srX, srY, srZ, 200, 50, 50, 40, 0.010, 0.020, 0
    E3D_StarfieldAddLayer srX, srY, srZ,  60, 40, 30, 25, 0.035, 0.070, 1
    E3D_StarfieldAddLayer srX, srY, srZ,  15, 25, 15, 12, 0.100, 0.180, 2
End Sub
