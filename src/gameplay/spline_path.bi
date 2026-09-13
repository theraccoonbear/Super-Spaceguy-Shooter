' spline_path.bi — Catmull-Rom spline evaluation for boss flight paths.
'
' Generated functions (SpEf* prefix, in spline_path_gen.bi):
'   SpEfMkFrame, SpEfActualPos, SpEfRollFrame, SpEfCrWeights,
'   SpEfCrDerivWeights, SpEfFacingNorm, SpEfArcAdvance
'
' Hand-written infrastructure (array dispatch, ghost indices, scalar CR roll):
'   SpCrGhosts, SpEvalAt, SpTangentAt, SpEvalRollAt, SpShipFacing, SpSlewToward
'
' QB64-PE NOTE: All Dim and parameter names share a module-wide namespace.
' Every sub below uses a sub-specific prefix (sg=SpCrGhosts, sea=SpEvalAt,
' sta=SpTangentAt, sra=SpEvalRollAt, ssf=SpShipFacing, sst=SpSlewToward) to
' avoid collisions.
' Generated subs use their own prefixes (mf/ap/rf/cw/dw/fn/aa) — see math/spline-frame.js.
'
' Requires E3D_Coord (from src/3d/types.bi) before this file is included.

'$INCLUDE:'spline_path_gen.bi'

' ── Ghost indices (JS: ghosts()) ──────────────────────────────────────────
' Closed paths store an explicit duplicate of waypoint 0 as their last waypoint
' (the convention TrailForge's exporter uses -- see format.ts) rather than being
' truly cyclic over sgNW distinct points. So segment count is sgNW-1 either way
' (see the NS calcs below) and only the two boundary segments need wraparound
' ghost points, taken from the *other* end of the array, to keep curvature
' smooth across the seam without an extra zero-length closing segment (issue #211).
Sub SpCrGhosts (sgSeg As Integer, sgNW As Integer, sgCl As Integer, _
                sgG0 As Integer, sgG1 As Integer, sgG2 As Integer, sgG3 As Integer)
    If sgCl Then
        Dim sgLast As Integer : sgLast = sgNW - 2   ' index of the last unique point (sgNW-1 duplicates index 0)
        If sgSeg = 0 Then sgG0 = sgLast Else sgG0 = sgSeg - 1
        sgG1 = sgSeg
        sgG2 = sgSeg + 1
        If sgSeg = sgLast Then sgG3 = 1 Else sgG3 = sgSeg + 2
    Else
        sgG0 = sgSeg - 1 : If sgG0 < 0 Then sgG0 = 0
        sgG1 = sgSeg
        sgG2 = sgSeg + 1 : If sgG2 >= sgNW Then sgG2 = sgNW - 1
        sgG3 = sgSeg + 2 : If sgG3 >= sgNW Then sgG3 = sgNW - 1
    End If
End Sub

' ── Evaluate position at atParam (JS: evalAt) ────────────────────────────
Sub SpEvalAt (seaWps() As E3D_Coord, seaNW As Integer, seaAt As Single, seaCl As Integer, _
              seaOX As Single, seaOY As Single, seaOZ As Single)
    Dim seaNS As Integer : seaNS = seaNW - 1   ' closed paths store a duplicate closing waypoint -- see SpCrGhosts
    Dim seaSg As Integer : seaSg = Int(seaAt)
    If seaSg >= seaNS Then seaSg = seaNS - 1
    Dim seaT As Double : seaT = CDbl(seaAt) - seaSg
    Dim seaI0 As Integer, seaI1 As Integer, seaI2 As Integer, seaI3 As Integer
    SpCrGhosts seaSg, seaNW, seaCl, seaI0, seaI1, seaI2, seaI3
    Dim seaW0 As Double, seaW1 As Double, seaW2 As Double, seaW3 As Double
    SpEfCrWeights seaT, seaW0, seaW1, seaW2, seaW3
    seaOX = CSng(seaW0*seaWps(seaI0).x + seaW1*seaWps(seaI1).x + seaW2*seaWps(seaI2).x + seaW3*seaWps(seaI3).x)
    seaOY = CSng(seaW0*seaWps(seaI0).y + seaW1*seaWps(seaI1).y + seaW2*seaWps(seaI2).y + seaW3*seaWps(seaI3).y)
    seaOZ = CSng(seaW0*seaWps(seaI0).z + seaW1*seaWps(seaI1).z + seaW2*seaWps(seaI2).z + seaW3*seaWps(seaI3).z)
