' upgrades.bas -- credits ($) and the upgrade table bought at the dock (#268)
'
' Credits are a second currency, separate from score: kills, bosses, stage clears and
' the asteroid field earn them, the dock (src/state/dock.bas) spends them, and spending
' never touches score. Credits and upgrades last one run (UPG_Reset on a new game).
'
' Every amount, price and effect comes from assets/gamevalues.ini (see the comments
' there for the line format). No rendering or input here, so tests drive it directly:
'   UPG_Load                       read the table and credit amounts (after GTEXT_LoadVars)
'   UPG_Reset                      new run: no credits, every upgrade at level 0
'   CR_Add n                       earn n credits (amounts: crKill, crBoss, crStage, ...)
'   r = UPG_Buy%(id)               buy the next level: UPG_OK / UPG_NOFUNDS / UPG_MAXED / UPG_FULL
'   UPG_Apply                      recompute the effect values in dims.bas from the levels
'   UPG_DockVisit                  per dock: refill nova charges, allow one hull repair
'   ok = UPG_RollTry%(dir)         start an evasive roll if unlocked and cooled down
'   UPG_RollTick                   once per frame in play
'   ok = UPG_NovaTry%              spend a nova charge
'   UPG_RegenTick                  once per frame in play: shield regen after regenDelay
'   d = UPG_ArmourDmg%(dmg)        collision damage after hull armour
' Local variable prefix: upg* / cr*

Const UPG_COUNT   = 12
Const UPG_MAX_LV  = 5
Const UPG_LASER   = 1
Const UPG_CANNON  = 2
Const UPG_RAPID   = 3
Const UPG_SHIELD  = 4
Const UPG_REGEN   = 5
Const UPG_ARMOUR  = 6
Const UPG_NOVA    = 7
Const UPG_THRUST  = 8
Const UPG_ROLL    = 9
Const UPG_TRACTOR = 10
Const UPG_FUEL    = 11
Const UPG_REPAIR  = 12

Const UPG_OK      = 0
Const UPG_NOFUNDS = 1
Const UPG_MAXED   = 2
Const UPG_FULL    = 3   ' hull repair with the shields already full

Dim Shared upgKey$(1 To UPG_COUNT)
Dim Shared upgNames$(1 To UPG_COUNT)    ' "NAME" or "NAME LV1,NAME LV2,..."
Dim Shared upgDesc$(1 To UPG_COUNT)     ' what it does (upgdesc_<key>), for the dock and the SHIP SYSTEMS page
Dim Shared upgHintPending As String   ' "ROLL READY ..." lines (Chr$(10)-separated) to show on the next launch
Dim Shared upgHintNova As String, upgHintRoll As String
Dim Shared upgMax(1 To UPG_COUNT) As Integer
Dim Shared upgLevel(1 To UPG_COUNT) As Integer
Dim Shared upgPrice(1 To UPG_COUNT, 1 To UPG_MAX_LV) As Long
Dim Shared upgFxA(1 To UPG_COUNT, 0 To UPG_MAX_LV) As Single
Dim Shared upgFxB(1 To UPG_COUNT, 0 To UPG_MAX_LV) As Single
Dim Shared upgLoadErr As String
Dim Shared crKill As Long, crBoss As Long, crStage As Long
Dim Shared crAstNear As Long, crAstKill As Long, crAstSurvive As Long

' Splits "a,b,c" into upgsOut$(1..) (at most UPG_MAX_LV + 1 entries).
Sub UPG_Split (upgsSrc As String, upgsSep As String, upgsOut() As String, upgsCnt As Integer)
    Dim upgsStart As Integer, upgsAt As Integer
    upgsCnt = 0 : upgsStart = 1
    If Len(upgsSrc) = 0 Then Exit Sub
    Do
        upgsAt = InStr(upgsStart, upgsSrc, upgsSep)
        If upgsAt = 0 Then upgsAt = Len(upgsSrc) + 1
        If upgsCnt >= UBound(upgsOut) Then Exit Do
        upgsCnt = upgsCnt + 1
        upgsOut(upgsCnt) = LTrim$(RTrim$(Mid$(upgsSrc, upgsStart, upgsAt - upgsStart)))
        If upgsAt > Len(upgsSrc) Then Exit Do
        upgsStart = upgsAt + 1
    Loop
