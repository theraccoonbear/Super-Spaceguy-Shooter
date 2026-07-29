' Boss movement modes (boss.state):
'   0 hunt    -- soft-track player Y/Z at a rate just below player max velocity
'   1 evade   -- dart to small world-space Y/Z offset, then return to hunt
'   2 charge  -- close on X, Y/Z toward snapshot target set at charge start
'   3 retreat -- back to BOSS_COMBAT_DIST on X
'   4 arc     -- sweep Y/Z arc around player's position at mode-pick time
'   5 xyzrush -- charge on X + arc sweep simultaneously
'
' Hunt mode uses continuous soft-tracking so the boss stays in the player's
' engagement zone.  Rate is low enough that player movement is meaningful.
' All other modes commit to a fixed snapshot of player.py/pz at pick time.
'
' Arc entry: arcAngle is initialised from the boss's current position so the
' transition is smooth (no teleport).  boss.py/pz lerps toward the arc circle.

' BOSS_COMBAT_DIST defined here (behavior.bas included before boss.bas)
Const BOSS_COMBAT_DIST = 20    ' standard X distance for combat
Const BOSS_CLOSE_DIST  = 5.0   ' X distance at closest approach during charge

Const BOSS_CHARGE_SPD  = 0.30  ' X close speed during charge
Const BOSS_RETREAT_SPD = 0.18  ' X retreat speed back to combat dist

Const BOSS_ARC_SPD1 = 0.012    ' arc sweep rate (rad/frame) phase 1
Const BOSS_ARC_SPD2 = 0.020    ' phase 2
Const BOSS_ARC_SPD3 = 0.030    ' phase 3

Const BOSS_ARC_RAD1 = 3.0      ' arc radius in Y/Z plane phase 1
Const BOSS_ARC_RAD2 = 5.0      ' phase 2
Const BOSS_ARC_RAD3 = 7.0      ' phase 3

Const BOSS_ENGAGE_MAX = 5.0    ' max Y/Z distance from player for evade targets

Const BOSS_CHARGE_CD1 = 300    ' frames between charge eligibility, phase 1
Const BOSS_CHARGE_CD2 = 190    ' phase 2
Const BOSS_CHARGE_CD3 = 110    ' phase 3

