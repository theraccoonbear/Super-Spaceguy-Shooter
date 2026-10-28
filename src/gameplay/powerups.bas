' powerups.bas -- the three power-up kinds: odds, amounts, grab and tractor tests (#183)
'
' Tuning comes from assets/config/powerups.ini (see the comments there). No rendering, no
' spawning, no object pool here (wave.bas spawns, playing.bas moves, draws and grabs), so
' tests drive it directly:
'   ok = PUP_Load%                    read the tuning (after CFG_Parse$ of powerups.ini); 0 + pupLoadErr
'   k = PUP_PickKind%(r)              kind for a roll r in 0..1, by pup_weights
'   a = PUP_Amount!(kind, chapter)    what a pickup of that kind gives in that chapter
'   g = PUP_Grabbed%(dx, dy, dz)      -1 when a pickup that far from the ship is caught
'   t = PUP_InTractor%(dx, dy, dz, r) -1 when a tractor beam of reach r holds it
'   a = PUP_Apply!(kind, chapter)     gives it: shield / fuel up to the cap, else score.
'                                     Returns the amount applied; pupOverflowPts says what a full
'                                     gauge paid in score instead (0 when it wasn't full)
'   n$ = PUP_KindName$(kind)          "points" / "shield" / "fuel" (telemetry)
' Local variable prefix: pup*

Const PUP_POINTS = 1
Const PUP_SHIELD = 2
Const PUP_FUEL   = 3
Const PUP_KINDS  = 3
Const PUP_MAX_CH = 16
Const PUP_TRACTOR_DX_MIN = -2   ' the tractor beam reaches from just behind the ship...
Const PUP_TRACTOR_DX_MAX = 45   ' ...to this far ahead

Dim Shared pupChance As Single, pupW(1 To PUP_KINDS) As Single, pupWTotal As Single
Dim Shared pupPoints As Long, pupShield As Integer, pupOverflow As Long
Dim Shared pupFuel(1 To PUP_MAX_CH) As Single, pupFuelCnt As Integer
Dim Shared pupSpawnX As Single, pupSpawnXVar As Single, pupSpreadY As Single, pupSpreadZ As Single
Dim Shared pupSpeed As Single, pupGrabR As Single, pupGrabDX As Single, pupMarkerFrames As Integer
Dim Shared pupOverflowPts As Long
Dim Shared pupLoadErr As String

Function PUP_Load%
    Dim puplV(1 To PUP_MAX_CH) As String, puplN As Integer, puplI As Integer
    PUP_Load% = 0
    pupLoadErr = ""
    pupChance = Val(CFG_Get$(cfgPowerups, "pup_chance"))
    pupPoints = Val(CFG_Get$(cfgPowerups, "pup_points"))
    pupShield = Val(CFG_Get$(cfgPowerups, "pup_shield"))
    pupOverflow = Val(CFG_Get$(cfgPowerups, "pup_overflow_pts"))
    pupSpreadY = Val(CFG_Get$(cfgPowerups, "pup_spread_y"))
    pupSpreadZ = Val(CFG_Get$(cfgPowerups, "pup_spread_z"))
    pupSpeed = Val(CFG_Get$(cfgPowerups, "pup_speed"))
    pupGrabR = Val(CFG_Get$(cfgPowerups, "pup_grab_r"))
    pupGrabDX = Val(CFG_Get$(cfgPowerups, "pup_grab_dx"))
    pupMarkerFrames = Val(CFG_Get$(cfgPowerups, "pup_marker_frames"))
    If pupChance < 0 Or pupChance > 1 Then pupLoadErr = "config/powerups.ini pup_chance must be 0..1" : Exit Function
    If pupPoints <= 0 Or pupShield <= 0 Or pupOverflow < 0 Then pupLoadErr = "config/powerups.ini needs pup_points and pup_shield above 0" : Exit Function
    If pupSpeed <= 0 Or pupGrabR <= 0 Or pupGrabDX <= 0 Then pupLoadErr = "config/powerups.ini needs pup_speed, pup_grab_r and pup_grab_dx above 0" : Exit Function
    If pupMarkerFrames < 0 Then pupLoadErr = "config/powerups.ini pup_marker_frames can't be negative" : Exit Function

    UPG_Split CFG_Get$(cfgPowerups, "pup_weights"), ",", puplV(), puplN
    If puplN <> PUP_KINDS Then pupLoadErr = "config/powerups.ini pup_weights needs 3 values (points, shield, fuel)" : Exit Function
    pupWTotal = 0
    For puplI = 1 To PUP_KINDS
        pupW(puplI) = Val(puplV(puplI))
        If pupW(puplI) < 0 Then pupLoadErr = "config/powerups.ini pup_weights can't be negative" : Exit Function
        pupWTotal = pupWTotal + pupW(puplI)
    Next puplI
    If pupWTotal <= 0 Then pupLoadErr = "config/powerups.ini pup_weights add up to 0" : Exit Function

    UPG_Split CFG_Get$(cfgPowerups, "pup_fuel"), ",", puplV(), pupFuelCnt
    If pupFuelCnt < 1 Then pupLoadErr = "config/powerups.ini has no pup_fuel" : Exit Function
    For puplI = 1 To pupFuelCnt
        pupFuel(puplI) = Val(puplV(puplI))
        If pupFuel(puplI) <= 0 Then pupLoadErr = "config/powerups.ini pup_fuel: every value above 0" : Exit Function
    Next puplI

    UPG_Split CFG_Get$(cfgPowerups, "pup_spawn_x"), ",", puplV(), puplN
    If puplN <> 2 Then pupLoadErr = "config/powerups.ini pup_spawn_x needs min,variance" : Exit Function
    pupSpawnX = Val(puplV(1)) : pupSpawnXVar = Val(puplV(2))
    If pupSpawnX <= pupGrabDX Or pupSpawnXVar < 0 Then pupLoadErr = "config/powerups.ini pup_spawn_x must start ahead of the grab zone" : Exit Function
    PUP_Load% = -1
