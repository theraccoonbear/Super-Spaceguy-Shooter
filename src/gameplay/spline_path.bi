' spline_path.bi — Catmull-Rom spline evaluation for boss flight paths.
' Mirrors src/math/spline.ts exactly.  Single I/O; Double temps for precision.
' Ship local axes: X=forward  Y=up  Z=right
'
' QB64-PE NOTE: ALL Dim and parameter names in any Sub/Function share a single module-wide
' namespace.  Every name below uses a sub-specific prefix (sg=SpCrGhosts, sw=SpCrWeights,
' sea=SpEvalAt, sta=SpTangentAt, sra=SpEvalRollAt, smf=SpMakeFrame, sap=SpActualPos,
' ssf=SpShipFacing, srf=SpRollFrame) to prevent collisions with the rest of the codebase.
'
' Requires E3D_Coord (from src/3d/types.bi) to be defined before this file is included.

' ── Ghost indices (JS: ghosts()) ──────────────────────────────────────────
Sub SpCrGhosts (sgSeg As Integer, sgNW As Integer, sgCl As Integer, _
                sgG0 As Integer, sgG1 As Integer, sgG2 As Integer, sgG3 As Integer)
    If sgCl Then
        sgG0 = ((sgSeg - 1) Mod sgNW + sgNW) Mod sgNW
        sgG1 = sgSeg Mod sgNW
        sgG2 = (sgSeg + 1) Mod sgNW
        sgG3 = (sgSeg + 2) Mod sgNW
    Else
        sgG0 = sgSeg - 1 : If sgG0 < 0 Then sgG0 = 0
        sgG1 = sgSeg
        sgG2 = sgSeg + 1 : If sgG2 >= sgNW Then sgG2 = sgNW - 1
        sgG3 = sgSeg + 2 : If sgG3 >= sgNW Then sgG3 = sgNW - 1
    End If
End Sub

' ── CR basis weights (JS: crEval weights) ────────────────────────────────
Sub SpCrWeights (swT As Double, swW0 As Double, swW1 As Double, swW2 As Double, swW3 As Double)
    Dim swT2 As Double : swT2 = swT * swT
    Dim swT3 As Double : swT3 = swT2 * swT
    swW0 = 0.5 * (-swT3 + 2*swT2 - swT)
    swW1 = 0.5 * (3*swT3 - 5*swT2 + 2)
    swW2 = 0.5 * (-3*swT3 + 4*swT2 + swT)
    swW3 = 0.5 * (swT3 - swT2)
End Sub

' ── Evaluate position at atParam (JS: evalAt) ────────────────────────────
Sub SpEvalAt (seaWps() As E3D_Coord, seaNW As Integer, seaAt As Single, seaCl As Integer, _
              seaOX As Single, seaOY As Single, seaOZ As Single)
    Dim seaNS As Integer : If seaCl Then seaNS = seaNW Else seaNS = seaNW - 1
    Dim seaSg As Integer : seaSg = Int(seaAt)
    If seaSg >= seaNS Then seaSg = seaNS - 1
    Dim seaT As Double : seaT = CDbl(seaAt) - seaSg
    Dim seaI0 As Integer, seaI1 As Integer, seaI2 As Integer, seaI3 As Integer
    SpCrGhosts seaSg, seaNW, seaCl, seaI0, seaI1, seaI2, seaI3
    Dim seaW0 As Double, seaW1 As Double, seaW2 As Double, seaW3 As Double
    SpCrWeights seaT, seaW0, seaW1, seaW2, seaW3
    seaOX = CSng(seaW0*seaWps(seaI0).x + seaW1*seaWps(seaI1).x + seaW2*seaWps(seaI2).x + seaW3*seaWps(seaI3).x)
    seaOY = CSng(seaW0*seaWps(seaI0).y + seaW1*seaWps(seaI1).y + seaW2*seaWps(seaI2).y + seaW3*seaWps(seaI3).y)
    seaOZ = CSng(seaW0*seaWps(seaI0).z + seaW1*seaWps(seaI1).z + seaW2*seaWps(seaI2).z + seaW3*seaWps(seaI3).z)
End Sub

