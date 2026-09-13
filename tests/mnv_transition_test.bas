' mnv_transition_test.bas -- regression guard for boss maneuver entry/handoff
' continuity (issue #212): position and tangent must not jump discontinuously
' at any state 5 (transition) <-> state 6 (flyover) boundary, across all three
' real boss maneuvers.
'
' Drives BOSS_PickMode/BOSS_UpdateMovement through 1500 ticks cycling
' boss-x-flight, boss-v-flight, and attack-pass, and flags any state-boundary
' position jump that exceeds 3x the maneuver's own steady-state per-tick
' travel. Tangent jump is printed for diagnostic visibility but not yet
' asserted -- issue #211 (tangent flip on closed-loop maneuvers) is a
' separate, still-open bug this test does not yet guard against.
'
' Build: from repo root:
'   ./tools/buildqb tests/mnv_transition_test.bas
' Run:   builds/mnv_transition_test   (exit 0 = pass, exit 1 = fail)

$CONSOLE:ONLY
$EMBED:'assets/sequence.txt':'SEQTXT'
$EMBED:'assets/maneuvers/attack-pass.mvr':'MNVATTACKPASS'
$EMBED:'assets/maneuvers/boss-v-flight.mvr':'MNVBOSSVFLIGHT'
$EMBED:'assets/maneuvers/boss-x-flight.mvr':'MNVBOSSXFLIGHT'

Sub DBG_Print(dbgMsg As String)
End Sub

'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/gameplay/spline_path.bi'
'$INCLUDE:'../src/gameplay/behavior.bas'
'$INCLUDE:'../src/gameplay/maneuvers.bas'

player.px = 0 : player.py = 0 : player.pz = 0
boss.px = player.px + 55 : boss.py = 0 : boss.pz = 0   ' spawn distance, matches BOSS_SPAWN_DIST
boss.vx = -0.05
boss.state = 0 : boss.phase = 1
bsmTurnDir = 1

bossManeuverCnt = 3
bossManeuverList$(0) = "boss-x-flight"
bossManeuverList$(1) = "boss-v-flight"
bossManeuverList$(2) = "attack-pass"

Dim prevPX As Single, prevPY As Single, prevPZ As Single
Dim prevTX As Single, prevTY As Single, prevTZ As Single
Dim prevState As Integer
Dim cruiseJumpEMA As Single   ' rolling steady-state per-tick travel, to judge boundary jumps against
Dim worstBoundaryRatio As Single, worstBoundaryTick As Integer
Dim i As Integer, entries As Integer

prevPX = boss.px : prevPY = boss.py : prevPZ = boss.pz
prevTX = 0 : prevTY = 0 : prevTZ = 0
prevState = boss.state
cruiseJumpEMA = 0.25   ' seed at the maneuver's own speed= so the very first boundary has a sane baseline

For i = 1 To 1500
    ' mimic boss.bas: fire volley -> BOSS_PickMode when idle (state 0)
    If boss.state = 0 Then
        BOSS_PickMode
        entries = entries + 1
        Print "--- entry #" + LTrim$(Str$(entries)) + " (tick " + LTrim$(Str$(i)) + ") maneuver=" + bsmManeuverName + " ---"
    End If

    BOSS_UpdateMovement

    Dim posJump As Single : posJump = Sqr((boss.px-prevPX)^2 + (boss.py-prevPY)^2 + (boss.pz-prevPZ)^2)
    Dim tanJump As Single : tanJump = Sqr((bsmFlTnX-prevTX)^2 + (bsmFlTnY-prevTY)^2 + (bsmFlTnZ-prevTZ)^2)

    If boss.state <> prevState And i > 1 Then
        Dim ratio As Single : ratio = posJump / cruiseJumpEMA
        Print "  [state " + LTrim$(Str$(prevState)) + "->" + LTrim$(Str$(boss.state)) + " @ tick " + LTrim$(Str$(i)) + "]  posJump=" + Str$(posJump) + "  (" + Str$(ratio) + "x steady-state)  tanJump=" + Str$(tanJump)
        If prevState <> 0 And boss.state <> 0 And ratio > worstBoundaryRatio Then worstBoundaryRatio = ratio : worstBoundaryTick = i
    ElseIf i > 1 And boss.state = prevState And boss.state <> 0 Then
        cruiseJumpEMA = cruiseJumpEMA * 0.9 + posJump * 0.1   ' only learn steady-state speed away from boundaries
    End If

    prevPX = boss.px : prevPY = boss.py : prevPZ = boss.pz
    prevTX = bsmFlTnX : prevTY = bsmFlTnY : prevTZ = bsmFlTnZ
    prevState = boss.state
Next i

Print
Print "entries=" + LTrim$(Str$(entries)) + "  steady-state cruise~=" + Str$(cruiseJumpEMA) + "/tick  worst entry/exit boundary=" + Str$(worstBoundaryRatio) + "x @tick " + LTrim$(Str$(worstBoundaryTick))
If worstBoundaryRatio < 3.0 Then
    Print "PASS  no boundary meaningfully exceeds steady-state per-tick travel"
    System 0
Else
    Print "FAIL  a state-transition boundary jump exceeds steady-state travel by 3x+ -- see [state x->y] lines above"
    System 1
End If
