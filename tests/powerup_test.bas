' powerup_test.bas -- the three power-up kinds (src/gameplay/powerups.bas, #183)
'
' Drives the real module against the real assets/config/powerups.ini: loading it (and
' rejecting broken values), the kind roll's band edges, the grab zone's boundaries, the
' tractor beam's reach, per-chapter fuel amounts (past the end of the list too), shield and
' fuel capped at the gauge, and the score a full gauge pays instead.
'
' Build: ./tools/buildqb tests/powerup_test.bas
' Run:   builds/powerup_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/config/powerups.ini':'CFGPOWERUPS'
$EMBED:'assets/config/difficulty.ini':'CFGDIFFICULTY'

Sub DBG_Print (pttDbg As String) : End Sub
Sub TELEM_UpgradeBought (ptuItem As String, ptuLevel As Integer, ptuPrice As Long) : End Sub
Sub TELEM_CreditBonus (ptcC As Long, ptcR As Double, ptcP As Long) : End Sub

'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/credits.bas'
'$INCLUDE:'../src/gameplay/upgrades.bas'
'$INCLUDE:'../src/gameplay/powerups.bas'

Dim Shared ptPassed As Integer, ptFailed As Integer

Sub PT_Assert (ptaCond As Integer, ptaName As String)
    If ptaCond Then
        Print "PASS  " + ptaName
        ptPassed = ptPassed + 1
    Else
        Print "FAIL  " + ptaName
        ptFailed = ptFailed + 1
    End If
End Sub

Function PT_Near% (ptnA As Single, ptnB As Single)
    PT_Near% = (Abs(ptnA - ptnB) < 0.0001)
End Function

' Loads a variant of the real file with one key's value replaced; returns PUP_Load%.
Function PT_LoadWith% (ptlKey As String, ptlVal As String)
    Dim ptlSrc As String, ptlP As Long, ptlQ As Long
    ptlSrc = _EMBEDDED$("CFGPOWERUPS")
    ptlP = InStr(ptlSrc, Chr$(10) + ptlKey + "=")
    If ptlP > 0 Then
        ptlQ = InStr(ptlP + 1, ptlSrc, Chr$(10))
        If ptlQ = 0 Then ptlQ = Len(ptlSrc) + 1
        ptlSrc = Left$(ptlSrc, ptlP) + ptlKey + "=" + ptlVal + Mid$(ptlSrc, ptlQ)
    End If
    cfgPowerups = CFG_Parse$(ptlSrc)
    PT_LoadWith% = PUP_Load%
End Function

Dim ptOk As Integer, ptAmt As Single, ptScore As Long, ptW1 As Single, ptW2 As Single

Print "=== powerup_test ==="
Print ""

Print "--- config: the real powerups.ini ---"
cfgPowerups = CFG_Parse$(_EMBEDDED$("CFGPOWERUPS"))
ptOk = PUP_Load%
PT_Assert ptOk <> 0, "powerups.ini loads " + pupLoadErr
PT_Assert PT_Near%(pupChance, 0.15), "pup_chance 0.15"
PT_Assert PT_Near%(pupW(PUP_POINTS), 45) And PT_Near%(pupW(PUP_SHIELD), 40) And PT_Near%(pupW(PUP_FUEL), 15), "weights points 45, shield 40, fuel 15"
PT_Assert pupPoints = 500 And pupShield = 45 And pupOverflow = 250, "points 500, shield 45, overflow 250"
PT_Assert pupFuelCnt = 5, "fuel amounts for 5 chapters"
PT_Assert PT_Near%(pupSpawnX, 45) And PT_Near%(pupSpawnXVar, 10), "spawn 45..55 ahead"
PT_Assert PT_Near%(pupSpreadY, 10) And PT_Near%(pupSpreadZ, 14), "spread y 10, z 14"
PT_Assert PT_Near%(pupSpeed, 0.08) And PT_Near%(pupGrabR, 1.6) And PT_Near%(pupGrabDX, 1.2) And pupMarkerFrames = 90, "speed, grab zone and marker frames"
PT_Assert pupSpawnX + pupSpawnXVar > PUP_TRACTOR_DX_MAX And pupSpawnX <= PUP_TRACTOR_DX_MAX + pupSpawnXVar, "spawns ahead of the tractor's reach, so every one drifts into it"

Print ""
Print "--- config: broken values are rejected ---"
PT_Assert PT_LoadWith%("pup_weights", "45,40") = 0, "two weights: rejected"
PT_Assert PT_LoadWith%("pup_weights", "0,0,0") = 0, "weights adding up to 0: rejected"
PT_Assert PT_LoadWith%("pup_weights", "45,-1,15") = 0, "a negative weight: rejected"
PT_Assert PT_LoadWith%("pup_chance", "1.5") = 0, "chance above 1: rejected"
PT_Assert PT_LoadWith%("pup_fuel", "10,0,6") = 0, "a fuel amount of 0: rejected"
PT_Assert PT_LoadWith%("pup_grab_r", "0") = 0, "grab radius 0: rejected"
PT_Assert PT_LoadWith%("pup_spawn_x", "45") = 0, "spawn x without a variance: rejected"
PT_Assert PT_LoadWith%("pup_spawn_x", "1,10") = 0, "spawning inside the grab zone: rejected"
cfgPowerups = CFG_Parse$(_EMBEDDED$("CFGPOWERUPS"))
PT_Assert PUP_Load% <> 0, "the real file loads again"

