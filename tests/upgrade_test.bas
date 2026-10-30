' upgrade_test.bas -- credits and the upgrade table (src/gameplay/upgrades.bas, #268)
'
' Drives the real module against the real assets/config/*.ini (read through the shared
' CFG_Parse$ in src/sys/config.bas): parsing the upgrade
' table and credit amounts (and rejecting a malformed line), the economy target, earning,
' buying (affordable, too expensive, maxed), each upgrade's effect values, fuel and shields
' bought by the amount (src/gameplay/supplies.bas: prices, the rising fuel surcharge, partial
' and fill-what-you-can-afford buys, the next jump's fuel need, stranded), nova charges refilled at every dock, the roll's immunity window and
' cooldown, shield regen after the no-hit delay, hull armour, and the new-game reset.
'
' Build: ./tools/buildqb tests/upgrade_test.bas
' Run:   builds/upgrade_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'
$EMBED:'assets/config/economy.ini':'CFGECONOMY'
$EMBED:'assets/config/upgrades.ini':'CFGUPGRADES'
$EMBED:'assets/config/abilities.ini':'CFGABILITIES'

Sub DBG_Print (upgtDbg As String) : End Sub

' TELEM_UpgradeBought records instead of writing telemetry
Dim Shared utItem As String, utLevel As Integer, utPrice As Long, utBuys As Integer
Sub TELEM_UpgradeBought (tuItem As String, tuLevel As Integer, tuPrice As Long)
    utItem = tuItem : utLevel = tuLevel : utPrice = tuPrice : utBuys = utBuys + 1
End Sub
Dim Shared utBonusLogs As Integer
Sub TELEM_CreditBonus (tcbC As Long, tcbR As Double, tcbP As Long)
    utBonusLogs = utBonusLogs + 1
End Sub
Dim Shared utFuelBuys As Integer, utFuelAmt As Integer, utFuelPrice As Long, utFuelUnit As Single, utFuelMult As Single, utFuelCh As Integer
Sub TELEM_FuelBought (tfbA As Integer, tfbP As Long, tfbU As Single, tfbM As Single, tfbC As Integer)
    utFuelBuys = utFuelBuys + 1 : utFuelAmt = tfbA : utFuelPrice = tfbP : utFuelUnit = tfbU : utFuelMult = tfbM : utFuelCh = tfbC
End Sub
Dim Shared utShieldBuys As Integer, utShieldAmt As Integer, utShieldPrice As Long, utShieldCh As Integer
Sub TELEM_ShieldBought (tsbA As Integer, tsbP As Long, tsbC As Integer)
    utShieldBuys = utShieldBuys + 1 : utShieldAmt = tsbA : utShieldPrice = tsbP : utShieldCh = tsbC
End Sub
' SEQ_NextLeg (sequence.bas) reports this stub leg
Dim Shared utLegKills As Long, utLegBossFuel As Single, utLegBoss As Integer, utLegAst As Integer
Sub SEQ_NextLeg (snlK As Long, snlBF As Single, snlB As Integer, snlA As Integer)
    snlK = utLegKills : snlBF = utLegBossFuel : snlB = utLegBoss : snlA = utLegAst
End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/credits.bas'
'$INCLUDE:'../src/gameplay/upgrades.bas'
'$INCLUDE:'../src/gameplay/supplies.bas'
'$INCLUDE:'../src/2d/prompttext.bas'

Dim Shared utPassed As Integer, utFailed As Integer

Sub UT_Assert (utaCond As Integer, utaName As String)
    If utaCond Then
        Print "PASS  " + utaName
        utPassed = utPassed + 1
    Else
        Print "FAIL  " + utaName
        utFailed = utFailed + 1
    End If
End Sub

Function UT_Near% (utnA As Single, utnB As Single)
    UT_Near% = (Abs(utnA - utnB) < 0.0001)
End Function

Dim utOk As Integer, utR As Integer, utI As Integer, utJ As Integer
Dim utTotal As Long, utEarn As Long, utCr As Long

Print "=== upgrade_test ==="
Print ""

