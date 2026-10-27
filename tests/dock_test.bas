' dock_test.bas -- the upgrade dock driven by scripted input (src/state/docklogic.bas, #268)
'
' Plays input scripts through the real input path (ISC_Apply -> held() -> KEY_Pressed% /
' KEY_Confirm% / KEY_Back%) into the real DOCK_Input% each frame, as the game does, with
' the real upgrade table from assets/config/: navigating (keys, W/S, stick, d-pad,
' wrap-around, scrolling), buying, a purchase it can't afford, a held ENTER buying once,
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

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/inputscript.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/upgrades.bas'
'$INCLUDE:'../src/state/docklogic.bas'

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

' Fresh dock with dtsCredits, then the script lines (separated by "/").
Sub DT_Script (dtsCredits As Long, dtsLines As String)
    Dim dtsP As Integer, dtsQ As Integer, dtsOk As Integer
    UPG_Reset
    credits = dtsCredits
    lives = shieldMax
    DOCK_Open
    ISC_Clear
    For dtsP = 0 To 32767 : held(dtsP) = 0 : Next dtsP
    dtsP = 1
    Do While dtsP <= Len(dtsLines)
        dtsQ = InStr(dtsP, dtsLines, "/")
        If dtsQ = 0 Then dtsQ = Len(dtsLines) + 1
        dtsOk = ISC_ParseLine%(Mid$(dtsLines, dtsP, dtsQ - dtsP))
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

Dim dtLeft As Integer, dtI As Integer, dtN As Integer

Print "=== dock_test ==="
Print ""
cfgEconomy = CFG_Parse$(_EMBEDDED$("CFGECONOMY"))
cfgUpgrades = CFG_Parse$(_EMBEDDED$("CFGUPGRADES"))
cfgAbilities = CFG_Parse$(_EMBEDDED$("CFGABILITIES"))
DT_Assert UPG_Load% <> 0, "upgrade table loads"

Print ""
Print "--- navigate and buy ---"
DT_Script 100, "2 2 DOWN/4 4 UP/6 6 ENTER/8 8 ENTER/10 10 PAD_DOWN/12 12 PAD_A/14 14 PAD_DPAD_UP/16 16 W/18 18 ENTER"
dtLeft = DT_Run%(30)
DT_Assert dtRes(2) = DOCK_MOVED, "DOWN moves the cursor"
DT_Assert dtRes(6) = DOCK_BOUGHT, "ENTER on LASER CAPACITOR buys it"
DT_Assert upgLevel(UPG_LASER) = 1 And credits = 20, "laser capacitor 1 installed, 80 spent, 20 left"
DT_Assert dtRes(8) = DOCK_NOFUNDS, "ENTER again: level 2 costs 150, not enough credits"
DT_Assert upgLevel(UPG_LASER) = 1 And credits = 20, "nothing bought, nothing charged"
DT_Assert dockMsg = "NOT ENOUGH CREDITS" And dockMsgBad <> 0, "the dock says so"
DT_Assert dtRes(10) = DOCK_MOVED And dtRes(12) = DOCK_NOFUNDS, "stick down + pad A on TWIN CANNONS ($200): not enough credits"
DT_Assert dtRes(14) = DOCK_MOVED And dtRes(16) = DOCK_MOVED, "d-pad up and W move up"
DT_Assert dockSel = DOCK_LAUNCH, "up from the top row wraps to LAUNCH"
DT_Assert dtLeft = 18, "ENTER on LAUNCH leaves the dock"

Print ""
Print "--- a held ENTER buys once ---"
DT_Script 1000, "3 40 ENTER"
dtLeft = DT_Run%(50)
dtN = 0
For dtI = 0 To 50
    If dtRes(dtI) = DOCK_BOUGHT Then dtN = dtN + 1
Next dtI
DT_Assert dtN = 1 And upgLevel(UPG_LASER) = 1 And credits = 920, "one purchase for one press"
DT_Assert dtLeft = -1, "and the dock stays open"

Print ""
Print "--- max level ---"
DT_Script 10000, "2 2 ENTER/4 4 ENTER/6 6 ENTER/8 8 ENTER"
dtLeft = DT_Run%(10)
DT_Assert upgLevel(UPG_LASER) = 3 And dtRes(8) = DOCK_MAXED, "fourth ENTER on a 3-level upgrade: already at max"
DT_Assert credits = 10000 - 80 - 150 - 250, "only three levels charged"

Print ""
Print "--- scrolling ---"
DT_Script 0, "2 2 S/4 4 S/6 6 S/8 8 S/10 10 S/12 12 S/14 14 S/16 16 S/18 18 S"
dtLeft = DT_Run%(20)
DT_Assert dockSel = 10 And dockTop = 10 - DOCK_VISIBLE + 1, "9 downs: cursor on row 10, list scrolled to keep it in view"

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
Print "=== " + LTrim$(Str$(dtPassed + dtFailed)) + " tests: " + LTrim$(Str$(dtPassed)) + " passed, " + LTrim$(Str$(dtFailed)) + " failed ==="
If dtFailed > 0 Then System 1
System 0