End Sub

' One upgrade line "names|prices|fxA|fxB" (fxA/fxB optional: level 0..max values).
Function UPG_ParseLine% (upgpId As Integer, upgpKey As String, upgpLine As String)
    Dim upgpPart(1 To UPG_MAX_LV + 1) As String, upgpParts As Integer
    Dim upgpVal(1 To UPG_MAX_LV + 1) As String, upgpVals As Integer
    Dim upgpI As Integer
    UPG_ParseLine% = 0
    upgKey$(upgpId) = upgpKey
    upgMax(upgpId) = 0
    For upgpI = 0 To UPG_MAX_LV
        upgFxA(upgpId, upgpI) = 0 : upgFxB(upgpId, upgpI) = 0
    Next upgpI
    UPG_Split upgpLine, "|", upgpPart(), upgpParts
    If upgpParts < 2 Then upgLoadErr = "upg_" + upgpKey + ": needs name|prices" : Exit Function
    upgNames$(upgpId) = upgpPart(1)
    UPG_Split upgpPart(2), ",", upgpVal(), upgpVals
    If upgpVals < 1 Or upgpVals > UPG_MAX_LV Then upgLoadErr = "upg_" + upgpKey + ": 1 to" + Str$(UPG_MAX_LV) + " prices" : Exit Function
    upgMax(upgpId) = upgpVals
    For upgpI = 1 To upgpVals
        upgPrice(upgpId, upgpI) = Val(upgpVal(upgpI))
    Next upgpI
    If upgpParts >= 3 Then
        UPG_Split upgpPart(3), ",", upgpVal(), upgpVals
        If upgpVals <> upgMax(upgpId) + 1 Then upgLoadErr = "upg_" + upgpKey + ": effect A needs one value per level, 0 to max" : Exit Function
        For upgpI = 1 To upgpVals : upgFxA(upgpId, upgpI - 1) = Val(upgpVal(upgpI)) : Next upgpI
    End If
    If upgpParts >= 4 Then
        UPG_Split upgpPart(4), ",", upgpVal(), upgpVals
        If upgpVals <> upgMax(upgpId) + 1 Then upgLoadErr = "upg_" + upgpKey + ": effect B needs one value per level, 0 to max" : Exit Function
        For upgpI = 1 To upgpVals : upgFxB(upgpId, upgpI - 1) = Val(upgpVal(upgpI)) : Next upgpI
    End If
    UPG_ParseLine% = -1
End Function

' Reads the table from the gamevalues tokens (GTEXT_LoadVars first). 0 + upgLoadErr on error.
Function UPG_Load%
    Dim upglI As Integer, upglKey As String, upglLine As String, upglOk As Integer
    UPG_Load% = 0
    upgLoadErr = ""
    For upglI = 1 To UPG_COUNT
        upglKey = UPG_KeyOf$(upglI)
        upglLine = GTEXT_Var$("upg_" + upglKey)
        If Len(upglLine) = 0 Then upgLoadErr = "gamevalues.ini has no upg_" + upglKey : Exit Function
        upglOk = UPG_ParseLine%(upglI, upglKey, upglLine)
        If upglOk = 0 Then Exit Function
        upgDesc$(upglI) = GTEXT_Var$("upgdesc_" + upglKey)
        If Len(upgDesc$(upglI)) = 0 Then upgLoadErr = "gamevalues.ini has no upgdesc_" + upglKey : Exit Function
    Next upglI
    crKill = Val(GTEXT_Var$("cr_kill"))
    crBoss = Val(GTEXT_Var$("cr_boss"))
    crStage = Val(GTEXT_Var$("cr_stage"))
    crAstNear = Val(GTEXT_Var$("cr_ast_near"))
    crAstKill = Val(GTEXT_Var$("cr_ast_kill"))
    crAstSurvive = Val(GTEXT_Var$("cr_ast_survive"))
    novaRadius = Val(GTEXT_Var$("nova_radius"))
    novaBossDmg = Val(GTEXT_Var$("nova_boss_dmg"))
    rollFrames = Val(GTEXT_Var$("roll_frames"))
    rollSpeed = Val(GTEXT_Var$("roll_speed"))
    upgHintNova = GTEXT_Var$("hint_nova")
    upgHintRoll = GTEXT_Var$("hint_roll")
    If rollFrames < 1 Then rollFrames = 1
    UPG_Load% = -1
