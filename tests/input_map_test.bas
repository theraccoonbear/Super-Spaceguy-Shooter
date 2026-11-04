' input_map_test.bas -- which input does what, per screen family (#426)
'
' Proceed = ENTER / pad A (flow screens also take the fire key), Back = ESC / pad B, Menu = ESC /
' pad Start inside a run. Scripted input goes through the real path (ISC_Apply -> held() ->
' KEY_*), into the shared helpers, then into the screens' own input functions: the title's
' toggles, LAUNCH NOW?, the data notice, a crawl's skip, the pause dialog and the dock's menu
' (open, cancel, quit, controls, launch).
'
' Build: ./tools/buildqb tests/input_map_test.bas
' Run:   builds/input_map_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/config/economy.ini':'CFGECONOMY'
$EMBED:'assets/config/upgrades.ini':'CFGUPGRADES'
$EMBED:'assets/config/abilities.ini':'CFGABILITIES'
$EMBED:'assets/config/difficulty.ini':'CFGDIFFICULTY'

Sub DBG_Print (imDbg As String) : End Sub
Sub TELEM_UpgradeBought (imItem As String, imLevel As Integer, imPrice As Long) : End Sub
Sub TELEM_CreditBonus (imC As Long, imR As Double, imP As Long) : End Sub
Sub TELEM_FuelBought (imA As Integer, imP As Long, imU As Single, imM As Single, imC As Integer) : End Sub
Sub TELEM_ShieldBought (imA As Integer, imP As Long, imC As Integer) : End Sub
Sub SEQ_NextLeg (imK As Long, imBS As Single, imB As Integer, imA As Integer)
    imK = 10 : imBS = 0 : imB = 0 : imA = 0
End Sub

'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/inputscript.bas'
'$INCLUDE:'../src/sys/menunav.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/credits.bas'
'$INCLUDE:'../src/gameplay/upgrades.bas'
'$INCLUDE:'../src/gameplay/supplies.bas'
'$INCLUDE:'../src/state/pauselogic.bas'
'$INCLUDE:'../src/state/docklogic.bas'
'$INCLUDE:'../src/state/consentlogic.bas'
'$INCLUDE:'../src/state/launchlogic.bas'

Dim Shared imPassed As Integer, imFailed As Integer

Sub IM_Assert (imaCond As Integer, imaName As String)
    If imaCond Then
        Print "PASS  " + imaName
        imPassed = imPassed + 1
    Else
        Print "FAIL  " + imaName
        imFailed = imFailed + 1
    End If
End Sub

' Fresh script from lines separated by "/".
Sub IM_Script (imsLines As String)
    Dim imsP As Integer, imsQ As Integer, imsOk As Integer
    ISC_Clear
    iscActive = -1
    For imsP = 0 To 32767 : held(imsP) = 0 : keyPrevHeld(imsP) = 0 : Next imsP
    imsP = 1
    Do While imsP <= Len(imsLines)
        imsQ = InStr(imsP, imsLines, "/")
        If imsQ = 0 Then imsQ = Len(imsLines) + 1
        imsOk = ISC_ParseLine%(Mid$(imsLines, imsP, imsQ - imsP))
        If imsOk = 0 Then Print "bad script line: "; iscError
        imsP = imsQ + 1
    Loop
End Sub

Sub IM_Frame (imfF As Long)
    KEY_FrameBegin
    ISC_Apply imfF, held()
End Sub

' The four shared actions on the frame the input goes down: "C P B M" as 0/1 digits.
Function IM_Acts$ (imaKey As String)
    Dim imaOut As String
    IM_Script "3 3 " + imaKey
    IM_Frame 0 : IM_Frame 1 : IM_Frame 2 : IM_Frame 3
    imaOut = LTrim$(Str$(Abs(KEY_Confirm%))) + LTrim$(Str$(Abs(KEY_Proceed%))) + LTrim$(Str$(Abs(KEY_Back%))) + LTrim$(Str$(Abs(KEY_Menu%)))
    IM_Acts$ = imaOut
End Function

' Dock from a fresh visit: runs frames 0..imdLast of the script through DOCK_Frame%; returns
' the last result seen that wasn't NONE/MOVED/PAUSED, or the last result if none.
Dim Shared imDockRes(0 To 99) As Integer

Sub IM_Dock (imdScript As String, imdLast As Integer)
    Dim imdF As Integer
    UPG_Reset
    credits = 500 : lives = shieldMax : fuelLevel = fuelMax : levelNum = 2
    DOCK_Open
    escConfirm = 0 : escWas = 0 : pauseSel = PAUSE_ROW_CANCEL
    IM_Script imdScript
    For imdF = 0 To imdLast
        IM_Frame imdF
        imDockRes(imdF) = DOCK_Frame%
    Next imdF
