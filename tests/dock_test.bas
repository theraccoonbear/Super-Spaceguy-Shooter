' dock_test.bas -- the upgrade dock driven by scripted input (src/state/docklogic.bas, #268)
'
' Plays input scripts through the real input path (ISC_Apply -> held() -> KEY_Pressed% /
' KEY_Confirm% / KEY_Back%) into the real DOCK_Input% each frame, as the game does, with
' the real upgrade table from assets/config/: navigating (keys, W/S, stick, d-pad,
' wrap-around, scrolling), buying, a purchase it can't afford, a held ENTER buying once,
' fuel and shields by the amount (LEFT / RIGHT, fill what you can afford, FULL, #277), the
' stranded dialog (only YES answers it; LAUNCH and back both raise it, #277),
' LAUNCH, and leaving in one press with ESC, pad B or pad Start.
'
' Build: ./tools/buildqb tests/dock_test.bas
' Run:   builds/dock_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/config/economy.ini':'CFGECONOMY'
$EMBED:'assets/config/upgrades.ini':'CFGUPGRADES'
$EMBED:'assets/config/abilities.ini':'CFGABILITIES'

Sub DBG_Print (dktDbg As String) : End Sub
Sub TELEM_UpgradeBought (dtuItem As String, dtuLevel As Integer, dtuPrice As Long) : End Sub
Sub TELEM_CreditBonus (dtcC As Long, dtcR As Double, dtcP As Long) : End Sub
Sub TELEM_FuelBought (dtfA As Integer, dtfP As Long, dtfU As Single, dtfM As Single, dtfC As Integer) : End Sub
Sub TELEM_ShieldBought (dtsbA As Integer, dtsbP As Long, dtsbC As Integer) : End Sub
' SEQ_NextLeg (sequence.bas) reports this stub leg: 10 kills and a boss, 55 fuel
Dim Shared dtLegKills As Long, dtLegBoss As Integer
Sub SEQ_NextLeg (dtnK As Long, dtnB As Integer, dtnA As Integer)
    dtnK = dtLegKills : dtnB = dtLegBoss : dtnA = 0
End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/inputscript.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/credits.bas'
'$INCLUDE:'../src/gameplay/upgrades.bas'
'$INCLUDE:'../src/gameplay/supplies.bas'
'$INCLUDE:'../src/state/docklogic.bas'
'$INCLUDE:'../src/2d/prompttext.bas'

Dim Shared dtPassed As Integer, dtFailed As Integer
Dim Shared dtRes(0 To 199) As Integer   ' DOCK_Input% result per frame of the last run

Sub DT_Assert (dtaCond As Integer, dtaName As String)
    If dtaCond Then
        Print "PASS  " + dtaName
        dtPassed = dtPassed + 1
    Else
        Print "FAIL  " + dtaName
        dtFailed = dtFailed + 1
    End If
End Sub

' Fresh dock with dtsCredits, a full tank and full shields, then the script lines (separated by "/").
Sub DT_Script (dtsCredits As Long, dtsLines As String)
    DT_ScriptAt dtsCredits, -1, -1, dtsLines
End Sub

' The same with dtaFuel fuel and dtaShield shield points (-1 = full) when the dock opens.
Sub DT_ScriptAt (dtaCredits As Long, dtaFuel As Single, dtaShield As Integer, dtaLines As String)
    Dim dtsP As Integer, dtsQ As Integer, dtsOk As Integer
    UPG_Reset
    credits = dtaCredits
    If dtaShield < 0 Then lives = shieldMax Else lives = dtaShield
    If dtaFuel < 0 Then fuelLevel = fuelMax Else fuelLevel = dtaFuel
    DOCK_Open
    ISC_Clear
    For dtsP = 0 To 32767 : held(dtsP) = 0 : Next dtsP
    dtsP = 1
    Do While dtsP <= Len(dtaLines)
        dtsQ = InStr(dtsP, dtaLines, "/")
        If dtsQ = 0 Then dtsQ = Len(dtaLines) + 1
        dtsOk = ISC_ParseLine%(Mid$(dtaLines, dtsP, dtsQ - dtsP))
        If dtsOk = 0 Then Print "bad script line: "; iscError
        dtsP = dtsQ + 1
    Loop
