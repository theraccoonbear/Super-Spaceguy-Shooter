' wavetiming.bas -- when, how big and how far ahead a combat stage's enemy waves spawn, how
' hard its fighters fire, and the clear-out at the end of a stage (#90)
'
' Tuning comes from assets/config/waves.ini (see the comments there). No spawning here
' (wave.bas and enemy.bas do that), so tests drive it directly:
'   ok = WVT_Load%                   read the tuning (after CFG_Parse$ of waves.ini); 0 + wvtLoadErr
'   t = WVT_GapTicks!(n, diff, st)   spawnTimer value the next wave waits for, when n waves of
'                                    stage st have spawned so far, at difficulty diff (0..1)
'   m = WVT_WaveSize%(n, st, size)   members a wave gets: an opening wave is cut down
'   d = WVT_DistMin!(n)              spawn distance ahead of the ship for that wave: min...
'   v = WVT_DistVar!(n)              ...and variance
'   f = WVT_FireScale!(st)           multiplier on enemy fire cooldowns in stage st
'   ok = WVT_CanSpawn%(cleared)      0 once the stage's kill target is reached
'   r = WVT_ClearDone%(t, e, p, pop) clear-out after t frames with e fighters, p power-ups and
'                                    a score pop-up timer pop left: WVT_CLEAR_WAIT / _DONE / _FORCE
'   WVT_Retreat dx, dy, dz, vx, vy, vz  a breaking-off fighter's velocity, from where it sits
'                                    relative to the ship: on away along x, and out to the side
'   g = WVT_Gone%(dx, dy, dz)        -1 once a retreating fighter has left the playfield
' spawnTimer gains WVT_TICK every frame of play (playing.bas).
' Local variable prefix: wvt*

Const WVT_TICK = 0.025
Const WVT_MAX_ST = 16
Const WVT_CLEAR_WAIT  = 0
Const WVT_CLEAR_DONE  = 1
Const WVT_CLEAR_FORCE = 2
Const WVT_GONE_X = 110   ' a retreating fighter is gone this far ahead or behind...
Const WVT_GONE_YZ = 45   ' ...or this far out to a side

Dim Shared wvtFirst As Single, wvtOpen As Integer
Dim Shared wvtOpenGap(1 To WVT_MAX_ST) As Single, wvtOpenGapN As Integer
Dim Shared wvtOpenSize(1 To WVT_MAX_ST) As Integer, wvtOpenSizeN As Integer
Dim Shared wvtGapPct(1 To WVT_MAX_ST) As Single, wvtGapPctN As Integer
Dim Shared wvtFirePct(1 To WVT_MAX_ST) As Single, wvtFirePctN As Integer
Dim Shared wvtGap0 As Single, wvtGap1 As Single
Dim Shared wvtOpenDist As Single, wvtOpenDistVar As Single, wvtDist As Single, wvtDistVar As Single
Dim Shared wvtClear As Long, wvtClearMax As Long, wvtRetreat As Single
Dim Shared wvtLoadErr As String

' Reads a per-stage list into wvtlsOut(); every value must be above 0. Returns the count (0 = bad).
Function WVT_LoadList% (wvtlsKey As String, wvtlsOut() As Single)
    Dim wvtlsV(1 To WVT_MAX_ST) As String, wvtlsN As Integer, wvtlsI As Integer
    WVT_LoadList% = 0
    UPG_Split CFG_Get$(cfgWaves, wvtlsKey), ",", wvtlsV(), wvtlsN
    If wvtlsN < 1 Then Exit Function
    For wvtlsI = 1 To wvtlsN
        wvtlsOut(wvtlsI) = Val(wvtlsV(wvtlsI))
        If wvtlsOut(wvtlsI) <= 0 Then Exit Function
    Next wvtlsI
    WVT_LoadList% = wvtlsN
End Function