End Sub

' ── Evaluate normalized tangent at atParam (JS: tangentAt) ───────────────
Sub SpTangentAt (staWps() As E3D_Coord, staNW As Integer, staAt As Single, staCl As Integer, _
                 staTX As Single, staTY As Single, staTZ As Single)
    Dim staNS As Integer : staNS = staNW - 1   ' closed paths store a duplicate closing waypoint -- see SpCrGhosts
    Dim staSg As Integer : staSg = Int(staAt)
    If staSg >= staNS Then staSg = staNS - 1
    Dim staT As Double : staT = CDbl(staAt) - staSg
    Dim staI0 As Integer, staI1 As Integer, staI2 As Integer, staI3 As Integer
    SpCrGhosts staSg, staNW, staCl, staI0, staI1, staI2, staI3
    Dim staDW0 As Double, staDW1 As Double, staDW2 As Double, staDW3 As Double
    SpEfCrDerivWeights staT, staDW0, staDW1, staDW2, staDW3
    Dim staDX As Double : staDX = staDW0*staWps(staI0).x + staDW1*staWps(staI1).x + staDW2*staWps(staI2).x + staDW3*staWps(staI3).x
    Dim staDY As Double : staDY = staDW0*staWps(staI0).y + staDW1*staWps(staI1).y + staDW2*staWps(staI2).y + staDW3*staWps(staI3).y
    Dim staDZ As Double : staDZ = staDW0*staWps(staI0).z + staDW1*staWps(staI1).z + staDW2*staWps(staI2).z + staDW3*staWps(staI3).z
    Dim staFX As Double, staFY As Double, staFZ As Double
    SpEfFacingNorm staDX, staDY, staDZ, staFX, staFY, staFZ
    staTX = CSng(staFX) : staTY = CSng(staFY) : staTZ = CSng(staFZ)
End Sub

' ── CR scalar interpolation for roll arrays (JS: crEval1D / evalRollAt) ───
Sub SpEvalRollAt (sraRolls() As Single, sraNW As Integer, sraAt As Single, sraCl As Integer, _
                  sraRes As Single)
    Dim sraNS As Integer : sraNS = sraNW - 1   ' closed paths store a duplicate closing waypoint -- see SpCrGhosts
    Dim sraSg As Integer : sraSg = Int(sraAt)
    If sraSg >= sraNS Then sraSg = sraNS - 1
    Dim sraT As Double : sraT = CDbl(sraAt) - sraSg
    Dim sraI0 As Integer, sraI1 As Integer, sraI2 As Integer, sraI3 As Integer
    SpCrGhosts sraSg, sraNW, sraCl, sraI0, sraI1, sraI2, sraI3
    Dim sraW0 As Double, sraW1 As Double, sraW2 As Double, sraW3 As Double
    SpEfCrWeights sraT, sraW0, sraW1, sraW2, sraW3
    sraRes = CSng(sraW0*sraRolls(sraI0) + sraW1*sraRolls(sraI1) + sraW2*sraRolls(sraI2) + sraW3*sraRolls(sraI3))
End Sub