End Sub

' Runs frames 0..dtrLast like the main loop; stops after the frame the dock is left.
' Returns that frame, or -1 if it never left.
Function DT_Run% (dtrLast As Integer)
    Dim dtrF As Integer
    DT_Run% = -1
    For dtrF = 0 To 199 : dtRes(dtrF) = DOCK_NONE : Next dtrF
    For dtrF = 0 To dtrLast
        KEY_FrameBegin
        ISC_Apply dtrF, held()
        dtRes(dtrF) = DOCK_Input%
        If dtRes(dtrF) = DOCK_LEAVE Then DT_Run% = dtrF : Exit Function
    Next dtrF
End Function

' How many frames of the last run gave result dcRes (each one plays one sound in DOCK_Update).
Function DT_Count% (dcRes As Integer)
    Dim dcF As Integer, dcN As Integer
    For dcF = 0 To 199
        If dtRes(dcF) = dcRes Then dcN = dcN + 1
    Next dcF
    DT_Count% = dcN
End Function

Dim dtLeft As Integer, dtI As Integer, dtN As Integer

Print "=== dock_test ==="
Print ""
cfgEconomy = CFG_Parse$(_EMBEDDED$("CFGECONOMY"))
cfgUpgrades = CFG_Parse$(_EMBEDDED$("CFGUPGRADES"))
cfgAbilities = CFG_Parse$(_EMBEDDED$("CFGABILITIES"))
DT_Assert UPG_Load% <> 0, "upgrade table loads"
DT_Assert SUP_Load% <> 0, "supply prices load"
levelNum = 2 : dtLegKills = 10 : dtLegBoss = 1   ' the dock after chapter 2: fuel $2.80 a unit
DT_Assert DOCK_REFUEL = 1 And DOCK_SHIELDS = 2 And DOCK_LAUNCH = UPG_COUNT + 3, "rows: REFUEL, SHIELDS, the" + Str$(UPG_COUNT) + " upgrades, LAUNCH"

Print ""
Print "--- navigate and buy ---"
DT_Script 100, "2 2 S/4 4 S/6 6 DOWN/8 8 UP/10 10 ENTER/12 12 ENTER/14 14 PAD_DOWN/16 16 PAD_A/18 18 PAD_DPAD_UP/20 20 W/22 22 UP/24 24 UP/26 26 ENTER"
dtLeft = DT_Run%(40)
DT_Assert dtRes(2) = DOCK_MOVED And dtRes(6) = DOCK_MOVED, "S and DOWN move the cursor"
DT_Assert dtRes(10) = DOCK_BOUGHT, "ENTER on LASER CAPACITOR buys it"
DT_Assert upgLevel(UPG_LASER) = 1 And credits = 20, "laser capacitor 1 installed, 80 spent, 20 left"
DT_Assert dtRes(12) = DOCK_NOFUNDS, "ENTER again: level 2 costs 150, not enough credits"
DT_Assert upgLevel(UPG_LASER) = 1 And credits = 20, "nothing bought, nothing charged"
DT_Assert dockMsg = "NOT ENOUGH CREDITS" And dockMsgBad <> 0, "the dock says so"
DT_Assert dtRes(14) = DOCK_MOVED And dtRes(16) = DOCK_NOFUNDS, "stick down + pad A on TWIN CANNONS ($200): not enough credits"
DT_Assert dtRes(18) = DOCK_MOVED And dtRes(20) = DOCK_MOVED, "d-pad up and W move up"
DT_Assert dtRes(24) = DOCK_MOVED And dockSel = DOCK_LAUNCH, "up from the top row (REFUEL) wraps to LAUNCH"
DT_Assert dtLeft = 26, "ENTER on LAUNCH leaves the dock"

