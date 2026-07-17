Sub COMBAT_SceneDraw()
    Dim cbtDJ As Integer
    Dim cbtDDist As Single, cbtDDimF As Single
    Static cbtDBossDbgLogged As Integer
    Dim cbtDBossScnBefore As Integer

    For cbtDJ = 1 To MAX_ENEMIES
        If enemies(cbtDJ).active Then
            If enemies(cbtDJ).px > cam.POS.x Then
                pPos.x = enemies(cbtDJ).px : pPos.y = enemies(cbtDJ).py : pPos.z = enemies(cbtDJ).pz
                pRot.x = enemies(cbtDJ).rx : pRot.y = enemies(cbtDJ).ry : pRot.z = enemies(cbtDJ).rz
                E3D_BuildObjectMat pPos, pRot, enemies(cbtDJ).scl, objMat
                cbtDDist = enemies(cbtDJ).px - player.px
                If cbtDDist > DIM_FAR Then
                    cbtDDimF = DIM_AMBIENT
                ElseIf cbtDDist > DIM_NEAR Then
                    cbtDDimF = DIM_AMBIENT + (cbtDDist - DIM_NEAR) * ((1.0 - DIM_AMBIENT) / (DIM_FAR - DIM_NEAR))
                Else
                    cbtDDimF = 1.0
                End If
                eLitDir.x = lightDir.x * cbtDDimF
                eLitDir.y = lightDir.y * cbtDDimF
                eLitDir.z = lightDir.z * cbtDDimF
                E3D_SceneAddMeshLit meshLib(enemies(cbtDJ).meshIdx), objMat, cam.POS, tt, eLitDir
            End If
        End If
    Next cbtDJ

    If boss.active Then
        pPos.x = boss.px : pPos.y = boss.py : pPos.z = boss.pz
        pRot.x = boss.rx : pRot.y = boss.ry : pRot.z = boss.rz
        E3D_BuildObjectMat pPos, pRot, boss.scl, objMat
        cbtDDist = boss.px - player.px
        If cbtDDist > DIM_FAR Then
            cbtDDimF = 0.35
        ElseIf cbtDDist > DIM_NEAR Then
            cbtDDimF = 0.35 + (cbtDDist - DIM_NEAR) * (0.65 / (DIM_FAR - DIM_NEAR))
        Else
            cbtDDimF = 1.0
        End If
        eLitDir.x = lightDir.x * cbtDDimF
        eLitDir.y = lightDir.y * cbtDDimF
        eLitDir.z = lightDir.z * cbtDDimF
        cbtDBossScnBefore = E3D_scnCount
        E3D_SceneAddMeshLit meshLib(MESH_BOSS), objMat, cam.POS, tt, eLitDir
        If debugMode And cbtDBossDbgLogged = 0 Then
            DBG_Print "[boss-rend] faces_rendered=" + LTrim$(Str$(E3D_scnCount - cbtDBossScnBefore)) + "  dist=" + LTrim$(Str$(boss.px - cam.POS.x))
            cbtDBossDbgLogged = -1
        End If
    End If
End Sub