Sub BOSS_UpdateMovement()
    Dim bsmArcSpd As Single, bsmArcRad As Single, bsmRate As Single
    Dim bsmArcTgtY As Single, bsmArcTgtZ As Single

    boss.chargeTimer = boss.chargeTimer - 1
    If boss.chargeTimer < 0 Then boss.chargeTimer = 0

    Select Case boss.state
    Case 0  ' hunt: soft-track player continuously at below-player-speed rate
        Select Case boss.phase
            Case 1 : bsmRate = 0.010
            Case 2 : bsmRate = 0.014
            Case 3 : bsmRate = 0.018
        End Select
        boss.py = boss.py + (player.py - boss.py) * bsmRate
        boss.pz = boss.pz + (player.pz - boss.pz) * bsmRate

    Case 1  ' evade: dart to small fixed offset, then return to hunt
        Select Case boss.phase
            Case 1 : bsmRate = 0.040
            Case 2 : bsmRate = 0.055
            Case 3 : bsmRate = 0.070
        End Select
        boss.py = boss.py + (boss.targetY - boss.py) * bsmRate
        boss.pz = boss.pz + (boss.targetZ - boss.pz) * bsmRate
        boss.moveTimer = boss.moveTimer - 1
        If boss.moveTimer <= 0 Then boss.state = 0

    Case 2  ' charge: close on X, Y/Z toward snapshot target from charge start
        Select Case boss.phase
            Case 1 : bsmRate = 0.035
            Case 2 : bsmRate = 0.050
            Case 3 : bsmRate = 0.070
        End Select
        boss.py = boss.py + (boss.targetY - boss.py) * bsmRate
        boss.pz = boss.pz + (boss.targetZ - boss.pz) * bsmRate
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

    Case 4  ' arc: sweep Y/Z circle around snapshot center (boss.targetY/Z)
        Select Case boss.phase
            Case 1 : bsmArcSpd = BOSS_ARC_SPD1 : bsmArcRad = BOSS_ARC_RAD1
            Case 2 : bsmArcSpd = BOSS_ARC_SPD2 : bsmArcRad = BOSS_ARC_RAD2
            Case 3 : bsmArcSpd = BOSS_ARC_SPD3 : bsmArcRad = BOSS_ARC_RAD3
        End Select
        boss.arcAngle = boss.arcAngle + bsmArcSpd
        bsmArcTgtY = boss.targetY + SIN(boss.arcAngle) * bsmArcRad
        bsmArcTgtZ = boss.targetZ + COS(boss.arcAngle) * bsmArcRad
        boss.py = boss.py + (bsmArcTgtY - boss.py) * 0.12
        boss.pz = boss.pz + (bsmArcTgtZ - boss.pz) * 0.12
        boss.moveTimer = boss.moveTimer - 1
        If boss.moveTimer <= 0 Then boss.state = 0

    Case 5  ' XYZ rush: charge on X + arc sweep around fixed center simultaneously
        Select Case boss.phase
            Case 1 : bsmArcSpd = BOSS_ARC_SPD1       : bsmArcRad = BOSS_ARC_RAD1
            Case 2 : bsmArcSpd = BOSS_ARC_SPD2 * 1.2 : bsmArcRad = BOSS_ARC_RAD2
            Case 3 : bsmArcSpd = BOSS_ARC_SPD3 * 1.2 : bsmArcRad = BOSS_ARC_RAD3
        End Select
        boss.arcAngle = boss.arcAngle + bsmArcSpd
        bsmArcTgtY = boss.targetY + SIN(boss.arcAngle) * bsmArcRad
        bsmArcTgtZ = boss.targetZ + COS(boss.arcAngle) * bsmArcRad
        boss.py = boss.py + (bsmArcTgtY - boss.py) * 0.12
        boss.pz = boss.pz + (bsmArcTgtZ - boss.pz) * 0.12
        If boss.px > player.px + BOSS_CLOSE_DIST Then
            boss.px = boss.px - BOSS_CHARGE_SPD * 0.8
        Else
            boss.moveTimer = boss.moveTimer - 1
            If boss.moveTimer <= 0 Then boss.state = 3
        End If

    End Select
End Sub