Print "--- config files: the upgrade table, economy and abilities ---"
cfgEconomy = CFG_Parse$(_EMBEDDED$("CFGECONOMY"))
cfgUpgrades = CFG_Parse$(_EMBEDDED$("CFGUPGRADES"))
cfgAbilities = CFG_Parse$(_EMBEDDED$("CFGABILITIES"))
utOk = UPG_Load%
UT_Assert utOk <> 0, "UPG_Load% reads every upg_ line (" + upgLoadErr + ")"
UT_Assert upgMax(UPG_LASER) = 3 And upgMax(UPG_CANNON) = 2 And upgMax(UPG_NOVA) = 3, "levels: laser 3, cannon 2, nova 3"
UT_Assert upgPrice(UPG_LASER, 1) = 80 And upgPrice(UPG_LASER, 2) = 150 And upgPrice(UPG_LASER, 3) = 250, "laser prices 80, 150, 250"
UT_Assert UT_Near%(upgFxA(UPG_LASER, 0), 100) And UT_Near%(upgFxA(UPG_LASER, 3), 180), "laser max 100 at level 0, 180 at level 3"
UT_Assert UT_Near%(upgFxB(UPG_LASER, 0), 0.3) And UT_Near%(upgFxB(UPG_LASER, 3), 0.5), "laser regen 0.30 at level 0, 0.50 at level 3"
UT_Assert UT_Near%(upgFxA(UPG_RAPID, 0), 0.18), "rapid fire level 0 is today's 0.18 s cooldown"
UT_Assert UT_Near%(upgFxA(UPG_THRUST, 0), 0.12), "thrusters level 0 is today's 0.12 max speed"
UT_Assert crKill = 25 And crBoss = 600 And crStage = 200, "credit amounts: kill 25, boss 600, stage 200"
UT_Assert crAstNear = 20 And crAstKill = 20 And crAstSurvive = 400, "asteroid credits: near miss 20, nova kill 20, survive 400"
UT_Assert UT_Near%(novaRadius, 24) And novaBossDmg = 3, "nova radius 24, boss damage 3"
UT_Assert rollFrames = 20 And UT_Near%(rollSpeed, 0.32), "roll lasts 20 frames at 0.32 per frame"
For utI = 1 To UPG_COUNT
    If Len(UPG_KeyOf$(utI)) = 0 Or Len(upgNames$(utI)) = 0 Then utOk = 0
Next utI
UT_Assert utOk <> 0, "all 11 upgrades have a key and a name"

' economy: every level of everything is 90-100% of what stages 1-5 pay
utTotal = 0
For utI = 1 To UPG_COUNT
    For utJ = 1 To upgMax(utI) : utTotal = utTotal + upgPrice(utI, utJ) : Next utJ
Next utI
utEarn = 50 * crKill + 2 * crBoss + 5 * crStage + 15 * crAstNear + crAstSurvive
UT_Assert utTotal = 3960, "all upgrades cost 3960 (" + LTrim$(Str$(utTotal)) + ")"
UT_Assert utTotal * 100 >= utEarn * 90 And utTotal <= utEarn, "total cost is 90-100% of a strong run's spendable credits (" + LTrim$(Str$(utEarn)) + ")"

Print ""
Print "--- the shared parser ---"
Dim utStore As String
utStore = CFG_Parse$("; comment" + Chr$(13) + Chr$(10) + "  a=1  " + Chr$(10) + Chr$(10) + "b=x|y,z" + Chr$(13) + Chr$(10) + "=nokey" + Chr$(10) + "c=")
UT_Assert CFG_Get$(utStore, "a") = "1" And CFG_Get$(utStore, "b") = "x|y,z", "key=value lines, CRLF, comments and blank lines"
UT_Assert CFG_Get$(utStore, "missing") = "" And CFG_Count%(utStore) = 3, "a missing key is empty; =nokey is skipped"
utStore = CFG_Parse$(_EMBEDDED$("GAMEVALUES"))
UT_Assert CFG_Get$(utStore, "emperor") <> "" And CFG_Get$(utStore, "upg_laser") = "" And CFG_Get$(utStore, "cr_kill") = "", "gamevalues.ini keeps only text tokens: no upgrade or credit keys"
UT_Assert CFG_Get$(cfgUpgrades, "cr_kill") = "" And CFG_Get$(cfgEconomy, "upg_laser") = "", "each config file holds its own keys"

Print ""
Print "--- a malformed line is rejected ---"
utOk = UPG_ParseLine%(UPG_RAPID, "rapid", "RAPID FIRE|100,200|0.18,0.14")
UT_Assert utOk = 0 And InStr(upgLoadErr, "rapid") > 0, "effect list one short: rejected, error names it"
utOk = UPG_ParseLine%(UPG_RAPID, "rapid", "RAPID FIRE")
UT_Assert utOk = 0, "no prices: rejected"
Dim utAbSave As String
utAbSave = cfgAbilities
cfgAbilities = CFG_Parse$("nova_charges=0,1" + Chr$(10) + "roll_cooldown=0,150,90")
utOk = UPG_Load%
UT_Assert utOk = 0 And InStr(upgLoadErr, "abilities.ini nova_charges") > 0, "nova_charges with too few levels: rejected, error names abilities.ini (" + upgLoadErr + ")"
cfgAbilities = utAbSave
utOk = UPG_Load%   ' put the real table back

