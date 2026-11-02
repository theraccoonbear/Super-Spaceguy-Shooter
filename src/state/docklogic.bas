' docklogic.bas -- the upgrade dock's list and input, without drawing (#268)
'
' Row DOCK_REFUEL and DOCK_SHIELDS sell fuel and shields by the amount (supplies.bas, #277),
' rows DOCK_UPG0 + 1 .. DOCK_UPG0 + UPG_COUNT are the upgrades, row DOCK_LAUNCH leaves.
' dock.bas draws it and calls DOCK_Input% once per frame; tests call DOCK_Input% (scripted
' input) or DOCK_Step% (plain flags) directly.
'   DOCK_Open                      entering the dock: cursor on the first row, per-visit refills
'   r = DOCK_Step%(up, dn, lf, rt, buy, back)
'   w = DOCK_TankWarn%(over, tick) -1 on the frames the fuel line shows DOCK_TankWarnText$(tank)
'                                  instead of NEXT JUMP NEEDS (only when the jump is longer
'                                  than the tank: SUP_OverTank%)
'   r = DOCK_Input%                reads up/down/left/right (arrows, W/S/A/D, stick, d-pad),
'                                  ENTER / pad A to buy, ESC / pad B / pad Start to leave
' A supply row's amount (dockAmt) starts at what the credits fill, and goes back there after
' every purchase; LEFT / RIGHT change it by SUP_Step% within 1..what's missing.
' Leaving (LAUNCH or back) when even every credit spent on fuel won't reach the next planet
' (SUP_Stranded%) opens the stranded dialog instead (dockAsk, DOCK_ASK): its one answer is
' YES, so only ENTER / pad A does anything there, and it ends the run (DOCK_STRANDED).
' Results: DOCK_NONE, DOCK_MOVED, DOCK_BOUGHT, DOCK_NOFUNDS, DOCK_MAXED, DOCK_FULL, DOCK_LEAVE,
'          DOCK_ASK, DOCK_STRANDED
' Local variable prefix: dk*

Const DOCK_REFUEL  = 1
Const DOCK_SHIELDS = 2
Const DOCK_UPG0    = 2     ' upgrade id = row - DOCK_UPG0
Const DOCK_LAUNCH  = DOCK_UPG0 + UPG_COUNT + 1
Const DOCK_VISIBLE = 7     ' list rows on screen; the list scrolls to keep the cursor in view
Const DOCK_NONE    = 0
Const DOCK_MOVED   = 1
Const DOCK_BOUGHT  = 2
Const DOCK_NOFUNDS = 3
Const DOCK_MAXED   = 4
Const DOCK_FULL    = 5
Const DOCK_LEAVE   = 6
Const DOCK_ASK     = 7
Const DOCK_STRANDED = 8
Const DOCK_TANKWARN_FRAMES = 90   ' a jump longer than the tank: NEXT JUMP NEEDS and UPGRADE TANK take turns this long

Dim Shared dockSel As Integer, dockTop As Integer
Dim Shared dockMsg As String, dockMsgTimer As Integer, dockMsgBad As Integer
Dim Shared dockAmt(1 To 2) As Integer   ' amount on the REFUEL / SHIELDS rows (SUP_FUEL / SUP_SHIELD)
Dim Shared dockAsk As Integer          ' -1 = the stranded dialog is up

Sub DOCK_Open
    dockSel = 1 : dockTop = 1
    dockMsg = "" : dockMsgTimer = 0 : dockMsgBad = 0 : dockAsk = 0
    UPG_DockVisit
    DOCK_ResetAmts
End Sub

' Each supply row back to "fill what the credits buy"; with nothing affordable, the whole gap
' (its price shows red and ENTER says why).
Sub DOCK_ResetAmts
    Dim dkrK As Integer
    For dkrK = SUP_FUEL To SUP_SHIELD
        dockAmt(dkrK) = SUP_MaxAffordable%(dkrK, levelNum)
        If dockAmt(dkrK) = 0 Then dockAmt(dkrK) = SUP_Missing%(dkrK)
    Next dkrK
End Sub

' The supply a row sells (SUP_FUEL / SUP_SHIELD), 0 for the other rows.
Function DOCK_SupplyOf% (dksoRow As Integer)
    DOCK_SupplyOf% = 0
    If dksoRow = DOCK_REFUEL Then DOCK_SupplyOf% = SUP_FUEL
    If dksoRow = DOCK_SHIELDS Then DOCK_SupplyOf% = SUP_SHIELD
End Function

Sub DOCK_Say (dksMsg As String, dksBad As Integer)
    dockMsg = dksMsg : dockMsgTimer = 120 : dockMsgBad = dksBad
End Sub

Function DOCK_Step% (dkUp As Integer, dkDn As Integer, dkLf As Integer, dkRt As Integer, dkBuy As Integer, dkBack As Integer)
    Dim dkRes As Integer, dkBuyRes As Integer, dkKind As Integer, dkMiss As Integer, dkAmt As Integer
    dkRes = DOCK_NONE
    If dockMsgTimer > 0 Then dockMsgTimer = dockMsgTimer - 1
    If dockAsk Then
        If dkBuy Then DOCK_Step% = DOCK_STRANDED Else DOCK_Step% = DOCK_NONE
        Exit Function
    End If
    If dkBack Then DOCK_Step% = DOCK_TryLeave% : Exit Function
    dkKind = DOCK_SupplyOf%(dockSel)
    If dkUp Then
        dockSel = dockSel - 1 : If dockSel < 1 Then dockSel = DOCK_LAUNCH
        dkRes = DOCK_MOVED
    ElseIf dkDn Then
        dockSel = dockSel + 1 : If dockSel > DOCK_LAUNCH Then dockSel = 1
        dkRes = DOCK_MOVED
    ElseIf (dkLf Or dkRt) And dkKind > 0 Then
        dkMiss = SUP_Missing%(dkKind)
        dkAmt = dockAmt(dkKind)
        If dkLf Then dkAmt = dkAmt - SUP_Step%(dkKind) Else dkAmt = dkAmt + SUP_Step%(dkKind)
        If dkAmt > dkMiss Then dkAmt = dkMiss
        If dkAmt < 1 Then dkAmt = 1
        If dkMiss = 0 Then dkAmt = 0
        If dkAmt <> dockAmt(dkKind) Then dockAmt(dkKind) = dkAmt : dkRes = DOCK_MOVED
    ElseIf dkBuy Then
        If dockSel = DOCK_LAUNCH Then DOCK_Step% = DOCK_TryLeave% : Exit Function
        If dkKind > 0 Then
            dkAmt = dockAmt(dkKind)
            dkBuyRes = SUP_Buy%(dkKind, dkAmt, levelNum)
            Select Case dkBuyRes
                Case SUP_OK
                    dkRes = DOCK_BOUGHT
                    If dkKind = SUP_FUEL Then DOCK_Say "BOUGHT" + Str$(dkAmt) + " FUEL", 0 Else DOCK_Say "REPAIRED" + Str$(dkAmt) + " SHIELD", 0
                Case SUP_NOFUNDS
                    dkRes = DOCK_NOFUNDS
                    DOCK_Say "NOT ENOUGH CREDITS", -1
                Case Else
                    dkRes = DOCK_FULL
                    If dkKind = SUP_FUEL Then DOCK_Say "TANK ALREADY FULL", -1 Else DOCK_Say "SHIELDS ALREADY FULL", -1
            End Select
        Else
            dkBuyRes = UPG_Buy%(dockSel - DOCK_UPG0)
            Select Case dkBuyRes
                Case UPG_OK
                    dkRes = DOCK_BOUGHT
                    DOCK_Say "INSTALLED " + DOCK_BoughtName$(dockSel - DOCK_UPG0), 0
                Case UPG_NOFUNDS
                    dkRes = DOCK_NOFUNDS
                    DOCK_Say "NOT ENOUGH CREDITS", -1
                Case Else
                    dkRes = DOCK_MAXED
                    DOCK_Say "ALREADY AT MAX", -1
            End Select
        End If
        If dkRes = DOCK_BOUGHT Then DOCK_ResetAmts
    End If
    If dockSel < dockTop Then dockTop = dockSel
    If dockSel > dockTop + DOCK_VISIBLE - 1 Then dockTop = dockSel - DOCK_VISIBLE + 1
    DOCK_Step% = dkRes
End Function

' LAUNCH or back: leave, unless the next jump is out of reach (then ask).
Function DOCK_TryLeave%
    If SUP_Stranded% Then dockAsk = -1 : DOCK_TryLeave% = DOCK_ASK Else DOCK_TryLeave% = DOCK_LEAVE
End Function

' Name of what was just bought: the level now owned.
Function DOCK_BoughtName$ (dknId As Integer)
    Dim dknPart(1 To UPG_MAX_LV + 1) As String, dknCnt As Integer, dknI As Integer
    UPG_Split upgNames$(dknId), ",", dknPart(), dknCnt
    dknI = upgLevel(dknId)
    If dknI > dknCnt Then dknI = dknCnt
    If dknI < 1 Then dknI = 1
    DOCK_BoughtName$ = dknPart(dknI)
End Function

Function DOCK_Input%
    Dim dkiUp As Integer, dkiDn As Integer, dkiLf As Integer, dkiRt As Integer, dkiBuy As Integer, dkiBack As Integer
    dkiUp = KEY_Pressed%(E3D_KEY_UP) Or KEY_Pressed%(E3D_KEY_W)
    dkiDn = KEY_Pressed%(E3D_KEY_DOWN) Or KEY_Pressed%(E3D_KEY_S)
    dkiLf = KEY_Pressed%(E3D_KEY_LEFT) Or KEY_Pressed%(E3D_KEY_A)
    dkiRt = KEY_Pressed%(E3D_KEY_RIGHT) Or KEY_Pressed%(E3D_KEY_D)
    dkiBuy = KEY_Confirm%
    dkiBack = KEY_Back%
    DOCK_Input% = DOCK_Step%(dkiUp, dkiDn, dkiLf, dkiRt, dkiBuy, dkiBack)
End Function

Function DOCK_TankWarn% (dtwOver As Integer, dtwTick As Long)
    DOCK_TankWarn% = 0
    If dtwOver = 0 Then Exit Function
    If (dtwTick \ DOCK_TANKWARN_FRAMES) Mod 2 = 1 Then DOCK_TankWarn% = -1
End Function

Function DOCK_TankWarnText$ (dtsMax As Single)
    DOCK_TankWarnText$ = "TANK " + LTrim$(Str$(Int(dtsMax))) + ": UPGRADE TANK"
End Function

' The art each dock row shows (#364): one id per picture in assets/32px/, 0 for a row with none.
' dock.bas loads and draws the pictures; the 13x13 inline row icons will read this same table.
Const DOCK_ART_COUNT   = 14
Const DOCK_ART_REFUEL  = 1
Const DOCK_ART_SHIELDS = 2
Const DOCK_ART_TWIN    = 3
Const DOCK_ART_SPREAD  = 4

' Picture id for upgrade u, indexed by upgrade id; the cannon is resolved by level (DOCK_ArtOf%).
Function DOCK_ArtOfUpgrade% (daouId As Integer)
    Select Case daouId
        Case UPG_LASER : DOCK_ArtOfUpgrade% = 5
        Case UPG_CANNON : DOCK_ArtOfUpgrade% = DOCK_ART_TWIN
        Case UPG_RAPID : DOCK_ArtOfUpgrade% = 6
        Case UPG_SHIELD : DOCK_ArtOfUpgrade% = 7
        Case UPG_REGEN : DOCK_ArtOfUpgrade% = 8
        Case UPG_ARMOUR : DOCK_ArtOfUpgrade% = 9
        Case UPG_NOVA : DOCK_ArtOfUpgrade% = 10
        Case UPG_THRUST : DOCK_ArtOfUpgrade% = 11
        Case UPG_ROLL : DOCK_ArtOfUpgrade% = 12
        Case UPG_TRACTOR : DOCK_ArtOfUpgrade% = 13
        Case UPG_FUEL : DOCK_ArtOfUpgrade% = 14
        Case Else : DOCK_ArtOfUpgrade% = 0
    End Select
End Function

' Picture for a list row: twin cannons until the next level buys the three-way spread, then
' (and when maxed) spread shot; LAUNCH and any other row 0.
Function DOCK_ArtOf% (daoRow As Integer)
    Dim daoU As Integer
    DOCK_ArtOf% = 0
    If daoRow = DOCK_REFUEL Then DOCK_ArtOf% = DOCK_ART_REFUEL : Exit Function
    If daoRow = DOCK_SHIELDS Then DOCK_ArtOf% = DOCK_ART_SHIELDS : Exit Function
    If daoRow <= DOCK_UPG0 Or daoRow >= DOCK_LAUNCH Then Exit Function
    daoU = daoRow - DOCK_UPG0
    DOCK_ArtOf% = DOCK_ArtOfUpgrade%(daoU)
    If daoU = UPG_CANNON Then
        If upgLevel(daoU) >= upgMax(daoU) Then
            DOCK_ArtOf% = DOCK_ART_SPREAD
        ElseIf upgFxA(daoU, upgLevel(daoU) + 1) >= 3 Then
            DOCK_ArtOf% = DOCK_ART_SPREAD
        End If
    End If
End Function