Sub COMBAT_OverlayDraw()
    Dim cbtOJ As Integer
    Dim cbtOEBClr As Long
    Dim cbtOPjX As Single, cbtOPjY As Single, cbtOPjW As Single
    Dim cbtOPjX2 As Single, cbtOPjY2 As Single, cbtOPjW2 As Single
    Dim cbtOPjBX As Single, cbtOPjBY As Single, cbtOPjBZ As Single
    Dim cbtOPjFade As Single
    Dim cbtOPartR As Integer
    Dim cbtOBdbVx As Single, cbtOBdbVy As Single, cbtOBdbVz As Single, cbtOBdbW As Single
    Dim cbtOBdbSx(1 To 8) As Single, cbtOBdbSy(1 To 8) As Single
    Dim cbtOBdbAllFwd As Integer, cbtOBdbI As Integer
    Dim cbtOBdbMinX As Single, cbtOBdbMaxX As Single
    Dim cbtOBdbMinY As Single, cbtOBdbMaxY As Single
    Dim cbtOBdbHx As Single, cbtOBdbHy As Single, cbtOBdbHz As Single

    ' [DEBUG] yellow AABB box overlay around boss
    If debugMode And boss.active Then
        cbtOBdbHx = boxLib(MESH_BOSS).hx
        cbtOBdbHy = boxLib(MESH_BOSS).hy
        cbtOBdbHz = boxLib(MESH_BOSS).hz
        cbtOBdbAllFwd = -1
        For cbtOBdbI = 1 To 8
            If (cbtOBdbI And 1) Then cbtOBdbVx = boss.px + cbtOBdbHx Else cbtOBdbVx = boss.px - cbtOBdbHx
            If (cbtOBdbI And 2) Then cbtOBdbVy = boss.py + cbtOBdbHy Else cbtOBdbVy = boss.py - cbtOBdbHy
            If (cbtOBdbI And 4) Then cbtOBdbVz = boss.pz + cbtOBdbHz Else cbtOBdbVz = boss.pz - cbtOBdbHz
            cbtOBdbW = cbtOBdbVx * vpMat.m(3,0) + cbtOBdbVy * vpMat.m(3,1) + cbtOBdbVz * vpMat.m(3,2) + vpMat.m(3,3)
            If cbtOBdbW > 0.0001 Then
                cbtOBdbSx(cbtOBdbI) = ((cbtOBdbVx * vpMat.m(0,0) + cbtOBdbVy * vpMat.m(0,1) + cbtOBdbVz * vpMat.m(0,2) + vpMat.m(0,3)) / cbtOBdbW + 1.0) * scrW * 0.5
                cbtOBdbSy(cbtOBdbI) = (1.0 - (cbtOBdbVx * vpMat.m(1,0) + cbtOBdbVy * vpMat.m(1,1) + cbtOBdbVz * vpMat.m(1,2) + vpMat.m(1,3)) / cbtOBdbW) * scrH * 0.5
            Else
                cbtOBdbAllFwd = 0
            End If
        Next cbtOBdbI
        If cbtOBdbAllFwd Then
            cbtOBdbMinX = cbtOBdbSx(1) : cbtOBdbMaxX = cbtOBdbSx(1)
            cbtOBdbMinY = cbtOBdbSy(1) : cbtOBdbMaxY = cbtOBdbSy(1)
            For cbtOBdbI = 2 To 8
                If cbtOBdbSx(cbtOBdbI) < cbtOBdbMinX Then cbtOBdbMinX = cbtOBdbSx(cbtOBdbI)
                If cbtOBdbSx(cbtOBdbI) > cbtOBdbMaxX Then cbtOBdbMaxX = cbtOBdbSx(cbtOBdbI)
                If cbtOBdbSy(cbtOBdbI) < cbtOBdbMinY Then cbtOBdbMinY = cbtOBdbSy(cbtOBdbI)
                If cbtOBdbSy(cbtOBdbI) > cbtOBdbMaxY Then cbtOBdbMaxY = cbtOBdbSy(cbtOBdbI)
            Next cbtOBdbI
            _Dest backBuffer
            Line (cbtOBdbMinX, cbtOBdbMinY)-(cbtOBdbMaxX, cbtOBdbMaxY), _RGB(255, 255, 0), B
        End If
    End If

    _Dest backBuffer

    ' player bullets
    For cbtOJ = 1 To MAX_BULLETS
        If bullets(cbtOJ).active Then
            cbtOPjX  = bullets(cbtOJ).px * vpMat.m(0,0) + bullets(cbtOJ).py * vpMat.m(0,1) + bullets(cbtOJ).pz * vpMat.m(0,2) + vpMat.m(0,3)
            cbtOPjY  = bullets(cbtOJ).px * vpMat.m(1,0) + bullets(cbtOJ).py * vpMat.m(1,1) + bullets(cbtOJ).pz * vpMat.m(1,2) + vpMat.m(1,3)
            cbtOPjW  = bullets(cbtOJ).px * vpMat.m(3,0) + bullets(cbtOJ).py * vpMat.m(3,1) + bullets(cbtOJ).pz * vpMat.m(3,2) + vpMat.m(3,3)
            cbtOPjBX = bullets(cbtOJ).px - bullets(cbtOJ).vx * (BULLET_TRAIL_LEN / BULLET_SPEED)
            cbtOPjBY = bullets(cbtOJ).py - bullets(cbtOJ).vy * (BULLET_TRAIL_LEN / BULLET_SPEED)
            cbtOPjBZ = bullets(cbtOJ).pz - bullets(cbtOJ).vz * (BULLET_TRAIL_LEN / BULLET_SPEED)
            cbtOPjX2 = cbtOPjBX * vpMat.m(0,0) + cbtOPjBY * vpMat.m(0,1) + cbtOPjBZ * vpMat.m(0,2) + vpMat.m(0,3)
            cbtOPjY2 = cbtOPjBX * vpMat.m(1,0) + cbtOPjBY * vpMat.m(1,1) + cbtOPjBZ * vpMat.m(1,2) + vpMat.m(1,3)
            cbtOPjW2 = cbtOPjBX * vpMat.m(3,0) + cbtOPjBY * vpMat.m(3,1) + cbtOPjBZ * vpMat.m(3,2) + vpMat.m(3,3)
            If cbtOPjW > 0.0001 And cbtOPjW2 > 0.0001 Then
                cbtOPjX  = (cbtOPjX  / cbtOPjW  + 1.0) * scrW * 0.5
                cbtOPjY  = (1.0 - cbtOPjY  / cbtOPjW)  * scrH * 0.5
                cbtOPjX2 = (cbtOPjX2 / cbtOPjW2 + 1.0) * scrW * 0.5
                cbtOPjY2 = (1.0 - cbtOPjY2 / cbtOPjW2) * scrH * 0.5
                If cbtOPjX >= 0 And cbtOPjX < scrW And cbtOPjY >= 0 And cbtOPjY < scrH Then
                    cbtOPjFade = bullets(cbtOJ).life / (BULLET_RANGE / BULLET_SPEED)
                    If cbtOPjFade > 1.0 Then cbtOPjFade = 1.0
                    Line (Int(cbtOPjX2), Int(cbtOPjY2))-(Int(cbtOPjX), Int(cbtOPjY)), _RGB(Int(210*cbtOPjFade), Int(215*cbtOPjFade), Int(60*cbtOPjFade))
                    PSet (Int(cbtOPjX), Int(cbtOPjY)), _RGB(Int(240*cbtOPjFade), Int(245*cbtOPjFade), Int(140*cbtOPjFade))
                End If
            End If
        End If
    Next cbtOJ

    ' enemy bullets
    For cbtOJ = 1 To MAX_EBULLETS
        If ebullets(cbtOJ).active Then
            cbtOPjX = ebullets(cbtOJ).px * vpMat.m(0,0) + ebullets(cbtOJ).py * vpMat.m(0,1) + ebullets(cbtOJ).pz * vpMat.m(0,2) + vpMat.m(0,3)
            cbtOPjY = ebullets(cbtOJ).px * vpMat.m(1,0) + ebullets(cbtOJ).py * vpMat.m(1,1) + ebullets(cbtOJ).pz * vpMat.m(1,2) + vpMat.m(1,3)
            cbtOPjW = ebullets(cbtOJ).px * vpMat.m(3,0) + ebullets(cbtOJ).py * vpMat.m(3,1) + ebullets(cbtOJ).pz * vpMat.m(3,2) + vpMat.m(3,3)
            If cbtOPjW > 0.0001 Then
                cbtOPjX = (cbtOPjX / cbtOPjW + 1.0) * scrW * 0.5
                cbtOPjY = (1.0 - cbtOPjY / cbtOPjW) * scrH * 0.5
                If cbtOPjX >= 4 And cbtOPjX < scrW - 4 And cbtOPjY >= 3 And cbtOPjY < scrH - 3 Then
                    Select Case ebullets(cbtOJ).meshIdx
                    Case MESH_BOSS         : cbtOEBClr = _RGB(255, 200,   0)
                    Case MESH_ENEMY        : cbtOEBClr = _RGB(255,  80,  60)
                    Case MESH_ENEMY_ARROW  : cbtOEBClr = _RGB(220,  35,  65)
                    Case MESH_ENEMY_HLINE  : cbtOEBClr = _RGB( 80, 140, 255)
                    Case MESH_ENEMY_VCOL   : cbtOEBClr = _RGB(180,  65, 255)
                    Case MESH_ENEMY_PINCER : cbtOEBClr = _RGB(255,  45, 190)
                    Case Else              : cbtOEBClr = _RGB(185,  80, 255)
                    End Select
                    Line (cbtOPjX - 4, cbtOPjY)-(cbtOPjX + 4, cbtOPjY), cbtOEBClr
                    Line (cbtOPjX, cbtOPjY - 2)-(cbtOPjX, cbtOPjY + 2), cbtOEBClr
                    PSet (cbtOPjX, cbtOPjY), _RGB(255, 255, 255)
                End If
            End If
        End If
    Next cbtOJ

    ' spawn flash
    If spawnFlashTimer > 0 Then
        cbtOPjX = spawnFlashPX * vpMat.m(0,0) + spawnFlashPY * vpMat.m(0,1) + spawnFlashPZ * vpMat.m(0,2) + vpMat.m(0,3)
        cbtOPjY = spawnFlashPX * vpMat.m(1,0) + spawnFlashPY * vpMat.m(1,1) + spawnFlashPZ * vpMat.m(1,2) + vpMat.m(1,3)
        cbtOPjW = spawnFlashPX * vpMat.m(3,0) + spawnFlashPY * vpMat.m(3,1) + spawnFlashPZ * vpMat.m(3,2) + vpMat.m(3,3)
        If cbtOPjW > 0.0001 Then
            cbtOPjX = (cbtOPjX / cbtOPjW + 1.0) * scrW * 0.5
            cbtOPjY = (1.0 - cbtOPjY / cbtOPjW) * scrH * 0.5
            If cbtOPjX >= 3 And cbtOPjX < scrW - 3 And cbtOPjY >= 3 And cbtOPjY < scrH - 3 Then
                cbtOPartR = spawnFlashTimer * 26
                Line (cbtOPjX - 4, cbtOPjY)-(cbtOPjX + 4, cbtOPjY), _RGB(cbtOPartR, cbtOPartR, cbtOPartR)
                Line (cbtOPjX, cbtOPjY - 4)-(cbtOPjX, cbtOPjY + 4), _RGB(cbtOPartR, cbtOPartR, cbtOPartR)
            End If
        End If
        spawnFlashTimer = spawnFlashTimer - 1
    End If
End Sub