Print ""
Print "--- kind roll: weight band edges (45 / 40 / 15 of 100) ---"
ptW1 = 45 / 100 : ptW2 = 85 / 100
PT_Assert PUP_PickKind%(0) = PUP_POINTS, "roll 0: points"
PT_Assert PUP_PickKind%(ptW1 - 0.001) = PUP_POINTS, "just under 0.45: points"
PT_Assert PUP_PickKind%(ptW1 + 0.001) = PUP_SHIELD, "just over 0.45: shield"
PT_Assert PUP_PickKind%(ptW2 - 0.001) = PUP_SHIELD, "just under 0.85: shield"
PT_Assert PUP_PickKind%(ptW2 + 0.001) = PUP_FUEL, "just over 0.85: fuel"
PT_Assert PUP_PickKind%(0.9999) = PUP_FUEL, "roll near 1: fuel"
PT_Assert PUP_KindName$(PUP_POINTS) = "points" And PUP_KindName$(PUP_SHIELD) = "shield" And PUP_KindName$(PUP_FUEL) = "fuel", "telemetry kind names"

Print ""
Print "--- grab zone: |dx| <= 1.2 and sqrt(dy^2 + dz^2) <= 1.6 ---"
PT_Assert PUP_Grabbed%(0, 0, 0), "dead centre: caught"
PT_Assert PUP_Grabbed%(1.2, 0, 0), "dx 1.2 (edge): caught"
PT_Assert PUP_Grabbed%(1.21, 0, 0) = 0, "dx 1.21: not yet"
PT_Assert PUP_Grabbed%(-1.2, 0, 0), "dx -1.2 (just past the ship): caught"
PT_Assert PUP_Grabbed%(-1.21, 0, 0) = 0, "dx -1.21: gone by"
PT_Assert PUP_Grabbed%(0, 1.6, 0), "1.6 above: caught"
PT_Assert PUP_Grabbed%(0, 0, -1.61) = 0, "1.61 to the side: missed"
PT_Assert PUP_Grabbed%(0.5, 1.1, 1.1), "1.1 up and 1.1 across (1.56): caught"
PT_Assert PUP_Grabbed%(0.5, 1.2, 1.2) = 0, "1.2 up and 1.2 across (1.70): missed"

Print ""
Print "--- tractor reach: dx -2..45, within r across ---"
PT_Assert PUP_InTractor%(10, 3, 4, 10), "10 ahead, 5 across, reach 10: held"
PT_Assert PUP_InTractor%(10, 6, 8, 10), "exactly 10 across: held"
PT_Assert PUP_InTractor%(10, 6, 8.1, 10) = 0, "just beyond 10 across: not held"
PT_Assert PUP_InTractor%(45, 0, 0, 10), "45 ahead (the far edge): held"
PT_Assert PUP_InTractor%(45.01, 0, 0, 10) = 0, "past 45 ahead: not yet"
PT_Assert PUP_InTractor%(-2, 0, 0, 10), "2 behind (the near edge): held"
PT_Assert PUP_InTractor%(-2.01, 0, 0, 10) = 0, "further behind: let go"
PT_Assert PUP_InTractor%(10, 0, 0, 0) = 0, "no tractor fitted: never held"
PT_Assert PUP_InTractor%(10, 10, 14, 18), "level 2 (reach 18) holds a spawn at the lane's corner (10 up, 14 across)"

Print ""
Print "--- amounts per chapter ---"
PT_Assert PT_Near%(PUP_Amount!(PUP_POINTS, 3), 500), "points: 500"
PT_Assert PT_Near%(PUP_Amount!(PUP_SHIELD, 3), 45), "shield: 45"
PT_Assert PT_Near%(PUP_Amount!(PUP_FUEL, 1), 15), "fuel chapter 1: 15"
PT_Assert PT_Near%(PUP_Amount!(PUP_FUEL, 2), 15), "fuel chapter 2: 15"
PT_Assert PT_Near%(PUP_Amount!(PUP_FUEL, 3), 15), "fuel chapter 3: 15"
PT_Assert PT_Near%(PUP_Amount!(PUP_FUEL, 5), 15), "fuel chapter 5: 15"
PT_Assert PT_Near%(PUP_Amount!(PUP_FUEL, 6), 15), "fuel chapter 6 (past the end): the last value, 15"
PT_Assert PT_Near%(PUP_Amount!(PUP_FUEL, 0), 15), "fuel chapter 0 (before the first): the first value"