' ── shipFacing direction (JS: shipFacing) ─────────────────────────────────
' ssfOM 0=path-following (tangent), 1=fixed target
Sub SpShipFacing (ssfAX As Single, ssfAY As Single, ssfAZ As Single, _
                  ssfTnX As Single, ssfTnY As Single, ssfTnZ As Single, _
                  ssfOM As Integer, _
                  ssfTgX As Single, ssfTgY As Single, ssfTgZ As Single, _
                  ssfFX As Single, ssfFY As Single, ssfFZ As Single)
    If ssfOM = 1 Then
        Dim ssfDX As Single : ssfDX = ssfTgX - ssfAX
        Dim ssfDY As Single : ssfDY = ssfTgY - ssfAY
        Dim ssfDZ As Single : ssfDZ = ssfTgZ - ssfAZ
        Dim ssfFXD As Double, ssfFYD As Double, ssfFZD As Double
        SpEfFacingNorm CDbl(ssfDX), CDbl(ssfDY), CDbl(ssfDZ), ssfFXD, ssfFYD, ssfFZD
        ssfFX = CSng(ssfFXD) : ssfFY = CSng(ssfFYD) : ssfFZ = CSng(ssfFZD)
    Else
        ssfFX = ssfTnX : ssfFY = ssfTnY : ssfFZ = ssfTnZ
    End If
End Sub

' ── Slew a unit vector toward a target unit vector, capped at maxCos ──────
' If sstCur is already within sstMaxCos of sstTgt, snaps straight to sstTgt.
' Otherwise rotates sstCur toward sstTgt by exactly the max allowed angle
' (Rodrigues, axis = cur x tgt) -- used to smooth boss.bas's displayed facing
' through a real curve cusp (issue #211), where the analytic tangent itself
' legitimately flips discontinuously and no amount of finer position sampling
' can make that continuous. Output params may alias the input sstCur params.
Sub SpSlewToward (sstCurX As Single, sstCurY As Single, sstCurZ As Single, _
                  sstTgtX As Single, sstTgtY As Single, sstTgtZ As Single, _
                  sstMaxCos As Single, _
                  sstOutX As Single, sstOutY As Single, sstOutZ As Single)
    Dim sstDot As Single : sstDot = sstCurX*sstTgtX + sstCurY*sstTgtY + sstCurZ*sstTgtZ
    If sstDot >= sstMaxCos Then
        sstOutX = sstTgtX : sstOutY = sstTgtY : sstOutZ = sstTgtZ
        Exit Sub
    End If
    Dim sstAxX As Single, sstAxY As Single, sstAxZ As Single
    sstAxX = sstCurY*sstTgtZ - sstCurZ*sstTgtY
    sstAxY = sstCurZ*sstTgtX - sstCurX*sstTgtZ
    sstAxZ = sstCurX*sstTgtY - sstCurY*sstTgtX
    Dim sstAxLen As Single : sstAxLen = Sqr(sstAxX*sstAxX + sstAxY*sstAxY + sstAxZ*sstAxZ)
    If sstAxLen < 0.000001 Then
        ' cur and tgt are (anti-)parallel -- no well-defined rotation axis; snap
        ' to target rather than leave the facing frozen (rare, degenerate case).
        sstOutX = sstTgtX : sstOutY = sstTgtY : sstOutZ = sstTgtZ
        Exit Sub
    End If
    sstAxX = sstAxX / sstAxLen : sstAxY = sstAxY / sstAxLen : sstAxZ = sstAxZ / sstAxLen
    Dim sstSin As Single : sstSin = Sqr(1 - sstMaxCos*sstMaxCos)
    ' Rodrigues, axis is perpendicular to cur so the axis.(axis.cur) term drops:
    ' out = cur*cos(theta) + (axis x cur)*sin(theta)
    Dim sstCXx As Single, sstCXy As Single, sstCXz As Single
    sstCXx = sstAxY*sstCurZ - sstAxZ*sstCurY
    sstCXy = sstAxZ*sstCurX - sstAxX*sstCurZ
    sstCXz = sstAxX*sstCurY - sstAxY*sstCurX
    sstOutX = sstCurX*sstMaxCos + sstCXx*sstSin
    sstOutY = sstCurY*sstMaxCos + sstCXy*sstSin
    sstOutZ = sstCurZ*sstMaxCos + sstCXz*sstSin
End Sub
