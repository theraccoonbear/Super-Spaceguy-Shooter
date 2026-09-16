' Boss movement modes (boss.state):
'   0 idle       -- closing initial spawn distance to BOSS_COMBAT_DIST on X; no other motion
'   5 transition -- short Hermite blend from wherever the boss actually is/is heading into
'                   the next maneuver's real entry point (P0 + its own entry tangent).
'                   Continuous position AND heading -- no snap, regardless of open/closed.
'   6 flyover    -- Catmull-Rom spline: the boss's active flight pattern once a transition
'                   completes, driven entirely by the maneuver loaded via MNV_Load
'                   (assets/maneuvers/*.mvr)
'
' Flyover path (state 6): boss.arcAngle is repurposed as the spline t parameter (0..bsmWpCount-1).
' Waypoints are player-relative, set by MNV_Load at flyover entry (via BOSS_PickMode); Z column
' is signed by bsmTurnDir so the arc alternates sides each pass. Attitude (yaw/pitch/roll) is
' derived from bsmFlTnX/Y/Z (the exposed facing) each frame, so banking follows the curve
' naturally -- same is true during state 5, off the Hermite tangent instead. bsmFlTnX/Y/Z is
' the true spline tangent slewed toward a max turn rate (BOSS_FLYOVER_MAX_FACE_TURN_COS), not
' the raw tangent itself -- see Case 6 -- so a real curve cusp eases rather than snaps.
'
' Every BOSS_PickMode call (first-ever entry from spawn, and every pass-to-pass handoff) goes
' through state 5 first: entry into a maneuver is no longer a hand-anchored special case, it's
' the same transition mechanism regardless of why or how often it fires.

' BOSS_COMBAT_DIST defined here (behavior.bas included before boss.bas)
Const BOSS_COMBAT_DIST = 20    ' standard X distance for combat

Const BOSS_CHARGE_CD1 = 300    ' frames between charge eligibility, phase 1
Const BOSS_CHARGE_CD2 = 190    ' phase 2
Const BOSS_CHARGE_CD3 = 110    ' phase 3

' Flyover (state 6) splits each tick's arc-length advance into this many smaller,
' fixed-size steps, resampling the raw derivative each time: a single Euler step
' samples |D| once and can badly overshoot near a sharp knot, where |D| changes
' fast over a short arc-length span. Improves position accuracy near tight turns;
' see BOSS_FLYOVER_MAX_FACE_TURN_COS below for the actual issue #211 fix.
Const BOSS_FLYOVER_SUBSTEPS = 8

' issue #211: a real Catmull-Rom cusp (a knot where the analytic derivative
' genuinely reverses direction, e.g. boss-x-flight's sharp out-and-back spike)
' makes the raw tangent flip discontinuously right at that point -- position
' stays correct (it truly does reverse there), but no amount of finer position
' stepping can make a real discontinuity in the curve look continuous, because
' facing is only ever sampled/rendered once per tick. So the actual fix is at
' the orientation layer: bsmFlTnX/Y/Z (the facing vector boss.bas reads) is
' slewed toward each sub-step's raw sampled tangent at most this much per
' sub-step (cos of 1.25 deg), rather than snapping straight to it -- 8 sub-steps
' x 1.25 deg caps the worst-case facing turn at 10 deg/tick. The true, unsmoothed
' curve still drives position and the arc-length speed correction; only the
' *displayed* facing/banking eases through a cusp instead of snapping.
Const BOSS_FLYOVER_MAX_FACE_TURN_COS = 0.9997621

Dim Shared bsmFlySpd      As Single   ' t-advance per frame; set by MNV_Load
Dim Shared bsmManeuverName As String   ' which [block] to load; set before BOSS_FlyoverInit

' ── transition (state 5) -- Hermite blend into the next maneuver's entry ──
Dim Shared bsmTrP0X As Single, bsmTrP0Y As Single, bsmTrP0Z As Single   ' start: boss's actual pos at transition entry (player-relative)
Dim Shared bsmTrP1X As Single, bsmTrP1Y As Single, bsmTrP1Z As Single   ' end: target maneuver's real P0 (player-relative)
Dim Shared bsmTrM0X As Single, bsmTrM0Y As Single, bsmTrM0Z As Single   ' scaled start tangent (SpEfHermiteTangentScale)
Dim Shared bsmTrM1X As Single, bsmTrM1Y As Single, bsmTrM1Z As Single   ' scaled end tangent
Dim Shared bsmTrT   As Single                                          ' Hermite parameter, 0..1

