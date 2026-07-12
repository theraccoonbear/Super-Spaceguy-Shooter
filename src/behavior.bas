Sub BOSS_UpdateMovement()
    boss.moveTimer = boss.moveTimer - 1
    If boss.moveTimer < 0 Then boss.moveTimer = 0
    If boss.state = 0 Then
        ' hunting: actively converge on player Y/Z
        Select Case boss.phase
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
        Select Case boss.phase
            Case 1
                boss.py = boss.py + (boss.targetY - boss.py) * 0.065
                boss.pz = boss.pz + (boss.targetZ - boss.pz) * 0.065
            Case 2
                boss.py = boss.py + (boss.targetY - boss.py) * 0.095
                boss.pz = boss.pz + (boss.targetZ - boss.pz) * 0.095
            Case 3
                boss.py = boss.py + (boss.targetY - boss.py) * 0.130
                boss.pz = boss.pz + (boss.targetZ - boss.pz) * 0.130
        End Select
        If boss.moveTimer <= 0 Then boss.state = 0
    End If
End Sub

Sub BOSS_SetEvasion(phase As Integer)
    ' dart relative to player — keeps boss inside firing cone (15deg pitch / 7deg yaw at BOSS_COMBAT_DIST=45)
    If boss.py >= player.py Then
        boss.targetY = player.py - (3 + Rnd * 5)
    Else
        boss.targetY = player.py + (3 + Rnd * 5)
    End If
    If boss.pz >= player.pz Then
        boss.targetZ = player.pz - (2 + Rnd * 3)
    Else
        boss.targetZ = player.pz + (2 + Rnd * 3)
    End If
    Select Case phase
        Case 1 : boss.moveTimer = 70
        Case 2 : boss.moveTimer = 50
        Case 3 : boss.moveTimer = 20
    End Select
    boss.state = 1
End Sub
