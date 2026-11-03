' Frame-time bench (#394): --bench <file> times each frame's phases and writes the table at the
' end of a --frames run. BENCH_Lap is a no-op without the flag, so normal play is untouched.
' Driven by tools/dev bench (tests/bench/bench.sh).
Const BENCH_SIM = 0
Const BENCH_BACKDROP = 1
Const BENCH_BUILD = 2
Const BENCH_RASTER = 3
Const BENCH_PARTICLES = 4
Const BENCH_OVERLAY = 5
Const BENCH_FX = 6
Const BENCH_HUD = 7
Const BENCH_REST = 8
Const BENCH_TOTAL = 9

Dim Shared benchOn As Integer
Dim Shared benchLast As Double
Dim Shared benchStart As Double
Dim Shared benchRendered As Integer
Dim Shared benchN As Long
Dim Shared benchAcc(0 To 9) As Single
ReDim Shared benchMs(0 To 9, 1 To 1) As Single

Sub BENCH_Init ()
    ReDim benchMs(0 To 9, 1 To cliFrames) As Single
    benchOn = -1
End Sub

Sub BENCH_FrameBegin ()
    Dim bfI As Integer
    If benchOn = 0 Then Exit Sub
    If benchStart > 0 Then BENCH_FrameEnd
    For bfI = 0 To 9
        benchAcc(bfI) = 0
    Next bfI
    benchRendered = 0
    benchStart = Timer(0.001)
    benchLast = benchStart
End Sub

Sub BENCH_Lap (blPhase As Integer)
    Dim blNow As Double
    If benchOn = 0 Then Exit Sub
    blNow = Timer(0.001)
    If blNow > benchLast Then benchAcc(blPhase) = benchAcc(blPhase) + (blNow - benchLast) * 1000
    benchLast = blNow
    If blPhase = BENCH_RASTER Then benchRendered = -1
End Sub

' Closes the previous frame, started by BENCH_FrameBegin, so the main loop needs no call of its own at the end. Frames that never reached the renderer (menus, crawls, pause) are left out.
Sub BENCH_FrameEnd ()
    Dim beI As Integer
    BENCH_Lap BENCH_REST
    If benchRendered = 0 Or benchN >= cliFrames Then Exit Sub
    benchN = benchN + 1
    For beI = 0 To 8
        benchMs(beI, benchN) = benchAcc(beI)
    Next beI
    benchMs(BENCH_TOTAL, benchN) = (benchLast - benchStart) * 1000
End Sub

Function BENCH_Fmt$ (bmV As Single)
    Dim bmU As Long
    bmU = Int(bmV * 1000 + 0.5)
    BENCH_Fmt$ = Right$(Space$(9) + LTrim$(Str$(bmU \ 1000)) + "." + Right$("000" + LTrim$(Str$(bmU Mod 1000)), 3), 9)
End Function

Sub BENCH_Sort (bsA() As Single, bsN As Long)
    Dim bsGap As Long, bsI As Long, bsJ As Long, bsT As Single
    bsGap = bsN \ 2
    Do While bsGap > 0
        For bsI = bsGap + 1 To bsN
            bsT = bsA(bsI)
            bsJ = bsI
            Do While bsJ > bsGap
                If bsA(bsJ - bsGap) <= bsT Then Exit Do
                bsA(bsJ) = bsA(bsJ - bsGap)
                bsJ = bsJ - bsGap
            Loop
            bsA(bsJ) = bsT
        Next bsI
        bsGap = bsGap \ 2
    Loop
End Sub

Sub BENCH_Report ()
    Dim brF As Integer, brP As Integer, brI As Long, brSum As Double, brP95 As Long
    Dim brCol(1 To 1) As Single
    Dim brNames(0 To 9) As String
    If benchOn = 0 Then Exit Sub
    brNames(0) = "sim" : brNames(1) = "backdrop" : brNames(2) = "scene_build" : brNames(3) = "raster"
    brNames(4) = "particles" : brNames(5) = "overlay" : brNames(6) = "fx" : brNames(7) = "hud"
    brNames(8) = "rest" : brNames(9) = "total"
    brF = FreeFile
    Open benchPath For Output As #brF
    Print #brF, "frames_measured " + LTrim$(Str$(benchN)) + " of " + LTrim$(Str$(cliFrames))
    Print #brF, "phase           avg_ms    p95_ms  worst_ms"
    If benchN > 0 Then
        ReDim brCol(1 To benchN) As Single
        brP95 = Int(benchN * 0.95 + 0.999999)
        If brP95 < 1 Then brP95 = 1
        If brP95 > benchN Then brP95 = benchN
        For brP = 0 To 9
            brSum = 0
            For brI = 1 To benchN
                brCol(brI) = benchMs(brP, brI)
                brSum = brSum + brCol(brI)
            Next brI
            BENCH_Sort brCol(), benchN
            Print #brF, Left$(brNames(brP) + Space$(14), 14) + BENCH_Fmt$(brSum / benchN) + BENCH_Fmt$(brCol(brP95)) + BENCH_Fmt$(brCol(benchN))
        Next brP
    End If
    Close #brF
End Sub
