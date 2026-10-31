' difficulty_test.bas -- difficulty levels (src/gameplay/difficulty.bas, #102)
'
' Drives the real module and the real config loaders against the real assets/config/*.ini:
' loading difficulty.ini (and rejecting unknown levels, unknown knobs and values of 0 or less),
' a knob a level doesn't set being 1, a made-up 5-level file working the same as the real one,
' Normal leaving every loader's values bit-for-bit as they are without difficulty.ini, Easy and
' Hard spot values, which level a run plays (setting, --difficulty), and the rounding helpers.
'
' Build: ./tools/buildqb tests/difficulty_test.bas
' Run:   builds/difficulty_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/config/difficulty.ini':'CFGDIFFICULTY'
$EMBED:'assets/config/economy.ini':'CFGECONOMY'
$EMBED:'assets/config/upgrades.ini':'CFGUPGRADES'
$EMBED:'assets/config/abilities.ini':'CFGABILITIES'
$EMBED:'assets/config/powerups.ini':'CFGPOWERUPS'
$EMBED:'assets/config/waves.ini':'CFGWAVES'
$EMBED:'assets/config/bosses.ini':'CFGBOSSES'

Sub DBG_Print (dltDbg As String) : End Sub
Sub TELEM_UpgradeBought (dltuItem As String, dltuLevel As Integer, dltuPrice As Long) : End Sub
Sub TELEM_CreditBonus (dltcC As Long, dltcR As Double, dltcP As Long) : End Sub
Sub TELEM_FuelBought (dltfA As Integer, dltfP As Long, dltfU As Single, dltfM As Single, dltfC As Integer) : End Sub
Sub TELEM_ShieldBought (dltsA As Integer, dltsP As Long, dltsC As Integer) : End Sub
Sub SEQ_NextLeg (dltnK As Long, dltnBS As Single, dltnB As Integer, dltnA As Integer)
    dltnK = 10 : dltnBS = 40 : dltnB = 1 : dltnA = 1
End Sub

'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/credits.bas'
'$INCLUDE:'../src/gameplay/upgrades.bas'
'$INCLUDE:'../src/gameplay/supplies.bas'
'$INCLUDE:'../src/gameplay/powerups.bas'
'$INCLUDE:'../src/gameplay/wavetiming.bas'
'$INCLUDE:'../src/gameplay/bosshp.bas'
'$INCLUDE:'../src/2d/prompttext.bas'

Dim Shared dltPassed As Integer, dltFailed As Integer

Sub DLT_Assert (dltaCond As Integer, dltaName As String)
    If dltaCond Then
        Print "PASS  " + dltaName
        dltPassed = dltPassed + 1
    Else
        Print "FAIL  " + dltaName
        dltFailed = dltFailed + 1
    End If
End Sub

Function DLT_Near% (dltnA As Double, dltnB As Double)
    DLT_Near% = (Abs(dltnA - dltnB) < 0.0001)
End Function

' Every config loader, from the real files, at the level in use. -1 when all of them load.
Function DLT_LoadAll%
    cfgEconomy = CFG_Parse$(_EMBEDDED$("CFGECONOMY"))
    cfgUpgrades = CFG_Parse$(_EMBEDDED$("CFGUPGRADES"))
    cfgAbilities = CFG_Parse$(_EMBEDDED$("CFGABILITIES"))
    cfgPowerups = CFG_Parse$(_EMBEDDED$("CFGPOWERUPS"))
    cfgWaves = CFG_Parse$(_EMBEDDED$("CFGWAVES"))
    cfgBosses = CFG_Parse$(_EMBEDDED$("CFGBOSSES"))
    DLT_LoadAll% = 0
    If UPG_Load% = 0 Then Print "  " + upgLoadErr : Exit Function
    If SUP_Load% = 0 Then Print "  " + supLoadErr : Exit Function
    If PUP_Load% = 0 Then Print "  " + pupLoadErr : Exit Function
    If WVT_Load% = 0 Then Print "  " + wvtLoadErr : Exit Function
    If BHP_Load% = 0 Then Print "  " + bhpLoadErr : Exit Function
    DLT_LoadAll% = -1
End Function