Print ""
Print "--- new run ---"
credits = 999 : upgLevel(UPG_LASER) = 2
UPG_Reset
UT_Assert credits = 0 And creditsEarned = 0 And creditsSpent = 0, "credits reset"
UT_Assert upgLevel(UPG_LASER) = 0, "levels reset"
UT_Assert UT_Near%(laserMax, 100) And UT_Near%(laserRegen, 0.3) And UT_Near%(fireCool, 0.18), "laser 100 / regen 0.30 / cooldown 0.18"
UT_Assert UT_Near%(shipMaxVel, 0.12) And shieldMax = 100 And UT_Near%(fuelMax, 100) And gunShots = 1, "speed 0.12, shield 100, fuel 100, one shot"
UT_Assert rollCoolMax = 0 And novaMax = 0 And regenEvery = 0 And UT_Near%(armourMul, 1) And tractorR = 0, "no roll, nova, regen, armour or tractor"

Print ""
Print "--- earning ---"
CR_Add crKill
UT_Assert credits = 25 And creditsEarned = 25, "a kill earns 25"
CR_StageClear
UT_Assert credits = 225 And creditsEarned = 225, "a stage clear earns 200"
CR_Add crBoss
UT_Assert credits = 825, "a boss earns 600"

Print ""
Print "--- dock info lines: what it does, what the next level changes ---"
UPG_Reset
UT_Assert UPG_Info$(UPG_LASER) = "BIGGER, FASTER LASER BANK", "laser info comes from upgdesc_laser"
UT_Assert UPG_Next$(UPG_LASER) = "BANK 100 > 125 REGEN +20%", "laser next: BANK 100 > 125 REGEN +20% (" + UPG_Next$(UPG_LASER) + ")"
UT_Assert UPG_Next$(UPG_CANNON) = "NEXT: 2 PARALLEL SHOTS", "cannon next: 2 parallel shots"
UT_Assert UPG_Next$(UPG_RAPID) = "SHOT DELAY .18>.14S", "rapid next: SHOT DELAY .18>.14S (" + UPG_Next$(UPG_RAPID) + ")"
UT_Assert UPG_Next$(UPG_NOVA) = "CHARGES/STAGE 0>1" And Left$(UPG_Info$(UPG_NOVA), 5) = UI_Tok$("", E3D_ACT_NOVA) + ":", "nova: charges 0>1, and its info opens with the nova key token"
UT_Assert UPG_Next$(UPG_ROLL) = "UNLOCKS THE ROLL" And Left$(UPG_Info$(UPG_ROLL), 5) = UI_Tok$("", E3D_ACT_ROLL) + ":", "roll: unlocks, and its info opens with the roll key token"
E3D_KeyDefaults
UT_Assert UI_PromptsKeyText$(UPG_Info$(UPG_NOVA)) = "Q: CLEAR SHOTS+BLAST" And UI_PromptsKeyText$(UPG_Info$(UPG_ROLL)) = "E: UNTOUCHABLE DASH", "default keys: Q: CLEAR SHOTS+BLAST / E: UNTOUCHABLE DASH"
keyBind(E3D_ACT_NOVA) = Asc("k") : keyBind(E3D_ACT_ROLL) = E3D_KEY_SPACE
UT_Assert UI_PromptsKeyText$(UPG_Info$(UPG_NOVA)) = "K: CLEAR SHOTS+BLAST" And UI_PromptsKeyText$(UPG_Info$(UPG_ROLL)) = "SPACE: UNTOUCHABLE DASH", "remapped nova to K, roll to SPACE: the info lines follow (" + UI_PromptsKeyText$(UPG_Info$(UPG_ROLL)) + ")"
UT_Assert UI_PromptsKeyText$(CFG_Get$(cfgAbilities, "hint_nova")) = "NOVA READY - K" And UI_PromptsKeyText$(CFG_Get$(cfgAbilities, "hint_roll")) = "ROLL READY - SPACE", "remapped: the launch hints name the new keys"
E3D_KeyDefaults
UT_Assert UI_PromptsKeyText$(CFG_Get$(cfgAbilities, "hint_nova")) = "NOVA READY - Q" And UI_PromptsKeyText$(CFG_Get$(cfgAbilities, "hint_roll")) = "ROLL READY - E", "default keys: NOVA READY - Q / ROLL READY - E"
UT_Assert UPG_Next$(UPG_ARMOUR) = "CRASH DAMAGE 100>75%", "armour next: CRASH DAMAGE 100>75% (" + UPG_Next$(UPG_ARMOUR) + ")"
credits = 10000
utR = UPG_Buy%(UPG_CANNON)
UT_Assert UPG_Next$(UPG_CANNON) = "NEXT: 3-WAY SPREAD", "after twin: next is the 3-way spread"
utR = UPG_Buy%(UPG_CANNON)
UT_Assert UPG_Next$(UPG_CANNON) = "MAXED", "after spread: MAXED"