End Function

Sub UPG_Reset
    Dim upgrI As Integer
    For upgrI = 1 To UPG_COUNT : upgLevel(upgrI) = 0 : Next upgrI
    credits = 0 : creditsEarned = 0 : creditsSpent = 0
    novaCharges = 0 : novaFxTimer = 0
    rollTimer = 0 : rollCool = 0 : rollDir = 1
    regenTick = 0 : noHitFrames = 0
    upgHintPending = ""
    UPG_Apply
End Sub

Sub UPG_Apply
    Dim upgaL As Integer
    laserMax = upgFxA(UPG_LASER, upgLevel(UPG_LASER))
    laserRegen = upgFxB(UPG_LASER, upgLevel(UPG_LASER))
    gunShots = upgFxA(UPG_CANNON, upgLevel(UPG_CANNON))
    If gunShots < 1 Then gunShots = 1
    gunSpread = upgFxB(UPG_CANNON, upgLevel(UPG_CANNON))
    fireCool = upgFxA(UPG_RAPID, upgLevel(UPG_RAPID))
    shieldMax = upgFxA(UPG_SHIELD, upgLevel(UPG_SHIELD))
    regenEvery = upgFxA(UPG_REGEN, upgLevel(UPG_REGEN))
    regenDelay = upgFxB(UPG_REGEN, upgLevel(UPG_REGEN))
    armourMul = upgFxA(UPG_ARMOUR, upgLevel(UPG_ARMOUR))
    novaMax = upgFxA(UPG_NOVA, upgLevel(UPG_NOVA))
    shipMaxVel = upgFxA(UPG_THRUST, upgLevel(UPG_THRUST))
    upgaL = upgLevel(UPG_ROLL)
    rollCoolMax = upgFxA(UPG_ROLL, upgaL)
    tractorR = upgFxA(UPG_TRACTOR, upgLevel(UPG_TRACTOR))
    tractorPull = upgFxB(UPG_TRACTOR, upgLevel(UPG_TRACTOR))
    fuelMax = upgFxA(UPG_FUEL, upgLevel(UPG_FUEL))
End Sub

' Name shown for the next level to buy (the last one once maxed).
Function UPG_Name$ (upgnId As Integer)
    Dim upgnPart(1 To UPG_MAX_LV + 1) As String, upgnCnt As Integer, upgnI As Integer
    UPG_Split upgNames$(upgnId), ",", upgnPart(), upgnCnt
    upgnI = upgLevel(upgnId) + 1
    If upgnI > upgnCnt Then upgnI = upgnCnt
    If upgnI < 1 Then UPG_Name$ = "" Else UPG_Name$ = upgnPart(upgnI)
End Function

' Price of the next level, 0 when maxed.
Function UPG_Price& (upgcId As Integer)
    If upgLevel(upgcId) >= upgMax(upgcId) Then UPG_Price& = 0 Else UPG_Price& = upgPrice(upgcId, upgLevel(upgcId) + 1)
End Function

Function UPG_Buy% (upgbId As Integer)
    Dim upgbPrice As Long
    If upgLevel(upgbId) >= upgMax(upgbId) Then UPG_Buy% = UPG_MAXED : Exit Function
    If upgbId = UPG_REPAIR And lives >= shieldMax Then UPG_Buy% = UPG_FULL : Exit Function
    upgbPrice = UPG_Price&(upgbId)
    If upgbPrice > credits Then UPG_Buy% = UPG_NOFUNDS : Exit Function
    credits = credits - upgbPrice
    creditsSpent = creditsSpent + upgbPrice
    upgLevel(upgbId) = upgLevel(upgbId) + 1
    UPG_Apply
    Select Case upgbId
        Case UPG_NOVA : novaCharges = novaMax
        Case UPG_REPAIR : lives = shieldMax
        Case UPG_LASER : laserEnergy = laserMax
        Case UPG_FUEL : fuelLevel = fuelMax
    End Select
    ' first time an active ability is bought this run: tell the player its key on launch
    If upgLevel(upgbId) = 1 Then
        If upgbId = UPG_NOVA Then UPG_AddHint upgHintNova
        If upgbId = UPG_ROLL Then UPG_AddHint upgHintRoll
    End If
    TELEM_UpgradeBought upgKey$(upgbId), upgLevel(upgbId), upgbPrice
    UPG_Buy% = UPG_OK