Print ""
Print "--- a held ENTER buys once ---"
DT_Script 1000, "1 1 DOWN/3 3 DOWN/5 40 ENTER"
dtLeft = DT_Run%(50)
dtN = 0
For dtI = 0 To 50
    If dtRes(dtI) = DOCK_BOUGHT Then dtN = dtN + 1
Next dtI
DT_Assert dtN = 1 And upgLevel(UPG_LASER) = 1 And credits = 920, "one purchase for one press"
DT_Assert dtLeft = -1, "and the dock stays open"

Print ""
Print "--- max level ---"
DT_Script 10000, "2 2 DOWN/4 4 DOWN/6 6 ENTER/8 8 ENTER/10 10 ENTER/12 12 ENTER"
dtLeft = DT_Run%(14)
DT_Assert upgLevel(UPG_LASER) = 3 And dtRes(12) = DOCK_MAXED, "fourth ENTER on a 3-level upgrade: already at max"
DT_Assert credits = 10000 - 80 - 150 - 250, "only three levels charged"

Print ""
Print "--- scrolling ---"
DT_Script 0, "2 2 S/4 4 S/6 6 S/8 8 S/10 10 S/12 12 S/14 14 S/16 16 S/18 18 S"
dtLeft = DT_Run%(20)
DT_Assert dockSel = 10 And dockTop = 10 - DOCK_VISIBLE + 1, "9 downs: cursor on row 10, list scrolled to keep it in view"

Print ""
Print "--- one sound per press (no double trigger) ---"
DT_Script 1000, "2 31 DOWN"
dtLeft = DT_Run%(40) : DT_Assert DT_Count%(DOCK_MOVED) = 1, "DOWN held 30 frames: one move"
DT_Script 1000, "2 31 S"
dtLeft = DT_Run%(40) : DT_Assert DT_Count%(DOCK_MOVED) = 1, "S held 30 frames: one move"
DT_Script 1000, "2 31 PAD_DPAD_DOWN"
dtLeft = DT_Run%(40) : DT_Assert DT_Count%(DOCK_MOVED) = 1, "d-pad held 30 frames: one move"
DT_Script 1000, "2 31 PAD_DOWN"
dtLeft = DT_Run%(40) : DT_Assert DT_Count%(DOCK_MOVED) = 1, "stick held 30 frames: one move"
DT_Script 1000, "2 31 DOWN PAD_DOWN S"
dtLeft = DT_Run%(40) : DT_Assert DT_Count%(DOCK_MOVED) = 1 And dockSel = 2, "arrow + stick + S together: still one move, one row"
DT_ScriptAt 1000, 50, -1, "2 31 ENTER PAD_A"
dtLeft = DT_Run%(40) : DT_Assert DT_Count%(DOCK_BOUGHT) = 1 And DT_Count%(DOCK_NOFUNDS) + DT_Count%(DOCK_FULL) = 0, "ENTER + pad A held on REFUEL: one purchase, one sound"
DT_ScriptAt 1000, 0, -1, "2 31 RIGHT PAD_RIGHT D"
dtLeft = DT_Run%(40) : DT_Assert DT_Count%(DOCK_MOVED) = 0 And dockAmt(SUP_FUEL) = 100, "RIGHT + stick + D held on a full amount: nothing to add"
DT_ScriptAt 1000, 0, -1, "2 31 LEFT PAD_LEFT A"
dtLeft = DT_Run%(40) : DT_Assert DT_Count%(DOCK_MOVED) = 1 And dockAmt(SUP_FUEL) = 90, "LEFT + stick + A held 30 frames: one step"

