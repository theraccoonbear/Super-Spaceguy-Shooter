Const EB_BOLT_LEN    = 1.4    ' world-unit length of an enemy bolt's streak
Const EB_BOLT_R      = 0.14   ' world-unit glow radius (projected, so it grows as it nears)
Const EB_HOT_DIST    = 3      ' at or nearer than this (X from player): full heat
Const EB_COLD_DIST   = 30     ' at or beyond this: coolest, dimmest
Const EB_COLD_BRIGHT = 0.35   ' brightness at EB_COLD_DIST, so far shots never outshine ships
Const DEV_CHEV_NEAR  = 20     ' devour drag chevrons: pixels from the ship where they start (clear of its hull)
Const DEV_CHEV_FAR   = 52     ' ... and where they fade out
Const DEV_CHEV_SIZE  = 7      ' chevron half-width / depth in pixels

' World point -> backBuffer pixel; cpOk = 0 when it's behind the camera.
Sub COMBAT_Project(cpX As Single, cpY As Single, cpZ As Single, cpSX As Single, cpSY As Single, cpOk As Integer)
    Dim cpW As Single
    cpW = cpX * vpMat.m(3,0) + cpY * vpMat.m(3,1) + cpZ * vpMat.m(3,2) + vpMat.m(3,3)
    cpOk = (cpW > 0.0001)
    If cpOk = 0 Then Exit Sub
    cpSX = ((cpX * vpMat.m(0,0) + cpY * vpMat.m(0,1) + cpZ * vpMat.m(0,2) + vpMat.m(0,3)) / cpW + 1.0) * scrW * 0.5
    cpSY = (1.0 - (cpX * vpMat.m(1,0) + cpY * vpMat.m(1,1) + cpZ * vpMat.m(1,2) + vpMat.m(1,3)) / cpW) * scrH * 0.5
End Sub

' Closing impact ring at world point (irX, irY, irZ), world radius irR. irFrac 1 = just
' appeared (faint, base colour), 0 = impact now (solid, red).
Sub COMBAT_ImpactRing(irX As Single, irY As Single, irZ As Single, irR As Single, irFrac As Single, irCR As Integer, irCG As Integer, irCB As Integer)
    Dim irSX As Single, irSY As Single, irEX As Single, irEY As Single, irOk As Integer, irOk2 As Integer
    Dim irPx As Single, irA As Integer, irG As Integer, irB As Integer
    COMBAT_Project irX, irY, irZ, irSX, irSY, irOk
    COMBAT_Project irX, irY + irR, irZ, irEX, irEY, irOk2
    If irOk = 0 Or irOk2 = 0 Then Exit Sub
    irPx = Abs(irSY - irEY)
    If irPx < 2 Or irPx > 400 Then Exit Sub
    irA = Int(60 + 170 * (1 - irFrac))
    irG = Int(irCG * irFrac + 30 * (1 - irFrac))
    irB = Int(irCB * irFrac + 30 * (1 - irFrac))
    Circle (irSX, irSY), irPx, _RGBA(irCR, irG, irB, irA)
    Circle (irSX, irSY), irPx + 1, _RGBA(irCR, irG, irB, irA \ 2)
End Sub

' One ">" chevron pointing along screen direction (chUX, chUY) from (chX, chY), its back
' chD pixels out; DEV_CHEV_SIZE deep and half-wide.
Sub COMBAT_Chevron(chX As Single, chY As Single, chUX As Single, chUY As Single, chD As Single, chClr As Long)
    Dim chTX As Single, chTY As Single, chBX As Single, chBY As Single
    chTX = chX + chUX * (chD + DEV_CHEV_SIZE) : chTY = chY + chUY * (chD + DEV_CHEV_SIZE)
    chBX = chX + chUX * chD : chBY = chY + chUY * chD
    Line (chBX - chUY * DEV_CHEV_SIZE, chBY + chUX * DEV_CHEV_SIZE)-(chTX, chTY), chClr
    Line (chBX + chUY * DEV_CHEV_SIZE, chBY - chUX * DEV_CHEV_SIZE)-(chTX, chTY), chClr