End Sub

Dim imF As Integer

Print "=== input_map_test ==="
Print ""
cfgEconomy = CFG_Parse$(_EMBEDDED$("CFGECONOMY"))
cfgUpgrades = CFG_Parse$(_EMBEDDED$("CFGUPGRADES"))
cfgAbilities = CFG_Parse$(_EMBEDDED$("CFGABILITIES"))
IM_Assert UPG_Load% <> 0 And SUP_Load% <> 0, "upgrade and supply tables load"
E3D_KeyDefaults
E3D_PadSelect "Microsoft X-Box 360 pad", 11, 8

Print ""
Print "--- the shared actions (confirm, proceed, back, menu) ---"
IM_Assert IM_Acts$("ENTER") = "1100", "ENTER: confirm + proceed"
IM_Assert IM_Acts$("PAD_A") = "1100", "pad A: confirm + proceed"
IM_Assert IM_Acts$("SPACE") = "0100", "SPACE (fire): proceed on flow screens only"
IM_Assert IM_Acts$("ESC") = "0011", "ESC: back + menu"
IM_Assert IM_Acts$("PAD_START") = "0011", "pad Start: back + menu (it shares ESC's slot)"
IM_Assert IM_Acts$("PAD_B") = "0010", "pad B: back only; it fires too but never proceeds or opens the menu"

Print ""
Print "--- title root ---"
IM_Assert NAV_TitleToggle%(-1, 0, 0, 0, 0, 0) <> 0, "ESC opens the command console"
IM_Assert NAV_TitleToggle%(-1, 0, 0, 0, -1, 0) <> 0, "ESC closes it again"
IM_Assert NAV_TitleToggle%(0, 0, 0, -1, 0, 0) <> 0, "pad B opens it"
IM_Assert NAV_TitleToggle%(0, 0, 0, -1, -1, 0) = 0, "pad B inside it is the cancel row, not a toggle"
IM_Assert NAV_TitleToggle%(0, 0, -1, 0, 0, 0) <> 0, "pad Select opens it"
IM_Assert NAV_TitleToggle%(-1, -1, 0, 0, 0, 0) = 0, "pad Start (which sets ESC too) does not open it"
IM_Assert NAV_TitleToggle%(-1, 0, 0, 0, 0, -1) = 0 And NAV_TitleToggle%(0, 0, 0, -1, 0, -1) = 0, "nothing opens it while LAUNCH NOW? is up"
IM_Assert NAV_TitleGo%(-1, 0, 0) <> 0, "P or pad Start start the launch confirm"
IM_Assert NAV_TitleGo%(0, -1, 0) <> 0, "ENTER or pad A start it"
IM_Assert NAV_TitleGo%(0, -1, -1) = 0, "ENTER or A while it is up don't re-open it (they pick the row)"

Print ""
Print "--- LAUNCH NOW? ---"
launchOpen = 0 : launchSel = LAUNCH_ROW_YES : pWas = 0
IM_Script "2 2 ENTER/5 5 ENTER"
IM_Frame 0 : IM_Frame 1
IM_Assert LAUNCH_Input%(NAV_TitleGo%(0, KEY_Confirm%, launchOpen)) = LAUNCH_NONE And launchOpen = 0, "setup: nothing yet"
IM_Frame 2
IM_Assert LAUNCH_Input%(NAV_TitleGo%(0, KEY_Confirm%, launchOpen)) = LAUNCH_NONE And launchOpen <> 0, "ENTER on the title opens LAUNCH NOW?"
IM_Frame 3 : IM_Frame 4
IM_Assert LAUNCH_Input%(NAV_TitleGo%(0, KEY_Confirm%, launchOpen)) = LAUNCH_NONE, "still open"
IM_Frame 5
IM_Assert LAUNCH_Input%(NAV_TitleGo%(0, KEY_Confirm%, launchOpen)) = LAUNCH_YES, "a second ENTER, on YES, launches"
launchOpen = 0 : launchSel = LAUNCH_ROW_YES : pWas = 0
IM_Script "2 2 PAD_A/5 5 PAD_B"
IM_Frame 2
imF = LAUNCH_Input%(NAV_TitleGo%(0, KEY_Confirm%, launchOpen))
IM_Frame 5
IM_Assert LAUNCH_Input%(NAV_TitleGo%(0, KEY_Confirm%, launchOpen)) = LAUNCH_NO, "pad A opens it, pad B backs out"