' ── flyover waypoint array -- populated by BOSS_FlyoverInit at state-6 entry ──
Const BSM_WP_MAX = 128
Dim Shared bsmWp(0 To BSM_WP_MAX - 1) As E3D_Coord
Dim Shared bsmWpCount As Integer

' ── extended path metadata (format v2 fields) ────────────────────────────
Dim Shared bsmClosed     As Integer    ' 1=closed loop, 0=open (old format default)
Dim Shared bsmStandoff   As Single     ' perpendicular standoff distance (world units)
Dim Shared bsmOrientMode As Integer    ' 0=path-following, 1=fixed-target
Dim Shared bsmTargetX    As Single     ' fixed-target world X (when orient=target)
Dim Shared bsmTargetY    As Single
Dim Shared bsmTargetZ    As Single
Dim Shared bsmPathRoll(0 To BSM_WP_MAX - 1)  As Single  ' per-wp path roll (degrees)
Dim Shared bsmCraftRoll(0 To BSM_WP_MAX - 1) As Single  ' per-wp craft roll (degrees)

' ── phase triggers -- trigger: <t>, phase, <n> lines from the .mvr file ──
' t is a simplified parameter-space fraction (0..1 of one pass), not true
' arc-length -- same known simplification TrailForge itself hasn't resolved
' yet for trigger t (see its issue #209). Good enough for choreographed
' phase handoffs; not claiming frame-accurate timing.
Const BSM_TRIG_MAX = 16
Dim Shared bsmPhaseTrigT(0 To BSM_TRIG_MAX - 1)     As Single   ' 0..1 fraction of one pass
Dim Shared bsmPhaseTrigVal(0 To BSM_TRIG_MAX - 1)   As Integer  ' target boss.phase
Dim Shared bsmPhaseTrigCount                        As Integer
Dim Shared bsmPhaseTrigFired(0 To BSM_TRIG_MAX - 1) As Integer  ' re-armed each pass by BOSS_FlyoverInit
Dim Shared bsmFlTnX As Single, bsmFlTnY As Single, bsmFlTnZ As Single  ' normalized tangent at current t — written by Case 6, read by boss.bas
Dim Shared bsmFlCR  As Single                                           ' interpolated craftRoll at current t
' Parallel-transport frame (Rodrigues) — updated each Case 6 tick via SpEfTransportFrame.
' R (right) and U (up) rotate with the path, preventing twist. Read by boss.bas for body orientation.
Dim Shared bsmFlFRX As Single, bsmFlFRY As Single, bsmFlFRZ As Single         ' transported right vector
Dim Shared bsmFlFUX As Single, bsmFlFUY As Single, bsmFlFUZ As Single         ' transported up vector
Dim Shared bsmFlPrevTnX As Single, bsmFlPrevTnY As Single, bsmFlPrevTnZ As Single  ' tangent on previous tick
Dim Shared bsmFlFrameReady As Integer                                         ' 0=needs init, 1=frame live