' The exact bits of everything the loaders set, the dlvF* factors and what the timing and
' boss hit point functions return, as one string: two snapshots are equal only when every
' value is identical.
Function DLT_Snap$
    Dim dltsS As String, dltsI As Integer, dltsL As Integer, dltsN As Integer
    For dltsI = 1 To UPG_COUNT
        dltsS = dltsS + MKI$(upgMax(dltsI))
        For dltsL = 1 To UPG_MAX_LV : dltsS = dltsS + MKL$(upgPrice(dltsI, dltsL)) : Next dltsL
        For dltsL = 0 To UPG_MAX_LV : dltsS = dltsS + MKS$(upgFxA(dltsI, dltsL)) + MKS$(upgFxB(dltsI, dltsL)) : Next dltsL
    Next dltsI
    dltsS = dltsS + MKL$(crKill) + MKL$(crBoss) + MKL$(crStage) + MKL$(crAstNear) + MKL$(crAstKill) + MKL$(crAstSurvive) + MKD$(crBonusRate)
    dltsS = dltsS + MKS$(supFuelPrice) + MKS$(supShieldPrice) + MKS$(supStepPct) + MKS$(supBurn) + MKS$(supMargin)
    dltsS = dltsS + MKS$(supBossSecs) + MKS$(supAstSecs) + MKS$(supBossHpMult)
    For dltsI = 1 To supKillSecsCnt : dltsS = dltsS + MKS$(supKillSecs(dltsI)) : Next dltsI
    For dltsI = 1 To supMultCnt : dltsS = dltsS + MKS$(supMult(dltsI)) : Next dltsI
    dltsS = dltsS + MKS$(SUP_LegNeed!)
    dltsS = dltsS + MKS$(pupChance) + MKL$(pupPoints) + MKI$(pupShield) + MKL$(pupOverflow) + MKS$(pupWTotal)
    For dltsI = 1 To PUP_KINDS : dltsS = dltsS + MKS$(pupW(dltsI)) : Next dltsI
    For dltsI = 1 To pupFuelCnt : dltsS = dltsS + MKS$(pupFuel(dltsI)) : Next dltsI
    dltsS = dltsS + MKS$(pupSpawnX) + MKS$(pupSpawnXVar) + MKS$(pupSpreadY) + MKS$(pupSpreadZ) + MKS$(pupSpeed) + MKS$(pupGrabR) + MKS$(pupGrabDX)
    dltsS = dltsS + MKS$(wvtFirst) + MKI$(wvtOpen) + MKS$(wvtGap0) + MKS$(wvtGap1)
    For dltsI = 1 To wvtOpenGapN : dltsS = dltsS + MKS$(wvtOpenGap(dltsI)) : Next dltsI
    For dltsI = 1 To wvtGapPctN : dltsS = dltsS + MKS$(wvtGapPct(dltsI)) : Next dltsI
    For dltsI = 1 To wvtFirePctN : dltsS = dltsS + MKS$(wvtFirePct(dltsI)) : Next dltsI
    For dltsI = 1 To wvtOpenSizeN : dltsS = dltsS + MKI$(wvtOpenSize(dltsI)) : Next dltsI
    dltsS = dltsS + MKS$(wvtOpenDist) + MKS$(wvtOpenDistVar) + MKS$(wvtDist) + MKS$(wvtDistVar) + MKL$(wvtClear) + MKL$(wvtClearMax) + MKS$(wvtRetreat)
    For dltsI = 1 To 6
        For dltsN = 0 To 4
            dltsS = dltsS + MKS$(WVT_GapTicks!(dltsN, 0, dltsI)) + MKS$(WVT_GapTicks!(dltsN, 0.5, dltsI)) + MKS$(WVT_GapTicks!(dltsN, 1, dltsI))
        Next dltsN
        dltsS = dltsS + MKS$(WVT_FireScale!(dltsI))
    Next dltsI
    dltsS = dltsS + MKI$(bhpDefault) + MKI$(bhpNerfMin) + MKS$(bhpPct2) + MKS$(bhpPct3) + MKL$(bhpShieldPad) + MKL$(bhpShieldMin) + MKS$(bhpHpMult)
    For dltsI = 0 To 200 Step 5 : dltsS = dltsS + MKI$(BHP_MaxHP%(dltsI, 0)) + MKI$(BHP_MaxHP%(dltsI, -1)) : Next dltsI
    dltsS = dltsS + MKS$(dlvFEnemyFire) + MKS$(dlvFEnemyLead) + MKS$(dlvFEnemyHoming) + MKS$(dlvFEnemySpeed)
    dltsS = dltsS + MKS$(dlvFDmg) + MKS$(dlvFBossFire) + MKS$(dlvFFuelBurn) + MKS$(dlvFAstInterval)
    For dltsI = 0 To 120 : dltsS = dltsS + MKI$(DLV_Dmg%(dltsI)) : Next dltsI
    DLT_Snap$ = dltsS
