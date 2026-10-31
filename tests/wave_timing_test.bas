' wave_timing_test.bas -- combat waves and the clear-out before a boss (src/gameplay/wavetiming.bas, #90)
'
' Drives the real module against the real assets/config/waves.ini: loading it (and rejecting
' broken values), the stage's opening (first wave soon, the next ones close behind and nearer,
' smaller and slower in stages 1-2), the regular cadence (stage 3 matches the pre-#90 timing;
' stages 5-6 press harder), enemy fire per stage, and the clear-out at the end of a stage: no
' spawns once the kill target is reached, fighters break off and leave, power-ups in flight are
' pulled in and caught (with the real powerups.ini), and the boss waits for a clear field.
'
' Build: ./tools/buildqb tests/wave_timing_test.bas
' Run:   builds/wave_timing_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/config/waves.ini':'CFGWAVES'
$EMBED:'assets/config/powerups.ini':'CFGPOWERUPS'
$EMBED:'assets/config/difficulty.ini':'CFGDIFFICULTY'

Sub DBG_Print (wttDbg As String) : End Sub
Sub TELEM_UpgradeBought (wtuItem As String, wtuLevel As Integer, wtuPrice As Long) : End Sub
Sub TELEM_CreditBonus (wtcC As Long, wtcR As Double, wtcP As Long) : End Sub

'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/credits.bas'
'$INCLUDE:'../src/gameplay/upgrades.bas'
'$INCLUDE:'../src/gameplay/powerups.bas'
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
    WT_Near% = (Abs(wtnA - wtnB) < 0.001)
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
Function WT_FramesTo& (wtfN As Integer, wtfDiff As Single, wtfSt As Integer)
    Dim wtfTimer As Single, wtfFrames As Long
    Do
        wtfTimer = wtfTimer + WVT_TICK
        wtfFrames = wtfFrames + 1
    Loop Until wtfTimer > WVT_GapTicks!(wtfN, wtfDiff, wtfSt) Or wtfFrames > 100000
    WT_FramesTo& = wtfFrames
End Function

' Frames a fighter starting at (dx, dy, dz) from the ship takes to leave, stepped as enemy.bas does.
Function WT_RetreatFrames& (wtrX0 As Single, wtrY0 As Single, wtrZ0 As Single)
    Dim wtrVX As Single, wtrVY As Single, wtrVZ As Single, wtrF As Long
    Dim wtrX As Single, wtrY As Single, wtrZ As Single
    wtrX = wtrX0 : wtrY = wtrY0 : wtrZ = wtrZ0
    Do Until WVT_Gone%(wtrX, wtrY, wtrZ) Or wtrF > 100000
        WVT_Retreat wtrX, wtrY, wtrZ, wtrVX, wtrVY, wtrVZ
        wtrX = wtrX + wtrVX : wtrY = wtrY + wtrVY : wtrZ = wtrZ + wtrVZ
        wtrF = wtrF + 1
    Loop
    WT_RetreatFrames& = wtrF
End Function

' Frames a power-up starting at (dx, dy, dz) takes to be caught during a clear-out, stepped as
' playing.bas does; minus the frames it took to get past the ship uncaught (it is then removed).
Function WT_PullFrames& (wtpX0 As Single, wtpY0 As Single, wtpZ0 As Single)
    Dim wtpF As Long
    Dim wtpX As Single, wtpY As Single, wtpZ As Single
    wtpX = wtpX0 : wtpY = wtpY0 : wtpZ = wtpZ0
    Do
        wtpY = wtpY - wtpY * PUP_CLEAR_PULL
        wtpZ = wtpZ - wtpZ * PUP_CLEAR_PULL
        wtpX = wtpX - PUP_CLEAR_SPEED
        wtpF = wtpF + 1
        If PUP_Grabbed%(wtpX, wtpY, wtpZ) Then WT_PullFrames& = wtpF : Exit Function
    Loop Until wtpX < -5
    WT_PullFrames& = -wtpF
End Function

Dim wtOk As Integer, wtF As Long, wtMax As Long, wtI As Integer, wtJ As Integer, wtK As Integer
Dim wtX(1 To 4) As Single, wtYZ(1 To 3) As Single
Dim wtVX As Single, wtVY As Single, wtVZ As Single

Print "=== wave_timing_test ==="
Print ""

Print "--- config: the real waves.ini ---"
cfgWaves = CFG_Parse$(_EMBEDDED$("CFGWAVES"))
wtOk = WVT_Load%
WT_Assert wtOk <> 0, "waves.ini loads " + wvtLoadErr
WT_Assert WT_Near%(wvtFirst, 60) And wvtOpen = 3, "first wave 60 frames in, opening of 3 waves"
WT_Assert wvtOpenGapN = 6 And WT_Near%(wvtOpenGap(1), 210) And WT_Near%(wvtOpenGap(2), 180) And WT_Near%(wvtOpenGap(3), 150) And WT_Near%(wvtOpenGap(6), 150), "opening gap per stage: 210, 180, then 150"
WT_Assert wvtOpenSizeN = 6 And wvtOpenSize(1) = 1 And wvtOpenSize(2) = 2 And wvtOpenSize(3) = 3, "opening wave size per stage: 1, 2, then 3"
WT_Assert WT_Near%(wvtGap0, 280) And WT_Near%(wvtGap1, 200), "regular gap 280 frames, 200 at full difficulty"
WT_Assert WT_Near%(wvtGapPct(1), 110) And WT_Near%(wvtGapPct(2), 105) And WT_Near%(wvtGapPct(3), 100) And WT_Near%(wvtGapPct(5), 80) And WT_Near%(wvtGapPct(6), 70), "regular gap per stage: 110, 105, 100, 100, 80, 70 %"
WT_Assert WT_Near%(wvtFirePct(1), 125) And WT_Near%(wvtFirePct(2), 110) And WT_Near%(wvtFirePct(3), 100) And WT_Near%(wvtFirePct(5), 80) And WT_Near%(wvtFirePct(6), 70), "enemy fire cooldown per stage: 125, 110, 100, 100, 80, 70 %"
WT_Assert WT_Near%(wvtOpenDist, 55) And WT_Near%(wvtOpenDistVar, 15), "opening waves spawn 55..70 ahead"
WT_Assert WT_Near%(wvtDist, 70) And WT_Near%(wvtDistVar, 30), "later waves spawn 70..100 ahead"
WT_Assert wvtClear = 150 And wvtClearMax = 360 And WT_Near%(wvtRetreat, 0.35), "clear-out: 150 frames at least, 360 at most, fighters leave at 0.35"

Print ""
Print "--- config: broken values are rejected ---"
WT_Assert WT_LoadWith%("wave_gap", "280") = 0, "one gap value: rejected"
WT_Assert WT_LoadWith%("wave_gap", "280,0") = 0, "a gap of 0: rejected"
WT_Assert WT_LoadWith%("wave_open_gap", "210,0") = 0, "an opening gap of 0: rejected"
WT_Assert WT_LoadWith%("wave_gap_pct", "") = 0, "no gap %: rejected"
WT_Assert WT_LoadWith%("wave_fire_pct", "100,-5") = 0, "a negative fire %: rejected"
WT_Assert WT_LoadWith%("wave_open_size", "0") = 0, "an opening wave of 0: rejected"
WT_Assert WT_LoadWith%("wave_first", "-1") = 0, "a negative first-wave delay: rejected"
WT_Assert WT_LoadWith%("wave_dist", "70") = 0, "distance without a variance: rejected"
WT_Assert WT_LoadWith%("wave_open_dist", "0,15") = 0, "spawning on the ship: rejected"
WT_Assert WT_LoadWith%("wave_clear_max", "100") = 0, "a clear-out cap under its minimum: rejected"
WT_Assert WT_LoadWith%("wave_retreat", "0") = 0, "fighters that never leave: rejected"
cfgWaves = CFG_Parse$(_EMBEDDED$("CFGWAVES"))
WT_Assert WVT_Load% <> 0, "the real file loads again"

Print ""
Print "--- the opening: first wave soon; stages 1-2 smaller and slower ---"
WT_Assert WT_Near%(WVT_GapTicks!(0, 0, 1), 1.5) And WT_Near%(WVT_GapTicks!(0, 0.8, 6), 1.5), "first wave waits 1.5 ticks in every stage"
wtF = WT_FramesTo&(0, 0, 1)
WT_Assert wtF >= 60 And wtF <= 61, "first wave about 1 s into the stage (" + LTrim$(Str$(wtF)) + " frames)"
wtF = WT_FramesTo&(1, 0, 1)
WT_Assert wtF >= 210 And wtF <= 211, "stage 1: wave 2 about 3.5 s after the first (" + LTrim$(Str$(wtF)) + " frames)"
wtF = WT_FramesTo&(2, 0.17, 2)
WT_Assert wtF >= 180 And wtF <= 181, "stage 2: wave 3 about 3 s after wave 2 (" + LTrim$(Str$(wtF)) + " frames)"
wtF = WT_FramesTo&(1, 0.33, 3)
WT_Assert wtF >= 150 And wtF <= 151, "stage 3: 2.5 s apart (" + LTrim$(Str$(wtF)) + " frames)"
WT_Assert WT_Near%(WVT_GapTicks!(1, 0, 9), 3.75), "a stage past the end of the list uses its last value"
WT_Assert WVT_WaveSize%(0, 1, 3) = 1 And WVT_WaveSize%(2, 1, 2) = 1, "stage 1: opening waves are lone fighters"
WT_Assert WVT_WaveSize%(0, 2, 3) = 2 And WVT_WaveSize%(1, 2, 1) = 1, "stage 2: pairs at most (a solo stays a solo)"
WT_Assert WVT_WaveSize%(0, 3, 3) = 3 And WVT_WaveSize%(0, 6, 3) = 3, "stages 3+: opening waves keep their formation"
WT_Assert WVT_WaveSize%(3, 1, 3) = 3, "after the opening, stage 1 formations are whole again"
WT_Assert WT_Near%(WVT_DistMin!(0), 55) And WT_Near%(WVT_DistVar!(0), 15), "wave 1 spawns 55..70 ahead"
WT_Assert WT_Near%(WVT_DistMin!(2), 55), "wave 3 still in the opening"
WT_Assert WVT_DistMin!(0) + WVT_DistVar!(0) <= WVT_DistMin!(3), "an opening wave never spawns farther than a later one can"

Print ""
Print "--- after the opening: the regular cadence per stage ---"
WT_Assert WT_Near%(WVT_GapTicks!(3, 0, 3), 7.0) And WT_Near%(WVT_GapTicks!(3, 1, 3), 5.0), "stage 3 (100%): 7.0 ticks at difficulty 0, 5.0 at full, as before #90"
WT_Assert WT_Near%(WVT_GapTicks!(40, 0.5, 3), 6.0), "stage 3 halfway: 6.0 ticks"
wtF = WT_FramesTo&(3, 0, 1)
WT_Assert wtF >= 308 And wtF <= 309, "stage 1 (110%): about 5.1 s apart (" + LTrim$(Str$(wtF)) + " frames; was 280)"
wtF = WT_FramesTo&(3, 5 / 6, 6)
WT_Assert wtF >= 149 And wtF <= 150, "stage 6 at its opening difficulty (70%): about 2.5 s apart (" + LTrim$(Str$(wtF)) + " frames; was 213)"
WT_Assert WVT_GapTicks!(3, 2 / 3, 5) < (280 - 2 / 3 * 80) * WVT_TICK, "stage 5 waves come faster than before #90"
WT_Assert WT_Near%(WVT_DistMin!(3), 70) And WT_Near%(WVT_DistVar!(3), 30), "wave 4 spawns 70..100 ahead"
WT_Assert WT_Near%(WVT_FireScale!(1), 1.25) And WT_Near%(WVT_FireScale!(2), 1.1), "stages 1-2: enemies fire less often"
WT_Assert WT_Near%(WVT_FireScale!(3), 1) And WT_Near%(WVT_FireScale!(4), 1), "stage 3 as before (stage 4 is the asteroid field: no waves)"
WT_Assert WT_Near%(WVT_FireScale!(5), 0.8) And WT_Near%(WVT_FireScale!(6), 0.7), "stages 5-6: enemies fire more often"

Print ""
Print "--- the clear-out before a boss (or the planet) ---"
WT_Assert WVT_CanSpawn%(0) <> 0, "kill target not reached: waves spawn"
WT_Assert WVT_CanSpawn%(-1) = 0, "kill target reached: no new waves"
WT_Assert WVT_ClearDone%(1, 0, 0, 0) = WVT_CLEAR_WAIT, "an empty field still waits out wave_clear"
WT_Assert WVT_ClearDone%(149, 0, 0, 0) = WVT_CLEAR_WAIT, "149 frames: still clearing"
WT_Assert WVT_ClearDone%(150, 0, 0, 0) = WVT_CLEAR_DONE, "150 frames, empty field: the boss may come"
WT_Assert WVT_ClearDone%(200, 1, 0, 0) = WVT_CLEAR_WAIT, "a fighter still leaving: wait"
WT_Assert WVT_ClearDone%(200, 0, 1, 0) = WVT_CLEAR_WAIT, "a power-up still in flight: wait"
WT_Assert WVT_ClearDone%(200, 0, 0, 12) = WVT_CLEAR_WAIT, "a score pop-up still showing: wait"
WT_Assert WVT_ClearDone%(360, 2, 1, 5) = WVT_CLEAR_FORCE, "360 frames: whatever's left is removed"
WVT_Retreat 10, 2, -3, wtVX, wtVY, wtVZ
WT_Assert wtVX > 0 And wtVY > 0 And wtVZ < 0, "a fighter ahead and up-left breaks off ahead, up and left"
WVT_Retreat -2, -1, 1, wtVX, wtVY, wtVZ
WT_Assert wtVX < 0 And wtVY < 0 And wtVZ > 0, "a fighter just behind the ship leaves behind it"
wtX(1) = -4 : wtX(2) = 0.5 : wtX(3) = 40 : wtX(4) = 100
wtYZ(1) = -20 : wtYZ(2) = 0.1 : wtYZ(3) = 20
wtMax = 0
For wtI = 1 To 4
    For wtJ = 1 To 3
        For wtK = 1 To 3
            wtF = WT_RetreatFrames&(wtX(wtI), wtYZ(wtJ), wtYZ(wtK))
            If wtF > wtMax Then wtMax = wtF
        Next wtK
    Next wtJ
Next wtI
WT_Assert wtMax < wvtClearMax, "every fighter has left before the cap, wherever it was (slowest" + Str$(wtMax) + " frames)"

cfgPowerups = CFG_Parse$(_EMBEDDED$("CFGPOWERUPS"))
WT_Assert PUP_Load% <> 0, "powerups.ini loads " + pupLoadErr
wtMax = 0 : wtOk = -1
For wtJ = 1 To 3
    For wtK = 1 To 3
        wtF = WT_PullFrames&(pupSpawnX + pupSpawnXVar, pupSpreadY * Sgn(wtYZ(wtJ)), pupSpreadZ * Sgn(wtYZ(wtK)))
        If wtF <= 0 Then wtOk = 0
        If wtF > wtMax Then wtMax = wtF
        wtF = WT_PullFrames&(15, pupSpreadY * Sgn(wtYZ(wtJ)), pupSpreadZ * Sgn(wtYZ(wtK)))
        If wtF <= 0 Then wtOk = 0
        wtF = Abs(WT_PullFrames&(1, pupSpreadY * Sgn(wtYZ(wtJ)), pupSpreadZ * Sgn(wtYZ(wtK))))
        If wtF > wtMax Then wtMax = wtF
    Next wtK
Next wtJ
WT_Assert wtOk, "every power-up still 15 or more ahead is pulled in and caught, even from the lane's corners"
WT_Assert wtMax < wvtClearMax, "every power-up is caught or gone past before the cap (slowest" + Str$(wtMax) + " frames)"

Print ""
Print "--- difficulty levels (#102): pacing, not more enemies ---"
Dim wtdLv As Integer, wtdL As String, wtdAll As Integer, wtdOk As Integer
Dim wtdFirst As Long, wtdOpen As Long, wtdGap As Long, wtdF As Long
cfgWaves = CFG_Parse$(_EMBEDDED$("CFGWAVES"))
WT_Assert WVT_Load% <> 0, "the real waves.ini again"
wtdFirst = WT_FramesTo&(0, 0, 1) : wtdOpen = WT_FramesTo&(1, 0, 1) : wtdGap = WT_FramesTo&(5, 0, 3)
cfgDifficulty = CFG_Parse$(_EMBEDDED$("CFGDIFFICULTY"))
WT_Assert DLV_Load% <> 0, "difficulty.ini loads " + dlvLoadErr
wtdAll = -1
For wtdLv = 1 To DLV_Count%
    wtdL = DLV_LevelAt$(wtdLv)
    DLV_Use wtdL
    wtdOk = WVT_Load%
    If wtdOk = 0 Then wtdAll = 0 : Print "  " + wtdL + ": " + wvtLoadErr
    wtdF = WT_FramesTo&(0, 0, 1)
    If Abs(wtdF - (wtdFirst - 1) * DLV_M!("wave_first") - 1) > 1 Then wtdAll = 0 : Print "  " + wtdL + ": first wave at" + Str$(wtdF)
    wtdF = WT_FramesTo&(1, 0, 1)
    If Abs(wtdF - (wtdOpen - 1) * DLV_M!("wave_open_gap") - 1) > 1 Then wtdAll = 0 : Print "  " + wtdL + ": opening gap" + Str$(wtdF)
    wtdF = WT_FramesTo&(5, 0, 3)
    If Abs(wtdF - (wtdGap - 1) * DLV_M!("wave_gap") - 1) > 1 Then wtdAll = 0 : Print "  " + wtdL + ": regular gap" + Str$(wtdF)
    If WVT_WaveSize%(0, 1, 3) <> 1 Or WVT_WaveSize%(0, 2, 3) <> 2 Or WVT_WaveSize%(5, 6, 3) <> 3 Then wtdAll = 0 : Print "  " + wtdL + ": wave sizes changed"
    If WVT_DistMin!(0) <> 55 Or WVT_DistMin!(5) <> 70 Or WT_Near%(WVT_FireScale!(6), 0.7) = 0 Then wtdAll = 0 : Print "  " + wtdL + ": spawn distance or per-stage fire changed"
Next wtdLv
WT_Assert wtdAll, "every level: first wave, opening and regular gaps x wave_first / wave_open_gap / wave_gap; wave sizes, spawn distance and per-stage fire as they are"
DLV_Use "normal"
wtdOk = WVT_Load% : WT_Assert wtdOk <> 0 And WT_FramesTo&(0, 0, 1) = wtdFirst And WT_FramesTo&(1, 0, 1) = wtdOpen And WT_FramesTo&(5, 0, 3) = wtdGap, "normal: the same frames as without difficulty.ini"
DLV_Use "easy"
wtdOk = WVT_Load% : WT_Assert wtdOk <> 0 And WT_Near%(WVT_GapTicks!(5, 0, 3), 350 * WVT_TICK) And WT_Near%(WVT_GapTicks!(0, 0, 1), 90 * WVT_TICK), "easy: regular gap 350 frames in stage 3 (280 x 1.25), first wave at 90"
DLV_Use "hard"
wtdOk = WVT_Load% : WT_Assert wtdOk <> 0 And WT_Near%(WVT_GapTicks!(5, 0, 3), 238 * WVT_TICK) And WT_Near%(WVT_GapTicks!(5, 1, 3), 170 * WVT_TICK), "hard: regular gap 238 frames at difficulty 0, 170 at full"
DLV_Use "normal"
WT_Assert WVT_Load% <> 0, "back to normal"


Print "passed:" + Str$(wtPassed) + "  failed:" + Str$(wtFailed)
If wtFailed > 0 Then System 1
System 0