Print ""
Print "--- launch hint for a newly bought ability ---"
UPG_Reset : credits = 10000
utR = UPG_Buy%(UPG_NOVA)
UT_Assert upgHintPending = CFG_Get$(cfgAbilities, "hint_nova"), "first nova queues NOVA READY - {|4}"
utR = UPG_Buy%(UPG_NOVA)
UT_Assert upgHintPending = CFG_Get$(cfgAbilities, "hint_nova"), "nova level 2 adds no second hint"
utR = UPG_Buy%(UPG_ROLL)
UT_Assert upgHintPending = CFG_Get$(cfgAbilities, "hint_nova") + Chr$(10) + CFG_Get$(cfgAbilities, "hint_roll"), "first roll adds its own line"
utR = UPG_Buy%(UPG_THRUST)
UT_Assert InStr(upgHintPending, "THRUST") = 0, "passive upgrades give no hint"
UPG_Reset
UT_Assert upgHintPending = "", "a new run clears pending hints"

Print ""
Print "--- buying ---"
UPG_Reset : credits = 100 : utBuys = 0
utR = UPG_Buy%(UPG_LASER)
UT_Assert utR = UPG_OK And credits = 20 And creditsSpent = 80 And upgLevel(UPG_LASER) = 1, "laser capacitor 1 for 80: 20 left"
UT_Assert UT_Near%(laserMax, 125) And UT_Near%(laserRegen, 0.36) And UT_Near%(laserEnergy, 125), "laser max 125, regen 0.36, bank filled"
UT_Assert utBuys = 1 And utItem = "laser" And utLevel = 1 And utPrice = 80, "telemetry: upgrade_bought laser, level 1, 80"
utR = UPG_Buy%(UPG_LASER)
UT_Assert utR = UPG_NOFUNDS And credits = 20 And upgLevel(UPG_LASER) = 1 And utBuys = 1, "level 2 costs 150: refused, nothing changes"
credits = 10000
utR = UPG_Buy%(UPG_RAPID) : utR = UPG_Buy%(UPG_RAPID)
UT_Assert UT_Near%(fireCool, 0.1), "rapid fire 2: 0.10 s between shots"
utCr = credits
utR = UPG_Buy%(UPG_RAPID)
UT_Assert utR = UPG_MAXED And credits = utCr, "rapid fire past max: refused, no charge"
UT_Assert UPG_Price&(UPG_RAPID) = 0 And UPG_Next$(UPG_RAPID) = "MAXED", "maxed: no price, info line says MAXED"

Print ""
Print "--- effects ---"
UT_Assert UPG_Name$(UPG_CANNON) = "TWIN CANNONS", "cannon row starts as TWIN CANNONS"
utR = UPG_Buy%(UPG_CANNON)
UT_Assert gunShots = 2 And UT_Near%(gunSpread, 0), "twin cannons: 2 parallel shots"
UT_Assert UPG_Name$(UPG_CANNON) = "SPREAD SHOT", "next level is SPREAD SHOT"
utR = UPG_Buy%(UPG_CANNON)
UT_Assert gunShots = 3 And UT_Near%(gunSpread, 0.08), "spread shot: 3 shots, spread 0.08"
utR = UPG_Buy%(UPG_THRUST)
UT_Assert UT_Near%(shipMaxVel, 0.15), "thrusters 1: max sideways speed 0.15"
utR = UPG_Buy%(UPG_THRUST)
UT_Assert UT_Near%(shipMaxVel, 0.18), "thrusters 2: 0.18"
utR = UPG_Buy%(UPG_SHIELD)
UT_Assert shieldMax = 125, "shield capacity 1: 125"
fuelLevel = 60
utR = UPG_Buy%(UPG_FUEL)
UT_Assert UT_Near%(fuelMax, 130) And UT_Near%(fuelLevel, 60), "fuel tank 1: 130; the new capacity arrives empty (fuel still 60)"
utR = UPG_Buy%(UPG_TRACTOR)
UT_Assert UT_Near%(tractorR, 10) And UT_Near%(tractorPull, 0.05), "tractor beam 1: range 10, pull 0.05"
UT_Assert UT_ArmourCheck% = -1, "hull armour: 100 -> 75 -> 50, 17 -> 13 at 75%"
utOk = -1
keyBind(E3D_ACT_NOVA) = E3D_KEY_SPACE : keyBind(E3D_ACT_ROLL) = E3D_KEY_SPACE
For utI = 1 To UPG_COUNT
    If Len(UPG_Next$(utI)) = 0 Or Len(UPG_Next$(utI)) > 25 Then utOk = 0 : Print "  next: "; UPG_Next$(utI)
    If Len(UPG_Info$(utI)) = 0 Or Len(UI_PromptsKeyText$(UPG_Info$(utI))) > 25 Then utOk = 0 : Print "  info: "; UI_PromptsKeyText$(UPG_Info$(utI))
Next utI
E3D_KeyDefaults
UT_Assert utOk <> 0, "every row has an info line and a next-level line that fit the dock panel (25 chars, info with keys bound to SPACE)"