End Function

Function DLT_LoadSrc% (dltlSrc As String)
    cfgDifficulty = CFG_Parse$(dltlSrc)
    DLT_LoadSrc% = DLV_Load%
End Function

Function DLT_Lines$ (dltjS As String)
    Dim dltjI As Integer, dltjOut As String
    For dltjI = 1 To Len(dltjS)
        If Mid$(dltjS, dltjI, 1) = "/" Then dltjOut = dltjOut + Chr$(10) Else dltjOut = dltjOut + Mid$(dltjS, dltjI, 1)
    Next dltjI
    DLT_Lines$ = dltjOut
End Function

Dim dltBase As String, dltI As Integer, dltL As String, dltOk As Integer, dltAll As Integer
Dim dltSeq As String, dltCur As String

Print "=== difficulty_test ==="
Print ""
Print "--- without difficulty.ini: every knob is 1 ---"
levelNum = 2 : fuelMax = 100
DLT_Assert DLV_Count% = 0 And DLV_M!("wave_gap") = 1 And DLV_M!("credits") = 1 And DLV_Dmg%(17) = 17, "no levels loaded: multipliers 1, damage as given"
DLT_Assert DLT_LoadAll% <> 0, "every loader loads"
dltBase = DLT_Snap$

Print ""
Print "--- the real difficulty.ini ---"
cfgDifficulty = CFG_Parse$(_EMBEDDED$("CFGDIFFICULTY"))
DLT_Assert DLV_Load% <> 0, "loads " + dlvLoadErr
DLT_Assert DLV_Count% = 3 And DLV_LevelAt$(1) = "easy" And DLV_LevelAt$(2) = "normal" And DLV_LevelAt$(3) = "hard", "levels: easy, normal, hard, in that order"
DLT_Assert DLV_Default$ = "normal", "default: normal"
DLT_Assert DLV_Name$("easy") = "EASY" And DLV_Name$("normal") = "NORMAL" And DLV_Name$("hard") = "HARD", "names: EASY, NORMAL, HARD"
DLT_Assert DLV_Tag$("easy") = "E" And DLV_Tag$("normal") = "" And DLV_Tag$("hard") = "H", "leaderboard tags: E, none, H"
DLT_Assert DLV_List$ = "easy, normal or hard", "listed for the CLI: " + DLV_List$
dltAll = -1
For dltI = 1 To DLV_Count%
    DLV_Use DLV_LevelAt$(dltI)
    dltOk = DLT_LoadAll%
    If dltOk = 0 Then dltAll = 0 : Print "  " + DLV_LevelAt$(dltI) + " doesn't load"
Next dltI
DLT_Assert dltAll, "every level loads every config file (as boot checks)"
DLV_Use "normal"
dltAll = -1
For dltI = 1 To DLV_KNOBS
    If DLV_M!(dlvKnob(dltI)) <> 1 Then dltAll = 0
Next dltI
DLT_Assert dltAll And runDifficulty = "normal", "normal: every knob is 1"
dltOk = DLT_LoadAll% : DLT_Assert dltOk <> 0 And DLT_Snap$ = dltBase, "normal: every loader's values bit-for-bit as without difficulty.ini"
DLV_Use "bogus"
DLT_Assert runDifficulty = "normal", "an unknown level plays the default"