End Function

' Every dock visit: nova charges refill, and hull repair can be bought once more.
Sub UPG_DockVisit
    novaCharges = novaMax
    upgLevel(UPG_REPAIR) = 0
End Sub

Sub CR_Add (crN As Long)
    credits = credits + crN
    creditsEarned = creditsEarned + crN
End Sub

Sub CR_StageClear
    CR_Add crStage
End Sub

' Starts a roll toward urDir (-1 / +1). Needs the upgrade, no roll running, no cooldown.
Function UPG_RollTry% (urDir As Integer)
    UPG_RollTry% = 0
    If rollCoolMax <= 0 Or rollTimer > 0 Or rollCool > 0 Then Exit Function
    rollDir = urDir
    If rollDir = 0 Then rollDir = 1
    rollTimer = rollFrames
    rollCool = rollCoolMax
    UPG_RollTry% = -1
End Function

' The cooldown runs from the start of the roll.
Sub UPG_RollTick
    If rollTimer > 0 Then rollTimer = rollTimer - 1
    If rollCool > 0 Then rollCool = rollCool - 1
End Sub

Function UPG_NovaTry%
    UPG_NovaTry% = 0
    If novaCharges <= 0 Then Exit Function
    novaCharges = novaCharges - 1
    UPG_NovaTry% = -1
End Function

' Shield regen: after regenDelay frames without a hit, one point every regenEvery frames.
Sub UPG_RegenTick
    noHitFrames = noHitFrames + 1
    If regenEvery <= 0 Or lives >= shieldMax Or noHitFrames < regenDelay Then regenTick = 0 : Exit Sub
    regenTick = regenTick + 1
    If regenTick >= regenEvery Then
        regenTick = 0
        lives = lives + 1
    End If
End Sub

Function UPG_ArmourDmg% (uadDmg As Integer)
    UPG_ArmourDmg% = CInt(uadDmg * armourMul)
End Function

