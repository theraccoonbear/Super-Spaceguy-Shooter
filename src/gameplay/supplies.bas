' supplies.bas -- fuel and shields bought by the amount at the dock (#277)
'
' Prices and the next leg's fuel need come from assets/config/economy.ini (see the comments
' there). Fuel costs fuel_price x the dock's fuel_mult (the blockade surcharge, rising every
' chapter); shields cost a flat shield_price per point. No rendering or input here, so tests
' drive it directly:
'   ok = SUP_Load%                 read the prices (after CFG_Parse$ of economy.ini); 0 + supLoadErr
'   m = SUP_Mult!(chapter)         fuel surcharge at the dock after chapter (1 = no surcharge)
'   u = SUP_UnitPrice!(kind, ch)   credits per unit (SUP_FUEL / SUP_SHIELD)
'   c = SUP_Cost&(kind, n, ch)     credits for n units, rounded to the nearest credit
'   n = SUP_Missing%(kind)         units until full
'   n = SUP_MaxAffordable%(kind, ch)   most units the credits buy, at most the missing ones
'   n = SUP_Step%(kind)            LEFT / RIGHT step: supply_step_pct of the capacity
'   r = SUP_Buy%(kind, n, ch)      SUP_OK / SUP_NOFUNDS / SUP_FULL; buys at most what's missing
'   f = SUP_LegNeed!               fuel the next leg needs (SEQ_NextLeg; honest, may pass the tank)
'   f = SUP_LegReach!              ...of which the tank can hold: min(need, fuelMax)
'   o = SUP_OverTank%              -1 when the need is more than the tank holds (UPGRADE TANK)
'   s = SUP_Stranded%              -1 when even all the fuel the credits buy won't reach SUP_LegReach!
' Local variable prefix: sup*

Const SUP_FUEL    = 1
Const SUP_SHIELD  = 2
Const SUP_OK      = 0
Const SUP_NOFUNDS = 1
Const SUP_FULL    = 2
Const SUP_MAX_CH  = 16

Dim Shared supFuelPrice As Single, supShieldPrice As Single, supStepPct As Single
Dim Shared supMult(1 To SUP_MAX_CH) As Single, supMultCnt As Integer
Dim Shared supBurn As Single, supMargin As Single, supBossSecs As Single, supAstSecs As Single
Dim Shared supKillSecs(1 To SUP_MAX_CH) As Single, supKillSecsCnt As Integer
Dim Shared supBossHpMult As Single : supBossHpMult = 1
Dim Shared supLoadErr As String

Function SUP_Load%
    Dim suplV(1 To SUP_MAX_CH) As String, suplI As Integer
    SUP_Load% = 0
    supLoadErr = ""
    supFuelPrice = Val(CFG_Get$(cfgEconomy, "fuel_price"))
    supShieldPrice = Val(CFG_Get$(cfgEconomy, "shield_price"))
    supStepPct = Val(CFG_Get$(cfgEconomy, "supply_step_pct"))
    supBurn = Val(CFG_Get$(cfgEconomy, "fuel_burn"))
    supMargin = Val(CFG_Get$(cfgEconomy, "fuel_margin"))
    supBossSecs = Val(CFG_Get$(cfgEconomy, "fuel_boss_secs"))
    supAstSecs = Val(CFG_Get$(cfgEconomy, "fuel_asteroid_secs"))
    If supBurn <= 0 Or supMargin < 1 Then supLoadErr = "config/economy.ini needs fuel_burn above 0 and fuel_margin 1 or more" : Exit Function
    If supBossSecs <= 0 Or supAstSecs <= 0 Then supLoadErr = "config/economy.ini needs fuel_boss_secs and fuel_asteroid_secs above 0" : Exit Function
    supBurn = supBurn * DLV_M!("fuel_burn")
    supBossHpMult = DLV_M!("boss_hp")
    supBossSecs = supBossSecs * supBossHpMult
    UPG_Split CFG_Get$(cfgEconomy, "fuel_kill_secs"), ",", suplV(), supKillSecsCnt
    If supKillSecsCnt < 1 Then supLoadErr = "config/economy.ini has no fuel_kill_secs" : Exit Function
    For suplI = 1 To supKillSecsCnt
        supKillSecs(suplI) = Val(suplV(suplI))
        If supKillSecs(suplI) <= 0 Then supLoadErr = "config/economy.ini fuel_kill_secs: every value above 0" : Exit Function
        supKillSecs(suplI) = supKillSecs(suplI) * DLV_M!("wave_gap")
    Next suplI
    UPG_Split CFG_Get$(cfgEconomy, "fuel_mult"), ",", suplV(), supMultCnt
    If supFuelPrice <= 0 Or supShieldPrice <= 0 Then supLoadErr = "config/economy.ini needs fuel_price and shield_price above 0" : Exit Function
    supFuelPrice = supFuelPrice * DLV_M!("fuel_price")
    supShieldPrice = supShieldPrice * DLV_M!("shield_price")
    If supStepPct <= 0 Then supLoadErr = "config/economy.ini needs supply_step_pct above 0" : Exit Function
    If supMultCnt < 1 Then supLoadErr = "config/economy.ini has no fuel_mult" : Exit Function
    For suplI = 1 To supMultCnt
        supMult(suplI) = Val(suplV(suplI))
        If supMult(suplI) <= 0 Then supLoadErr = "config/economy.ini fuel_mult: every value above 0" : Exit Function
    Next suplI
    SUP_Load% = -1
End Function

Function SUP_Mult! (supmCh As Integer)
    Dim supmI As Integer
    supmI = supmCh
    If supmI < 1 Then supmI = 1
    If supmI > supMultCnt Then supmI = supMultCnt
    If supmI < 1 Then SUP_Mult! = 1 : Exit Function
    SUP_Mult! = supMult(supmI)
End Function

Function SUP_UnitPrice! (supuKind As Integer, supuCh As Integer)
    If supuKind = SUP_FUEL Then SUP_UnitPrice! = supFuelPrice * SUP_Mult!(supuCh) Else SUP_UnitPrice! = supShieldPrice
End Function

Function SUP_Cost& (supcKind As Integer, supcN As Integer, supcCh As Integer)
    If supcN <= 0 Then SUP_Cost& = 0 : Exit Function
    SUP_Cost& = Int(supcN * SUP_UnitPrice!(supcKind, supcCh) + 0.5)
End Function

' Rounded up, so a tank at 71.9 of 100 is 29 units short and buying them fills it.
Function SUP_Missing% (supmsKind As Integer)
    Dim supmsGap As Single
    If supmsKind = SUP_FUEL Then supmsGap = fuelMax - fuelLevel Else supmsGap = shieldMax - lives
    If supmsGap <= 0.001 Then SUP_Missing% = 0 : Exit Function
    SUP_Missing% = -Int(-(supmsGap - 0.001))
End Function

Function SUP_MaxAffordable% (supaKind As Integer, supaCh As Integer)
    Dim supaN As Long, supaMiss As Integer
    supaMiss = SUP_Missing%(supaKind)
    supaN = Int(credits / SUP_UnitPrice!(supaKind, supaCh))
    If supaN > supaMiss Then supaN = supaMiss
    If supaN < 0 Then supaN = 0
    ' rounding to whole credits can make one more or one fewer unit fit
    Do While supaN < supaMiss
        If SUP_Cost&(supaKind, supaN + 1, supaCh) > credits Then Exit Do
        supaN = supaN + 1
    Loop
    Do While supaN > 0
        If SUP_Cost&(supaKind, supaN, supaCh) <= credits Then Exit Do
        supaN = supaN - 1
    Loop
    SUP_MaxAffordable% = supaN
End Function

Function SUP_Step% (supsKind As Integer)
    Dim supsCap As Single, supsN As Integer
    If supsKind = SUP_FUEL Then supsCap = fuelMax Else supsCap = shieldMax
    supsN = Int(supsCap * supStepPct / 100 + 0.5)
    If supsN < 1 Then supsN = 1
    SUP_Step% = supsN
End Function

Function SUP_Buy% (supbKind As Integer, supbN As Integer, supbCh As Integer)
    Dim supbMiss As Integer, supbAmt As Integer, supbCost As Long
    supbMiss = SUP_Missing%(supbKind)
    If supbMiss = 0 Then SUP_Buy% = SUP_FULL : Exit Function
    supbAmt = supbN
    If supbAmt > supbMiss Then supbAmt = supbMiss
    If supbAmt < 1 Then SUP_Buy% = SUP_NOFUNDS : Exit Function
    supbCost = SUP_Cost&(supbKind, supbAmt, supbCh)
    If supbCost > credits Then SUP_Buy% = SUP_NOFUNDS : Exit Function
    credits = credits - supbCost
    creditsSpent = creditsSpent + supbCost
    If supbKind = SUP_FUEL Then
        fuelLevel = fuelLevel + supbAmt
        If fuelLevel > fuelMax Then fuelLevel = fuelMax
        fuelStranded = 0
        TELEM_FuelBought supbAmt, supbCost, SUP_UnitPrice!(SUP_FUEL, supbCh), SUP_Mult!(supbCh), supbCh
    Else
        lives = lives + supbAmt
        If lives > shieldMax Then lives = shieldMax
        TELEM_ShieldBought supbAmt, supbCost, supbCh
    End If
    SUP_Buy% = SUP_OK
End Function

' Seconds of play the leg after this dock (chapter levelNum + 1) is expected to take, x the
' play burn and margin: never capped at the tank (SUP_LegReach! is what the tank can take).
Function SUP_LegNeed!
    Dim supnKills As Long, supnBossSecs As Single, supnBoss As Integer, supnAst As Integer
    Dim supnSecs As Single, supnNeed As Single, supnCh As Integer
    SEQ_NextLeg supnKills, supnBossSecs, supnBoss, supnAst
    supnCh = levelNum + 1
    If supnCh < 1 Then supnCh = 1
    If supnCh > supKillSecsCnt Then supnCh = supKillSecsCnt
    supnSecs = supnKills * supKillSecs(supnCh) + supnBossSecs * supBossHpMult + supnBoss * supBossSecs + supnAst * supAstSecs
    supnNeed = supnSecs * supBurn * supMargin
    If settingNerf Then supnNeed = supnNeed * NERF_FACTOR
    SUP_LegNeed! = supnNeed
End Function

' The part of the next leg's need the tank can hold: min(need, fuelMax).
Function SUP_LegReach!
    Dim suprNeed As Single
    suprNeed = SUP_LegNeed!
    If suprNeed > fuelMax Then suprNeed = fuelMax
    SUP_LegReach! = suprNeed
End Function

' -1 when the next leg needs more than the tank holds (the dock says UPGRADE TANK).
Function SUP_OverTank%
    SUP_OverTank% = (SUP_LegNeed! > fuelMax)
End Function

' Stranded only when the credits can't even fill to what the tank can take of the leg: a leg
' longer than the tank is flown dry at the end, not refused at the dock.
Function SUP_Stranded%
    Dim supsdNeed As Single, supsdCan As Integer
    SUP_Stranded% = 0
    If godMode Then Exit Function
    supsdNeed = SUP_LegReach!
    If supsdNeed <= 0 Then Exit Function
    supsdCan = SUP_MaxAffordable%(SUP_FUEL, levelNum)
    If fuelLevel + supsdCan < supsdNeed Then SUP_Stranded% = -1
End Function