Print ""
Print "--- easy ---"
DLV_Use "easy"
dltOk = DLT_LoadAll% : DLT_Assert dltOk <> 0 And runDifficulty = "easy", "loads"
DLT_Assert DLT_Snap$ <> dltBase, "differs from normal"
DLT_Assert DLT_Near%(wvtFirst, 90) And DLT_Near%(wvtGap0, 350) And DLT_Near%(wvtGap1, 250) And DLT_Near%(wvtOpenGap(1), 252), "waves: first at 90 frames, regular gap 350..250, opening gap 252 in stage 1"
DLT_Assert DLT_Near%(wvtGapPct(1), 110) And wvtOpenSize(1) = 1 And wvtOpen = 3, "wave sizes and per-stage % untouched (no more enemies)"
DLT_Assert DLT_Near%(pupChance, 0.195) And pupShield = 60 And DLT_Near%(pupFuel(1), 19.95) And pupPoints = 500, "power-ups: 19.5% a wave, shield 60, fuel 19.95, points 500"
DLT_Assert crKill = 30 And crBoss = 720 And crStage = 240 And crAstSurvive = 480 And DLT_Near%(crBonusRate, 1), "credits x1.2: kill 30, boss 720, stage 240, asteroid field 480; cash-in rate stays 1"
DLT_Assert upgPrice(UPG_LASER, 1) = 68 And upgPrice(UPG_FUEL, 1) = 43, "upgrades x0.85: laser 68, fuel tank 43 (42.5 rounded)"
DLT_Assert DLT_Near%(supFuelPrice, 1.5) And DLT_Near%(supShieldPrice, 0.75) And DLT_Near%(supBurn, 1.188) And DLT_Near%(SUP_Mult!(2), 1.4), "supplies: fuel $1.50, shields $0.75, burn 1.188/s; the surcharge stays 1.4"
DLT_Assert BHP_MaxHP%(30, 0) = 21 And BHP_MaxHP%(90, 0) = 63 And BHP_MaxHP%(130, 0) = 91 And BHP_MaxHP%(0, 0) = 21, "boss hit points x0.7: 21, 63, 91 (and the default 30 -> 21)"
DLT_Assert BHP_MaxHP%(30, -1) = 3 And BHP_MaxHP%(130, -1) = 9, "--nerf after difficulty: 21 -> 3 (the minimum), 91 -> 9"
DLT_Assert DLV_Dmg%(5) = 4 And DLV_Dmg%(17) = 13 And DLV_Dmg%(1) = 1 And DLV_Dmg%(0) = 0, "damage x0.75: laser 5 -> 4, collision 17 -> 13, never below 1, 0 stays 0"
DLT_Assert DLT_Near%(dlvFEnemyFire, 1.35) And DLT_Near%(dlvFEnemyLead, 0.6) And DLT_Near%(dlvFEnemyHoming, 0.7) And DLT_Near%(dlvFEnemySpeed, 0.9) And DLT_Near%(dlvFBossFire, 1.3) And DLT_Near%(dlvFFuelBurn, 0.9) And DLT_Near%(dlvFAstInterval, 1.25), "in-play factors: fire 1.35, lead 0.6, homing 0.7, speed 0.9, boss fire 1.3, burn 0.9, asteroids 1.25"

Print ""
Print "--- hard ---"
DLV_Use "hard"
dltOk = DLT_LoadAll% : DLT_Assert dltOk <> 0 And runDifficulty = "hard", "loads"
DLT_Assert DLT_Near%(wvtFirst, 45) And DLT_Near%(wvtGap0, 238) And DLT_Near%(wvtGap1, 170) And DLT_Near%(wvtOpenGap(1), 189), "waves: first at 45 frames, regular gap 238..170, opening gap 189 in stage 1"
DLT_Assert DLT_Near%(pupChance, 0.1275) And pupShield = 41 And DLT_Near%(pupFuel(1), 15), "power-ups: 12.75% a wave, shield 41 (40.5 rounds up), fuel 15"
DLT_Assert crKill = 21 And crBoss = 510 And crStage = 170, "credits x0.85: kill 21 (21.25), boss 510, stage 170"
DLT_Assert upgPrice(UPG_LASER, 1) = 92 And upgPrice(UPG_LASER, 3) = 288 And upgPrice(UPG_RAPID, 1) = 115, "upgrades x1.15: laser 92 ... 288 (287.5 rounds up), rapid fire 115"
DLT_Assert DLT_Near%(supFuelPrice, 2.5) And DLT_Near%(supShieldPrice, 1.25) And DLT_Near%(supBurn, 1.452), "supplies: fuel $2.50, shields $1.25, burn 1.452/s"
DLT_Assert BHP_MaxHP%(30, 0) = 39 And BHP_MaxHP%(90, 0) = 117 And BHP_MaxHP%(130, 0) = 169 And BHP_MaxHP%(90, -1) = 12, "boss hit points x1.3: 39, 117, 169; --nerf 117 -> 12"
DLT_Assert DLV_Dmg%(5) = 6 And DLV_Dmg%(17) = 21 And DLV_Dmg%(100) = 125, "damage x1.25: laser 5 -> 6, collision 17 -> 21"
DLT_Assert DLT_Near%(dlvFEnemyLead, 1.25) And DLT_Near%(dlvFEnemyFire, 0.8) And DLT_Near%(dlvFBossFire, 0.85), "in-play factors: lead 1.25, fire 0.8, boss fire 0.85"