' What upgrade udId does, from gamevalues.ini's upgdesc_<key> (the dock's first info line
' and the SHIP SYSTEMS help page).
Function UPG_Info$ (uiId As Integer)
    UPG_Info$ = upgDesc$(uiId)
End Function

' The concrete change the next level makes, computed from the table (the dock's second
' info line); "MAXED" once there's nothing left to buy. At most 25 characters.
Function UPG_Next$ (udId As Integer)
    Dim udL As Integer, udA0 As Single, udA1 As Single, udB0 As Single, udB1 As Single
    udL = upgLevel(udId)
    If udId = UPG_REPAIR Then
        If udL >= upgMax(udId) Then
            UPG_Next$ = "DONE THIS VISIT"
        ElseIf lives >= shieldMax Then
            UPG_Next$ = "SHIELDS ALREADY FULL"
        Else
            UPG_Next$ = "SHIELDS " + UPG_Num$(lives) + ">" + UPG_Num$(shieldMax)
        End If
        Exit Function
    End If
    If udL >= upgMax(udId) Then UPG_Next$ = "MAXED" : Exit Function
    udA0 = upgFxA(udId, udL) : udA1 = upgFxA(udId, udL + 1)
    udB0 = upgFxB(udId, udL) : udB1 = upgFxB(udId, udL + 1)
    Select Case udId
        Case UPG_LASER : UPG_Next$ = "MAX " + UPG_Num$(udA0) + ">" + UPG_Num$(udA1) + ", REGEN +" + UPG_Num$(Int((udB1 / udB0 - 1) * 100 + 0.5)) + "%"
        Case UPG_CANNON
            If udA1 >= 3 Then UPG_Next$ = "NEXT: 3-WAY SPREAD" Else UPG_Next$ = "NEXT: 2 PARALLEL SHOTS"
        Case UPG_RAPID : UPG_Next$ = "SHOT DELAY " + UPG_Num$(udA0) + ">" + UPG_Num$(udA1) + "S"
        Case UPG_SHIELD : UPG_Next$ = "SHIELD MAX " + UPG_Num$(udA0) + ">" + UPG_Num$(udA1)
        Case UPG_REGEN : UPG_Next$ = UPG_Num$(Int(60 / udA1)) + " SH/S AFTER " + UPG_Num$(udB1 / 60) + "S UNHIT"
        Case UPG_ARMOUR : UPG_Next$ = "CRASH DAMAGE " + UPG_Num$(Int(udA0 * 100 + 0.5)) + ">" + UPG_Num$(Int(udA1 * 100 + 0.5)) + "%"
        Case UPG_NOVA : UPG_Next$ = "CHARGES/STAGE " + UPG_Num$(udA0) + ">" + UPG_Num$(udA1)
        Case UPG_THRUST : UPG_Next$ = "SIDE SPEED +" + UPG_Num$(Int((udA1 / udA0 - 1) * 100 + 0.5)) + "%"
        Case UPG_ROLL
            If udL = 0 Then UPG_Next$ = "UNLOCKS THE ROLL" Else UPG_Next$ = "COOLDOWN " + UPG_Num$(udA0 / 60) + ">" + UPG_Num$(udA1 / 60) + "S"
        Case UPG_TRACTOR : UPG_Next$ = "PULL RANGE " + UPG_Num$(udA0) + ">" + UPG_Num$(udA1)
        Case UPG_FUEL : UPG_Next$ = "FUEL TANK " + UPG_Num$(udA0) + ">" + UPG_Num$(udA1)
    End Select
End Function

' Number without the leading space or "0." clutter: 0.18 -> ".18", 2.5 -> "2.5", 125 -> "125"
Function UPG_Num$ (unV As Single)
    Dim unS As String
    unS = LTrim$(Str$(Int(unV * 100 + 0.5) / 100))
    UPG_Num$ = unS
End Function

' gamevalues.ini key suffix (upg_<key>) and telemetry item name for upgrade ukId
Function UPG_KeyOf$ (ukId As Integer)
    Select Case ukId
        Case UPG_LASER   : UPG_KeyOf$ = "laser"
        Case UPG_CANNON  : UPG_KeyOf$ = "cannon"
        Case UPG_RAPID   : UPG_KeyOf$ = "rapid"
        Case UPG_SHIELD  : UPG_KeyOf$ = "shield"
        Case UPG_REGEN   : UPG_KeyOf$ = "regen"
        Case UPG_ARMOUR  : UPG_KeyOf$ = "armour"
        Case UPG_NOVA    : UPG_KeyOf$ = "nova"
        Case UPG_THRUST  : UPG_KeyOf$ = "thrust"
        Case UPG_ROLL    : UPG_KeyOf$ = "roll"
        Case UPG_TRACTOR : UPG_KeyOf$ = "tractor"
        Case UPG_FUEL    : UPG_KeyOf$ = "fuel"
        Case UPG_REPAIR  : UPG_KeyOf$ = "repair"
        Case Else        : UPG_KeyOf$ = ""
    End Select
End Function

' --credits <n>: a whole number 0..999999999. 0 (and crpN untouched) if it isn't one.
Function CR_ParseArg% (crpS As String, crpN As Long)
    Dim crpI As Integer
    CR_ParseArg% = 0
    If Len(crpS) = 0 Or Len(crpS) > 9 Then Exit Function
    For crpI = 1 To Len(crpS)
        If Mid$(crpS, crpI, 1) < "0" Or Mid$(crpS, crpI, 1) > "9" Then Exit Function
    Next crpI
    crpN = Val(crpS)
    CR_ParseArg% = -1
End Function

Sub UPG_AddHint (uahText As String)
    If Len(uahText) = 0 Then Exit Sub
    If Len(upgHintPending) > 0 Then upgHintPending = upgHintPending + Chr$(10)
    upgHintPending = upgHintPending + uahText
End Sub