Print ""
Print "--- capacity bars: length follows capacity, absolute values (#268) ---"
UT_Assert UPG_BarLen%(100) = 28, "base capacity 100 draws today's 28px bar"
UT_Assert UPG_BarLen%(125) = 35 And UPG_BarLen%(150) = 42 And UPG_BarLen%(180) = 50, "shield/laser levels: 125 -> 35, 150 -> 42, 180 -> 50"
UT_Assert UPG_BarLen%(130) = 36 And UPG_BarLen%(160) = 45, "fuel tank levels: 130 -> 36, 160 -> 45"
UT_Assert UPG_BarLen%(1000) = UPG_BAR_MAX And UPG_BarLen%(0) = 1, "clamped to 1.." + LTrim$(Str$(UPG_BAR_MAX))
utOk = -1
For utI = 1 To UPG_COUNT
    If utI = UPG_LASER Or utI = UPG_SHIELD Or utI = UPG_FUEL Then
        If UPG_BarLen%(upgFxA(utI, 0)) <> UPG_BAR_BASE Then utOk = 0
        For utR = 1 To upgMax(utI)
            If UPG_BarLen%(upgFxA(utI, utR)) >= UPG_BAR_MAX Or UPG_BarLen%(upgFxA(utI, utR)) <= UPG_BarLen%(upgFxA(utI, utR - 1)) Then utOk = 0
        Next utR
    End If
Next utI
UT_Assert utOk <> 0, "every capacity level in upgrades.ini draws a longer bar, under the HUD's reserved max"
UT_Assert UPG_BarFill%(72, 125) = 20 And UPG_BarFill%(125, 125) = 35 And UPG_BarFill%(0, 125) = 0, "fill: 72/125 -> 20 of 35, full -> 35, empty -> 0"
UT_Assert UPG_BarFill%(-5, 100) = 0 And UPG_BarFill%(300, 100) = 28, "fill clamped to the bar"
UT_Assert UPG_StatusStr$("SH", 72, 125) = "SH 72/125", "status: SH 72/125 (" + UPG_StatusStr$("SH", 72, 125) + ")"
UT_Assert UPG_StatusStr$("FU", 71.9, 130) = "FU 71/130" And UPG_StatusStr$("LA", -1, 100) = "LA 0/100", "status: fuel rounds down, never negative"
Dim utSvFuel As Integer, utSvShield As Integer, utSvLaser As Integer
utSvFuel = upgLevel(UPG_FUEL) : utSvShield = upgLevel(UPG_SHIELD) : utSvLaser = upgLevel(UPG_LASER)
upgLevel(UPG_FUEL) = 1 : upgLevel(UPG_SHIELD) = 0 : upgLevel(UPG_LASER) = 0
UT_Assert UT_Near%(UPG_CapNext!(UPG_FUEL), 160) And UPG_Next$(UPG_FUEL) = "TANK 130 > 160", "fuel tank 1: next is TANK 130 > 160, ghost to 160 (" + UPG_Next$(UPG_FUEL) + ")"
UT_Assert UPG_Next$(UPG_SHIELD) = "SHIELD 100 > 125" And UT_Near%(UPG_CapNext!(UPG_SHIELD), 125), "shield: SHIELD 100 > 125, ghost to 125"
UT_Assert UT_Near%(UPG_CapNext!(UPG_LASER), 125), "laser: ghost to 125"
upgLevel(UPG_FUEL) = upgMax(UPG_FUEL)
UT_Assert UPG_CapNext!(UPG_FUEL) = 0 And UPG_CapNext!(UPG_THRUST) = 0, "no ghost once maxed, nor for a non-capacity upgrade"
upgLevel(UPG_FUEL) = utSvFuel : upgLevel(UPG_SHIELD) = utSvShield : upgLevel(UPG_LASER) = utSvLaser

Print ""
Print "--- bullet pool covers the fastest, widest fire upgrades.ini allows (#268) ---"
UT_Assert UPG_PeakBullets% > 0, "worst case from the table: fastest rapid fire x widest volley x bullet life =" + Str$(UPG_PeakBullets%) + " live bullets"
UT_Assert MAX_BULLETS >= UPG_PeakBullets%, "MAX_BULLETS (" + LTrim$(Str$(MAX_BULLETS)) + ") >= that worst case, so the gun never stalls"

Print ""
Print "--- supplies: fuel and shields by the amount (#277) ---"
utOk = SUP_Load%
UT_Assert utOk <> 0, "SUP_Load% reads economy.ini (" + supLoadErr + ")"
UT_Assert UT_Near%(supFuelPrice, 2) And UT_Near%(supShieldPrice, 1) And UT_Near%(supStepPct, 10), "fuel $2 a unit, shields $1 a point, steps of 10%"
UT_Assert UT_Near%(SUP_Mult!(1), 1) And UT_Near%(SUP_Mult!(2), 1.4) And UT_Near%(SUP_Mult!(3), 1.8) And UT_Near%(SUP_Mult!(4), 2.2) And UT_Near%(SUP_Mult!(5), 2.6), "fuel surcharge per dock: 1.0, 1.4, 1.8, 2.2, 2.6"
utOk = -1
For utI = 2 To supMultCnt
    If SUP_Mult!(utI) <= SUP_Mult!(utI - 1) Then utOk = 0