Print ""
Print "--- which level a run plays ---"
settingDifficulty = "" : cliDifficulty = ""
DLT_Assert DLV_Chosen$ = "normal", "nothing chosen: the default"
settingDifficulty = "hard"
DLT_Assert DLV_Chosen$ = "hard", "Settings says hard: hard"
cliDifficulty = "easy"
DLT_Assert DLV_Chosen$ = "easy", "--difficulty easy wins over the setting"
DLV_Begin
DLT_Assert runDifficulty = "easy" And DLT_Near%(DLV_M!("credits"), 1.2), "DLV_Begin plays it"
cliDifficulty = "" : settingDifficulty = "nightmare"
DLT_Assert DLV_Chosen$ = "normal" And DLV_Valid$("nightmare") = "normal" And DLV_Valid$("easy") = "easy", "an unknown setting (an older or edited file) plays the default"
settingDifficulty = ""

Print ""
Print "--- Settings steps through the levels in order, wrapping ---"
DLT_Assert DLV_Step$("normal", 1) = "hard" And DLV_Step$("hard", 1) = "easy" And DLV_Step$("easy", 1) = "normal", "right: normal, hard, easy, normal"
DLT_Assert DLV_Step$("normal", -1) = "easy" And DLV_Step$("easy", -1) = "hard", "left: normal, easy, hard"
DLT_Assert DLV_Step$("", 1) = "hard", "from no setting: steps from the default"

Print ""
Print "--- rounding helpers ---"
DLT_Assert DLV_Round&(25, 1) = 25 And DLV_Round&(25, 1.2) = 30 And DLV_Round&(80, 0.85) = 68 And DLV_Round&(7, 0.5) = 4 And DLV_Round&(0, 1.3) = 0, "DLV_Round&: x1 exact; 30, 68, 3.5 -> 4, 0 stays 0"

Print ""
Print "--- a 5-level file works the same, with no code change ---"
DLT_Assert DLT_LoadSrc%(DLT_Lines$("levels=a1,b2,c3,d4,e5/default=c3/a1_wave_gap=2/a1_tag=A/b2_name=BEE/e5_dmg_taken=3/e5_tag=X")) <> 0, "loads " + dlvLoadErr
DLT_Assert DLV_Count% = 5 And DLV_Default$ = "c3" And DLV_List$ = "a1, b2, c3, d4 or e5", "5 levels, default c3: " + DLV_List$
DLT_Assert DLV_Name$("b2") = "BEE" And DLV_Name$("d4") = "D4" And DLV_Tag$("a1") = "A" And DLV_Tag$("d4") = "", "names and tags: given, or the level in capitals and none"
dltSeq = "" : dltCur = "c3"
For dltI = 1 To 5 : dltCur = DLV_Step$(dltCur, 1) : dltSeq = dltSeq + dltCur + " " : Next dltI
DLT_Assert dltSeq = "d4 e5 a1 b2 c3 ", "right x5 from c3: " + dltSeq
dltSeq = "" : dltCur = "c3"
For dltI = 1 To 5 : dltCur = DLV_Step$(dltCur, -1) : dltSeq = dltSeq + dltCur + " " : Next dltI
DLT_Assert dltSeq = "b2 a1 e5 d4 c3 ", "left x5 from c3: " + dltSeq
dltAll = -1
For dltI = 1 To DLV_Count%
    DLV_Use DLV_LevelAt$(dltI)
    dltOk = DLT_LoadAll%
    If dltOk = 0 Then dltAll = 0