End Sub

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
        ' models.e3d's BOSS "axisfix -1 1 -1" re-orients the mesh for TrailForge's
        ' basis renderer; the Euler attitude above was tuned on the unflipped mesh,
        ' so undo the flip here (diag(-1,1,-1) is its own inverse).
        Dim cbtBossAxFix As E3D_Matrix4
        E3D_MatIdentity cbtBossAxFix
        cbtBossAxFix.m(0, 0) = -1 : cbtBossAxFix.m(2, 2) = -1
        E3D_MatMul objMat, cbtBossAxFix, objMat
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
    Dim cbtSpR As Single, cbtSpRing As Integer, cbtSpA As Integer
    Dim cbtEbF As Single, cbtEbMag As Single, cbtEbS As Single
    Dim cbtEbOk As Integer, cbtEbOk2 As Integer, cbtEbOk3 As Integer
    Dim cbtEbRX As Single, cbtEbRY As Single, cbtEbGX As Single, cbtEbGY As Single
    Dim cbtEbK As Integer, cbtEbR As Integer
    Dim cbtEbFr As Single, cbtEbCY As Single, cbtEbCZ As Single, cbtEbRF As Single, cbtEbSeek As Single
    Dim cbtRgFr(1 To MAX_EBULLETS) As Single, cbtRgY(1 To MAX_EBULLETS) As Single, cbtRgZ(1 To MAX_EBULLETS) As Single
    Dim cbtRgN As Integer, cbtRgBest As Integer
    Dim cbtSpPulse As Single
    Dim cbtCuCX As Single, cbtCuCY As Single, cbtCuAX As Single, cbtCuAY As Single
    Dim cbtCuBX As Single, cbtCuBY As Single, cbtCuHX As Single, cbtCuHY As Single
    Dim cbtCuOk As Integer, cbtCuOk2 As Integer, cbtCuOk3 As Integer, cbtCuOk4 As Integer
    Dim cbtCuOX As Integer, cbtCuOY As Integer, cbtCuHalf As Integer, cbtCuK As Integer
    Dim cbtCuF As Single, cbtCuClr As Long
    Dim cbtDvBX As Single, cbtDvBY As Single, cbtDvPX As Single, cbtDvPY As Single, cbtDvEX As Single, cbtDvEY As Single
    Dim cbtDvOk As Integer, cbtDvOk2 As Integer, cbtDvK As Integer, cbtDvA As Integer
    Dim cbtDvSpd As Single, cbtDvAng As Single, cbtDvPh As Single, cbtDvR1 As Single, cbtDvR2 As Single
    Dim cbtDvUX As Single, cbtDvUY As Single, cbtDvLen As Single, cbtDvD As Single, cbtDvT As Integer

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

    ' enemy bullets: red-orange bolts whose size and heat come from their real depth (far =
    ' small, dim, cool; near = big, hot), plus a closing impact ring on the player's plane
    ' for shots that will pass close (impact.bas), so players can triage what to dodge
    For cbtOJ = 1 To MAX_EBULLETS
        If ebullets(cbtOJ).active Then
            cbtEbF = (ebullets(cbtOJ).px - player.px - EB_HOT_DIST) / (EB_COLD_DIST - EB_HOT_DIST)
            If cbtEbF < 0 Then cbtEbF = 0
            If cbtEbF > 1 Then cbtEbF = 1
            cbtEbF = 1 - cbtEbF * (1 - EB_COLD_BRIGHT)
            cbtEbMag = Sqr(ebullets(cbtOJ).vx * ebullets(cbtOJ).vx + ebullets(cbtOJ).vy * ebullets(cbtOJ).vy + ebullets(cbtOJ).vz * ebullets(cbtOJ).vz)
            If cbtEbMag > 0.0001 Then
                COMBAT_Project ebullets(cbtOJ).px, ebullets(cbtOJ).py, ebullets(cbtOJ).pz, cbtOPjX, cbtOPjY, cbtEbOk
                COMBAT_Project ebullets(cbtOJ).px - ebullets(cbtOJ).vx / cbtEbMag * EB_BOLT_LEN, _
                               ebullets(cbtOJ).py - ebullets(cbtOJ).vy / cbtEbMag * EB_BOLT_LEN, _
                               ebullets(cbtOJ).pz - ebullets(cbtOJ).vz / cbtEbMag * EB_BOLT_LEN, cbtOPjX2, cbtOPjY2, cbtEbOk2
                COMBAT_Project ebullets(cbtOJ).px, ebullets(cbtOJ).py + EB_BOLT_R, ebullets(cbtOJ).pz, cbtEbRX, cbtEbRY, cbtEbOk3
                If cbtEbOk And cbtEbOk2 And cbtEbOk3 Then
                    If cbtOPjX >= 0 And cbtOPjX < scrW And cbtOPjY >= 0 And cbtOPjY < scrH Then
                        cbtEbS = Abs(cbtOPjY - cbtEbRY)
                        If cbtEbS < 1 Then cbtEbS = 1
                        If cbtEbS > 9 Then cbtEbS = 9
                        ' glow: stacked translucent discs along the bolt, densest at the head
                        For cbtEbK = 0 To 2
                            cbtEbGX = cbtOPjX + (cbtOPjX2 - cbtOPjX) * cbtEbK * 0.5
                            cbtEbGY = cbtOPjY + (cbtOPjY2 - cbtOPjY) * cbtEbK * 0.5
                            For cbtEbR = Int(cbtEbS * (1 - cbtEbK * 0.3)) To 1 Step -1
                                Circle (cbtEbGX, cbtEbGY), cbtEbR, _RGBA(255, Int(60 + 40 * cbtEbF), 20, Int(25 + 45 * cbtEbF))
                            Next cbtEbR
                        Next cbtEbK
                        Line (cbtOPjX2, cbtOPjY2)-(cbtOPjX, cbtOPjY), _RGB(Int(255 * cbtEbF), Int(150 * cbtEbF), Int(70 * cbtEbF))
                        Line (cbtOPjX + (cbtOPjX2 - cbtOPjX) * 0.5, cbtOPjY + (cbtOPjY2 - cbtOPjY) * 0.5)-(cbtOPjX, cbtOPjY), _RGB(Int(255 * cbtEbF), Int(235 * cbtEbF), Int(190 * cbtEbF))
                    End If
                End If
            End If

            If ebullets(cbtOJ).meshIdx = MESH_BOSS Then cbtEbSeek = bossSeekStr Else cbtEbSeek = 0
            IMP_Predict ebullets(cbtOJ).px, ebullets(cbtOJ).py, ebullets(cbtOJ).pz, _
                        ebullets(cbtOJ).vx, ebullets(cbtOJ).vy, ebullets(cbtOJ).vz, _
                        player.px, player.py, player.pz, cbtEbSeek, cbtEbFr, cbtEbCY, cbtEbCZ
            cbtRgFr(cbtOJ) = -1
            If cbtEbFr >= 0 And cbtEbFr <= IMP_RING_FRAMES Then
                If IMP_Threat%(cbtEbCY, cbtEbCZ, player.py, player.pz) Then
                    cbtRgFr(cbtOJ) = cbtEbFr : cbtRgY(cbtOJ) = cbtEbCY : cbtRgZ(cbtOJ) = cbtEbCZ
                End If
            End If
        Else
            cbtRgFr(cbtOJ) = -1
        End If
    Next cbtOJ

    ' rings for the IMP_RING_MAX_N soonest impacts only
    For cbtRgN = 1 To IMP_RING_MAX_N
        cbtRgBest = 0
        For cbtOJ = 1 To MAX_EBULLETS
            If cbtRgFr(cbtOJ) >= 0 Then
                If cbtRgBest = 0 Then
                    cbtRgBest = cbtOJ
                ElseIf cbtRgFr(cbtOJ) < cbtRgFr(cbtRgBest) Then
                    cbtRgBest = cbtOJ
                End If
            End If
        Next cbtOJ
        If cbtRgBest = 0 Then Exit For
        cbtEbRF = IMP_RingFrac!(cbtRgFr(cbtRgBest), IMP_RING_FRAMES)
        COMBAT_ImpactRing player.px, cbtRgY(cbtRgBest), cbtRgZ(cbtRgBest), IMP_RING_R_MIN + (IMP_RING_R_MAX - IMP_RING_R_MIN) * cbtEbRF, cbtEbRF, 255, 120, 30
        cbtRgFr(cbtRgBest) = -1
    Next cbtRgN

    ' spore clouds (boss attack A, spores.bas): hazy green rings, radius projected to pixels
    For cbtOJ = 1 To SPORE_MAX
        If sporeActive(cbtOJ) Then
            ' landing ring: where the cloud will settle, closing as it arrives
            If sporeAge(cbtOJ) < SPORE_DRIFT_FRAMES Then
                cbtEbRF = IMP_RingFrac!(SPORE_DRIFT_FRAMES - sporeAge(cbtOJ), SPORE_DRIFT_FRAMES)
                COMBAT_ImpactRing sporeX1(cbtOJ), sporeY1(cbtOJ), sporeZ1(cbtOJ), SPORE_R_MAX * (1 + cbtEbRF), cbtEbRF, 110, 230, 80
            End If
            cbtOPjX = sporeX(cbtOJ) * vpMat.m(0,0) + sporeY(cbtOJ) * vpMat.m(0,1) + sporeZ(cbtOJ) * vpMat.m(0,2) + vpMat.m(0,3)
            cbtOPjY = sporeX(cbtOJ) * vpMat.m(1,0) + sporeY(cbtOJ) * vpMat.m(1,1) + sporeZ(cbtOJ) * vpMat.m(1,2) + vpMat.m(1,3)
            cbtOPjW = sporeX(cbtOJ) * vpMat.m(3,0) + sporeY(cbtOJ) * vpMat.m(3,1) + sporeZ(cbtOJ) * vpMat.m(3,2) + vpMat.m(3,3)
            cbtOPjY2 = sporeX(cbtOJ) * vpMat.m(1,0) + (sporeY(cbtOJ) + sporeR(cbtOJ)) * vpMat.m(1,1) + sporeZ(cbtOJ) * vpMat.m(1,2) + vpMat.m(1,3)
            cbtOPjW2 = sporeX(cbtOJ) * vpMat.m(3,0) + (sporeY(cbtOJ) + sporeR(cbtOJ)) * vpMat.m(3,1) + sporeZ(cbtOJ) * vpMat.m(3,2) + vpMat.m(3,3)
            If cbtOPjW > 0.0001 And cbtOPjW2 > 0.0001 Then
                cbtOPjX = (cbtOPjX / cbtOPjW + 1.0) * scrW * 0.5
                cbtOPjY = (1.0 - cbtOPjY / cbtOPjW) * scrH * 0.5
                cbtSpR = Abs(cbtOPjY - (1.0 - cbtOPjY2 / cbtOPjW2) * scrH * 0.5)
                If cbtSpR > 160 Then cbtSpR = 160
                If cbtSpR >= 1 Then
                    ' active (hurting) clouds pulse in size and brightness until their fade
                    If SPORE_Hurts%(cbtOJ) Then
                        cbtSpPulse = Sin(sporeAge(cbtOJ) * 0.2)
                        cbtSpA = 70 + Int(40 * cbtSpPulse)
                        cbtSpR = cbtSpR * (1 + 0.07 * cbtSpPulse)
                    Else
                        cbtSpA = 35
                    End If
                    For cbtSpRing = 0 To 2
                        Circle (cbtOPjX, cbtOPjY), cbtSpR * (1 - cbtSpRing * 0.3), _RGBA(110, 230, 80, cbtSpA + cbtSpRing * 35)
                    Next cbtSpRing
                End If
            End If
        End If
    Next cbtOJ

    ' the cut (boss attack B, cuts.bas): the band it will cover, plus a warning line that
    ' pulses faster and thickens as it nears firing; then a solid beam across the plane
    If cutStage = CUT_ST_WARN Or cutStage = CUT_ST_LIVE Then
        COMBAT_Project cutX, cutY, cutZ, cbtCuCX, cbtCuCY, cbtCuOk
        If cutHoriz Then
            COMBAT_Project cutX, cutY, cutZ - CUT_SPAN, cbtCuAX, cbtCuAY, cbtCuOk2
            COMBAT_Project cutX, cutY, cutZ + CUT_SPAN, cbtCuBX, cbtCuBY, cbtCuOk3
            COMBAT_Project cutX, cutY + CUT_HALF, cutZ, cbtCuHX, cbtCuHY, cbtCuOk4
            cbtCuOX = 0 : cbtCuOY = 1
        Else
            COMBAT_Project cutX, cutY - CUT_SPAN, cutZ, cbtCuAX, cbtCuAY, cbtCuOk2
            COMBAT_Project cutX, cutY + CUT_SPAN, cutZ, cbtCuBX, cbtCuBY, cbtCuOk3
            COMBAT_Project cutX, cutY, cutZ + CUT_HALF, cbtCuHX, cbtCuHY, cbtCuOk4
            cbtCuOX = 1 : cbtCuOY = 0
        End If
        If cbtCuOk And cbtCuOk2 And cbtCuOk3 And cbtCuOk4 Then
            cbtCuHalf = Int(Sqr((cbtCuHX - cbtCuCX) ^ 2 + (cbtCuHY - cbtCuCY) ^ 2))
            If cbtCuHalf < 2 Then cbtCuHalf = 2
            If cbtCuHalf > 200 Then cbtCuHalf = 200
            If cutStage = CUT_ST_WARN Then
                cbtCuF = CUT_WarnFrac!
                Line (cbtCuAX - cbtCuOX * cbtCuHalf, cbtCuAY - cbtCuOY * cbtCuHalf)-(cbtCuBX - cbtCuOX * cbtCuHalf, cbtCuBY - cbtCuOY * cbtCuHalf), _RGBA(255, 50, 40, 70)
                Line (cbtCuAX + cbtCuOX * cbtCuHalf, cbtCuAY + cbtCuOY * cbtCuHalf)-(cbtCuBX + cbtCuOX * cbtCuHalf, cbtCuBY + cbtCuOY * cbtCuHalf), _RGBA(255, 50, 40, 70)
                If (cutT \ (2 + Int(10 * cbtCuF))) Mod 2 = 0 Then
                    For cbtCuK = -Int((1 - cbtCuF) * 3) To Int((1 - cbtCuF) * 3)
                        Line (cbtCuAX + cbtCuOX * cbtCuK, cbtCuAY + cbtCuOY * cbtCuK)-(cbtCuBX + cbtCuOX * cbtCuK, cbtCuBY + cbtCuOY * cbtCuK), _RGBA(255, 60, 40, Int(140 + 100 * (1 - cbtCuF)))
                    Next cbtCuK
                End If
            Else
                For cbtCuK = -cbtCuHalf To cbtCuHalf
                    If Abs(cbtCuK) <= 2 Then cbtCuClr = _RGB(255, 245, 235) Else cbtCuClr = _RGBA(255, 70, 50, 120)
                    Line (cbtCuAX + cbtCuOX * cbtCuK, cbtCuAY + cbtCuOY * cbtCuK)-(cbtCuBX + cbtCuOX * cbtCuK, cbtCuBY + cbtCuOY * cbtCuK), cbtCuClr
                Next cbtCuK
            End If
        End If
    End If

    ' devour (boss attack C, devour.bas): suction streaks converging on the boss, faint and
    ' slow during the warning, bright and fast while pulling, plus a drag line on the ship
    If devStage <> DEV_ST_IDLE And boss.active Then
        COMBAT_Project boss.px, boss.py, boss.pz, cbtDvBX, cbtDvBY, cbtDvOk
        If cbtDvOk Then
            If devStage = DEV_ST_WARN Then
                cbtDvSpd = 0.012 : cbtDvA = Int(50 + 110 * (1 - DEV_WarnFrac!))
            Else
                cbtDvSpd = 0.035 : cbtDvA = 200
            End If
            For cbtDvK = 0 To 15
                cbtDvAng = cbtDvK * 6.2832 / 16
                cbtDvPh = devT * cbtDvSpd + cbtDvK * 0.37
                cbtDvPh = cbtDvPh - Int(cbtDvPh)
                cbtDvR1 = scrH * 0.55 * (1 - cbtDvPh)
                cbtDvR2 = cbtDvR1 * 0.7
                Line (cbtDvBX + Cos(cbtDvAng) * cbtDvR1, cbtDvBY + Sin(cbtDvAng) * cbtDvR1)-(cbtDvBX + Cos(cbtDvAng) * cbtDvR2, cbtDvBY + Sin(cbtDvAng) * cbtDvR2), _RGBA(190, 90, 255, cbtDvA)
            Next cbtDvK
        End If
        ' drag: chevrons marching out from the ship the way it's being pulled, fading as
        ' they go, so "you're being dragged THAT way" reads at a glance
        If devStage = DEV_ST_PULL Then
            COMBAT_Project player.px, player.py, player.pz, cbtDvPX, cbtDvPY, cbtDvOk
            COMBAT_Project player.px, player.py + devPullY * 25, player.pz + devPullZ * 25, cbtDvEX, cbtDvEY, cbtDvOk2
            If cbtDvOk And cbtDvOk2 Then
                cbtDvUX = cbtDvEX - cbtDvPX : cbtDvUY = cbtDvEY - cbtDvPY
                cbtDvLen = Sqr(cbtDvUX * cbtDvUX + cbtDvUY * cbtDvUY)
                If cbtDvLen > 0.5 Then
                    cbtDvUX = cbtDvUX / cbtDvLen : cbtDvUY = cbtDvUY / cbtDvLen
                    For cbtDvK = 0 To 2
                        cbtDvPh = devT * 0.04 + cbtDvK / 3
                        cbtDvPh = cbtDvPh - Int(cbtDvPh)
                        cbtDvD = DEV_CHEV_NEAR + cbtDvPh * (DEV_CHEV_FAR - DEV_CHEV_NEAR)
                        cbtDvA = Int(255 * (1 - cbtDvPh))
                        ' dark outline strokes either side first, then the bright double stroke,
                        ' so they read over the planet and the boss
                        COMBAT_Chevron cbtDvPX, cbtDvPY, cbtDvUX, cbtDvUY, cbtDvD + 1, _RGBA(25, 0, 45, Int(cbtDvA * 0.8))
                        COMBAT_Chevron cbtDvPX, cbtDvPY, cbtDvUX, cbtDvUY, cbtDvD - 2, _RGBA(25, 0, 45, Int(cbtDvA * 0.8))
                        For cbtDvT = 0 To 1
                            COMBAT_Chevron cbtDvPX, cbtDvPY, cbtDvUX, cbtDvUY, cbtDvD - cbtDvT, _RGBA(225, 140, 255, cbtDvA)
                        Next cbtDvT
                    Next cbtDvK
                End If
            End If
        End If
    End If

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