' ── Evaluate normalized tangent at atParam (JS: tangentAt) ───────────────
Sub SpTangentAt (staWps() As E3D_Coord, staNW As Integer, staAt As Single, staCl As Integer, _
                 staTX As Single, staTY As Single, staTZ As Single)
    Dim staNS As Integer : If staCl Then staNS = staNW Else staNS = staNW - 1
    Dim staSg As Integer : staSg = Int(staAt)
    If staSg >= staNS Then staSg = staNS - 1
    Dim staT As Double : staT = CDbl(staAt) - staSg
    Dim staI0 As Integer, staI1 As Integer, staI2 As Integer, staI3 As Integer
    SpCrGhosts staSg, staNW, staCl, staI0, staI1, staI2, staI3
    Dim staT2 As Double : staT2 = staT * staT
    Dim staDW0 As Double : staDW0 = 0.5 * (-3*staT2 + 4*staT - 1)
    Dim staDW1 As Double : staDW1 = 0.5 * (9*staT2 - 10*staT)
    Dim staDW2 As Double : staDW2 = 0.5 * (-9*staT2 + 8*staT + 1)
    Dim staDW3 As Double : staDW3 = 0.5 * (3*staT2 - 2*staT)
    Dim staDX As Double : staDX = staDW0*staWps(staI0).x + staDW1*staWps(staI1).x + staDW2*staWps(staI2).x + staDW3*staWps(staI3).x
    Dim staDY As Double : staDY = staDW0*staWps(staI0).y + staDW1*staWps(staI1).y + staDW2*staWps(staI2).y + staDW3*staWps(staI3).y
    Dim staDZ As Double : staDZ = staDW0*staWps(staI0).z + staDW1*staWps(staI1).z + staDW2*staWps(staI2).z + staDW3*staWps(staI3).z
    Dim staDL As Double : staDL = Sqr(staDX*staDX + staDY*staDY + staDZ*staDZ)
    If staDL > 0.000001 Then
        staTX = CSng(staDX/staDL) : staTY = CSng(staDY/staDL) : staTZ = CSng(staDZ/staDL)
    Else
        staTX = 1 : staTY = 0 : staTZ = 0
    End If
End Sub

' ── CR scalar interpolation for roll arrays (JS: crEval1D / evalRollAt) ───
' QB64-PE prohibits array params on Function declarations — uses Sub + result param instead.
Sub SpEvalRollAt (sraRolls() As Single, sraNW As Integer, sraAt As Single, sraCl As Integer, _
                  sraRes As Single)
    Dim sraNS As Integer : If sraCl Then sraNS = sraNW Else sraNS = sraNW - 1
    Dim sraSg As Integer : sraSg = Int(sraAt)
    If sraSg >= sraNS Then sraSg = sraNS - 1
    Dim sraT As Double : sraT = CDbl(sraAt) - sraSg
    Dim sraI0 As Integer, sraI1 As Integer, sraI2 As Integer, sraI3 As Integer
    SpCrGhosts sraSg, sraNW, sraCl, sraI0, sraI1, sraI2, sraI3
    Dim sraW0 As Double, sraW1 As Double, sraW2 As Double, sraW3 As Double
    SpCrWeights sraT, sraW0, sraW1, sraW2, sraW3
    sraRes = CSng(sraW0*sraRolls(sraI0) + sraW1*sraRolls(sraI1) + sraW2*sraRolls(sraI2) + sraW3*sraRolls(sraI3))
End Sub

' ── makeFrame: Gram-Schmidt {R,U} from normalized tangent T (JS: makeFrame) ──
' worldUp = (0,0,1) when |T.y|>0.98 (near-vertical); else (0,1,0).
' R = normalize(T × worldUp)   U = R × T
Sub SpMakeFrame (smfTX As Single, smfTY As Single, smfTZ As Single, _
                 smfRX As Single, smfRY As Single, smfRZ As Single, _
                 smfUX As Single, smfUY As Single, smfUZ As Single)
    Dim smfWY As Single, smfWZ As Single
    If Abs(smfTY) > 0.98 Then smfWY = 0 : smfWZ = 1 Else smfWY = 1 : smfWZ = 0
    ' R = T × worldUp  (worldUp.x always 0, so ry = -tx*wz, rz = tx*wy)
    smfRX = smfTY*smfWZ - smfTZ*smfWY
    smfRY = smfTZ*0 - smfTX*smfWZ
    smfRZ = smfTX*smfWY - smfTY*0
    Dim smfRL As Single : smfRL = Sqr(smfRX*smfRX + smfRY*smfRY + smfRZ*smfRZ)
    If smfRL > 0.000001 Then smfRX = smfRX/smfRL : smfRY = smfRY/smfRL : smfRZ = smfRZ/smfRL
    ' U = R × T
    smfUX = smfRY*smfTZ - smfRZ*smfTY
    smfUY = smfRZ*smfTX - smfRX*smfTZ
    smfUZ = smfRX*smfTY - smfRY*smfTX
