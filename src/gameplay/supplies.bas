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
'   f = SUP_LegNeed!               fuel the next leg needs (SEQ_NextLeg); 0 when there is none
'   s = SUP_Stranded%              -1 when even all the fuel the credits buy won't reach it
' Local variable prefix: sup*

Const SUP_FUEL    = 1
Const SUP_SHIELD  = 2
Const SUP_OK      = 0
Const SUP_NOFUNDS = 1
Const SUP_FULL    = 2
Const SUP_MAX_CH  = 16

Dim Shared supFuelPrice As Single, supShieldPrice As Single, supStepPct As Single
Dim Shared supMult(1 To SUP_MAX_CH) As Single, supMultCnt As Integer
Dim Shared supPerKill As Single, supBoss As Single, supAsteroid As Single
Dim Shared supLoadErr As String

Function SUP_Load%
    Dim suplV(1 To SUP_MAX_CH) As String, suplI As Integer
    SUP_Load% = 0
    supLoadErr = ""
    supFuelPrice = Val(CFG_Get$(cfgEconomy, "fuel_price"))
    supShieldPrice = Val(CFG_Get$(cfgEconomy, "shield_price"))
    supStepPct = Val(CFG_Get$(cfgEconomy, "supply_step_pct"))
    supPerKill = Val(CFG_Get$(cfgEconomy, "fuel_per_kill"))
    supBoss = Val(CFG_Get$(cfgEconomy, "fuel_boss"))
    supAsteroid = Val(CFG_Get$(cfgEconomy, "fuel_asteroid"))
    UPG_Split CFG_Get$(cfgEconomy, "fuel_mult"), ",", suplV(), supMultCnt
    If supFuelPrice <= 0 Or supShieldPrice <= 0 Then supLoadErr = "config/economy.ini needs fuel_price and shield_price above 0" : Exit Function
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

Function SUP_LegNeed!
    Dim supnKills As Long, supnBossFuel As Single, supnBoss As Integer, supnAst As Integer, supnNeed As Single, supnCap As Single
    SEQ_NextLeg supnKills, supnBossFuel, supnBoss, supnAst
    supnNeed = supnKills * supPerKill + supnBossFuel + supnBoss * supBoss + supnAst * supAsteroid
    supnCap = upgFxA(UPG_FUEL, 0)
    If supnNeed > supnCap Then supnNeed = supnCap
    If settingNerf Then supnNeed = supnNeed * NERF_FACTOR
    SUP_LegNeed! = supnNeed
End Function

Function SUP_Stranded%
    Dim supsdNeed As Single, supsdCan As Integer
    SUP_Stranded% = 0
    If godMode Then Exit Function
    supsdNeed = SUP_LegNeed!
    If supsdNeed <= 0 Then Exit Function
    supsdCan = SUP_MaxAffordable%(SUP_FUEL, levelNum)
    If fuelLevel + supsdCan < supsdNeed Then SUP_Stranded% = -1
End Function
