' boss_hp_test.bas -- boss hit points, phases and the phase-change shield (src/gameplay/bosshp.bas, #90)
'
' Drives the real module against the real assets/config/bosses.ini and the hp= of each boss
' fight in the real assets/sequence.txt: loading (and rejecting broken values), per-boss and
' --nerf hit points, where phases 2 and 3 start, damage that never carries past a phase's
' start (so a hard hitter still fights every phase), no damage while shielded, and how long
' the shield lasts for a callout.
'
' Build: ./tools/buildqb tests/boss_hp_test.bas
' Run:   builds/boss_hp_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/config/bosses.ini':'CFGBOSSES'
$EMBED:'assets/sequence.txt':'SEQTXT'

Sub DBG_Print (bttDbg As String) : End Sub
Sub TELEM_UpgradeBought (btuItem As String, btuLevel As Integer, btuPrice As Long) : End Sub
Sub TELEM_CreditBonus (btcC As Long, btcR As Double, btcP As Long) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/credits.bas'
'$INCLUDE:'../src/gameplay/upgrades.bas'
'$INCLUDE:'../src/gameplay/bosshp.bas'

Dim Shared btPassed As Integer, btFailed As Integer

Sub BT_Assert (btaCond As Integer, btaName As String)
    If btaCond Then
        Print "PASS  " + btaName
        btPassed = btPassed + 1
    Else
        Print "FAIL  " + btaName
        btFailed = btFailed + 1
    End If
End Sub

' Loads a variant of the real file with one key's value replaced; returns BHP_Load%.
Function BT_LoadWith% (btlKey As String, btlVal As String)
    Dim btlSrc As String, btlP As Long, btlQ As Long
    btlSrc = _EMBEDDED$("CFGBOSSES")
    btlP = InStr(btlSrc, Chr$(10) + btlKey + "=")
    If btlP > 0 Then
        btlQ = InStr(btlP + 1, btlSrc, Chr$(10))
        If btlQ = 0 Then btlQ = Len(btlSrc) + 1
        btlSrc = Left$(btlSrc, btlP) + btlKey + "=" + btlVal + Mid$(btlSrc, btlQ)
    End If
    cfgBosses = CFG_Parse$(btlSrc)
    BT_LoadWith% = BHP_Load%
End Function

' Shots of dmg each it takes to beat a boss of maxHp, shooting every frame and counting the frames
' the boss spends shielded (a new phase shields it for shieldF frames). Returns shots that landed.
Function BT_Fight% (btfMax As Integer, btfDmg As Integer, btfShieldF As Long, btfPhases As Integer)
    Dim btfHp As Integer, btfShield As Long, btfShots As Integer, btfOld As Integer, btfGuard As Long
    btfHp = btfMax : btfPhases = 1
    Do While btfHp > 0 And btfGuard < 100000
        btfGuard = btfGuard + 1
        If btfShield > 0 Then
            btfShield = btfShield - 1
        Else
            btfOld = btfHp
            btfHp = BHP_Damage%(btfHp, btfMax, btfDmg, 0)
            btfShots = btfShots + 1
            If btfHp > 0 And BHP_Phase%(btfHp, btfMax) <> BHP_Phase%(btfOld, btfMax) Then
                btfShield = btfShieldF
                btfPhases = btfPhases + 1
            End If
        End If
    Loop
    BT_Fight% = btfShots
End Function

Dim btOk As Integer, btSrc As String, btP As Long, btQ As Long, btLine As String, btN As Integer
Dim btHp(1 To 8) As Integer, btSecs(1 To 8) As Integer, btH As Integer, btPh As Integer, btShots As Integer

Print "=== boss_hp_test ==="
Print ""

Print "--- config: the real bosses.ini ---"
cfgBosses = CFG_Parse$(_EMBEDDED$("CFGBOSSES"))
btOk = BHP_Load%
BT_Assert btOk <> 0, "bosses.ini loads " + bhpLoadErr
BT_Assert bhpDefault = 30 And bhpNerfMin = 3, "default 30 HP, at least 3 under --nerf"
BT_Assert bhpPct2 = 66 And bhpPct3 = 33, "phases 2 and 3 at 66% and 33%"
BT_Assert bhpShieldPad = 30 And bhpShieldMin = 90, "shield: callout + 30 frames, 90 at least"
BT_Assert BT_LoadWith%("boss_phase", "66") = 0, "one phase value: rejected"
BT_Assert BT_LoadWith%("boss_phase", "33,66") = 0, "phase 3 before phase 2: rejected"
BT_Assert BT_LoadWith%("boss_phase", "100,33") = 0, "phase 2 at full HP: rejected"
BT_Assert BT_LoadWith%("boss_hp_default", "2") = 0, "fewer HP than phases: rejected"
BT_Assert BT_LoadWith%("boss_shield_min", "-1") = 0, "a negative shield: rejected"
cfgBosses = CFG_Parse$(_EMBEDDED$("CFGBOSSES"))
BT_Assert BHP_Load% <> 0, "the real file loads again"