Function WVT_Load%
    Dim wvtlV(1 To 4) As String, wvtlN As Integer, wvtlI As Integer
    Dim wvtlS(1 To WVT_MAX_ST) As Single
    WVT_Load% = 0
    wvtLoadErr = ""
    wvtFirst = Val(CFG_Get$(cfgWaves, "wave_first"))
    wvtOpen = Val(CFG_Get$(cfgWaves, "wave_open"))
    If wvtFirst < 0 Or wvtOpen < 0 Then wvtLoadErr = "config/waves.ini needs wave_first and wave_open 0 or more" : Exit Function
    wvtFirst = wvtFirst * DLV_M!("wave_first")

    wvtOpenGapN = WVT_LoadList%("wave_open_gap", wvtOpenGap())
    If wvtOpenGapN = 0 Then wvtLoadErr = "config/waves.ini wave_open_gap: one or more values, each above 0" : Exit Function
    For wvtlI = 1 To wvtOpenGapN : wvtOpenGap(wvtlI) = wvtOpenGap(wvtlI) * DLV_M!("wave_open_gap") : Next wvtlI
    wvtGapPctN = WVT_LoadList%("wave_gap_pct", wvtGapPct())
    If wvtGapPctN = 0 Then wvtLoadErr = "config/waves.ini wave_gap_pct: one or more values, each above 0" : Exit Function
    wvtFirePctN = WVT_LoadList%("wave_fire_pct", wvtFirePct())
    If wvtFirePctN = 0 Then wvtLoadErr = "config/waves.ini wave_fire_pct: one or more values, each above 0" : Exit Function
    wvtOpenSizeN = WVT_LoadList%("wave_open_size", wvtlS())
    If wvtOpenSizeN = 0 Then wvtLoadErr = "config/waves.ini wave_open_size: one or more values, each 1 or more" : Exit Function
    For wvtlI = 1 To wvtOpenSizeN : wvtOpenSize(wvtlI) = Int(wvtlS(wvtlI)) : Next wvtlI

    UPG_Split CFG_Get$(cfgWaves, "wave_gap"), ",", wvtlV(), wvtlN
    If wvtlN <> 2 Then wvtLoadErr = "config/waves.ini wave_gap needs 2 values (difficulty 0, full)" : Exit Function
    wvtGap0 = Val(wvtlV(1)) : wvtGap1 = Val(wvtlV(2))
    If wvtGap0 <= 0 Or wvtGap1 <= 0 Then wvtLoadErr = "config/waves.ini wave_gap: both values above 0" : Exit Function
    wvtGap0 = wvtGap0 * DLV_M!("wave_gap") : wvtGap1 = wvtGap1 * DLV_M!("wave_gap")

    UPG_Split CFG_Get$(cfgWaves, "wave_open_dist"), ",", wvtlV(), wvtlN
    If wvtlN <> 2 Then wvtLoadErr = "config/waves.ini wave_open_dist needs min,variance" : Exit Function
    wvtOpenDist = Val(wvtlV(1)) : wvtOpenDistVar = Val(wvtlV(2))
    UPG_Split CFG_Get$(cfgWaves, "wave_dist"), ",", wvtlV(), wvtlN
    If wvtlN <> 2 Then wvtLoadErr = "config/waves.ini wave_dist needs min,variance" : Exit Function
    wvtDist = Val(wvtlV(1)) : wvtDistVar = Val(wvtlV(2))
    If wvtOpenDist <= 0 Or wvtDist <= 0 Or wvtOpenDistVar < 0 Or wvtDistVar < 0 Then wvtLoadErr = "config/waves.ini spawn distances must be ahead of the ship" : Exit Function

    wvtClear = Val(CFG_Get$(cfgWaves, "wave_clear"))
    wvtClearMax = Val(CFG_Get$(cfgWaves, "wave_clear_max"))
    wvtRetreat = Val(CFG_Get$(cfgWaves, "wave_retreat"))
    If wvtClear < 1 Or wvtClearMax < wvtClear Then wvtLoadErr = "config/waves.ini needs wave_clear 1 or more and wave_clear_max at least that" : Exit Function
    If wvtRetreat <= 0 Then wvtLoadErr = "config/waves.ini wave_retreat must be above 0" : Exit Function
    WVT_Load% = -1