' Called each time the boss fires to pick the next movement mode.
' Hunt uses live player tracking; all other modes snapshot player.py/pz at pick time.
' States 2/3/5 run to completion; only call when boss.state is 0, 1, or 4.
Sub BOSS_PickMode(bpmPhase As Integer)
    Dim bpmRoll As Single : bpmRoll = Rnd

    Select Case bpmPhase
    Case 1
        ' 30% hunt, 35% evade, 25% arc, 10% charge
        If bpmRoll < 0.30 Then
            boss.state = 0
        ElseIf bpmRoll < 0.65 Then
            BOSS_SetEvadeTarget
            boss.state = 1
        ElseIf bpmRoll < 0.90 Then
            boss.targetY = player.py : boss.targetZ = player.pz
            boss.arcAngle = _ATAN2(boss.py - player.py, boss.pz - player.pz)
            boss.moveTimer = 200
            boss.state = 4
        Else
            If boss.chargeTimer <= 0 Then
                boss.targetY = player.py : boss.targetZ = player.pz
                boss.moveTimer = 20
                boss.state = 2
            Else
                boss.state = 0
            End If
        End If

    Case 2
        ' 15% hunt, 20% evade, 30% arc, 25% charge, 10% XYZ rush
        If bpmRoll < 0.15 Then
            boss.state = 0
        ElseIf bpmRoll < 0.35 Then
            BOSS_SetEvadeTarget
            boss.state = 1
        ElseIf bpmRoll < 0.65 Then
            boss.targetY = player.py : boss.targetZ = player.pz
            boss.arcAngle = _ATAN2(boss.py - player.py, boss.pz - player.pz)
            boss.moveTimer = 160
            boss.state = 4
        ElseIf bpmRoll < 0.90 Then
            If boss.chargeTimer <= 0 Then
                boss.targetY = player.py : boss.targetZ = player.pz
                boss.moveTimer = 25
                boss.state = 2
            Else
                boss.targetY = player.py : boss.targetZ = player.pz
                boss.arcAngle = _ATAN2(boss.py - player.py, boss.pz - player.pz)
                boss.moveTimer = 160
                boss.state = 4
            End If
        Else
            If boss.chargeTimer <= 0 Then
                boss.targetY = player.py : boss.targetZ = player.pz
                boss.arcAngle = _ATAN2(boss.py - player.py, boss.pz - player.pz)
                boss.moveTimer = 25
                boss.state = 5
            Else
                boss.targetY = player.py : boss.targetZ = player.pz
                boss.arcAngle = _ATAN2(boss.py - player.py, boss.pz - player.pz)
                boss.moveTimer = 160
                boss.state = 4
            End If
        End If

    Case 3
        ' 10% hunt, 10% evade, 20% arc, 30% charge, 30% XYZ rush
        If bpmRoll < 0.10 Then
            boss.state = 0
        ElseIf bpmRoll < 0.20 Then
            BOSS_SetEvadeTarget
            boss.state = 1
        ElseIf bpmRoll < 0.40 Then
            boss.targetY = player.py : boss.targetZ = player.pz
            boss.arcAngle = _ATAN2(boss.py - player.py, boss.pz - player.pz)
            boss.moveTimer = 120
            boss.state = 4
        ElseIf bpmRoll < 0.70 Then
            If boss.chargeTimer <= 0 Then
                boss.targetY = player.py : boss.targetZ = player.pz
                boss.moveTimer = 30
                boss.state = 2
            Else
                boss.targetY = player.py : boss.targetZ = player.pz
                boss.arcAngle = _ATAN2(boss.py - player.py, boss.pz - player.pz)
                boss.moveTimer = 120
                boss.state = 4
            End If
        Else
            If boss.chargeTimer <= 0 Then
                boss.targetY = player.py : boss.targetZ = player.pz
                boss.arcAngle = _ATAN2(boss.py - player.py, boss.pz - player.pz)
                boss.moveTimer = 30
                boss.state = 5
            Else
                boss.targetY = player.py : boss.targetZ = player.pz
                boss.arcAngle = _ATAN2(boss.py - player.py, boss.pz - player.pz)
                boss.moveTimer = 120
                boss.state = 4
            End If
        End If

    End Select
End Sub

Sub BOSS_SetEvadeTarget()
    ' Small world-space offset from player -- clamped to BOSS_ENGAGE_MAX so boss never leaves the arena
    Dim bstOffY As Single, bstOffZ As Single
    bstOffY = 1.5 + Rnd * 2.5   ' 1.5 to 4.0 units
    bstOffZ = 1.0 + Rnd * 2.0   ' 1.0 to 3.0 units
    If boss.py >= player.py Then
        boss.targetY = player.py - bstOffY
    Else
        boss.targetY = player.py + bstOffY
    End If
    If boss.pz >= player.pz Then
        boss.targetZ = player.pz - bstOffZ
    Else
        boss.targetZ = player.pz + bstOffZ
    End If
    ' clamp to engagement zone
    If boss.targetY < player.py - BOSS_ENGAGE_MAX Then boss.targetY = player.py - BOSS_ENGAGE_MAX
    If boss.targetY > player.py + BOSS_ENGAGE_MAX Then boss.targetY = player.py + BOSS_ENGAGE_MAX
    If boss.targetZ < player.pz - BOSS_ENGAGE_MAX Then boss.targetZ = player.pz - BOSS_ENGAGE_MAX
    If boss.targetZ > player.pz + BOSS_ENGAGE_MAX Then boss.targetZ = player.pz + BOSS_ENGAGE_MAX
    Select Case boss.phase
        Case 1 : boss.moveTimer = 120
        Case 2 : boss.moveTimer = 90
        Case 3 : boss.moveTimer = 60
    End Select
End Sub
