' mnv_load_test.bas -- verify MNV_ParseBlock parses the .mvr grammar correctly.
'
' Phase 1 (spatial-only) of the TrailForge maneuver-format integration: the new
' .mvr files add behavioral line types (segment:/segseam:/trigger:/craftroll:/
' loopseam:) and a type= key that MNV_ParseBlock must skip, not mis-parse as
' bogus waypoints (the exact bug the old single-blob parser had).
'
' Build: from repo root:
'   ./tools/buildqb tests/mnv_load_test.bas
' Run:   builds/mnv_load_test   (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY
' MNV_Load (pulled in via maneuvers.bas below) references these $EMBED handles;
' QB64-PE validates them at compile time even though this test only exercises
' MNV_ParseBlock directly and never calls MNV_Load.
$EMBED:'assets/maneuvers/attack-pass.mvr':'MNVATTACKPASS'
$EMBED:'assets/maneuvers/boss-v-flight.mvr':'MNVBOSSVFLIGHT'
$EMBED:'assets/maneuvers/boss-x-flight.mvr':'MNVBOSSXFLIGHT'

' ── minimal shared state MNV_ParseBlock writes into (mirrors behavior.bas) ──
Type E3D_Coord
    x As Single
    y As Single
    z As Single
End Type

Const BSM_WP_MAX = 128
Dim Shared bsmWp(0 To BSM_WP_MAX - 1) As E3D_Coord
Dim Shared bsmWpCount    As Integer
Dim Shared bsmFlySpd     As Single
Dim Shared bsmClosed     As Integer
Dim Shared bsmStandoff   As Single
Dim Shared bsmOrientMode As Integer
Dim Shared bsmTargetX    As Single
Dim Shared bsmTargetY    As Single
Dim Shared bsmTargetZ    As Single
Dim Shared bsmPathRoll(0 To BSM_WP_MAX - 1)  As Single
Dim Shared bsmCraftRoll(0 To BSM_WP_MAX - 1) As Single

Const BSM_TRIG_MAX = 16
' bsmPhaseTrigFired isn't declared here -- MNV_ParseBlock never touches it,
' only BOSS_FlyoverInit/BOSS_UpdateMovement (behavior.bas) do, which this
' test doesn't include.
Dim Shared bsmPhaseTrigT(0 To BSM_TRIG_MAX - 1)   As Single
Dim Shared bsmPhaseTrigVal(0 To BSM_TRIG_MAX - 1) As Integer
Dim Shared bsmPhaseTrigCount                      As Integer

'$INCLUDE:'../src/gameplay/maneuvers.bas'

' ── test helpers ─────────────────────────────────────────────────────────────
Dim Shared mtPassed As Integer, mtFailed As Integer

Sub MT_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        mtPassed = mtPassed + 1
    Else
        Print "FAIL  " + testName
        mtFailed = mtFailed + 1
    End If
End Sub

Function NearlyEq%(a As Single, b As Single)
    NearlyEq% = (Abs(a - b) < 0.001)
End Function

' ─────────────────────────────────────────────────────────────────────────────
Print "=== mnv_load_test ==="
Print ""

' -- Scenario 1: new-format block -- type=, segment:/segseam:/trigger:/
'    craftroll:/loopseam: lines interleaved with waypoints must all be
'    skipped, not counted as waypoints or corrupt the ones that follow.
Dim fixture1 As String
fixture1 = "[new-fmt]" + Chr$(10) + _
    "type=craft" + Chr$(10) + _
    "speed=0.25" + Chr$(10) + _
    "orient=target:1,6,2" + Chr$(10) + _
    "closed=1" + Chr$(10) + _
    Chr$(10) + _
    " 10   0   0" + Chr$(10) + _
    " 25   8  15" + Chr$(10) + _
    " 10   0   0" + Chr$(10) + _
    Chr$(10) + _
    "segment: standoff, 0.0000, 0.2000, 8, absolute, linear" + Chr$(10) + _
    "segseam: standoff, 0.05, 0.05, 8, in-out" + Chr$(10) + _
    "trigger: 0.0500, fireMode, on" + Chr$(10) + _
    "craftroll: 0.0000, 0.3000, 45, cw, relative, in-out" + Chr$(10) + _
    "loopseam: 0.05, 0.05, 0, in-out" + Chr$(10)

MNV_ParseBlock fixture1

MT_Assert bsmWpCount = 3, "new-fmt: waypoint count ignores behavioral lines (got " + LTrim$(Str$(bsmWpCount)) + ")"
MT_Assert NearlyEq%(bsmWp(0).x, 10) And NearlyEq%(bsmWp(0).y, 0) And NearlyEq%(bsmWp(0).z, 0), "new-fmt: waypoint 0 parsed correctly"
MT_Assert NearlyEq%(bsmWp(1).x, 25) And NearlyEq%(bsmWp(1).y, 8) And NearlyEq%(bsmWp(1).z, 15), "new-fmt: waypoint 1 parsed correctly"
MT_Assert NearlyEq%(bsmWp(2).x, 10) And NearlyEq%(bsmWp(2).y, 0) And NearlyEq%(bsmWp(2).z, 0), "new-fmt: closed-loop duplicate endpoint parsed correctly"
MT_Assert NearlyEq%(bsmFlySpd, 0.25), "new-fmt: speed= parsed"
MT_Assert bsmClosed = 1, "new-fmt: closed= parsed"
MT_Assert bsmOrientMode = 1, "new-fmt: orient=target sets target mode"
MT_Assert NearlyEq%(bsmTargetX, 1) And NearlyEq%(bsmTargetY, 6) And NearlyEq%(bsmTargetZ, 2), "new-fmt: orient=target coords parsed"
MT_Assert NearlyEq%(bsmPathRoll(0), 0) And NearlyEq%(bsmCraftRoll(0), 0), "new-fmt: no inline roll data on new-format waypoints"
Print ""

