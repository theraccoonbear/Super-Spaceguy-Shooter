Sub ASTEROIDS_Update()
    Dim astUI As Integer, astUJ As Integer, astUHit As Integer

    For astUI = 1 To MAX_ASTEROIDS
        If asteroids(astUI).active Then
            asteroids(astUI).px  = asteroids(astUI).px  + asteroids(astUI).vx
            asteroids(astUI).rx  = asteroids(astUI).rx  + asteroids(astUI).drx
            asteroids(astUI).ry  = asteroids(astUI).ry  + asteroids(astUI).dry
            asteroids(astUI).rz  = asteroids(astUI).rz  + asteroids(astUI).drz
            If asteroids(astUI).px < player.px + 25 Then
                asteroids(astUI).py = asteroids(astUI).py + (player.py - asteroids(astUI).py) * 0.004
                asteroids(astUI).pz = asteroids(astUI).pz + (player.pz - asteroids(astUI).pz) * 0.004
            End If
            If asteroids(astUI).px < -5 Then asteroids(astUI).active = 0

            For astUJ = 1 To MAX_BULLETS
                If bullets(astUJ).active Then
                    E3D_AABBOverlap asteroids(astUI).px, asteroids(astUI).py, asteroids(astUI).pz, boxLib(MESH_ASTEROID), _
                    bullets(astUJ).px, bullets(astUJ).py, bullets(astUJ).pz, boxLib(MESH_BULLET), astUHit
                    If astUHit Then
                        asteroids(astUI).active = 0
                        bullets(astUJ).active = 0
                        score = score + SCORE_ASTEROID
                        SND_Boom
                        scorePopTimer = 30 : scorePopY = scrH * 0.45 : scorePopVal = SCORE_ASTEROID
                        FX_SpawnBurst asteroids(astUI).px, asteroids(astUI).py, asteroids(astUI).pz, 8, 0.18, 15, 7, _RGB(120 + Int(Rnd * 40), 100 + Int(Rnd * 30), 75 + Int(Rnd * 20))
                    End If
                End If
            Next astUJ

            E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
            asteroids(astUI).px, asteroids(astUI).py, asteroids(astUI).pz, boxLib(MESH_ASTEROID), astUHit
            If astUHit And invTimer = 0 Then
                asteroids(astUI).active = 0
                SND_Boom
                FX_SpawnBurst asteroids(astUI).px, asteroids(astUI).py, asteroids(astUI).pz, 8, 0.18, 15, 7, _RGB(120 + Int(Rnd * 40), 100 + Int(Rnd * 30), 75 + Int(Rnd * 20))
                PLAYER_TakeDamage DMG_COLLISION, SHAKE_COLLISION, FLASH_COLLISION
            End If
        End If
    Next astUI
End Sub

Sub ASTEROIDS_Draw()
    Dim astDJ As Integer

    For astDJ = 1 To MAX_ASTEROIDS
        If asteroids(astDJ).active Then
            If asteroids(astDJ).px > cam.POS.x Then
                pPos.x = asteroids(astDJ).px : pPos.y = asteroids(astDJ).py : pPos.z = asteroids(astDJ).pz
                pRot.x = asteroids(astDJ).rx : pRot.y = asteroids(astDJ).ry : pRot.z = asteroids(astDJ).rz
                E3D_BuildObjectMat pPos, pRot, asteroids(astDJ).scl, objMat
                E3D_SceneAddMeshLit meshLib(MESH_ASTEROID), objMat, cam.POS, tt, lightDir
            End If
        End If
    Next astDJ
End Sub
