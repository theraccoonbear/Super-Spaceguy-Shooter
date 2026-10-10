' spline_path.bi — Catmull-Rom spline evaluation for boss flight paths.
'
' Generated functions (SpEf* prefix, in spline_path_gen.bi):
'   SpEfMkFrame, SpEfActualPos, SpEfRollFrame, SpEfCrWeights,
'   SpEfCrDerivWeights, SpEfFacingNorm, SpEfArcAdvance, SpEfGhostIndices
'
' Hand-written infrastructure (array dispatch, scalar CR roll):
'   SpEvalAt, SpTangentAt, SpEvalRollAt, SpShipFacing, SpSlewToward
'
' QB64-PE NOTE: All Dim and parameter names share a module-wide namespace.
' Every sub below uses a sub-specific prefix (sea=SpEvalAt, sta=SpTangentAt,
' sra=SpEvalRollAt, ssf=SpShipFacing, sst=SpSlewToward) to avoid collisions.
' Generated subs use their own prefixes (mf/ap/rf/cw/dw/fn/aa/gi/cd) — see
' math/formula.expr.
'
' Requires E3D_Coord (from src/3d/types.bi) before this file is included.

'$INCLUDE:'spline_path_gen.bi'

' ── Evaluate position at atParam (JS: evalAt) ────────────────────────────
' Ghost-point index math (wraparound at a closed loop's seam, clamping at an
' open path's ends -- issue #211) now lives in SpEfGhostIndices, generated
' from math/formula.expr instead of hand-written here -- see
' docs/proposals/exprforge-array-support.md. seaCl is normalized to a strict
' 0.0/1.0 double before the call: QB64's own boolean True is -1, and
' SpEfGhostIndices deliberately checks "> 0", not "<> 0" or "!= 0" (ExprForge's
' QB64 emitter passes "!=" through verbatim, which isn't valid QB64 -- see
' that same doc).
Sub SpEvalAt (seaWps() As E3D_Coord, seaNW As Integer, seaAt As Single, seaCl As Integer, _
              seaOX As Single, seaOY As Single, seaOZ As Single)
    Dim seaNS As Integer : seaNS = seaNW - 1   ' closed paths store a duplicate closing waypoint -- see SpEfGhostIndices
    Dim seaSg As Integer : seaSg = Int(seaAt)
    If seaSg >= seaNS Then seaSg = seaNS - 1
    Dim seaT As Double : seaT = CDbl(seaAt) - seaSg
    Dim seaClF As Double : If seaCl <> 0 Then seaClF = 1 Else seaClF = 0
    Dim seaI0D As Double, seaI1D As Double, seaI2D As Double, seaI3D As Double
    SpEfGhostIndices CDbl(seaNW), CDbl(seaSg), seaClF, seaI0D, seaI1D, seaI2D, seaI3D
    Dim seaI0 As Integer, seaI1 As Integer, seaI2 As Integer, seaI3 As Integer
    seaI0 = CInt(seaI0D) : seaI1 = CInt(seaI1D) : seaI2 = CInt(seaI2D) : seaI3 = CInt(seaI3D)
    Dim seaW0 As Double, seaW1 As Double, seaW2 As Double, seaW3 As Double
    SpEfCrWeights seaT, seaW0, seaW1, seaW2, seaW3
    seaOX = CSng(seaW0*seaWps(seaI0).x + seaW1*seaWps(seaI1).x + seaW2*seaWps(seaI2).x + seaW3*seaWps(seaI3).x)
    seaOY = CSng(seaW0*seaWps(seaI0).y + seaW1*seaWps(seaI1).y + seaW2*seaWps(seaI2).y + seaW3*seaWps(seaI3).y)
    seaOZ = CSng(seaW0*seaWps(seaI0).z + seaW1*seaWps(seaI1).z + seaW2*seaWps(seaI2).z + seaW3*seaWps(seaI3).z)
End Sub

' ── Evaluate normalized tangent at atParam (JS: tangentAt) ───────────────
Sub SpTangentAt (staWps() As E3D_Coord, staNW As Integer, staAt As Single, staCl As Integer, _
                 staTX As Single, staTY As Single, staTZ As Single)
    Dim staNS As Integer : staNS = staNW - 1   ' closed paths store a duplicate closing waypoint -- see SpEfGhostIndices
    Dim staSg As Integer : staSg = Int(staAt)
    If staSg >= staNS Then staSg = staNS - 1
    Dim staT As Double : staT = CDbl(staAt) - staSg
    Dim staClF As Double : If staCl <> 0 Then staClF = 1 Else staClF = 0
    Dim staI0D As Double, staI1D As Double, staI2D As Double, staI3D As Double
    SpEfGhostIndices CDbl(staNW), CDbl(staSg), staClF, staI0D, staI1D, staI2D, staI3D
    Dim staI0 As Integer, staI1 As Integer, staI2 As Integer, staI3 As Integer
    staI0 = CInt(staI0D) : staI1 = CInt(staI1D) : staI2 = CInt(staI2D) : staI3 = CInt(staI3D)
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
    Dim sraNS As Integer : sraNS = sraNW - 1   ' closed paths store a duplicate closing waypoint -- see SpEfGhostIndices
    Dim sraSg As Integer : sraSg = Int(sraAt)
    If sraSg >= sraNS Then sraSg = sraNS - 1
    Dim sraT As Double : sraT = CDbl(sraAt) - sraSg
    Dim sraClF As Double : If sraCl <> 0 Then sraClF = 1 Else sraClF = 0
    Dim sraI0D As Double, sraI1D As Double, sraI2D As Double, sraI3D As Double
    SpEfGhostIndices CDbl(sraNW), CDbl(sraSg), sraClF, sraI0D, sraI1D, sraI2D, sraI3D
    Dim sraI0 As Integer, sraI1 As Integer, sraI2 As Integer, sraI3 As Integer
    sraI0 = CInt(sraI0D) : sraI1 = CInt(sraI1D) : sraI2 = CInt(sraI2D) : sraI3 = CInt(sraI3D)
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
