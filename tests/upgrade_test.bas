' upgrade_test.bas -- credits and the upgrade table (src/gameplay/upgrades.bas, #268)
'
' Drives the real module against the real assets/gamevalues.ini: parsing the upgrade
' table and credit amounts (and rejecting a malformed line), the economy target, earning,
' buying (affordable, too expensive, maxed), each upgrade's effect values, hull repair
' once per dock, nova charges refilled at every dock, the roll's immunity window and
' cooldown, shield regen after the no-hit delay, hull armour, and the new-game reset.
'
' Build: ./tools/buildqb tests/upgrade_test.bas
' Run:   builds/upgrade_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'

Sub DBG_Print (upgtDbg As String) : End Sub

' TELEM_UpgradeBought records instead of writing telemetry
Dim Shared utItem As String, utLevel As Integer, utPrice As Long, utBuys As Integer
Sub TELEM_UpgradeBought (tuItem As String, tuLevel As Integer, tuPrice As Long)
    utItem = tuItem : utLevel = tuLevel : utPrice = tuPrice : utBuys = utBuys + 1
End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/gametext.bas'
'$INCLUDE:'../src/gameplay/upgrades.bas'

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

Print "--- gamevalues.ini: the upgrade table ---"
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
utOk = UPG_Load%
UT_Assert utOk <> 0, "UPG_Load% reads every upg_ line (" + upgLoadErr + ")"
UT_Assert upgMax(UPG_LASER) = 3 And upgMax(UPG_CANNON) = 2 And upgMax(UPG_NOVA) = 3 And upgMax(UPG_REPAIR) = 1, "levels: laser 3, cannon 2, nova 3, repair 1"
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
UT_Assert utOk <> 0, "all 12 upgrades have a key and a name"

' economy: every level of everything (repairs aside) is 90-100% of what stages 1-5 pay
utTotal = 0
For utI = 1 To UPG_COUNT
    If utI <> UPG_REPAIR Then
        For utJ = 1 To upgMax(utI) : utTotal = utTotal + upgPrice(utI, utJ) : Next utJ
    End If
Next utI
utEarn = 50 * crKill + 2 * crBoss + 5 * crStage + 15 * crAstNear + crAstSurvive
UT_Assert utTotal = 3960, "all upgrades cost 3960 (" + LTrim$(Str$(utTotal)) + ")"
UT_Assert utTotal * 100 >= utEarn * 90 And utTotal <= utEarn, "total cost is 90-100% of a strong run's spendable credits (" + LTrim$(Str$(utEarn)) + ")"

Print ""
Print "--- a malformed line is rejected ---"
utOk = UPG_ParseLine%(UPG_RAPID, "rapid", "RAPID FIRE|100,200|0.18,0.14")
UT_Assert utOk = 0 And InStr(upgLoadErr, "rapid") > 0, "effect list one short: rejected, error names it"
utOk = UPG_ParseLine%(UPG_RAPID, "rapid", "RAPID FIRE")
UT_Assert utOk = 0, "no prices: rejected"
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
UT_Assert UPG_Price&(UPG_RAPID) = 0 And UPG_Desc$(UPG_RAPID) = "FULLY UPGRADED", "maxed: no price, FULLY UPGRADED"

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
utR = UPG_Buy%(UPG_FUEL)
UT_Assert UT_Near%(fuelMax, 130) And UT_Near%(fuelLevel, 130), "fuel tank 1: 130, and filled"
utR = UPG_Buy%(UPG_TRACTOR)
UT_Assert UT_Near%(tractorR, 10) And UT_Near%(tractorPull, 0.05), "tractor beam 1: range 10, pull 0.05"
UT_Assert UT_ArmourCheck% = -1, "hull armour: 100 -> 75 -> 50, 17 -> 13 at 75%"
utOk = -1
For utI = 1 To UPG_COUNT
    If Len(UPG_Desc$(utI)) = 0 Or Len(UPG_Desc$(utI)) > 25 Then utOk = 0 : Print "  desc: "; UPG_Desc$(utI)
Next utI
UT_Assert utOk <> 0, "every row has a description that fits the dock panel (25 chars)"

Print ""
Print "--- hull repair: once per dock ---"
lives = 50
utR = UPG_Buy%(UPG_REPAIR)
UT_Assert utR = UPG_OK And lives = shieldMax, "repair refills the shields to max"
lives = 40
utR = UPG_Buy%(UPG_REPAIR)
UT_Assert utR = UPG_MAXED And lives = 40, "a second repair at the same dock is refused"
UPG_DockVisit
utR = UPG_Buy%(UPG_REPAIR)
UT_Assert utR = UPG_OK And lives = shieldMax, "the next dock sells it again"
UPG_DockVisit
utCr = credits
utR = UPG_Buy%(UPG_REPAIR)
UT_Assert utR = UPG_FULL And credits = utCr, "full shields: refused, no charge"

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