Next utI
UT_Assert utOk <> 0, "the blockade only tightens: every dock's fuel price is above the last"
UT_Assert UT_Near%(SUP_Mult!(9), SUP_Mult!(supMultCnt)) And UT_Near%(SUP_Mult!(0), SUP_Mult!(1)), "past the list: its last value; before it: the first"
UT_Assert UT_Near%(SUP_UnitPrice!(SUP_FUEL, 2), 2.8) And UT_Near%(SUP_UnitPrice!(SUP_SHIELD, 5), 1), "dock 2 fuel $2.80 a unit; shields flat $1 at any dock"
UT_Assert SUP_Cost&(SUP_FUEL, 40, 2) = 112 And SUP_Cost&(SUP_FUEL, 40, 1) = 80 And SUP_Cost&(SUP_FUEL, 40, 5) = 208, "40 fuel: $80 at dock 1, $112 at dock 2, $208 at dock 5"
UT_Assert SUP_Cost&(SUP_SHIELD, 35, 3) = 35 And SUP_Cost&(SUP_FUEL, 0, 2) = 0, "35 shield points $35; nothing costs nothing"
UPG_Reset
fuelLevel = 71.9
UT_Assert SUP_Missing%(SUP_FUEL) = 29, "a tank at 71.9 of 100 is 29 units short (" + LTrim$(Str$(SUP_Missing%(SUP_FUEL))) + ")"
UT_Assert SUP_Step%(SUP_FUEL) = 10 And SUP_Step%(SUP_SHIELD) = 10, "LEFT / RIGHT step: 10% of a 100 tank or shield"
credits = 1000
UT_Assert SUP_MaxAffordable%(SUP_FUEL, 2) = 29, "plenty of credits: fill what's missing, no more"
credits = 50 : fuelLevel = 0
UT_Assert SUP_MaxAffordable%(SUP_FUEL, 2) = 18, "$50 at $2.80: 18 units ($50.40 rounds to $50) (" + LTrim$(Str$(SUP_MaxAffordable%(SUP_FUEL, 2))) + ")"
credits = 2
UT_Assert SUP_MaxAffordable%(SUP_FUEL, 2) = 0, "$2 buys no $2.80 unit"

credits = 500 : creditsSpent = 0 : fuelLevel = 40 : utFuelBuys = 0 : fuelStranded = -1
utR = SUP_Buy%(SUP_FUEL, 30, 2)
UT_Assert utR = SUP_OK And UT_Near%(fuelLevel, 70) And credits = 416 And creditsSpent = 84, "partial: 30 fuel at dock 2 for $84, tank 40 -> 70"
UT_Assert fuelStranded = 0, "fuel in the tank: no longer drifting"
UT_Assert utFuelBuys = 1 And utFuelAmt = 30 And utFuelPrice = 84 And UT_Near%(utFuelUnit, 2.8) And UT_Near%(utFuelMult, 1.4) And utFuelCh = 2, "telemetry: fuel_bought 30, $84, $2.80/u, x1.4, chapter 2"
utR = SUP_Buy%(SUP_FUEL, 50, 2)
UT_Assert utR = SUP_OK And UT_Near%(fuelLevel, 100) And credits = 332, "asking for more than's missing buys only the 30 missing"
utR = SUP_Buy%(SUP_FUEL, 10, 2)
UT_Assert utR = SUP_FULL And credits = 332 And utFuelBuys = 2, "a full tank: refused, no charge, nothing logged"
fuelLevel = 0 : credits = 10
utR = SUP_Buy%(SUP_FUEL, 50, 2)
UT_Assert utR = SUP_NOFUNDS And credits = 10 And UT_Near%(fuelLevel, 0), "50 fuel for $140 with $10: refused, nothing changes"
utR = SUP_Buy%(SUP_FUEL, 0, 2)
UT_Assert utR = SUP_NOFUNDS And credits = 10, "an amount of 0 buys nothing"
credits = 50
utR = SUP_Buy%(SUP_FUEL, SUP_MaxAffordable%(SUP_FUEL, 2), 2)
UT_Assert utR = SUP_OK And UT_Near%(fuelLevel, 18) And credits = 0, "fill what you can afford: 18 units, $50 spent, $0 left"
lives = 40 : credits = 30 : utShieldBuys = 0
UT_Assert SUP_Missing%(SUP_SHIELD) = 60 And SUP_MaxAffordable%(SUP_SHIELD, 4) = 30, "shields 40/100 with $30: 30 points affordable"
utR = SUP_Buy%(SUP_SHIELD, 30, 4)
UT_Assert utR = SUP_OK And lives = 70 And credits = 0, "30 shield points for $30: 40 -> 70"
UT_Assert utShieldBuys = 1 And utShieldAmt = 30 And utShieldPrice = 30 And utShieldCh = 4, "telemetry: shield_bought 30, $30, chapter 4"
lives = shieldMax
UT_Assert SUP_Buy%(SUP_SHIELD, 5, 4) = SUP_FULL, "full shields: refused"

