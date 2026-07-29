' Boss movement modes (boss.state):
'   0 hunt    -- lerp Y/Z toward player
'   1 evade   -- dart to Y/Z offset from player
'   2 charge  -- close on X toward player, fire throughout
'   3 retreat -- back to BOSS_COMBAT_DIST on X
'   4 arc     -- sweep Y/Z arc around player position
'   5 xyzrush -- charge on X + arc sweep Y/Z simultaneously

' BOSS_COMBAT_DIST defined here (behavior.bas included before boss.bas)
Const BOSS_COMBAT_DIST = 20    ' standard X distance for combat
Const BOSS_CLOSE_DIST  = 5.0   ' X distance at closest approach during charge

Const BOSS_CHARGE_SPD  = 0.30  ' X close speed during charge
Const BOSS_RETREAT_SPD = 0.18  ' X retreat speed back to combat dist

Const BOSS_ARC_SPD1 = 0.022    ' arc sweep rate (rad/frame) phase 1
Const BOSS_ARC_SPD2 = 0.036    ' phase 2
Const BOSS_ARC_SPD3 = 0.052    ' phase 3

Const BOSS_ARC_RAD1 = 7.0      ' arc radius in Y/Z plane phase 1
Const BOSS_ARC_RAD2 = 10.0     ' phase 2
Const BOSS_ARC_RAD3 = 13.0     ' phase 3

Const BOSS_CHARGE_CD1 = 300    ' frames between charge eligibility, phase 1
Const BOSS_CHARGE_CD2 = 190    ' phase 2
Const BOSS_CHARGE_CD3 = 110    ' phase 3

Sub BOSS_UpdateMovement()
    Dim bsmArcSpd As Single, bsmArcRad As Single, bsmHuntRate As Single

    boss.chargeTimer = boss.chargeTimer - 1
    If boss.chargeTimer < 0 Then boss.chargeTimer = 0

    Select Case boss.state
    Case 0  ' hunt: converge Y/Z toward player
        Select Case boss.phase
            Case 1 : bsmHuntRate = 0.045
            Case 2 : bsmHuntRate = 0.070
            Case 3 : bsmHuntRate = 0.100
        End Select
        boss.py = boss.py + (player.py - boss.py) * bsmHuntRate
        boss.pz = boss.pz + (player.pz - boss.pz) * bsmHuntRate

    Case 1  ' evade: dart to Y/Z offset from player
        Select Case boss.phase
            Case 1 : bsmHuntRate = 0.065
            Case 2 : bsmHuntRate = 0.095
            Case 3 : bsmHuntRate = 0.130
        End Select
        boss.py = boss.py + (boss.targetY - boss.py) * bsmHuntRate
        boss.pz = boss.pz + (boss.targetZ - boss.pz) * bsmHuntRate
        boss.moveTimer = boss.moveTimer - 1
        If boss.moveTimer <= 0 Then boss.state = 0

    Case 2  ' charge: close on X while tracking player Y/Z, fire throughout
        Select Case boss.phase
            Case 1 : bsmHuntRate = 0.055
            Case 2 : bsmHuntRate = 0.080
            Case 3 : bsmHuntRate = 0.110
        End Select
        boss.py = boss.py + (player.py - boss.py) * bsmHuntRate
        boss.pz = boss.pz + (player.pz - boss.pz) * bsmHuntRate
        If boss.px > player.px + BOSS_CLOSE_DIST Then
            boss.px = boss.px - BOSS_CHARGE_SPD
        Else
            boss.moveTimer = boss.moveTimer - 1
            If boss.moveTimer <= 0 Then boss.state = 3
        End If

    Case 3  ' retreat: back to combat distance
        boss.px = boss.px + BOSS_RETREAT_SPD
        If boss.px >= player.px + BOSS_COMBAT_DIST Then
            boss.px = player.px + BOSS_COMBAT_DIST
            Select Case boss.phase
                Case 1 : boss.chargeTimer = BOSS_CHARGE_CD1
                Case 2 : boss.chargeTimer = BOSS_CHARGE_CD2
                Case 3 : boss.chargeTimer = BOSS_CHARGE_CD3
            End Select
            boss.state = 0
        End If

    Case 4  ' arc: sweep Y/Z circle around player
        Select Case boss.phase
            Case 1 : bsmArcSpd = BOSS_ARC_SPD1 : bsmArcRad = BOSS_ARC_RAD1
            Case 2 : bsmArcSpd = BOSS_ARC_SPD2 : bsmArcRad = BOSS_ARC_RAD2
            Case 3 : bsmArcSpd = BOSS_ARC_SPD3 : bsmArcRad = BOSS_ARC_RAD3
        End Select
        boss.arcAngle = boss.arcAngle + bsmArcSpd
        boss.py = player.py + SIN(boss.arcAngle) * bsmArcRad
        boss.pz = player.pz + COS(boss.arcAngle) * bsmArcRad
        boss.moveTimer = boss.moveTimer - 1
        If boss.moveTimer <= 0 Then boss.state = 0

    Case 5  ' XYZ rush: charge on X + arc sweep Y/Z simultaneously
        Select Case boss.phase
            Case 1 : bsmArcSpd = BOSS_ARC_SPD1       : bsmArcRad = BOSS_ARC_RAD1
            Case 2 : bsmArcSpd = BOSS_ARC_SPD2 * 1.2 : bsmArcRad = BOSS_ARC_RAD2
            Case 3 : bsmArcSpd = BOSS_ARC_SPD3 * 1.2 : bsmArcRad = BOSS_ARC_RAD3
        End Select
        boss.arcAngle = boss.arcAngle + bsmArcSpd
        boss.py = player.py + SIN(boss.arcAngle) * bsmArcRad
        boss.pz = player.pz + COS(boss.arcAngle) * bsmArcRad
        If boss.px > player.px + BOSS_CLOSE_DIST Then
            boss.px = boss.px - BOSS_CHARGE_SPD * 0.8
        Else
            boss.moveTimer = boss.moveTimer - 1
            If boss.moveTimer <= 0 Then boss.state = 3
        End If

    End Select