End Function

' Index into a per-stage list of wvtsiN values: stages before 1 use the first, past the end the last.
Function WVT_StageIdx% (wvtsiSt As Integer, wvtsiN As Integer)
    Dim wvtsiI As Integer
    wvtsiI = wvtsiSt
    If wvtsiI < 1 Then wvtsiI = 1
    If wvtsiI > wvtsiN Then wvtsiI = wvtsiN
    WVT_StageIdx% = wvtsiI
End Function

Function WVT_GapTicks! (wvtgN As Integer, wvtgDiff As Single, wvtgSt As Integer)
    If wvtgN <= 0 Then
        WVT_GapTicks! = wvtFirst * WVT_TICK
    ElseIf wvtgN < wvtOpen Then
        WVT_GapTicks! = wvtOpenGap(WVT_StageIdx%(wvtgSt, wvtOpenGapN)) * WVT_TICK
    Else
        WVT_GapTicks! = (wvtGap0 - wvtgDiff * (wvtGap0 - wvtGap1)) * (wvtGapPct(WVT_StageIdx%(wvtgSt, wvtGapPctN)) / 100) * WVT_TICK
    End If
End Function

Function WVT_WaveSize% (wvtwN As Integer, wvtwSt As Integer, wvtwSize As Integer)
    Dim wvtwCap As Integer
    WVT_WaveSize% = wvtwSize
    If wvtwN >= wvtOpen Then Exit Function
    wvtwCap = wvtOpenSize(WVT_StageIdx%(wvtwSt, wvtOpenSizeN))
    If wvtwSize > wvtwCap Then WVT_WaveSize% = wvtwCap
End Function

Function WVT_DistMin! (wvtdN As Integer)
    If wvtdN < wvtOpen Then WVT_DistMin! = wvtOpenDist Else WVT_DistMin! = wvtDist
End Function

Function WVT_DistVar! (wvtvN As Integer)
    If wvtvN < wvtOpen Then WVT_DistVar! = wvtOpenDistVar Else WVT_DistVar! = wvtDistVar
End Function

Function WVT_FireScale! (wvtfSt As Integer)
    WVT_FireScale! = wvtFirePct(WVT_StageIdx%(wvtfSt, wvtFirePctN)) / 100
End Function

Function WVT_CanSpawn% (wvtcCleared As Integer)
    If wvtcCleared Then WVT_CanSpawn% = 0 Else WVT_CanSpawn% = -1
End Function

Function WVT_ClearDone% (wvtdT As Long, wvtdEnemies As Integer, wvtdPups As Integer, wvtdPop As Integer)
    WVT_ClearDone% = WVT_CLEAR_WAIT
    If wvtdT >= wvtClearMax Then WVT_ClearDone% = WVT_CLEAR_FORCE : Exit Function
    If wvtdT < wvtClear Then Exit Function
    If wvtdEnemies > 0 Or wvtdPups > 0 Or wvtdPop > 0 Then Exit Function
    WVT_ClearDone% = WVT_CLEAR_DONE
End Function

Sub WVT_Retreat (wvtrDX As Single, wvtrDY As Single, wvtrDZ As Single, wvtrVX As Single, wvtrVY As Single, wvtrVZ As Single)
    If wvtrDX < 0 Then wvtrVX = -wvtRetreat Else wvtrVX = wvtRetreat
    If wvtrDY < 0 Then wvtrVY = -wvtRetreat * 0.5 Else wvtrVY = wvtRetreat * 0.5
    If wvtrDZ < 0 Then wvtrVZ = -wvtRetreat * 0.6 Else wvtrVZ = wvtRetreat * 0.6
End Sub

Function WVT_Gone% (wvtoDX As Single, wvtoDY As Single, wvtoDZ As Single)
    WVT_Gone% = (Abs(wvtoDX) > WVT_GONE_X Or Abs(wvtoDY) > WVT_GONE_YZ Or Abs(wvtoDZ) > WVT_GONE_YZ)
End Function
