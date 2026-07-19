Sub ASTEROIDS_Update()
    Dim astUI As Integer, astUJ As Integer, astUHit As Integer, astUNmPts As Long

    If astNmSndCool > 0 Then astNmSndCool = astNmSndCool - 1
    For astUI = 1 To MAX_ASTEROIDS
        If asteroids(astUI).active Then
            asteroids(astUI).px  = asteroids(astUI).px  + asteroids(astUI).vx
            asteroids(astUI).py  = asteroids(astUI).py  + asteroids(astUI).vy
            asteroids(astUI).pz  = asteroids(astUI).pz  + asteroids(astUI).vz
            asteroids(astUI).rx  = asteroids(astUI).rx  + asteroids(astUI).drx
            asteroids(astUI).ry  = asteroids(astUI).ry  + asteroids(astUI).dry
            asteroids(astUI).rz  = asteroids(astUI).rz  + asteroids(astUI).drz
            If levelType = LEVEL_COMBAT And asteroids(astUI).px < player.px + 25 Then
                asteroids(astUI).py = asteroids(astUI).py + (player.py - asteroids(astUI).py) * 0.004
                asteroids(astUI).pz = asteroids(astUI).pz + (player.pz - asteroids(astUI).pz) * 0.004
            End If
            If asteroids(astUI).px < player.px - 20 Then asteroids(astUI).active = 0
            If asteroids(astUI).life > 0 Then
                asteroids(astUI).life = asteroids(astUI).life - 1
                If asteroids(astUI).life <= 0 Then asteroids(astUI).active = 0
            End If

            For astUJ = 1 To MAX_BULLETS
                If bullets(astUJ).active Then
                    E3D_AABBOverlap asteroids(astUI).px, asteroids(astUI).py, asteroids(astUI).pz, boxLib(MESH_ASTEROID), _
                    bullets(astUJ).px, bullets(astUJ).py, bullets(astUJ).pz, boxLib(MESH_BULLET), astUHit
                    If astUHit Then
                        bullets(astUJ).active = 0
                        SND_Boom
                    End If
                End If
            Next astUJ

            E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
            asteroids(astUI).px, asteroids(astUI).py, asteroids(astUI).pz, boxLib(MESH_ASTEROID), astUHit
            If astUHit And invTimer = 0 Then
                If asteroids(astUI).strafeCool >= 10 Then
                    fxShakeTimer = 6
                    SND_Whoosh asteroids(astUI).scl
                Else
                    SND_Boom
                    FX_SpawnBurst asteroids(astUI).px, asteroids(astUI).py, asteroids(astUI).pz, 8, 0.18, 15, 7, _RGB(120 + Int(Rnd * 40), 100 + Int(Rnd * 30), 75 + Int(Rnd * 20))
                    telemDeathCause = "asteroid"
                    PLAYER_TakeDamage DMG_ASTEROID, SHAKE_COLLISION, FLASH_COLLISION
                End If
            ElseIf astNmSndCool = 0 And levelType = LEVEL_ASTEROID Then
                If Abs(asteroids(astUI).py - player.py) < 7 And Abs(asteroids(astUI).pz - player.pz) < 7 Then
                    If asteroids(astUI).px < player.px + 5 And asteroids(astUI).px > player.px - 4 Then
                        fxShakeTimer = 3
                        astNmSndCool = 50
                        SND_Whoosh asteroids(astUI).scl
                        astUNmPts = INT(asteroids(astUI).scl * 60)
                        score = score + astUNmPts
                        scorePopVal = astUNmPts
                        scorePopTimer = 30
                        scorePopY = scrH * 0.4
                    End If
                End If
            End If
        End If
    Next astUI
End Sub