Sub BOSS_UpdateMovement()
    Dim bsmFt As Single, bsmFseg As Integer
    Dim bsmFu As Single
    Dim bsmFi0 As Integer, bsmFi1 As Integer, bsmFi2 As Integer, bsmFi3 As Integer
    Dim bsmFi0D As Double, bsmFi1D As Double, bsmFi2D As Double, bsmFi3D As Double  ' SpEfGhostIndices output
    Dim bsmClosedF As Double  ' bsmClosed normalized to strict 0.0/1.0 -- see SpEfGhostIndices's own comment
    Dim bsmFlNS As Integer     ' number of segments (always nWps-1 -- see SpEfGhostIndices)
    Dim bsmFlPR As Single      ' interpolated pathRoll (degrees)
    Dim bsmFlAX As Single, bsmFlAY As Single, bsmFlAZ As Single     ' actual pos after standoff
    Dim bsmFlAXD As Double, bsmFlAYD As Double, bsmFlAZD As Double  ' Double temps for SpEfActualPos
    Dim bsmEvX As Single, bsmEvY As Single, bsmEvZ As Single        ' SpEvalAt output (player-relative)
    Dim bsmDw0D As Double, bsmDw1D As Double, bsmDw2D As Double, bsmDw3D As Double  ' SpEfCrDerivWeights output
    Dim bsmDXD As Double, bsmDYD As Double, bsmDZD As Double        ' raw (unnormalized) derivative
    Dim bsmArcAdvD As Double                                        ' SpEfArcAdvance output
    Dim bsmTanLen As Single
    Dim bsmTrPosXD As Double, bsmTrPosYD As Double, bsmTrPosZD As Double  ' SpEfHermitePos output
    Dim bsmTrRawXD As Double, bsmTrRawYD As Double, bsmTrRawZD As Double  ' SpEfHermiteTangent raw output
    Dim bsmTrFxD As Double, bsmTrFyD As Double, bsmTrFzD As Double        ' SpEfFacingNorm output
    Dim bsmTrAdvD As Double                                                ' SpEfArcAdvance output (transition)
    Dim bsmSubI As Integer, bsmSubSpd As Single   ' flyover sub-step loop (see BOSS_FLYOVER_SUBSTEPS)
    Dim bsmRawTnX As Single, bsmRawTnY As Single, bsmRawTnZ As Single   ' true (unsmoothed) tangent this sub-step

    boss.chargeTimer = boss.chargeTimer - 1
    If boss.chargeTimer < 0 Then boss.chargeTimer = 0

    Select Case boss.state
    Case 5  ' transition: short Hermite blend from current heading into the next maneuver's entry.
            ' All curve math is ExprForge-generated (SpEfHermitePos/SpEfHermiteTangent) -- this
            ' is plumbing only, mirroring how Case 6 drives SpEvalAt/SpTangentAt.
        SpEfHermitePos CDbl(bsmTrP0X), CDbl(bsmTrP0Y), CDbl(bsmTrP0Z), _
                       CDbl(bsmTrM0X), CDbl(bsmTrM0Y), CDbl(bsmTrM0Z), _
                       CDbl(bsmTrP1X), CDbl(bsmTrP1Y), CDbl(bsmTrP1Z), _
                       CDbl(bsmTrM1X), CDbl(bsmTrM1Y), CDbl(bsmTrM1Z), _
                       CDbl(bsmTrT), bsmTrPosXD, bsmTrPosYD, bsmTrPosZD
        boss.px = player.px + CSng(bsmTrPosXD)
        boss.py = player.py + CSng(bsmTrPosYD)
        boss.pz = player.pz + CSng(bsmTrPosZD)

        SpEfHermiteTangent CDbl(bsmTrP0X), CDbl(bsmTrP0Y), CDbl(bsmTrP0Z), _
                            CDbl(bsmTrM0X), CDbl(bsmTrM0Y), CDbl(bsmTrM0Z), _
                            CDbl(bsmTrP1X), CDbl(bsmTrP1Y), CDbl(bsmTrP1Z), _
                            CDbl(bsmTrM1X), CDbl(bsmTrM1Y), CDbl(bsmTrM1Z), _
                            CDbl(bsmTrT), bsmTrRawXD, bsmTrRawYD, bsmTrRawZD
        SpEfFacingNorm bsmTrRawXD, bsmTrRawYD, bsmTrRawZD, bsmTrFxD, bsmTrFyD, bsmTrFzD
        bsmFlTnX = CSng(bsmTrFxD) : bsmFlTnY = CSng(bsmTrFyD) : bsmFlTnZ = CSng(bsmTrFzD)

        ' Same arc-length reparameterization as flyover, at the target maneuver's own speed --
        ' no separate "transition duration" constant; farther/closer entries take proportionately
        ' longer/shorter at a consistent world-speed, matching the maneuver it's leading into.
        SpEfArcAdvance bsmTrRawXD, bsmTrRawYD, bsmTrRawZD, CDbl(bsmFlySpd), bsmTrAdvD
        bsmTrT = bsmTrT + CSng(bsmTrAdvD)

        BOSS_UpdateTransportFrame   ' same parallel-transport as state 6 -- roll carries through the handoff

        If bsmTrT >= 1.0 Then
            ' Snap to the exact endpoint, same idiom Case 6's own path-complete branch
            ' uses: this tick's Hermite sample is at bsmTrT *before* the increment above,
            ' i.e. fractionally short of t=1 -- left alone it's a small but real gap
            ' before flyover's SpEvalAt(t=0) lands on bsmTrP1 exactly next tick.
            boss.px = player.px + bsmTrP1X
            boss.py = player.py + bsmTrP1Y
            boss.pz = player.pz + bsmTrP1Z
            boss.arcAngle = 0       ' state 6 starts its own spline parameter fresh
            ' Re-seed the transport frame instead of carrying over whatever the
            ' transition accumulated: parallel transport is path-dependent, and
            ' transporting through a large, unrelated re-orientation (e.g. the
            ' very first entry, blending from spawn's straight approach) picks
            ' up a real, exact (not a numerical error -- confirmed unchanged at
            ' 20000x finer sampling) twist that has nothing to do with the
            ' flyover maneuver itself. Re-seeding here makes every entry behave
            ' identically regardless of where the boss was coming from.
            bsmFlFrameReady = 0
            boss.state = 6
        End If

    Case 6  ' flyover: Catmull-Rom spline — supports standoff, closed paths, pathRoll
        bsmFseg  = Int(boss.arcAngle)
        ' Closed maneuvers store an explicit duplicate of waypoint 0 as their last
        ' waypoint (see SpEfGhostIndices) rather than being truly cyclic, so segment
        ' count is bsmWpCount-1 either way -- issue #211's zero-length closing segment
        ' came from double-counting this as an extra wraparound segment on top of it.
        bsmFlNS  = bsmWpCount - 1
        If bsmFseg >= bsmFlNS Then
            ' path complete: land on final waypoint, flip arc dir, return to combat
            boss.px = player.px + bsmWp(bsmWpCount - 1).x
            boss.py = player.py + bsmWp(bsmWpCount - 1).y
            boss.pz = player.pz + bsmWp(bsmWpCount - 1).z
            bsmTurnDir = bsmTurnDir * -1
            If bsmTurnDir = 0 Then bsmTurnDir = 1
            Select Case boss.phase
                Case 1 : boss.chargeTimer = BOSS_CHARGE_CD1
                Case 2 : boss.chargeTimer = BOSS_CHARGE_CD2
                Case 3 : boss.chargeTimer = BOSS_CHARGE_CD3
            End Select
            boss.state = 0
        Else
            ' Sub-step the tick's arc-length advance (see BOSS_FLYOVER_SUBSTEPS above):
            ' split the tick's speed budget into smaller steps, resampling the raw
            ' derivative each time, rather than one Euler step from a single stale
            ' sample. Position/arc-length speed always follow the true, unsmoothed
            ' curve; bsmFlTnX/Y/Z (the exposed facing) is slewed toward each
            ' sub-step's raw tangent rather than snapped to it -- see
            ' BOSS_FLYOVER_MAX_FACE_TURN_COS above (issue #211).
            bsmSubSpd = bsmFlySpd / BOSS_FLYOVER_SUBSTEPS

            For bsmSubI = 1 To BOSS_FLYOVER_SUBSTEPS
                If Int(boss.arcAngle) >= bsmFlNS Then Exit For   ' pass finished mid-loop

                bsmFt   = boss.arcAngle
                bsmFseg = Int(bsmFt)
                If bsmFseg >= bsmFlNS Then bsmFseg = bsmFlNS - 1
                bsmFu   = bsmFt - bsmFseg

                ' Position and true tangent: both fully delegated to the shared,
                ' ExprForge-backed evaluators (spline_path.bi) -- no hand-copied CR math.
                SpEvalAt bsmWp(), bsmWpCount, bsmFt, bsmClosed, bsmEvX, bsmEvY, bsmEvZ
                boss.px = player.px + bsmEvX
                boss.py = player.py + bsmEvY
                boss.pz = player.pz + bsmEvZ
                SpTangentAt bsmWp(), bsmWpCount, bsmFt, bsmClosed, bsmRawTnX, bsmRawTnY, bsmRawTnZ
                SpSlewToward bsmFlTnX, bsmFlTnY, bsmFlTnZ, bsmRawTnX, bsmRawTnY, bsmRawTnZ, _
                             BOSS_FLYOVER_MAX_FACE_TURN_COS, bsmFlTnX, bsmFlTnY, bsmFlTnZ

                ' Raw (unnormalized) derivative -- needed only for the arc-length speed
                ' correction below, since SpTangentAt returns just the normalized tangent.
                ' SpEfGhostIndices/SpEfCrDerivWeights are the same generated/shared calls
                ' SpTangentAt makes internally; recomputed here rather than changing its
                ' signature to expose them.
                If bsmClosed <> 0 Then bsmClosedF = 1 Else bsmClosedF = 0
                SpEfGhostIndices CDbl(bsmWpCount), CDbl(bsmFseg), bsmClosedF, bsmFi0D, bsmFi1D, bsmFi2D, bsmFi3D
                bsmFi0 = CInt(bsmFi0D) : bsmFi1 = CInt(bsmFi1D) : bsmFi2 = CInt(bsmFi2D) : bsmFi3 = CInt(bsmFi3D)
                SpEfCrDerivWeights CDbl(bsmFu), bsmDw0D, bsmDw1D, bsmDw2D, bsmDw3D
                bsmDXD = bsmDw0D*bsmWp(bsmFi0).x + bsmDw1D*bsmWp(bsmFi1).x + bsmDw2D*bsmWp(bsmFi2).x + bsmDw3D*bsmWp(bsmFi3).x
                bsmDYD = bsmDw0D*bsmWp(bsmFi0).y + bsmDw1D*bsmWp(bsmFi1).y + bsmDw2D*bsmWp(bsmFi2).y + bsmDw3D*bsmWp(bsmFi3).y
                bsmDZD = bsmDw0D*bsmWp(bsmFi0).z + bsmDw1D*bsmWp(bsmFi1).z + bsmDw2D*bsmWp(bsmFi2).z + bsmDw3D*bsmWp(bsmFi3).z
                SpEfArcAdvance bsmDXD, bsmDYD, bsmDZD, CDbl(bsmSubSpd), bsmArcAdvD
                boss.arcAngle = boss.arcAngle + CSng(bsmArcAdvD)
                bsmTanLen = CSng(Sqr(bsmDXD*bsmDXD + bsmDYD*bsmDYD + bsmDZD*bsmDZD))

                ' Phase triggers: trigger: <t>, phase, <n> lines from the .mvr file.
                ' t is fraction-of-one-pass in parameter space; fires once per pass,
                ' re-armed by BOSS_FlyoverInit at the start of each new pass.
                Dim bsmPtI As Integer
                For bsmPtI = 0 To bsmPhaseTrigCount - 1
                    If bsmPhaseTrigFired(bsmPtI) = 0 And boss.arcAngle >= bsmPhaseTrigT(bsmPtI) * bsmFlNS Then
                        bsmPhaseTrigFired(bsmPtI) = 1
                        boss.phase = bsmPhaseTrigVal(bsmPtI)
                    End If
                Next bsmPtI

                ' Parallel transport: maintain frame (R,U) across ticks using Rodrigues rotation,
                ' driven off the smoothed facing (bsmFlTnX/Y/Z) so banking eases through a cusp
                ' in step with the nose, rather than snapping independently of it. Shared with
                ' state 5 (BOSS_UpdateTransportFrame) so roll stays continuous through the
                ' transition-into-flyover handoff too, not just position/heading.
                BOSS_UpdateTransportFrame
            Next bsmSubI

            ' Standoff/craftRoll: cosmetic offsets of the tick's ending position, computed
            ' once against the final sub-step's parameter -- no benefit to redoing per sub-step.
            If bsmStandoff > 0.001 And bsmTanLen > 0.001 Then
                SpEvalRollAt bsmPathRoll(), bsmWpCount, bsmFt, bsmClosed, bsmFlPR
                SpEfActualPos CDbl(boss.px), CDbl(boss.py), CDbl(boss.pz), CDbl(bsmFlTnX), CDbl(bsmFlTnY), CDbl(bsmFlTnZ), _
                              CDbl(bsmFlPR), CDbl(bsmStandoff), bsmFlAXD, bsmFlAYD, bsmFlAZD
                bsmFlAX = CSng(bsmFlAXD) : bsmFlAY = CSng(bsmFlAYD) : bsmFlAZ = CSng(bsmFlAZD)
                boss.px = bsmFlAX : boss.py = bsmFlAY : boss.pz = bsmFlAZ
            End If

            SpEvalRollAt bsmCraftRoll(), bsmWpCount, bsmFt, bsmClosed, bsmFlCR
        End If

    End Select
