' wavetiming.bas -- when and how far ahead a combat stage's enemy waves spawn (#90)
'
' Tuning comes from assets/config/waves.ini (see the comments there). No spawning here
' (wave.bas does that), so tests drive it directly:
'   ok = WVT_Load%                 read the tuning (after CFG_Parse$ of waves.ini); 0 + wvtLoadErr
'   t = WVT_GapTicks!(n, diff)     spawnTimer value the next wave waits for, when n waves of this
'                                  stage have spawned so far, at difficulty diff (0..1)
'   d = WVT_DistMin!(n)            spawn distance ahead of the ship for that wave: min...
'   v = WVT_DistVar!(n)            ...and variance
' spawnTimer gains WVT_TICK every frame of play (playing.bas).
' Local variable prefix: wvt*

Const WVT_TICK = 0.025

Dim Shared wvtFirst As Single, wvtOpen As Integer, wvtOpenGap As Single
Dim Shared wvtGap0 As Single, wvtGap1 As Single
Dim Shared wvtOpenDist As Single, wvtOpenDistVar As Single, wvtDist As Single, wvtDistVar As Single
Dim Shared wvtLoadErr As String

Function WVT_Load%
    Dim wvtlV(1 To 4) As String, wvtlN As Integer
    WVT_Load% = 0
    wvtLoadErr = ""
    wvtFirst = Val(CFG_Get$(cfgWaves, "wave_first"))
    wvtOpen = Val(CFG_Get$(cfgWaves, "wave_open"))
    wvtOpenGap = Val(CFG_Get$(cfgWaves, "wave_open_gap"))
    If wvtFirst < 0 Or wvtOpen < 0 Or wvtOpenGap <= 0 Then wvtLoadErr = "config/waves.ini needs wave_first and wave_open 0 or more, wave_open_gap above 0" : Exit Function

    UPG_Split CFG_Get$(cfgWaves, "wave_gap"), ",", wvtlV(), wvtlN
    If wvtlN <> 2 Then wvtLoadErr = "config/waves.ini wave_gap needs 2 values (difficulty 0, full)" : Exit Function
    wvtGap0 = Val(wvtlV(1)) : wvtGap1 = Val(wvtlV(2))
    If wvtGap0 <= 0 Or wvtGap1 <= 0 Then wvtLoadErr = "config/waves.ini wave_gap: both values above 0" : Exit Function

    UPG_Split CFG_Get$(cfgWaves, "wave_open_dist"), ",", wvtlV(), wvtlN
    If wvtlN <> 2 Then wvtLoadErr = "config/waves.ini wave_open_dist needs min,variance" : Exit Function
    wvtOpenDist = Val(wvtlV(1)) : wvtOpenDistVar = Val(wvtlV(2))
    UPG_Split CFG_Get$(cfgWaves, "wave_dist"), ",", wvtlV(), wvtlN
    If wvtlN <> 2 Then wvtLoadErr = "config/waves.ini wave_dist needs min,variance" : Exit Function
    wvtDist = Val(wvtlV(1)) : wvtDistVar = Val(wvtlV(2))
    If wvtOpenDist <= 0 Or wvtDist <= 0 Or wvtOpenDistVar < 0 Or wvtDistVar < 0 Then wvtLoadErr = "config/waves.ini spawn distances must be ahead of the ship" : Exit Function
    WVT_Load% = -1
End Function

Function WVT_GapTicks! (wvtgN As Integer, wvtgDiff As Single)
    If wvtgN <= 0 Then
        WVT_GapTicks! = wvtFirst * WVT_TICK
    ElseIf wvtgN < wvtOpen Then
        WVT_GapTicks! = wvtOpenGap * WVT_TICK
    Else
        WVT_GapTicks! = (wvtGap0 - wvtgDiff * (wvtGap0 - wvtGap1)) * WVT_TICK
    End If
End Function

Function WVT_DistMin! (wvtdN As Integer)
    If wvtdN < wvtOpen Then WVT_DistMin! = wvtOpenDist Else WVT_DistMin! = wvtDist
End Function

Function WVT_DistVar! (wvtvN As Integer)
    If wvtvN < wvtOpen Then WVT_DistVar! = wvtOpenDistVar Else WVT_DistVar! = wvtDistVar
End Function