Print ""
Print "--- data notice ---"
consentSel = 0
IM_Script "1 1 ENTER"
IM_Frame 1
IM_Assert CONSENT_Input% = CONSENT_OK, "ENTER takes OK"
consentSel = 0
IM_Script "1 1 SPACE"
IM_Frame 1
IM_Assert CONSENT_Input% = CONSENT_OK, "SPACE takes OK"
consentSel = 0
IM_Script "1 1 PAD_B"
IM_Frame 1
IM_Assert CONSENT_Input% = CONSENT_NO, "pad B is NO THANKS"

Print ""
Print "--- crawls ---"
IM_Assert NAV_CrawlSkip%(-1, 0, 0, -1, 0) <> 0, "in a run: ENTER skips"
IM_Assert NAV_CrawlSkip%(0, -1, -1, -1, 0) <> 0, "in a run: pad B skips"
IM_Assert NAV_CrawlSkip%(0, 0, -1, -1, 0) = 0, "in a run: ESC / Start skip nothing (they open the menu)"
IM_Assert NAV_CrawlSkip%(0, 0, -1, 0, 0) <> 0, "outside a run: ESC backs out of the crawl"
IM_Assert NAV_CrawlSkip%(-1, -1, -1, -1, -1) = 0, "never on the frame the in-run menu closes"
IM_Script "1 1 PAD_A"
IM_Frame 1
IM_Assert NAV_CrawlSkip%(KEY_Pressed%(E3D_KEY_ENTER), KEY_Pressed%(E3D_KEY_PAD_B), KEY_Back%, 0, 0) = 0, "pad A (fast-forward) does not skip"

Print ""
Print "--- the in-run menu (pause dialog) ---"
escConfirm = 0 : escWas = 0 : pauseSel = PAUSE_ROW_RETREAT
IM_Script "2 2 ESC/6 6 ENTER"
IM_Frame 2
imF = PAUSE_Input%
IM_Assert escConfirm <> 0 And pauseShown <> 0 And pauseSel = PAUSE_ROW_CANCEL, "ESC opens it on CANCEL"
IM_Frame 6
imF = PAUSE_Input%
IM_Assert escConfirm = 0, "ENTER on CANCEL closes it"
escConfirm = 0 : escWas = 0
IM_Script "2 2 PAD_START/6 6 PAD_B"
IM_Frame 2
imF = PAUSE_Input%
IM_Assert escConfirm <> 0, "pad Start opens it"
IM_Frame 6
imF = PAUSE_Input%
IM_Assert escConfirm = 0, "pad B closes it"

Print ""
Print "--- the dock ---"
IM_Dock "5 5 ENTER", 6
IM_Assert imDockRes(5) = DOCK_BOUGHT Or imDockRes(5) = DOCK_FULL, "ENTER acts on the highlighted row (REFUEL)"
IM_Dock "5 5 ESC/10 10 ENTER", 12
IM_Assert imDockRes(5) = DOCK_PAUSED, "ESC opens the menu and the dock is frozen"
IM_Assert imDockRes(10) = DOCK_NONE And escConfirm = 0 And credits = 500, "ENTER on CANCEL closes it without buying"
IM_Dock "5 5 PAD_START/10 10 PAD_B/14 14 ENTER", 16
IM_Assert imDockRes(5) = DOCK_PAUSED And escConfirm = 0, "pad Start opens it, pad B cancels"
IM_Assert imDockRes(14) <> DOCK_LEAVE And dockSel = 1, "cancelling leaves the cursor where it was"
IM_Dock "5 5 ESC/10 10 UP/12 12 UP/14 14 UP/16 16 ENTER", 18
IM_Assert imDockRes(16) = DOCK_QUIT, "CONFIRM RETREAT quits the run"
IM_Dock "5 5 ESC/10 10 C", 12
IM_Assert imDockRes(10) = DOCK_CONTROLS, "C opens Controls from the menu"
IM_Dock "5 5 ESC/10 10 K", 12
IM_Assert imDockRes(10) = DOCK_REMAP, "K opens Remap from the menu"
IM_Dock "5 5 L", 6
IM_Assert imDockRes(5) = DOCK_LEAVE, "L launches"
IM_Dock "5 5 PAD_Y", 6
IM_Assert imDockRes(5) = DOCK_LEAVE, "pad Y launches"
IM_Dock "5 5 ESC/8 8 L", 10
IM_Assert imDockRes(8) <> DOCK_LEAVE, "L does nothing while the menu is up"
IM_Dock "5 5 PAD_B/8 8 ESC", 10
IM_Assert imDockRes(5) <> DOCK_LEAVE, "pad B does not launch"
UPG_Reset

Print ""
Print "=== " + LTrim$(Str$(imPassed + imFailed)) + " tests: " + LTrim$(Str$(imPassed)) + " passed, " + LTrim$(Str$(imFailed)) + " failed ==="
If imFailed > 0 Then System 1
System 0
