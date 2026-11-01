' Boss movement modes (boss.state):
'   0 hunt       -- converge on player Y/Z (boss.bas also closes X to BOSS_COMBAT_DIST)
'   1 evade      -- dart to BOSS_SetEvasion's target until moveTimer expires

' BOSS_COMBAT_DIST defined here (behavior.bas included before boss.bas)
Const BOSS_COMBAT_DIST = 20    ' standard X distance for combat

Const BOSS_CHARGE_CD1 = 300    ' frames between charge eligibility, phase 1
Const BOSS_CHARGE_CD2 = 190    ' phase 2
Const BOSS_CHARGE_CD3 = 110    ' phase 3

Sub BOSS_UpdateMovement()
    boss.chargeTimer = boss.chargeTimer - 1
    If boss.chargeTimer < 0 Then boss.chargeTimer = 0
    boss.moveTimer = boss.moveTimer - 1
    If boss.moveTimer < 0 Then boss.moveTimer = 0

    Select Case boss.state
    Case 0  ' hunting: actively converge on player Y/Z
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

    Case 1  ' evading: dart to arena-wide random position
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

    End Select
End Sub

Sub BOSS_SetEvasion(phase As Integer)
    ' dart relative to player — keeps boss inside firing cone (15deg pitch / 7deg yaw at BOSS_COMBAT_DIST=45)
    If boss.py >= player.py Then
        boss.targetY = player.py - (3 + RNG!(RNG_GAME) * 5)
    Else
        boss.targetY = player.py + (3 + RNG!(RNG_GAME) * 5)
    End If
    If boss.pz >= player.pz Then
        boss.targetZ = player.pz - (2 + RNG!(RNG_GAME) * 3)
    Else
        boss.targetZ = player.pz + (2 + RNG!(RNG_GAME) * 3)
    End If
    Select Case phase
        Case 1 : boss.moveTimer = 70
        Case 2 : boss.moveTimer = 50
        Case 3 : boss.moveTimer = 20
    End Select
    boss.state = 1
End Sub
