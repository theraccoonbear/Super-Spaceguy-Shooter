Const FX_MAX_PARTICLES = 250

Dim Shared fxPartActive(1 To FX_MAX_PARTICLES) As Integer
Dim Shared fxPartPX(1 To FX_MAX_PARTICLES)     As Single
Dim Shared fxPartPY(1 To FX_MAX_PARTICLES)     As Single
Dim Shared fxPartPZ(1 To FX_MAX_PARTICLES)     As Single
Dim Shared fxPartVX(1 To FX_MAX_PARTICLES)     As Single
Dim Shared fxPartVY(1 To FX_MAX_PARTICLES)     As Single
Dim Shared fxPartVZ(1 To FX_MAX_PARTICLES)     As Single
Dim Shared fxPartLife(1 To FX_MAX_PARTICLES)   As Integer
Dim Shared fxPartClr(1 To FX_MAX_PARTICLES)    As Long
Dim Shared fxShakeTimer As Integer
Dim Shared fxFlashTimer As Integer
Dim Shared fxShakeX     As Integer
Dim Shared fxShakeY     As Integer
Dim Shared fxVCRActive  As Integer

Sub FX_SpawnBurst(cx As Single, cy As Single, cz As Single, n As Integer, spd As Single, lifBase As Integer, lifVar As Integer, clr As Long)
    Dim i As Integer, found As Integer
    found = 0
    For i = 1 To FX_MAX_PARTICLES
        If fxPartActive(i) = 0 And found < n Then
            fxPartActive(i) = -1
            fxPartPX(i)     = cx
            fxPartPY(i)     = cy
            fxPartPZ(i)     = cz
            fxPartVX(i)     = (Rnd - 0.5) * spd
            fxPartVY(i)     = (Rnd - 0.5) * spd
            fxPartVZ(i)     = (Rnd - 0.5) * spd
            fxPartLife(i)   = lifBase + Int(Rnd * lifVar)
            fxPartClr(i)    = clr
            found = found + 1
        End If
    Next i
End Sub

Sub FX_SpawnTrail(cx As Single, cy As Single, cz As Single, n As Integer, spd As Single, lifBase As Integer, lifVar As Integer, clr As Long, bvx As Single, bvy As Single, bvz As Single)
    Dim fsti As Integer, fstFound As Integer
    fstFound = 0
    For fsti = 1 To FX_MAX_PARTICLES
        If fxPartActive(fsti) = 0 And fstFound < n Then
            fxPartActive(fsti) = -1
            fxPartPX(fsti)     = cx
            fxPartPY(fsti)     = cy
            fxPartPZ(fsti)     = cz
            fxPartVX(fsti)     = bvx + (Rnd - 0.5) * spd
            fxPartVY(fsti)     = bvy + (Rnd - 0.5) * spd
            fxPartVZ(fsti)     = bvz + (Rnd - 0.5) * spd
            fxPartLife(fsti)   = lifBase + Int(Rnd * lifVar)
            fxPartClr(fsti)    = clr
            fstFound = fstFound + 1
        End If
    Next fsti
End Sub

Sub FX_Update()
    Dim i As Integer
    For i = 1 To FX_MAX_PARTICLES
        If fxPartActive(i) Then
            fxPartPX(i) = fxPartPX(i) + fxPartVX(i)
            fxPartPY(i) = fxPartPY(i) + fxPartVY(i)
            fxPartPZ(i) = fxPartPZ(i) + fxPartVZ(i)
            fxPartLife(i) = fxPartLife(i) - 1
            If fxPartLife(i) <= 0 Then fxPartActive(i) = 0
        End If
    Next i
End Sub

Sub FX_Draw(vpMat As E3D_Matrix4, scrW As Single, scrH As Single)
    Dim i As Integer
    Dim pjX As Single, pjY As Single, pjW As Single
    Dim fade As Single, pr As Integer, pg As Integer, pb As Integer
    For i = 1 To FX_MAX_PARTICLES
        If fxPartActive(i) Then
            pjX = fxPartPX(i) * vpMat.m(0,0) + fxPartPY(i) * vpMat.m(0,1) + fxPartPZ(i) * vpMat.m(0,2) + vpMat.m(0,3)
            pjY = fxPartPX(i) * vpMat.m(1,0) + fxPartPY(i) * vpMat.m(1,1) + fxPartPZ(i) * vpMat.m(1,2) + vpMat.m(1,3)
            pjW = fxPartPX(i) * vpMat.m(3,0) + fxPartPY(i) * vpMat.m(3,1) + fxPartPZ(i) * vpMat.m(3,2) + vpMat.m(3,3)
            If pjW > 0.0001 Then
                pjX = (pjX / pjW + 1.0) * scrW * 0.5
                pjY = (1.0 - pjY / pjW) * scrH * 0.5
                If pjX >= 0 And pjX < scrW And pjY >= 0 And pjY < scrH Then
                    fade = fxPartLife(i) / 24.0
                    If fade > 1.0 Then fade = 1.0
                    pr = _Red32(fxPartClr(i))
                    pg = _Green32(fxPartClr(i))
                    pb = _Blue32(fxPartClr(i))
                    PSet (pjX, pjY), _RGB(Int(pr * fade), Int(pg * fade), Int(pb * fade))
                End If
            End If
        End If
    Next i
End Sub

Sub FX_Clear()
    Dim i As Integer
    For i = 1 To FX_MAX_PARTICLES
        fxPartActive(i) = 0
    Next i
End Sub

Sub FX_Flash(scrW As Single, scrH As Single)
    If fxFlashTimer > 0 Then
        Line (0, 0)-(scrW - 1, scrH - 1), _RGBA(220, 25, 25, 95), BF
        fxFlashTimer = fxFlashTimer - 1
    End If
End Sub

Sub FX_Shake(buf As Long, scrW As Single, scrH As Single)
    If fxShakeTimer > 0 Then
        fxShakeX = Int(Rnd * 9) - 4
        fxShakeY = Int(Rnd * 9) - 4
        fxShakeTimer = fxShakeTimer - 1
    Else
        fxShakeX = 0 : fxShakeY = 0
    End If
    Dim pDW As Long, pDH As Long
    pDW = _Width(0) : pDH = _Height(0)
    _Dest 0
    _PutImage (fxShakeX, fxShakeY)-(pDW - 1 + fxShakeX, pDH - 1 + fxShakeY), buf, 0
End Sub

Sub FX_VCRNoise(scrW As Single, scrH As Single)
    If Not fxVCRActive Then Exit Sub
    Dim vcrY As Integer, vcrBi As Integer, vcrHh As Integer
    ' scanline overlay — thin dark bars every 3 rows
    For vcrY = 0 To scrH - 1 Step 3
        LINE (0, vcrY)-(scrW - 1, vcrY), _RGBA(0, 0, 0, 50)
    Next vcrY
    ' tracking noise bands (2-4 per frame, random position/opacity)
    For vcrBi = 0 To 2
        If Rnd > 0.35 Then
            vcrY  = Int(Rnd * scrH)
            vcrHh = 1 + Int(Rnd * 3)
            LINE (0, vcrY)-(scrW - 1, vcrY + vcrHh), _RGBA(200 + Int(Rnd * 55), 195 + Int(Rnd * 55), 185 + Int(Rnd * 55), 55 + Int(Rnd * 90)), BF
        End If
    Next vcrBi
End Sub