Print ""
Print "--- the next jump's fuel need, and stranded (#277) ---"
UPG_Reset : settingNerf = 0 : godMode = 0
utLegKills = 10 : utLegBoss = 1 : utLegAst = 0
UT_Assert UT_Near%(SUP_LegNeed!, 55), "10-kill combat + a boss: 10 x 3 + 25 = 55"
utLegKills = 12 : utLegBoss = 0 : utLegBossFuel = 30 : utLegAst = 0
UT_Assert UT_Near%(SUP_LegNeed!, 66), "chapter 3: 12 x 3 + boss 1's fuel=30 = 66"
utLegKills = 18 : utLegBossFuel = 35
UT_Assert UT_Near%(SUP_LegNeed!, 89), "chapter 5: 18 x 3 + boss 2's fuel=35 = 89"
utLegKills = 20 : utLegBossFuel = 40
UT_Assert UT_Near%(SUP_LegNeed!, 100), "the last leg (chapter 6): 20 x 3 + boss 3's fuel=40 = 100, the base tank"
utLegBossFuel = 0
utLegKills = 24 : utLegBoss = 1 : utLegAst = 0
UT_Assert UT_Near%(SUP_LegNeed!, 97), "a boss with no fuel= uses fuel_boss: 24 x 3 + 25 = 97"
utLegKills = 0 : utLegBoss = 0 : utLegAst = 1
UT_Assert UT_Near%(SUP_LegNeed!, 90), "the asteroid field: 90 (it burns ~89)"
utLegKills = 40 : utLegBoss = 1
credits = 10000 : utR = UPG_Buy%(UPG_FUEL) : utR = UPG_Buy%(UPG_FUEL)
UT_Assert UT_Near%(SUP_LegNeed!, 100), "a long leg is capped at the base tank (100), even with a bigger tank"
UPG_Reset
utLegKills = 10 : utLegBoss = 1 : utLegAst = 0 : settingNerf = -1
UT_Assert UT_Near%(SUP_LegNeed!, 5.5), "--nerf: 55 x 0.1"
settingNerf = 0
utLegKills = 0 : utLegBoss = 0 : utLegAst = 0
UT_Assert UT_Near%(SUP_LegNeed!, 0), "no leg ahead: needs nothing"
fuelLevel = 0 : credits = 0
UT_Assert SUP_Stranded% = 0, "the last dock (no leg ahead) never strands"
utLegKills = 10 : utLegBoss = 1 : levelNum = 2
fuelLevel = 30 : credits = 70
UT_Assert SUP_Stranded% = 0, "30 in the tank + $70 = 25 units at $2.80: exactly 55, not stranded"
credits = 69
UT_Assert SUP_Stranded% <> 0, "$69 buys 24: 54 < 55, stranded"
godMode = -1
UT_Assert SUP_Stranded% = 0, "god mode is never stranded"
godMode = 0
fuelLevel = 55 : credits = 0
UT_Assert SUP_Stranded% = 0, "enough in the tank already, broke: not stranded"
fuelLevel = 100 : credits = 10000

Print ""
Print "--- nova pulse charges ---"
utOk = UPG_NovaTry%
UT_Assert utOk = 0, "no nova before buying it"
utR = UPG_Buy%(UPG_NOVA)
UT_Assert novaMax = 1 And novaCharges = 1, "nova 1: one charge, ready at once"
utOk = UPG_NovaTry%
UT_Assert utOk <> 0 And novaCharges = 0, "firing spends it"
utOk = UPG_NovaTry%
UT_Assert utOk = 0, "no charges left: nothing"
UPG_DockVisit
UT_Assert novaCharges = 1, "the dock refills the charge"
utR = UPG_Buy%(UPG_NOVA)
UT_Assert novaMax = 2 And novaCharges = 2, "nova 2: two charges"
utOk = UPG_NovaTry%
UPG_DockVisit
UT_Assert novaCharges = 2, "a dock refills to the full count"

Print ""
Print "--- evasive roll ---"
utOk = UPG_RollTry%(1)
UT_Assert utOk = 0 And rollTimer = 0, "locked until bought"
utR = UPG_Buy%(UPG_ROLL)
UT_Assert rollCoolMax = 150, "roll 1: 150-frame cooldown"
utOk = UPG_RollTry%(-1)
UT_Assert utOk <> 0 And rollTimer = 20 And rollDir = -1 And rollCool = 150, "roll left: 20 untouchable frames, cooldown starts"
utOk = UPG_RollTry%(1)
UT_Assert utOk = 0 And rollDir = -1, "can't roll again mid-roll"
utJ = 0
For utI = 1 To 200
    If rollTimer > 0 Then utJ = utJ + 1
    UPG_RollTick