Print ""
Print "--- fuel by the amount (#277) ---"
DT_ScriptAt 1000, 40, -1, ""
DT_Assert dockSel = DOCK_REFUEL And dockAmt(SUP_FUEL) = 60, "the dock opens on REFUEL, set to fill the tank (60 missing, affordable)"
DT_ScriptAt 1000, 40, -1, "2 2 LEFT/4 4 LEFT/6 6 RIGHT/8 8 ENTER"
dtLeft = DT_Run%(10)
DT_Assert dtRes(2) = DOCK_MOVED And dtRes(4) = DOCK_MOVED And dtRes(6) = DOCK_MOVED, "LEFT, LEFT, RIGHT: 60 -> 50 -> 40 -> 50"
DT_Assert dtRes(8) = DOCK_BOUGHT And Int(fuelLevel + 0.5) = 90 And credits = 860, "ENTER buys 50 fuel at $2.80: $140, tank 40 -> 90"
DT_Assert dockMsg = "BOUGHT 50 FUEL" And dockMsgBad = 0, "the dock says BOUGHT 50 FUEL (" + dockMsg + ")"
DT_Assert dockAmt(SUP_FUEL) = 10, "after a buy the amount goes back to filling what's left (10)"
DT_ScriptAt 1000, 95, -1, "2 2 RIGHT/4 4 LEFT"
dtLeft = DT_Run%(6)
DT_Assert dtRes(2) = DOCK_NONE And dtRes(4) = DOCK_MOVED And dockAmt(SUP_FUEL) = 1, "5 missing: RIGHT can't add more; LEFT stops at 1"
DT_ScriptAt 50, 0, -1, "2 2 ENTER/4 4 ENTER"
DT_Assert dockAmt(SUP_FUEL) = 18, "$50 and an empty tank: the amount is what $50 buys (18)"
dtLeft = DT_Run%(6)
DT_Assert dtRes(2) = DOCK_BOUGHT And Int(fuelLevel + 0.5) = 18 And credits = 0, "one ENTER: 18 fuel, every credit spent"
DT_Assert dockAmt(SUP_FUEL) = 82 And dtRes(4) = DOCK_NOFUNDS, "broke: the amount shows the whole gap, and ENTER says not enough credits"
DT_Script 1000, "2 2 ENTER"
dtLeft = DT_Run%(4)
DT_Assert dtRes(2) = DOCK_FULL And credits = 1000 And dockMsg = "TANK ALREADY FULL", "a full tank: refused, nothing charged, TANK ALREADY FULL"

Print ""
Print "--- shields by the amount (#277) ---"
DT_ScriptAt 500, -1, 30, "2 2 DOWN/4 4 ENTER"
dtLeft = DT_Run%(6)
DT_Assert dtRes(4) = DOCK_BOUGHT And lives = shieldMax And credits = 430, "70 shield points at $1: $70, shields 30 -> 100"
DT_Assert dockMsg = "REPAIRED 70 SHIELD", "the dock says REPAIRED 70 SHIELD (" + dockMsg + ")"
DT_Script 500, "2 2 DOWN/4 4 ENTER"
dtLeft = DT_Run%(6)
DT_Assert dtRes(4) = DOCK_FULL And credits = 500 And dockMsg = "SHIELDS ALREADY FULL", "full shields: refused, nothing charged"
DT_Script 500, "2 2 DOWN/4 4 DOWN/6 6 RIGHT/8 8 LEFT"
dtLeft = DT_Run%(10)
DT_Assert dtRes(6) = DOCK_NONE And dtRes(8) = DOCK_NONE And credits = 500, "LEFT / RIGHT on an upgrade row do nothing"