End Sub

' Parallel transport: maintain frame (R,U) across ticks using Rodrigues rotation.
' Shared by state 5 (transition) and state 6 (flyover) so roll stays continuous
' across the maneuver-entry handoff, not just position/heading. Reads the tangent
' the caller already wrote to bsmFlTnX/Y/Z this tick; reads/writes bsmFlPrevTnX/Y/Z,
' bsmFlFRX/Y/Z, bsmFlFUX/Y/Z, bsmFlFrameReady. All math is ExprForge-generated
' (SpEfMkFrame/SpEfTransportFrame) -- this is plumbing only.
Sub BOSS_UpdateTransportFrame()
    Dim butfNRX As Double, butfNRY As Double, butfNRZ As Double
    Dim butfNUX As Double, butfNUY As Double, butfNUZ As Double
    If bsmFlFrameReady = 0 Then
        SpEfMkFrame CDbl(bsmFlTnX), CDbl(bsmFlTnY), CDbl(bsmFlTnZ), _
                    butfNRX, butfNRY, butfNRZ, butfNUX, butfNUY, butfNUZ
        bsmFlFRX = CSng(butfNRX) : bsmFlFRY = CSng(butfNRY) : bsmFlFRZ = CSng(butfNRZ)
        bsmFlFUX = CSng(butfNUX) : bsmFlFUY = CSng(butfNUY) : bsmFlFUZ = CSng(butfNUZ)
        bsmFlPrevTnX = bsmFlTnX : bsmFlPrevTnY = bsmFlTnY : bsmFlPrevTnZ = bsmFlTnZ
        bsmFlFrameReady = 1
    Else
        SpEfTransportFrame CDbl(bsmFlPrevTnX), CDbl(bsmFlPrevTnY), CDbl(bsmFlPrevTnZ), _
                           CDbl(bsmFlTnX),     CDbl(bsmFlTnY),     CDbl(bsmFlTnZ), _
                           CDbl(bsmFlFRX), CDbl(bsmFlFRY), CDbl(bsmFlFRZ), _
                           CDbl(bsmFlFUX), CDbl(bsmFlFUY), CDbl(bsmFlFUZ), _
                           butfNRX, butfNRY, butfNRZ, butfNUX, butfNUY, butfNUZ
        bsmFlFRX = CSng(butfNRX) : bsmFlFRY = CSng(butfNRY) : bsmFlFRZ = CSng(butfNRZ)
        bsmFlFUX = CSng(butfNUX) : bsmFlFUY = CSng(butfNUY) : bsmFlFUZ = CSng(butfNUZ)
        bsmFlPrevTnX = bsmFlTnX : bsmFlPrevTnY = bsmFlTnY : bsmFlPrevTnZ = bsmFlTnZ
    End If
