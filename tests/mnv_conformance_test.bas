' mnv_conformance_test.bas -- cross-language conformance guard.
'
' SpEvalAt/SpTangentAt (spline_path.bi) and evalAt/tangentAt (TrailForge's
' src/math/spline.ts) are two independently hand-written implementations of
' the same closed-loop Catmull-Rom wraparound logic -- ExprForge generates
' the underlying weight/frame math identically into both languages, but the
' ghost-point array indexing and segment-count logic around it (SpCrGhosts /
' ghosts()) has no ExprForge array/indexing primitive to be generated from,
' so it is duplicated by hand once per language. That hand-duplication is
' exactly what caused both issue #211 (tangent flip) and the "teleport from
' last node to 0" bug: the two copies silently drifted apart.
'
' This test pins the QB64 side against real values computed by the actual
' TrailForge evalAt/tangentAt (see tools/TrailForge/src/math/spline.ts) on
' attack-pass's raw on-disk waypoints (duplicate closing waypoint present --
' the only shape the QB64 loader ever sees). If a future change to either
' side's hand-written wraparound logic makes them disagree, this test fails
' instead of the two implementations silently drifting again.
'
' To regenerate the golden values after an intentional math change: run the
' equivalent evalAt/tangentAt loop from tools/TrailForge/src/math/spline.ts
' against the same waypoint array and t values below, and update GOLDEN().
'
' Build: from repo root:
'   ./tools/buildqb tests/mnv_conformance_test.bas
' Run:   builds/mnv_conformance_test   (exit 0 = pass, exit 1 = fail)

$CONSOLE:ONLY

Sub DBG_Print(dbgMsg As String)
End Sub

'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/gameplay/spline_path.bi'

Const NW = 13   ' attack-pass.mvr waypoint count, including the duplicate closing waypoint
Dim Shared wps(0 To NW - 1) As E3D_Coord

Sub SetWp (idx As Integer, wx As Single, wy As Single, wz As Single)
    wps(idx).x = wx : wps(idx).y = wy : wps(idx).z = wz
End Sub

' attack-pass.mvr waypoints (turnDir=1) -- must match tools/TrailForge/src/math/loop-seam.test.ts's `wps`.
SetWp 0, 53.4405, 7.7616, -0.3503
SetWp 1, 49.4578, 3.2207, 33.0769
SetWp 2, 33.6243, 9.2982, 24.6690
SetWp 3, 8.7777, -0.7114, 0.1266
SetWp 4, -12.4921, -2.5898, 4.2717
SetWp 5, -19.0767, 15.1416, 12.1857
SetWp 6, -29.1371, 3, 4.0848
SetWp 7, -23.7362, -3.6647, -4.2481
SetWp 8, 0.3152, 3.6258, 0.5884
SetWp 9, 33.1357, -1.6223, -2.9403
SetWp 10, 42.0103, -1.6223, -21.8501
SetWp 11, 54.0500, 1.1726, -26.2122
SetWp 12, 53.4405, 7.7616, -0.3503

Const NSAMPLES = 25
Const NSEGS_F = 12.0   ' NW - 1

' Golden values from tools/TrailForge/src/math/spline.ts's real evalAt/tangentAt,
' sampled at t = (i/25)*12 for i = 0..24: t, px,py,pz, tx,ty,tz
Dim Shared GOLDEN(0 To NSAMPLES - 1, 0 To 6) As Double
Sub SetGolden (i As Integer, gt As Double, px As Double, py As Double, pz As Double, tx As Double, ty As Double, tz As Double)
    GOLDEN(i, 0) = gt : GOLDEN(i, 1) = px : GOLDEN(i, 2) = py : GOLDEN(i, 3) = pz
    GOLDEN(i, 4) = tx : GOLDEN(i, 5) = ty : GOLDEN(i, 6) = tz
End Sub

SetGolden 0, 0.000000, 53.440500, 7.761600, -0.350300, -0.077177, 0.034421, 0.996423
SetGolden 1, 0.480000, 52.457622, 5.668169, 17.709888, -0.068267, -0.178086, 0.981644
SetGolden 2, 0.960000, 49.838133, 3.215165, 32.505106, -0.493903, -0.025692, 0.869137
SetGolden 3, 1.440000, 43.797253, 6.034265, 33.138330, -0.753558, 0.457338, -0.472221
SetGolden 4, 1.920000, 35.231016, 9.325384, 26.011044, -0.758337, 0.045954, -0.650240
SetGolden 5, 2.400000, 24.162917, 6.062334, 14.636724, -0.624016, -0.295085, -0.723553
SetGolden 6, 2.880000, 11.650207, 0.213872, 1.840980, -0.772774, -0.290743, -0.564171
SetGolden 7, 3.360000, 0.247837, -2.800379, -0.652540, -0.964097, -0.200807, 0.173764
SetGolden 8, 3.840000, -9.956340, -3.483617, 3.087289, -0.888336, 0.170996, 0.426168
SetGolden 9, 4.320000, -15.564628, 2.673495, 7.082916, -0.242913, 0.878174, 0.412073
SetGolden 10, 4.800000, -17.772292, 13.193435, 11.567551, -0.290290, 0.896144, 0.335646
SetGolden 11, 5.280000, -22.077732, 13.755435, 11.086293, -0.678995, -0.620775, -0.391924
SetGolden 12, 5.760000, -27.718179, 6.188229, 6.395631, -0.420527, -0.758771, -0.497416
SetGolden 13, 6.240000, -29.320760, 0.715406, 1.812733, 0.063696, -0.671272, -0.738469
SetGolden 14, 6.720000, -27.038410, -2.965977, -2.864122, 0.702966, -0.388907, -0.595475
SetGolden 15, 7.200000, -20.259858, -2.899115, -3.989798, 0.929848, 0.319316, 0.182810
SetGolden 16, 7.680000, -8.679357, 1.734632, -0.798895, 0.918974, 0.318143, 0.232964
SetGolden 17, 8.160000, 5.328948, 3.437455, 0.661384, 0.995683, -0.092682, 0.004964
SetGolden 18, 8.640000, 22.722131, 0.400085, -0.189029, 0.970141, -0.207424, -0.125704
SetGolden 19, 9.120000, 35.293220, -1.883856, -4.586983, 0.688890, -0.078892, -0.720560
SetGolden 20, 9.600000, 39.381976, -2.075442, -14.595322, 0.213082, 0.029504, -0.976589
SetGolden 21, 10.080000, 42.903558, -1.504502, -22.780574, 0.711442, 0.093307, -0.696523
SetGolden 22, 10.560000, 49.453652, -0.470424, -27.166692, 0.923346, 0.194396, -0.331124
SetGolden 23, 11.040000, 54.261361, 1.374775, -25.740623, 0.329978, 0.366945, 0.869750
SetGolden 24, 11.520000, 54.709705, 5.093884, -15.065508, -0.063484, 0.276294, 0.958974

' Single-precision round trip through SpEvalAt/SpTangentAt loses a bit more
' than double precision would -- tolerance reflects that, not sloppiness.
Const POS_TOL = 0.01
Const TAN_TOL = 0.002

Dim i As Integer, worstPosErr As Double, worstTanErr As Double
Dim worstPosI As Integer, worstTanI As Integer

For i = 0 To NSAMPLES - 1
    Dim t As Single : t = CSng(GOLDEN(i, 0))
    Dim px As Single, py As Single, pz As Single
    Dim tx As Single, ty As Single, tz As Single
    SpEvalAt wps(), NW, t, -1, px, py, pz
    SpTangentAt wps(), NW, t, -1, tx, ty, tz

    Dim posErr As Double
    posErr = Sqr((px - GOLDEN(i, 1)) ^ 2 + (py - GOLDEN(i, 2)) ^ 2 + (pz - GOLDEN(i, 3)) ^ 2)
    Dim tanErr As Double
    tanErr = Sqr((tx - GOLDEN(i, 4)) ^ 2 + (ty - GOLDEN(i, 5)) ^ 2 + (tz - GOLDEN(i, 6)) ^ 2)

    If posErr > worstPosErr Then worstPosErr = posErr : worstPosI = i
    If tanErr > worstTanErr Then worstTanErr = tanErr : worstTanI = i

    If posErr > POS_TOL Or tanErr > TAN_TOL Then
        Print "MISMATCH @ t=" + Str$(t) + "  posErr=" + Str$(posErr) + "  tanErr=" + Str$(tanErr)
        Print "  QB64:  pos=(" + Str$(px) + "," + Str$(py) + "," + Str$(pz) + ")  tan=(" + Str$(tx) + "," + Str$(ty) + "," + Str$(tz) + ")"
        Print "  TS  :  pos=(" + Str$(GOLDEN(i, 1)) + "," + Str$(GOLDEN(i, 2)) + "," + Str$(GOLDEN(i, 3)) + ")  tan=(" + Str$(GOLDEN(i, 4)) + "," + Str$(GOLDEN(i, 5)) + "," + Str$(GOLDEN(i, 6)) + ")"
    End If
Next i

Print
Print "worst position error=" + Str$(worstPosErr) + " @sample " + LTrim$(Str$(worstPosI)) + "  (tol=" + Str$(POS_TOL) + ")"
Print "worst tangent error=" + Str$(worstTanErr) + " @sample " + LTrim$(Str$(worstTanI)) + "  (tol=" + Str$(TAN_TOL) + ")"

If worstPosErr > POS_TOL Or worstTanErr > TAN_TOL Then
    Print "FAIL  QB64 SpEvalAt/SpTangentAt disagrees with TrailForge's TS evalAt/tangentAt -- see MISMATCH lines above"
    System 1
Else
    Print "PASS  QB64 and TS spline evaluation agree within tolerance"
    System 0
End If
