Sub BOSS_UpdateMovement()
    bossMoveTimer = bossMoveTimer - 1
    If bossMoveTimer < 0 Then bossMoveTimer = 0
    If bossState = 0 Then
        ' hunting: actively converge on player Y/Z
        Select Case bossPhase
            Case 1
                boss.py = boss.py + (player.py - boss.py) * 0.045
                boss.pz = boss.pz + (player.pz - boss.pz) * 0.045
            Case 2
                boss.py = boss.py + (player.py - boss.py) * 0.070
                boss.pz = boss.pz + (player.pz - boss.pz) * 0.070
            Case 3
                boss.py = boss.py + (player.py - boss.py) * 0.100
                boss.pz = boss.pz + (player.pz - boss.pz) * 0.100
        End Select
    Else
        ' evading: dart to arena-wide random position
        Select Case bossPhase
            Case 1
                boss.py = boss.py + (bossTargetY - boss.py) * 0.065
                boss.pz = boss.pz + (bossTargetZ - boss.pz) * 0.065
            Case 2
                boss.py = boss.py + (bossTargetY - boss.py) * 0.095
                boss.pz = boss.pz + (bossTargetZ - boss.pz) * 0.095
            Case 3
                boss.py = boss.py + (bossTargetY - boss.py) * 0.130
                boss.pz = boss.pz + (bossTargetZ - boss.pz) * 0.130
        End Select
        If bossMoveTimer <= 0 Then bossState = 0
    End If
End Sub

Sub BOSS_SetEvasion(phase As Integer)
    ' flip to opposite quadrant — guarantees a visible cross-screen dart
    If boss.py >= 0 Then
        bossTargetY = -4 - Rnd * 8
    Else
        bossTargetY =  4 + Rnd * 8
    End If
    If boss.pz >= 0 Then
        bossTargetZ = -5 - Rnd * 9
    Else
        bossTargetZ =  5 + Rnd * 9
    End If
    Select Case phase
        Case 1 : bossMoveTimer = 70
        Case 2 : bossMoveTimer = 50
        Case 3 : bossMoveTimer = 20
    End Select
    bossState = 1
End Sub