Sub ASTEROIDS_Draw()
    Dim astDJ As Integer
    Dim astDTR As Single, astDTG As Single, astDTB As Single
    Dim astDDist As Single, astDFade As Single
    Dim astDSX As Single, astDSY As Single, astDSW As Single
    Dim astDR2D As Integer, astDR2DYY As Integer, astDR2DXW As Integer
    Dim astDBC As Long

    For astDJ = 1 To MAX_ASTEROIDS
        If asteroids(astDJ).active Then
            If asteroids(astDJ).px > cam.POS.x Then
                astDDist = asteroids(astDJ).px - player.px
                If astDDist > 300 Then GoTo astDSkip
                Dim astDTint As Integer : astDTint = asteroids(astDJ).strafeCool Mod 10
                Select Case astDTint
                Case 0 : astDTR = 1.00 : astDTG = 0.84 : astDTB = 0.54
                Case 1 : astDTR = 1.00 : astDTG = 0.62 : astDTB = 0.38
                Case 2 : astDTR = 0.72 : astDTG = 0.44 : astDTB = 0.26
                Case 3 : astDTR = 0.82 : astDTG = 0.82 : astDTB = 0.82
                Case 4 : astDTR = 0.56 : astDTG = 0.56 : astDTB = 0.62
                Case Else : astDTR = 1.00 : astDTG = 0.50 : astDTB = 0.32
                End Select
                If astDDist > 80 Then
                    ' mid/far: 2D projected blob — zero polygon cost
                    astDFade = 1.0 - (astDDist - 80) / 220
                    If astDFade < 0.0 Then astDFade = 0.0
                    astDSX = asteroids(astDJ).px * vpMat.m(0,0) + asteroids(astDJ).py * vpMat.m(0,1) + asteroids(astDJ).pz * vpMat.m(0,2) + vpMat.m(0,3)
                    astDSY = asteroids(astDJ).px * vpMat.m(1,0) + asteroids(astDJ).py * vpMat.m(1,1) + asteroids(astDJ).pz * vpMat.m(1,2) + vpMat.m(1,3)
                    astDSW = asteroids(astDJ).px * vpMat.m(3,0) + asteroids(astDJ).py * vpMat.m(3,1) + asteroids(astDJ).pz * vpMat.m(3,2) + vpMat.m(3,3)
                    If astDSW > 0.0001 Then
                        astDSX = (astDSX / astDSW + 1.0) * scrW * 0.5
                        astDSY = (1.0 - astDSY / astDSW) * scrH * 0.5
                        If astDSX >= 0 And astDSX < scrW And astDSY >= 0 And astDSY < scrH Then
                            ' screen radius using FOV factor (72° → f≈1.376) and avg asteroid radius 0.62
                            astDR2D = Int(asteroids(astDJ).scl * 0.853 * scrH * 0.5 / astDDist + 0.5)
                            If astDR2D < 1 Then astDR2D = 1
                            If astDR2D > 12 Then astDR2D = 12
                            astDBC = _RGB(Int(astDTR * astDFade * 160), Int(astDTG * astDFade * 128), Int(astDTB * astDFade * 100))
                            If astDR2D <= 1 Then
                                PSet (Int(astDSX), Int(astDSY)), astDBC
                            Else
                                For astDR2DYY = -astDR2D To astDR2D
                                    astDR2DXW = Int(Sqr(astDR2D * astDR2D - astDR2DYY * astDR2DYY) + 0.5)
                                    Line (Int(astDSX) - astDR2DXW, Int(astDSY) + astDR2DYY)-(Int(astDSX) + astDR2DXW, Int(astDSY) + astDR2DYY), astDBC
                                Next astDR2DYY
                            End If
                        End If
                    End If
                Else
                    ' close: full 3D mesh
                    pPos.x = asteroids(astDJ).px : pPos.y = asteroids(astDJ).py : pPos.z = asteroids(astDJ).pz
                    pRot.x = asteroids(astDJ).rx : pRot.y = asteroids(astDJ).ry : pRot.z = asteroids(astDJ).rz
                    E3D_BuildObjectMat pPos, pRot, asteroids(astDJ).scl, objMat
                    E3D_SceneAddMeshLitTinted meshLib(MESH_ASTEROID), objMat, cam.POS, tt, lightDir, astDTR, astDTG, astDTB
                End If
                astDSkip:
            End If
        End If
    Next astDJ
End Sub