End Sub

' Load the named flyover maneuver (via MNV_Load, from assets/maneuvers/*.mvr) and
' apply bsmTurnDir sign to the Z column. Does NOT touch the boss's actual position --
' BOSS_TransitionInit (state 5) handles getting the boss from wherever it actually is
' to this maneuver's real P0, continuously, regardless of open/closed.
Sub BOSS_FlyoverInit
    Dim bfiI As Integer
    ' pick maneuver for current phase; wrap to last entry if phase exceeds list length
    Dim bfiPIdx As Integer : bfiPIdx = boss.phase - 1
    If bossManeuverCnt > 0 Then
        If bfiPIdx >= bossManeuverCnt Then bfiPIdx = bossManeuverCnt - 1
        bsmManeuverName = bossManeuverList$(bfiPIdx)
    End If
    MNV_Load bsmManeuverName
    ' Apply turn-dir sign to Z column (and to fixed target Z when orient=target)
    For bfiI = 0 To bsmWpCount - 1
        bsmWp(bfiI).z = bsmWp(bfiI).z * bsmTurnDir
    Next bfiI
    If bsmOrientMode = 1 Then bsmTargetZ = bsmTargetZ * bsmTurnDir
    bsmFlFrameReady = 0   ' transport frame re-primed by the upcoming transition (state 5)
    Dim bfiT As Integer
    For bfiT = 0 To bsmPhaseTrigCount - 1
        bsmPhaseTrigFired(bfiT) = 0
    Next bfiT