End Sub

' Called each time the boss fires (or completes a state) to pick the next movement mode.
' States 2/3/5 are not interrupted mid-run; call only when boss.state = 0, 1, or 4.
Sub BOSS_PickMode(bpmPhase As Integer)
    Dim bpmRoll As Single : bpmRoll = Rnd

    Select Case bpmPhase
    Case 1
        ' 25% hunt, 35% evade, 30% arc, 10% charge
        If bpmRoll < 0.25 Then
            boss.state = 0
        ElseIf bpmRoll < 0.60 Then
            BOSS_SetEvadeTarget
            boss.state = 1
        ElseIf bpmRoll < 0.90 Then
            Select Case bpmPhase
                Case 1 : boss.moveTimer = 140
                Case 2 : boss.moveTimer = 100
                Case 3 : boss.moveTimer = 60
            End Select
            boss.state = 4
        Else
            If boss.chargeTimer <= 0 Then
                boss.moveTimer = 20
                boss.state = 2
            Else
                boss.state = 0
            End If
        End If

    Case 2
        ' 10% hunt, 20% evade, 30% arc, 25% charge, 15% XYZ rush
        If bpmRoll < 0.10 Then
            boss.state = 0
        ElseIf bpmRoll < 0.30 Then
            BOSS_SetEvadeTarget
            boss.state = 1
        ElseIf bpmRoll < 0.60 Then
            boss.moveTimer = 100
            boss.state = 4
        ElseIf bpmRoll < 0.85 Then
            If boss.chargeTimer <= 0 Then
                boss.moveTimer = 25
                boss.state = 2
            Else
                boss.moveTimer = 100
                boss.state = 4
            End If
        Else
            If boss.chargeTimer <= 0 Then
                boss.moveTimer = 25
                boss.state = 5
            Else
                boss.moveTimer = 100
                boss.state = 4
            End If
        End If

    Case 3
        ' 5% hunt, 10% evade, 20% arc, 30% charge, 35% XYZ rush
        If bpmRoll < 0.05 Then
            boss.state = 0
        ElseIf bpmRoll < 0.15 Then
            BOSS_SetEvadeTarget
            boss.state = 1
        ElseIf bpmRoll < 0.35 Then
            boss.moveTimer = 60
            boss.state = 4
        ElseIf bpmRoll < 0.65 Then
            If boss.chargeTimer <= 0 Then
                boss.moveTimer = 30
                boss.state = 2
            Else
                boss.moveTimer = 60
                boss.state = 4
            End If
        Else
            If boss.chargeTimer <= 0 Then
                boss.moveTimer = 30
                boss.state = 5
            Else
                boss.moveTimer = 60
                boss.state = 4
            End If
        End If

    End Select
End Sub

Sub BOSS_SetEvadeTarget()
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
End Sub