Next utI
UT_Assert utJ = 20, "immune for exactly roll_frames (20) frames"
UPG_Reset : credits = 10000
utR = UPG_Buy%(UPG_ROLL)
utOk = UPG_RollTry%(1)
For utI = 1 To 149 : UPG_RollTick : Next utI
utOk = UPG_RollTry%(1)
UT_Assert utOk = 0 And rollCool = 1, "still cooling down 1 frame early"
UPG_RollTick
utOk = UPG_RollTry%(0)
UT_Assert utOk <> 0 And rollDir = 1, "ready after 150 frames (no direction: rolls right)"
utR = UPG_Buy%(UPG_ROLL)
UT_Assert rollCoolMax = 90, "roll 2: 90-frame cooldown"

Print ""
Print "--- shield regen ---"
UPG_Reset : credits = 10000
utR = UPG_Buy%(UPG_REGEN)
UT_Assert regenEvery = 20 And regenDelay = 180, "regen 1: a point every 20 frames after 180 unhit"
lives = 90 : noHitFrames = 0 : regenTick = 0
For utI = 1 To 198 : UPG_RegenTick : Next utI
UT_Assert lives = 90, "nothing during the no-hit delay"
UPG_RegenTick
UT_Assert lives = 91, "first point 20 frames after the delay"
lives = 99
For utI = 1 To 100 : UPG_RegenTick : Next utI
UT_Assert lives = 100, "stops at the shield max"

Print ""
Print "--- --credits <n> ---"
Dim utArg As Long
utArg = 7
utOk = CR_ParseArg%("2500", utArg)
UT_Assert utOk <> 0 And utArg = 2500, "--credits 2500 sets 2500"
utOk = CR_ParseArg%("0", utArg)
UT_Assert utOk <> 0 And utArg = 0, "--credits 0 is fine"
utArg = 7
utOk = CR_ParseArg%("-5", utArg)
UT_Assert utOk = 0 And utArg = 7, "--credits -5 is a usage error"
UT_Assert CR_ParseArg%("12x", utArg) = 0 And CR_ParseArg%("1.5", utArg) = 0, "--credits 12x / 1.5 are usage errors"
UT_Assert CR_ParseArg%("", utArg) = 0 And CR_ParseArg%("9999999999", utArg) = 0, "--credits needs a value that fits"

Print ""
Print "--- end-of-run credit bonus ---"
UT_Assert UT_Near%(crBonusRate, 1), "credit_bonus_rate from economy.ini is 1"
UT_Assert CR_BonusPoints&(2350, 1) = 2350, "rate 1: 2350 credits -> 2350 points"
UT_Assert CR_BonusPoints&(2350, 0.5) = 1175 And CR_BonusPoints&(7, 0.3) = 2 And CR_BonusPoints&(10, 0.3) = 3, "decimal rates round down (7 x 0.3 -> 2, 10 x 0.3 -> 3)"
UT_Assert CR_BonusPoints&(0, 1) = 0 And CR_BonusPoints&(500, 0) = 0, "no credits, or rate 0: nothing"
UPG_Reset : CR_ResetRun
score = 1000 : credits = 400 : utBonusLogs = 0
CR_CashOut
UT_Assert score = 1400 And credits = 0 And crBonusPts = 400 And crBonusCredits = 400 And utBonusLogs = 1, "cash-out: 400 credits -> +400 score, credits spent, logged once"
credits = 50
CR_CashOut
CR_CashOutWin
UT_Assert score = 1400 And credits = 50 And utBonusLogs = 1 And crTallyTimer = 0, "a second cash-out (death then win paths) does nothing"
CR_ResetRun
score = 0 : credits = 120
CR_CashOutWin
UT_Assert score = 120 And crTallyTimer > 0 And utBonusLogs = 2, "a new run cashes out again; the win path shows the tally"

Print ""
Print "--- new game resets the run ---"
UPG_Reset
UT_Assert credits = 0 And upgLevel(UPG_ROLL) = 0 And upgLevel(UPG_REGEN) = 0 And rollCoolMax = 0 And regenEvery = 0, "credits and upgrades cleared"

Print ""
Print "=== " + LTrim$(Str$(utPassed + utFailed)) + " tests: " + LTrim$(Str$(utPassed)) + " passed, " + LTrim$(Str$(utFailed)) + " failed ==="
If utFailed > 0 Then System 1
System 0

Function UT_ArmourCheck%
    Dim uacOk As Integer
    uacOk = (UPG_ArmourDmg%(100) = 100)
    If UPG_Buy%(UPG_ARMOUR) <> UPG_OK Then uacOk = 0
    If UPG_ArmourDmg%(100) <> 75 Or UPG_ArmourDmg%(17) <> 13 Then uacOk = 0
    If UPG_Buy%(UPG_ARMOUR) <> UPG_OK Then uacOk = 0
    If UPG_ArmourDmg%(100) <> 50 Then uacOk = 0
    UT_ArmourCheck% = uacOk
End Function