Next dltI
DLT_Assert dltAll, "every one of the 5 levels loads every config file"
DLV_Use "a1"
dltOk = DLT_LoadAll% : DLT_Assert dltOk <> 0 And DLT_Near%(wvtGap0, 560) And DLT_Near%(DLV_M!("credits"), 1), "a1: wave_gap x2 (560), a knob it doesn't set is 1"
DLV_Use "e5"
DLT_Assert DLV_Dmg%(5) = 15 And DLT_Near%(DLV_M!("wave_gap"), 1), "e5: damage x3, wave_gap 1"
DLV_Use "c3"
dltOk = DLT_LoadAll% : DLT_Assert dltOk <> 0 And DLT_Snap$ = dltBase, "c3 (no knobs): bit-for-bit as without difficulty.ini"
settingDifficulty = "e5"
DLT_Assert DLV_Chosen$ = "e5", "a saved fifth level is played"
settingDifficulty = "hard"
DLT_Assert DLV_Chosen$ = "c3", "a level this file doesn't have plays its default"
settingDifficulty = ""

Print ""
Print "--- broken files fail the load ---"
dltOk = DLT_LoadSrc%(DLT_Lines$("levels=easy,normal/default=normal/easy_wave_gapp=1.2")) : DLT_Assert dltOk = 0 And InStr(dlvLoadErr, "wave_gapp") > 0, "an unknown knob: " + dlvLoadErr
DLT_Assert DLV_Count% = 0 And DLV_M!("wave_gap") = 1, "a failed load leaves no levels, every knob 1"
dltOk = DLT_LoadSrc%(DLT_Lines$("levels=easy,normal/default=normal/medium_wave_gap=1.2")) : DLT_Assert dltOk = 0 And InStr(dlvLoadErr, "medium_wave_gap") > 0, "a level not in levels: " + dlvLoadErr
dltOk = DLT_LoadSrc%(DLT_Lines$("levels=easy,normal/default=normal/easy_wave_gap=0")) : DLT_Assert dltOk = 0 And InStr(dlvLoadErr, "above 0") > 0, "a 0 multiplier: " + dlvLoadErr
DLT_Assert DLT_LoadSrc%(DLT_Lines$("levels=easy,normal/default=normal/easy_wave_gap=-1")) = 0, "a negative multiplier"
DLT_Assert DLT_LoadSrc%(DLT_Lines$("levels=easy,normal/default=normal/easy_wave_gap=lots")) = 0, "a multiplier that isn't a number"
dltOk = DLT_LoadSrc%(DLT_Lines$("default=normal")) : DLT_Assert dltOk = 0 And InStr(dlvLoadErr, "no levels") > 0, "no levels: " + dlvLoadErr
dltOk = DLT_LoadSrc%(DLT_Lines$("levels=easy,normal")) : DLT_Assert dltOk = 0 And InStr(dlvLoadErr, "default") > 0, "no default: " + dlvLoadErr
DLT_Assert DLT_LoadSrc%(DLT_Lines$("levels=easy,normal/default=hard")) = 0, "a default that isn't a level"
dltOk = DLT_LoadSrc%(DLT_Lines$("levels=easy,easy/default=easy")) : DLT_Assert dltOk = 0 And InStr(dlvLoadErr, "twice") > 0, "a level listed twice: " + dlvLoadErr
DLT_Assert DLT_LoadSrc%(DLT_Lines$("levels=Easy,normal/default=normal")) = 0, "a level name in capitals"
DLT_Assert DLT_LoadSrc%(DLT_Lines$("levels=very_easy,normal/default=normal")) = 0, "a level name with _ (it would split <level>_<knob> two ways)"
DLT_Assert DLT_LoadSrc%(DLT_Lines$("levels=easy,,normal/default=normal")) = 0, "an empty level"
DLT_Assert DLT_LoadSrc%(DLT_Lines$("levels=easy,normal/default=normal/easy_name=")) = 0, "an empty name"
DLT_Assert DLT_LoadSrc%(DLT_Lines$("levels=easy,normal/default=normal/easy_tag=")) <> 0, "an empty tag is fine (no tag)"

Print ""
Print "=== " + LTrim$(Str$(dltPassed + dltFailed)) + " tests: " + LTrim$(Str$(dltPassed)) + " passed, " + LTrim$(Str$(dltFailed)) + " failed ==="
If dltFailed > 0 Then System 1
System 0