End Sub

' Captures the boss's actual current position/heading and the target maneuver's
' real entry point/tangent, then computes the Hermite blend endpoints (state 5)
' via ExprForge-generated math (SpEfHermiteTangentScale). btiHadPrevPass tells us
' whether there's a real incoming spline tangent to blend from (bsmFlTnX/Y/Z, left
' over from the pass that just ended) or whether this is the very first-ever entry
' (from spawn's straight -X approach, boss.vx) -- caller must read bsmFlFrameReady
' BEFORE calling BOSS_FlyoverInit, which resets it.
Sub BOSS_TransitionInit(btiHadPrevPass As Integer)
    Dim btiInVX As Double, btiInVY As Double, btiInVZ As Double
    Dim btiEndTnX As Single, btiEndTnY As Single, btiEndTnZ As Single
    Dim btiM0XD As Double, btiM0YD As Double, btiM0ZD As Double
    Dim btiM1XD As Double, btiM1YD As Double, btiM1ZD As Double

    bsmTrP0X = boss.px - player.px
    bsmTrP0Y = boss.py - player.py
    bsmTrP0Z = boss.pz - player.pz

    If btiHadPrevPass Then
        btiInVX = CDbl(bsmFlTnX) : btiInVY = CDbl(bsmFlTnY) : btiInVZ = CDbl(bsmFlTnZ)
    Else
        btiInVX = CDbl(boss.vx) : btiInVY = 0# : btiInVZ = 0#
    End If

    If bsmWpCount > 0 Then
        bsmTrP1X = bsmWp(0).x : bsmTrP1Y = bsmWp(0).y : bsmTrP1Z = bsmWp(0).z
    Else
        bsmTrP1X = bsmTrP0X : bsmTrP1Y = bsmTrP0Y : bsmTrP1Z = bsmTrP0Z
    End If
    SpTangentAt bsmWp(), bsmWpCount, 0.0, bsmClosed, btiEndTnX, btiEndTnY, btiEndTnZ

    SpEfHermiteTangentScale CDbl(bsmTrP0X), CDbl(bsmTrP0Y), CDbl(bsmTrP0Z), _
                            btiInVX, btiInVY, btiInVZ, _
                            CDbl(bsmTrP1X), CDbl(bsmTrP1Y), CDbl(bsmTrP1Z), _
                            CDbl(btiEndTnX), CDbl(btiEndTnY), CDbl(btiEndTnZ), _
                            btiM0XD, btiM0YD, btiM0ZD, btiM1XD, btiM1YD, btiM1ZD
    bsmTrM0X = CSng(btiM0XD) : bsmTrM0Y = CSng(btiM0YD) : bsmTrM0Z = CSng(btiM0ZD)
    bsmTrM1X = CSng(btiM1XD) : bsmTrM1Y = CSng(btiM1YD) : bsmTrM1Z = CSng(btiM1ZD)

    bsmTrT = 0
End Sub

' Called each time the boss fires a volley, when not already mid-flyover.
' Always (re-)enters via a transition (state 5) first, then flyover (state 6) --
' the same path whether this is the very first entry from spawn or a repeat pass.
Sub BOSS_PickMode()
    Dim bpmHadPrevPass As Integer : bpmHadPrevPass = bsmFlFrameReady
    BOSS_FlyoverInit
    BOSS_TransitionInit bpmHadPrevPass
    boss.state = 5
End Sub