End Sub

' ── actualPos: standoff perpendicular offset (JS: actualPos) ─────────────
' actual = wire + standoff*(cos(pRollRad)*U + sin(pRollRad)*R)
Sub SpActualPos (sapWX As Single, sapWY As Single, sapWZ As Single, _
                 sapTX As Single, sapTY As Single, sapTZ As Single, _
                 sapPRDeg As Single, sapSO As Single, _
                 sapOX As Single, sapOY As Single, sapOZ As Single)
    If sapSO < 0.001 Then sapOX = sapWX : sapOY = sapWY : sapOZ = sapWZ : Exit Sub
    Dim sapRX As Single, sapRY As Single, sapRZ As Single
    Dim sapUX As Single, sapUY As Single, sapUZ As Single
    SpMakeFrame sapTX, sapTY, sapTZ, sapRX, sapRY, sapRZ, sapUX, sapUY, sapUZ
    Dim sapRad As Single : sapRad = sapPRDeg * (3.14159265! / 180!)
    Dim sapCos As Single : sapCos = Cos(sapRad)
    Dim sapSin As Single : sapSin = Sin(sapRad)
    sapOX = sapWX + sapSO * (sapCos*sapUX + sapSin*sapRX)
    sapOY = sapWY + sapSO * (sapCos*sapUY + sapSin*sapRY)
    sapOZ = sapWZ + sapSO * (sapCos*sapUZ + sapSin*sapRZ)
End Sub

' ── shipFacing direction (JS: shipFacing) ─────────────────────────────────
' ssfOM 0=path-following (tangent), 1=fixed target
Sub SpShipFacing (ssfAX As Single, ssfAY As Single, ssfAZ As Single, _
                  ssfTnX As Single, ssfTnY As Single, ssfTnZ As Single, _
                  ssfOM As Integer, _
                  ssfTgX As Single, ssfTgY As Single, ssfTgZ As Single, _
                  ssfFX As Single, ssfFY As Single, ssfFZ As Single)
    If ssfOM = 1 Then
        ssfFX = ssfTgX - ssfAX : ssfFY = ssfTgY - ssfAY : ssfFZ = ssfTgZ - ssfAZ
        Dim ssfDsq As Single : ssfDsq = ssfFX*ssfFX + ssfFY*ssfFY + ssfFZ*ssfFZ
        If ssfDsq < 0.000001 Then
            ssfFX = 1 : ssfFY = 0 : ssfFZ = 0
        Else
            Dim ssfD As Single : ssfD = Sqr(ssfDsq)
            ssfFX = ssfFX/ssfD : ssfFY = ssfFY/ssfD : ssfFZ = ssfFZ/ssfD
        End If
    Else
        ssfFX = ssfTnX : ssfFY = ssfTnY : ssfFZ = ssfTnZ
    End If
End Sub

' ── rollFrame: craftRoll rotation of {U,R} (JS: rollFrame) ───────────────
' rolledU = cos(rad)*U - sin(rad)*R
' rolledR = sin(rad)*U + cos(rad)*R
Sub SpRollFrame (srfUX As Single, srfUY As Single, srfUZ As Single, _
                 srfRX As Single, srfRY As Single, srfRZ As Single, _
                 srfCRDeg As Single, _
                 srfRUX As Single, srfRUY As Single, srfRUZ As Single, _
                 srfRRX As Single, srfRRY As Single, srfRRZ As Single)
    Dim srfRad As Single : srfRad = srfCRDeg * (3.14159265! / 180!)
    Dim srfC As Single : srfC = Cos(srfRad)
    Dim srfS As Single : srfS = Sin(srfRad)
    srfRUX = srfC*srfUX - srfS*srfRX : srfRUY = srfC*srfUY - srfS*srfRY : srfRUZ = srfC*srfUZ - srfS*srfRZ
    srfRRX = srfS*srfUX + srfC*srfRX : srfRRY = srfS*srfUY + srfC*srfRY : srfRRZ = srfS*srfUZ + srfC*srfRZ
End Sub
