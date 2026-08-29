' Boss movement modes (boss.state):
'   0 idle       -- closing initial spawn distance to BOSS_COMBAT_DIST on X; no other motion
'   6 flyover    -- Catmull-Rom spline: the boss's sole active movement pattern, driven
'                   entirely by the maneuver loaded via MNV_Load (assets/maneuvers/*.mvr)
'
' Flyover path (state 6): boss.arcAngle is repurposed as the spline t parameter (0..bsmWpCount-1).
' Waypoints are player-relative and set by BOSS_FlyoverInit at state entry; Z column is signed
' by bsmTurnDir so the arc alternates sides each pass.  Attitude (yaw/pitch/roll) is derived
' from the spline tangent (velocity vector) each frame, so banking follows the curve naturally.

' BOSS_COMBAT_DIST defined here (behavior.bas included before boss.bas)
Const BOSS_COMBAT_DIST = 20    ' standard X distance for combat

Const BOSS_CHARGE_CD1 = 300    ' frames between charge eligibility, phase 1
Const BOSS_CHARGE_CD2 = 190    ' phase 2
Const BOSS_CHARGE_CD3 = 110    ' phase 3

Dim Shared bsmFlySpd      As Single   ' t-advance per frame; set by MNV_Load
Dim Shared bsmManeuverName As String   ' which [block] to load; set before BOSS_FlyoverInit

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
    Dim bsmFlNS As Integer     ' number of segments (nWps for closed, nWps-1 for open)
    Dim bsmFlPR As Single      ' interpolated pathRoll (degrees)
    Dim bsmFlAX As Single, bsmFlAY As Single, bsmFlAZ As Single     ' actual pos after standoff
    Dim bsmFlAXD As Double, bsmFlAYD As Double, bsmFlAZD As Double  ' Double temps for SpEfActualPos
    Dim bsmTfNRX As Double, bsmTfNRY As Double, bsmTfNRZ As Double  ' SpEfTransportFrame output R
    Dim bsmTfNUX As Double, bsmTfNUY As Double, bsmTfNUZ As Double  ' SpEfTransportFrame output U
    Dim bsmEvX As Single, bsmEvY As Single, bsmEvZ As Single        ' SpEvalAt output (player-relative)
    Dim bsmDw0D As Double, bsmDw1D As Double, bsmDw2D As Double, bsmDw3D As Double  ' SpEfCrDerivWeights output
    Dim bsmDXD As Double, bsmDYD As Double, bsmDZD As Double        ' raw (unnormalized) derivative
    Dim bsmArcAdvD As Double                                        ' SpEfArcAdvance output
    Dim bsmTanLen As Single

    boss.chargeTimer = boss.chargeTimer - 1
    If boss.chargeTimer < 0 Then boss.chargeTimer = 0

    Select Case boss.state
    Case 6  ' flyover: Catmull-Rom spline — supports standoff, closed paths, pathRoll
        bsmFt    = boss.arcAngle
        bsmFseg  = Int(bsmFt)
        bsmFlNS  = bsmWpCount - 1
        If bsmClosed Then bsmFlNS = bsmWpCount   ' closed: N segments (one extra wraps back)
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
            bsmFu = bsmFt - bsmFseg

            ' Position and normalized tangent: both fully delegated to the shared,
            ' ExprForge-backed evaluators (spline_path.bi) -- no hand-copied CR math.
            SpEvalAt bsmWp(), bsmWpCount, bsmFt, bsmClosed, bsmEvX, bsmEvY, bsmEvZ
            boss.px = player.px + bsmEvX
            boss.py = player.py + bsmEvY
            boss.pz = player.pz + bsmEvZ
            SpTangentAt bsmWp(), bsmWpCount, bsmFt, bsmClosed, bsmFlTnX, bsmFlTnY, bsmFlTnZ

            ' Raw (unnormalized) derivative -- needed only for the arc-length speed
            ' correction below, since SpTangentAt returns just the normalized tangent.
            ' SpCrGhosts/SpEfCrDerivWeights are the same generated/shared calls
            ' SpTangentAt makes internally; recomputed here rather than changing its
            ' signature to expose them.
            SpCrGhosts bsmFseg, bsmWpCount, bsmClosed, bsmFi0, bsmFi1, bsmFi2, bsmFi3
            SpEfCrDerivWeights CDbl(bsmFu), bsmDw0D, bsmDw1D, bsmDw2D, bsmDw3D
            bsmDXD = bsmDw0D*bsmWp(bsmFi0).x + bsmDw1D*bsmWp(bsmFi1).x + bsmDw2D*bsmWp(bsmFi2).x + bsmDw3D*bsmWp(bsmFi3).x
            bsmDYD = bsmDw0D*bsmWp(bsmFi0).y + bsmDw1D*bsmWp(bsmFi1).y + bsmDw2D*bsmWp(bsmFi2).y + bsmDw3D*bsmWp(bsmFi3).y
            bsmDZD = bsmDw0D*bsmWp(bsmFi0).z + bsmDw1D*bsmWp(bsmFi1).z + bsmDw2D*bsmWp(bsmFi2).z + bsmDw3D*bsmWp(bsmFi3).z
            SpEfArcAdvance bsmDXD, bsmDYD, bsmDZD, CDbl(bsmFlySpd), bsmArcAdvD
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

            ' Parallel transport: maintain frame (R,U) across ticks using Rodrigues rotation.
            ' Matches editor exactly — same SpEfTransportFrame function, same 100% shared math.
            If bsmFlFrameReady = 0 Then
                SpEfMkFrame CDbl(bsmFlTnX), CDbl(bsmFlTnY), CDbl(bsmFlTnZ), _
                            bsmTfNRX, bsmTfNRY, bsmTfNRZ, bsmTfNUX, bsmTfNUY, bsmTfNUZ
                bsmFlFRX = CSng(bsmTfNRX) : bsmFlFRY = CSng(bsmTfNRY) : bsmFlFRZ = CSng(bsmTfNRZ)
                bsmFlFUX = CSng(bsmTfNUX) : bsmFlFUY = CSng(bsmTfNUY) : bsmFlFUZ = CSng(bsmTfNUZ)
                bsmFlPrevTnX = bsmFlTnX : bsmFlPrevTnY = bsmFlTnY : bsmFlPrevTnZ = bsmFlTnZ
                bsmFlFrameReady = 1
            Else
                SpEfTransportFrame CDbl(bsmFlPrevTnX), CDbl(bsmFlPrevTnY), CDbl(bsmFlPrevTnZ), _
                                   CDbl(bsmFlTnX),     CDbl(bsmFlTnY),     CDbl(bsmFlTnZ), _
                                   CDbl(bsmFlFRX), CDbl(bsmFlFRY), CDbl(bsmFlFRZ), _
                                   CDbl(bsmFlFUX), CDbl(bsmFlFUY), CDbl(bsmFlFUZ), _
                                   bsmTfNRX, bsmTfNRY, bsmTfNRZ, bsmTfNUX, bsmTfNUY, bsmTfNUZ
                bsmFlFRX = CSng(bsmTfNRX) : bsmFlFRY = CSng(bsmTfNRY) : bsmFlFRZ = CSng(bsmTfNRZ)
                bsmFlFUX = CSng(bsmTfNUX) : bsmFlFUY = CSng(bsmTfNUY) : bsmFlFUZ = CSng(bsmTfNUZ)
                bsmFlPrevTnX = bsmFlTnX : bsmFlPrevTnY = bsmFlTnY : bsmFlPrevTnZ = bsmFlTnZ
            End If

            ' Standoff: offset wire position perpendicular to tangent by pathRoll angle (JS: actualPos)
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

' Load the named flyover maneuver (via MNV_Load, from assets/maneuvers/*.mvr),
' apply bsmTurnDir sign to the Z column, then anchor P0 to the boss's actual
' position so there is no positional snap at flyover entry.
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
    ' Anchor P0 to boss's current player-relative position to prevent positional snap.
    ' Skip for closed paths: modular ghost wrapping means modifying P0 breaks the seam.
    If bsmClosed = 0 And bsmWpCount > 0 Then
        bsmWp(0).x = boss.px - player.px
        bsmWp(0).y = boss.py - player.py
        bsmWp(0).z = boss.pz - player.pz
    End If
    bsmFlFrameReady = 0   ' transport frame will be initialized on the first Case 6 tick
    Dim bfiT As Integer
    For bfiT = 0 To bsmPhaseTrigCount - 1
        bsmPhaseTrigFired(bfiT) = 0
    Next bfiT
End Sub

' Called each time the boss fires a volley, when not already mid-flyover.
' The boss's only movement mode is flyover -- always (re-)enter it.
Sub BOSS_PickMode()
    boss.arcAngle = 0
    BOSS_FlyoverInit
    boss.state = 6
End Sub