End Function

Function PUP_PickKind% (pupkR As Single)
    Dim pupkT As Single
    pupkT = pupkR * pupWTotal
    If pupkT < pupW(PUP_POINTS) Then
        PUP_PickKind% = PUP_POINTS
    ElseIf pupkT < pupW(PUP_POINTS) + pupW(PUP_SHIELD) Then
        PUP_PickKind% = PUP_SHIELD
    Else
        PUP_PickKind% = PUP_FUEL
    End If
End Function

Function PUP_Amount! (pupaKind As Integer, pupaCh As Integer)
    Dim pupaI As Integer
    Select Case pupaKind
        Case PUP_POINTS : PUP_Amount! = pupPoints
        Case PUP_SHIELD : PUP_Amount! = pupShield
        Case PUP_FUEL
            pupaI = pupaCh
            If pupaI < 1 Then pupaI = 1
            If pupaI > pupFuelCnt Then pupaI = pupFuelCnt
            PUP_Amount! = pupFuel(pupaI)
        Case Else : PUP_Amount! = 0
    End Select
End Function

Function PUP_Grabbed% (pupgDX As Single, pupgDY As Single, pupgDZ As Single)
    PUP_Grabbed% = 0
    If Abs(pupgDX) > pupGrabDX Then Exit Function
    If pupgDY * pupgDY + pupgDZ * pupgDZ > pupGrabR * pupGrabR Then Exit Function
    PUP_Grabbed% = -1
End Function

Function PUP_InTractor% (puptDX As Single, puptDY As Single, puptDZ As Single, puptR As Single)
    PUP_InTractor% = 0
    If puptR <= 0 Then Exit Function
    If puptDX < PUP_TRACTOR_DX_MIN Or puptDX > PUP_TRACTOR_DX_MAX Then Exit Function
    If puptDY * puptDY + puptDZ * puptDZ > puptR * puptR Then Exit Function
    PUP_InTractor% = -1
End Function

' A gauge with less than one unit of room counts as full: the pickup pays pup_overflow_pts.
Function PUP_Apply! (pupyKind As Integer, pupyCh As Integer)
    Dim pupyAmt As Single, pupyRoom As Single
    pupOverflowPts = 0
    pupyAmt = PUP_Amount!(pupyKind, pupyCh)
    Select Case pupyKind
        Case PUP_POINTS
            score = score + pupPoints
            PUP_Apply! = pupPoints
            Exit Function
        Case PUP_SHIELD : pupyRoom = shieldMax - lives
        Case PUP_FUEL : pupyRoom = fuelMax - fuelLevel
        Case Else : PUP_Apply! = 0 : Exit Function
    End Select
    If pupyRoom < 1 Then
        score = score + pupOverflow
        pupOverflowPts = pupOverflow
        PUP_Apply! = 0
        Exit Function
    End If
    If pupyAmt > pupyRoom Then pupyAmt = pupyRoom
    If pupyKind = PUP_SHIELD Then
        pupyAmt = Int(pupyAmt)
        lives = lives + pupyAmt
    Else
        fuelLevel = fuelLevel + pupyAmt
    End If
    PUP_Apply! = pupyAmt
End Function

Function PUP_KindName$ (pupnKind As Integer)
    Select Case pupnKind
        Case PUP_POINTS : PUP_KindName$ = "points"
        Case PUP_SHIELD : PUP_KindName$ = "shield"
        Case PUP_FUEL : PUP_KindName$ = "fuel"
        Case Else : PUP_KindName$ = "unknown"
    End Select
End Function