Print ""
Print "--- each boss's hit points: hp= in sequence.txt ---"
btSrc = _EMBEDDED$("SEQTXT") + Chr$(10)
btP = 1
Do
    btQ = InStr(btP, btSrc, Chr$(10))
    If btQ = 0 Then Exit Do
    btLine = Mid$(btSrc, btP, btQ - btP)
    btP = btQ + 1
    If InStr(btLine, "PLAY type=boss") > 0 And Left$(LTrim$(btLine), 1) <> ";" And btN < 8 Then
        btN = btN + 1
        If InStr(btLine, " hp=") > 0 Then btHp(btN) = Val(Mid$(btLine, InStr(btLine, " hp=") + 4))
        If InStr(btLine, " secs=") > 0 Then btSecs(btN) = Val(Mid$(btLine, InStr(btLine, " secs=") + 6))
    End If
Loop
BT_Assert btN = 3, "three boss fights"
BT_Assert btHp(1) = 30, "boss 1 (level 3): 30 HP, as before"
BT_Assert btHp(2) = 90, "boss 2 (level 5): 90 HP (was 30)"
BT_Assert btHp(3) = 130, "boss 3 (level 6): 130 HP (was 30)"
BT_Assert btSecs(1) = 22 And btSecs(2) = 25 And btSecs(3) = 32, "each fight's expected seconds for the fuel estimate (secs=): 22, 25, 32"
BT_Assert BHP_MaxHP%(btHp(2), 0) = 90 And BHP_MaxHP%(0, 0) = 30, "a fight's hp= is used; none falls back to the default"
BT_Assert BHP_MaxHP%(btHp(1), -1) = 3 And BHP_MaxHP%(btHp(2), -1) = 9 And BHP_MaxHP%(btHp(3), -1) = 13, "--nerf: 3, 9, 13"
BT_Assert BHP_MaxHP%(10, -1) = 3, "--nerf never below 3, one per phase"

Print ""
Print "--- phases ---"
BT_Assert BHP_PhaseStart%(30, 2) = 20 And BHP_PhaseStart%(30, 3) = 10, "30 HP: phase 2 at 20, phase 3 at 10 (as before)"
BT_Assert BHP_PhaseStart%(90, 2) = 59 And BHP_PhaseStart%(90, 3) = 30, "90 HP: phase 2 at 59, phase 3 at 30"
BT_Assert BHP_PhaseStart%(3, 2) = 2 And BHP_PhaseStart%(3, 3) = 1, "3 HP (--nerf): one HP per phase"
BT_Assert BHP_Phase%(30, 30) = 1 And BHP_Phase%(21, 30) = 1 And BHP_Phase%(20, 30) = 2, "phase 2 starts at 20 of 30"
BT_Assert BHP_Phase%(11, 30) = 2 And BHP_Phase%(10, 30) = 3 And BHP_Phase%(1, 30) = 3, "phase 3 starts at 10 of 30"

Print ""
Print "--- damage: none while shielded, never past a phase's start ---"
BT_Assert BHP_Damage%(30, 30, 1, 0) = 29, "a shot takes 1"
BT_Assert BHP_Damage%(25, 30, 1, 40) = 25, "shielded: nothing"
BT_Assert BHP_Damage%(22, 30, 3, 0) = 20, "a nova at 22 stops at phase 2's start (20), the rest is lost"
BT_Assert BHP_Damage%(21, 30, 50, 0) = 20, "even a huge hit stops at 20"
BT_Assert BHP_Damage%(12, 30, 3, 0) = 10, "phase 2 -> 3 the same way"
BT_Assert BHP_Damage%(2, 30, 3, 0) = 0, "phase 3 can be finished off"
BT_Assert BHP_Damage%(3, 3, 1, 0) = 2 And BHP_Damage%(2, 3, 1, 0) = 1 And BHP_Damage%(1, 3, 1, 0) = 0, "--nerf boss: one HP per phase"
btShots = BT_Fight%(30, 3, 90, btPh)
BT_Assert btPh = 3, "triple-damage hits: the boss still goes through all 3 phases"
btShots = BT_Fight%(130, 50, 90, btPh)
BT_Assert btPh = 3 And btShots = 3, "50-damage hits on 130 HP: one per phase, 130 -> 86 -> 43 -> 0 (" + LTrim$(Str$(btShots)) + " hits)"

Print ""
Print "--- the shield lasts the callout ---"
BT_Assert BHP_ShieldFrames&(0) = 90, "no callout: 90 frames"
BT_Assert BHP_ShieldFrames&(735) = 90, "a 1-frame callout: still 90"
BT_Assert BHP_ShieldFrames&(735 * 120) = 150, "a 2 s callout: 120 + 30 = 150 frames"
BT_Assert BHP_ShieldFrames&(735 * 120 + 1) = 151, "part of a frame counts as a frame"

Print ""
Print "passed:" + Str$(btPassed) + "  failed:" + Str$(btFailed)
If btFailed > 0 Then System 1
System 0