Print ""
Print "--- applying: caps and overflow ---"
shieldMax = 100 : fuelMax = 100
score = 1000 : stageKills = 3
ptAmt = PUP_Apply!(PUP_POINTS, 1)
PT_Assert PT_Near%(ptAmt, 500) And score = 1500 And pupOverflowPts = 0, "points: +500 score"
PT_Assert stageKills = 3, "points: the stage's kill count doesn't move (#312)"
lives = 50 : score = 0
ptAmt = PUP_Apply!(PUP_SHIELD, 1)
PT_Assert PT_Near%(ptAmt, 45) And lives = 95 And score = 0, "shield 50 -> 95"
lives = 80
ptAmt = PUP_Apply!(PUP_SHIELD, 1)
PT_Assert PT_Near%(ptAmt, 20) And lives = 100 And score = 0 And pupOverflowPts = 0, "shield 80: tops up to 100 (+20), no points"
ptAmt = PUP_Apply!(PUP_SHIELD, 1)
PT_Assert PT_Near%(ptAmt, 0) And lives = 100 And score = 250 And pupOverflowPts = 250, "shield full: +250 score instead"
PT_Assert stageKills = 3, "overflow bonus: the stage's kill count doesn't move (#312)"
fuelLevel = 50 : score = 0
ptAmt = PUP_Apply!(PUP_FUEL, 2)
PT_Assert PT_Near%(ptAmt, 15) And PT_Near%(fuelLevel, 65) And score = 0, "fuel chapter 2: 50 -> 65"
fuelLevel = 97.5
ptAmt = PUP_Apply!(PUP_FUEL, 1)
PT_Assert PT_Near%(ptAmt, 2.5) And PT_Near%(fuelLevel, 100) And pupOverflowPts = 0, "fuel 97.5: tops up to 100 (+2.5)"
fuelLevel = 99.5 : score = 0
ptAmt = PUP_Apply!(PUP_FUEL, 1)
PT_Assert PT_Near%(ptAmt, 0) And PT_Near%(fuelLevel, 99.5) And score = 250 And pupOverflowPts = 250, "fuel under a unit from full counts as full: +250 score"
fuelMax = 160 : fuelLevel = 100 : score = 0
ptAmt = PUP_Apply!(PUP_FUEL, 4)
PT_Assert PT_Near%(ptAmt, 15) And PT_Near%(fuelLevel, 115) And score = 0, "a bigger tank (160) has room: chapter 4 gives 15"
shieldMax = 150 : lives = 100
ptAmt = PUP_Apply!(PUP_SHIELD, 1)
PT_Assert PT_Near%(ptAmt, 45) And lives = 145, "a bigger shield (150) has room: +45"

Print ""
Print "--- difficulty levels (#102): chance and amounts ---"
Dim ptdLv As Integer, ptdAll As Integer, ptdOk As Integer
cfgPowerups = CFG_Parse$(_EMBEDDED$("CFGPOWERUPS"))
cfgDifficulty = CFG_Parse$(_EMBEDDED$("CFGDIFFICULTY"))
PT_Assert DLV_Load% <> 0, "difficulty.ini loads " + dlvLoadErr
ptdAll = -1
For ptdLv = 1 To DLV_Count%
    DLV_Use DLV_LevelAt$(ptdLv)
    ptdOk = PUP_Load%
    If ptdOk = 0 Then ptdAll = 0 : Print "  " + pupLoadErr
    If PT_Near%(pupChance, 0.15 * DLV_M!("pup_chance")) = 0 Or PT_Near%(PUP_Amount!(PUP_FUEL, 3), 15 * DLV_M!("pup_fuel")) = 0 Then ptdAll = 0 : Print "  " + DLV_LevelAt$(ptdLv) + ": chance or fuel off"
    If pupShield <> Int(45 * DLV_M!("pup_shield") + 0.501) Or pupPoints <> 500 Or PT_Near%(pupW(PUP_FUEL), 15) = 0 Then ptdAll = 0 : Print "  " + DLV_LevelAt$(ptdLv) + ": shield, points or weights off"
Next ptdLv
PT_Assert ptdAll, "every level: chance x pup_chance, fuel x pup_fuel, shield x pup_shield; points and the mix as they are"
DLV_Use "normal"
ptdOk = PUP_Load% : PT_Assert ptdOk <> 0 And pupChance = 0.15! And pupShield = 45 And PUP_Amount!(PUP_FUEL, 1) = 15, "normal: 0.15, shield 45, fuel 15 as without difficulty.ini"
DLV_Use "easy"
ptdOk = PUP_Load% : PT_Assert ptdOk <> 0 And PT_Near%(pupChance, 0.195) And pupShield = 60 And PT_Near%(PUP_Amount!(PUP_FUEL, 1), 19.95), "easy: 19.5% a wave, shield 60, fuel 19.95"
DLV_Use "hard"
ptdOk = PUP_Load% : PT_Assert ptdOk <> 0 And PT_Near%(pupChance, 0.1275) And pupShield = 41 And PT_Near%(PUP_Amount!(PUP_FUEL, 1), 15), "hard: 12.75% a wave, shield 41, fuel 15"
DLV_Use "normal"
PT_Assert PUP_Load% <> 0, "back to normal"

Print ""
Print "passed:" + Str$(ptPassed) + "  failed:" + Str$(ptFailed)
If ptFailed > 0 Then System 1
System 0
