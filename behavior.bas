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
    ' dart relative to player — keeps boss inside firing cone (15deg pitch / 7deg yaw at BOSS_COMBAT_DIST=45)
    If boss.py >= player.py Then
        bossTargetY = player.py - (3 + Rnd * 5)
    Else
        bossTargetY = player.py + (3 + Rnd * 5)
    End If
    If boss.pz >= player.pz Then
        bossTargetZ = player.pz - (2 + Rnd * 3)
    Else
        bossTargetZ = player.pz + (2 + Rnd * 3)
    End If
    Select Case phase
        Case 1 : bossMoveTimer = 70
        Case 2 : bossMoveTimer = 50
        Case 3 : bossMoveTimer = 20
    End Select
    bossState = 1
End Sub