' -- Scenario 2: orient=path (not target) ------------------------------------
Dim fixture2 As String
fixture2 = "[path-orient]" + Chr$(10) + _
    "speed=0.1" + Chr$(10) + _
    "orient=path" + Chr$(10) + _
    "closed=0" + Chr$(10) + _
    Chr$(10) + _
    " 0 0 0" + Chr$(10) + _
    " 5 5 5" + Chr$(10)

MNV_ParseBlock fixture2

MT_Assert bsmOrientMode = 0, "path-orient: orient=path sets path-follow mode"
MT_Assert bsmClosed = 0, "path-orient: closed=0 parsed"
MT_Assert bsmWpCount = 2, "path-orient: waypoint count correct (got " + LTrim$(Str$(bsmWpCount)) + ")"
Print ""

' -- Scenario 3: legacy-format block -- inline pathRoll/craftRoll columns on
'    waypoint lines must still parse (regression guard: new-line skipping
'    must not break the old 5-token waypoint format still used elsewhere).
Dim fixture3 As String
fixture3 = "[legacy-fmt]" + Chr$(10) + _
    "speed=0.05" + Chr$(10) + _
    "standoff=2.5" + Chr$(10) + _
    "closed=0" + Chr$(10) + _
    " 1 2 3 45 90" + Chr$(10) + _
    " 4 5 6" + Chr$(10)

MNV_ParseBlock fixture3

MT_Assert bsmWpCount = 2, "legacy-fmt: waypoint count correct (got " + LTrim$(Str$(bsmWpCount)) + ")"
MT_Assert NearlyEq%(bsmPathRoll(0), 45) And NearlyEq%(bsmCraftRoll(0), 90), "legacy-fmt: inline pathRoll/craftRoll still parsed"
MT_Assert NearlyEq%(bsmStandoff, 2.5), "legacy-fmt: standoff= still parsed"
Print ""

' -- Scenario 4: state reset -- loading a second block must not leak state
'    from whatever was parsed before it.
MNV_ParseBlock fixture2
MT_Assert bsmWpCount = 2 And bsmOrientMode = 0, "reset: re-parsing a different block clears prior state (got " + LTrim$(Str$(bsmWpCount)) + " wps)"

' -- Scenario 5: MNV_ListBlocks enumerates the hand-maintained name list ----
Dim mlbNames(0 To 15) As String
Dim mlbCount As Integer
MNV_ListBlocks mlbNames(), mlbCount
MT_Assert mlbCount = 3, "ListBlocks: 3 maneuvers listed (got " + LTrim$(Str$(mlbCount)) + ")"
Dim mlbFoundNew As Integer
mlbFoundNew = 0
Dim mlbI As Integer
For mlbI = 0 To mlbCount - 1
    If mlbNames(mlbI) = "boss-x-flight" Then mlbFoundNew = -1
Next mlbI
MT_Assert mlbFoundNew, "ListBlocks: boss-x-flight present"
Print ""

' -- Scenario 6: phase triggers -- trigger: <t>, phase, <n> is parsed; every
'    other trigger type is still skipped (not yet consumed, per the header).
Dim fixture6 As String
fixture6 = "[phase-trig]" + Chr$(10) + _
    "speed=0.1" + Chr$(10) + _
    "orient=path" + Chr$(10) + _
    "closed=1" + Chr$(10) + _
    Chr$(10) + _
    " 0 0 0" + Chr$(10) + _
    " 5 5 5" + Chr$(10) + _
    Chr$(10) + _
    "trigger: 0.1000, fireMode, on" + Chr$(10) + _
    "trigger: 0.9500, phase, 2" + Chr$(10)

MNV_ParseBlock fixture6

MT_Assert bsmPhaseTrigCount = 1, "phase-trig: only the phase trigger is counted (got " + LTrim$(Str$(bsmPhaseTrigCount)) + ")"
MT_Assert NearlyEq%(bsmPhaseTrigT(0), 0.95), "phase-trig: t parsed correctly"
MT_Assert bsmPhaseTrigVal(0) = 2, "phase-trig: target phase parsed correctly (got " + LTrim$(Str$(bsmPhaseTrigVal(0))) + ")"

' re-parsing a block with no trigger: lines must clear the count (no leak)
MNV_ParseBlock fixture2
MT_Assert bsmPhaseTrigCount = 0, "phase-trig: count resets on next parse (got " + LTrim$(Str$(bsmPhaseTrigCount)) + ")"

' ─────────────────────────────────────────────────────────────────────────────
Print ""
Print "=== " + LTrim$(Str$(mtPassed + mtFailed)) + " tests: " + LTrim$(Str$(mtPassed)) + " passed, " + LTrim$(Str$(mtFailed)) + " failed ==="
If mtFailed > 0 Then System 1 Else System 0