Print ""
Print "--- stranded: no fuel, no credits, no way out (#277) ---"
DT_ScriptAt 0, 10, -1, "2 2 UP/4 4 ENTER/6 6 ESC/8 8 UP/10 10 DOWN/12 12 LEFT/14 14 PAD_B/16 16 PAD_START/18 18 RIGHT/20 20 ENTER"
dtLeft = DT_Run%(24)
DT_Assert dtRes(4) = DOCK_ASK And dockAsk <> 0, "LAUNCH with 10 fuel, $0 and a 55-fuel jump ahead: the stranded dialog"
DT_Assert dtRes(6) = DOCK_NONE And dtRes(14) = DOCK_NONE And dtRes(16) = DOCK_NONE, "ESC, pad B and pad Start do nothing there"
DT_Assert dtRes(8) = DOCK_NONE And dtRes(10) = DOCK_NONE And dtRes(12) = DOCK_NONE And dtRes(18) = DOCK_NONE And dockSel = DOCK_LAUNCH, "nor do up, down, left or right"
DT_Assert dtRes(20) = DOCK_STRANDED And dtLeft = -1, "ENTER on [ YES ] ends the run (the dock never just leaves)"
DT_ScriptAt 0, 10, -1, "2 2 PAD_B/4 4 PAD_A"
dtLeft = DT_Run%(6)
DT_Assert dtRes(2) = DOCK_ASK And dtRes(4) = DOCK_STRANDED, "leaving with pad B asks too; pad A answers YES"
DT_ScriptAt 126, 10, -1, "2 2 ESC"
DT_Assert DT_Run%(4) = 2, "10 fuel + $126 (45 units at $2.80) reaches 55 exactly: leaves"
DT_ScriptAt 125, 10, -1, "2 2 ESC"
dtLeft = DT_Run%(4)
DT_Assert dtRes(2) = DOCK_ASK, "$125 buys only 44: stranded"
DT_ScriptAt 0, 60, -1, "2 2 ESC"
DT_Assert DT_Run%(4) = 2, "broke but 60 in the tank: leaves"
godMode = -1
DT_ScriptAt 0, 0, -1, "2 2 ESC"
DT_Assert DT_Run%(4) = 2, "god mode: never stranded"
godMode = 0
dtLegKills = 0 : dtLegBoss = 0
DT_ScriptAt 0, 0, -1, "2 2 ESC"
DT_Assert DT_Run%(4) = 2, "no jump ahead (the last dock): never stranded"
dtLegKills = 10 : dtLegBoss = 1
DT_ScriptAt 0, 10, -1, "2 2 ESC"
dtLeft = DT_Run%(4)
DOCK_Open
DT_Assert dockAsk = 0, "the next dock opens without the dialog"

Print ""
Print "--- skip in one press ---"
DT_Script 500, "5 5 ESC"
DT_Assert DT_Run%(20) = 5 And credits = 500, "ESC leaves at once, nothing bought"
DT_Script 500, "5 5 PAD_B"
DT_Assert DT_Run%(20) = 5, "pad B leaves at once"
DT_Script 500, "5 5 PAD_START"
DT_Assert DT_Run%(20) = 5, "pad Start leaves at once"
DT_Script 500, "0 30 FIRE"
DT_Assert DT_Run%(30) = -1 And credits = 500, "FIRE held from the stage (SPACE / pad fire) neither buys nor leaves"

Print ""
Print "--- each visit ---"
UPG_Reset
credits = 1000
DT_Assert UPG_Buy%(UPG_NOVA) = UPG_OK, "nova bought"
novaCharges = 0
DOCK_Open
DT_Assert novaCharges = novaMax And dockSel = 1 And dockTop = 1, "opening the dock refills nova and puts the cursor on the first row"

Print ""
Print "--- info lines name the bound keys (#287) ---"
DT_Assert InStr(UPG_Info$(UPG_NOVA), UI_Tok$("", E3D_ACT_NOVA)) = 1 And InStr(UPG_Info$(UPG_ROLL), UI_Tok$("", E3D_ACT_ROLL)) = 1, "nova and roll info lines open with their action's key token"
E3D_KeyDefaults
keyBind(E3D_ACT_NOVA) = Asc("k")
DT_Assert Left$(UI_PromptsKeyText$(UPG_Info$(UPG_NOVA)), 2) = "K:", "nova rebound to K: the dock's nova line reads K: (" + UI_PromptsKeyText$(UPG_Info$(UPG_NOVA)) + ")"
E3D_KeyDefaults

Print ""
Print "=== " + LTrim$(Str$(dtPassed + dtFailed)) + " tests: " + LTrim$(Str$(dtPassed)) + " passed, " + LTrim$(Str$(dtFailed)) + " failed ==="
If dtFailed > 0 Then System 1
System 0
