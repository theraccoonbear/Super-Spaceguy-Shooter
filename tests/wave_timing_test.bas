' wave_timing_test.bas -- combat wave timing and spawn distance (src/gameplay/wavetiming.bas, #90)
'
' Drives the real module against the real assets/config/waves.ini: loading it (and rejecting
' broken values), the stage's opening (first wave soon, the next ones close behind and nearer),
' then the regular cadence, which matches the pre-#90 timing (7.0 ticks at difficulty 0, 5.0 at
' full).
'
' Build: ./tools/buildqb tests/wave_timing_test.bas
' Run:   builds/wave_timing_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/config/waves.ini':'CFGWAVES'

Sub DBG_Print (wttDbg As String) : End Sub
Sub TELEM_UpgradeBought (wtuItem As String, wtuLevel As Integer, wtuPrice As Long) : End Sub
Sub TELEM_CreditBonus (wtcC As Long, wtcR As Double, wtcP As Long) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/credits.bas'
'$INCLUDE:'../src/gameplay/upgrades.bas'
'$INCLUDE:'../src/gameplay/wavetiming.bas'

Dim Shared wtPassed As Integer, wtFailed As Integer

Sub WT_Assert (wtaCond As Integer, wtaName As String)
    If wtaCond Then
        Print "PASS  " + wtaName
        wtPassed = wtPassed + 1
    Else
        Print "FAIL  " + wtaName
        wtFailed = wtFailed + 1
    End If
End Sub

Function WT_Near% (wtnA As Single, wtnB As Single)
    WT_Near% = (Abs(wtnA - wtnB) < 0.0001)
End Function

' Loads a variant of the real file with one key's value replaced; returns WVT_Load%.
Function WT_LoadWith% (wtlKey As String, wtlVal As String)
    Dim wtlSrc As String, wtlP As Long, wtlQ As Long
    wtlSrc = _EMBEDDED$("CFGWAVES")
    wtlP = InStr(wtlSrc, Chr$(10) + wtlKey + "=")
    If wtlP > 0 Then
        wtlQ = InStr(wtlP + 1, wtlSrc, Chr$(10))
        If wtlQ = 0 Then wtlQ = Len(wtlSrc) + 1
        wtlSrc = Left$(wtlSrc, wtlP) + wtlKey + "=" + wtlVal + Mid$(wtlSrc, wtlQ)
    End If
    cfgWaves = CFG_Parse$(wtlSrc)
    WT_LoadWith% = WVT_Load%
End Function

' Frames of play until the wave after n spawned waves fires, stepping spawnTimer as playing.bas does.
Function WT_FramesTo& (wtfN As Integer, wtfDiff As Single)
    Dim wtfTimer As Single, wtfFrames As Long
    Do
        wtfTimer = wtfTimer + WVT_TICK
        wtfFrames = wtfFrames + 1
    Loop Until wtfTimer > WVT_GapTicks!(wtfN, wtfDiff) Or wtfFrames > 100000
    WT_FramesTo& = wtfFrames
End Function

Dim wtOk As Integer, wtF As Long

Print "=== wave_timing_test ==="
Print ""

Print "--- config: the real waves.ini ---"
cfgWaves = CFG_Parse$(_EMBEDDED$("CFGWAVES"))
wtOk = WVT_Load%
WT_Assert wtOk <> 0, "waves.ini loads " + wvtLoadErr
WT_Assert WT_Near%(wvtFirst, 60) And wvtOpen = 3 And WT_Near%(wvtOpenGap, 150), "first wave 60 frames in, opening of 3 waves 150 frames apart"
WT_Assert WT_Near%(wvtGap0, 280) And WT_Near%(wvtGap1, 200), "regular gap 280 frames, 200 at full difficulty"
WT_Assert WT_Near%(wvtOpenDist, 55) And WT_Near%(wvtOpenDistVar, 15), "opening waves spawn 55..70 ahead"
WT_Assert WT_Near%(wvtDist, 70) And WT_Near%(wvtDistVar, 30), "later waves spawn 70..100 ahead"

Print ""
Print "--- config: broken values are rejected ---"
WT_Assert WT_LoadWith%("wave_gap", "280") = 0, "one gap value: rejected"
WT_Assert WT_LoadWith%("wave_gap", "280,0") = 0, "a gap of 0: rejected"
WT_Assert WT_LoadWith%("wave_open_gap", "0") = 0, "opening gap 0: rejected"
WT_Assert WT_LoadWith%("wave_first", "-1") = 0, "a negative first-wave delay: rejected"
WT_Assert WT_LoadWith%("wave_dist", "70") = 0, "distance without a variance: rejected"
WT_Assert WT_LoadWith%("wave_open_dist", "0,15") = 0, "spawning on the ship: rejected"
cfgWaves = CFG_Parse$(_EMBEDDED$("CFGWAVES"))
WT_Assert WVT_Load% <> 0, "the real file loads again"

Print ""
Print "--- the opening: first wave soon, the next two close behind ---"
WT_Assert WT_Near%(WVT_GapTicks!(0, 0), 1.5), "first wave waits 1.5 ticks"
wtF = WT_FramesTo&(0, 0)
WT_Assert wtF >= 60 And wtF <= 61, "first wave about 1 s into the stage (" + LTrim$(Str$(wtF)) + " frames)"
wtF = WT_FramesTo&(0, 1)
WT_Assert wtF >= 60 And wtF <= 61, "...at any difficulty"
WT_Assert WT_Near%(WVT_GapTicks!(1, 0), 3.75) And WT_Near%(WVT_GapTicks!(2, 0), 3.75), "waves 2 and 3: 150 frames apart"
wtF = WT_FramesTo&(1, 0)
WT_Assert wtF >= 150 And wtF <= 151, "wave 2 about 2.5 s after the first (" + LTrim$(Str$(wtF)) + " frames)"
WT_Assert WT_Near%(WVT_DistMin!(0), 55) And WT_Near%(WVT_DistVar!(0), 15), "wave 1 spawns 55..70 ahead"
WT_Assert WT_Near%(WVT_DistMin!(2), 55), "wave 3 still in the opening"
WT_Assert WVT_DistMin!(0) + WVT_DistVar!(0) <= WVT_DistMin!(3), "an opening wave never spawns farther than a later one can"

Print ""
Print "--- after the opening: the regular cadence, as before #90 ---"
WT_Assert WT_Near%(WVT_GapTicks!(3, 0), 7.0), "wave 4 at difficulty 0: 7.0 ticks"
WT_Assert WT_Near%(WVT_GapTicks!(3, 1), 5.0), "at full difficulty: 5.0 ticks"
WT_Assert WT_Near%(WVT_GapTicks!(40, 0.5), 6.0), "halfway: 6.0 ticks"
wtF = WT_FramesTo&(3, 0)
WT_Assert wtF >= 280 And wtF <= 281, "difficulty 0: about 4.7 s apart (" + LTrim$(Str$(wtF)) + " frames)"
wtF = WT_FramesTo&(3, 1)
WT_Assert wtF >= 200 And wtF <= 201, "full difficulty: about 3.3 s apart (" + LTrim$(Str$(wtF)) + " frames)"
WT_Assert WT_Near%(WVT_DistMin!(3), 70) And WT_Near%(WVT_DistVar!(3), 30), "wave 4 spawns 70..100 ahead"

Print ""
Print "passed:" + Str$(wtPassed) + "  failed:" + Str$(wtFailed)
If wtFailed > 0 Then System 1
System 0
