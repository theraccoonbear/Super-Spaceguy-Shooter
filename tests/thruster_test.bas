' thruster_test.bas -- the engine voice of #402: demand smoothing, the rumble's de-zippering,
' its level at different device rates and under narration.
'
' Build: ./tools/buildqb tests/thruster_test.bas
' Run:   ./tests/thruster_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/music.mus':'MUSICDATA'
$EMBED:'assets/sequence.txt':'SEQTXT'

Sub DBG_Print (dpMsg As String) : End Sub
'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/audiorate.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'

Const SND_UI_LAST   = SND_UI_SPIN + SND_UI_SPIN_N - 1

Dim Shared spkSampleOut As Single
Sub SPK_Advance () : End Sub

'$INCLUDE:'../src/audio/snd.bas'
'$INCLUDE:'../src/audio/music.bas'

Dim Shared ttPassed As Integer, ttFailed As Integer
Dim Shared ttPrev As Single

Sub TT_Assert (ttCond As Integer, ttName As String)
    If ttCond Then
        Print "PASS  " + ttName
        ttPassed = ttPassed + 1
    Else
        Print "FAIL  " + ttName
        ttFailed = ttFailed + 1
    End If
End Sub

Sub TT_Reset
    thrNoise = 12345 : thrSubPh = 0 : thrPh(0) = 0 : thrPh(1) = 0 : thrPh(2) = 0 : thrPh(3) = 0
    ttPrev = 0 : thrDemand = 0 : thrLevel = 0 : thrCoef = 0 : thrFreq = 0 : thrSpk = 0
    SND_ThrusterTimbre thrTimbre
    spkSampleOut = 0
End Sub

' Rumble samples for ttMs milliseconds; returns the rms, and the largest sample-to-sample step in ttStep.
Function TT_Run! (ttMs As Long, ttStep As Single)
    Dim ttI As Long, ttN As Long, ttS As Single, ttSum As Double
    ttN = CLng(ttMs * SAMPLE_RATE / 1000)
    ttStep = 0
    For ttI = 1 To ttN
        ttS = SND_RumbleNext!
        If Abs(ttS - ttPrev) > ttStep Then ttStep = Abs(ttS - ttPrev)
        ttPrev = ttS
        ttSum = ttSum + ttS * ttS
    Next ttI
    TT_Run! = CSng(Sqr(ttSum / ttN))
End Function

Dim ttRun As Integer
Dim ttI As Integer, ttStepA As Single, ttStepB As Single, ttRms As Single, ttRmsLo As Single, ttRmsHi As Single
Dim ttD1 As Single, ttD2 As Single, ttFq As Single

Print "=== thruster_test ==="

' attack and release: demand climbs fast and eases back slowly
TT_Reset
For ttI = 1 To 12 : SND_ThrusterFrame 1 : Next ttI
ttD1 = thrDemand
TT_Assert ttD1 > 0.6 And ttD1 < 1, "demand rises toward 1 within 200 ms of full thrust (" + Str$(ttD1) + ")"
For ttI = 1 To 12 : SND_ThrusterFrame 0 : Next ttI
ttD2 = thrDemand
TT_Assert ttD2 > 0.2 And ttD2 < ttD1, "demand falls more slowly than it rose (" + Str$(ttD2) + ")"
For ttI = 1 To 120 : SND_ThrusterFrame 1 : Next ttI
ttFq = sndEngineFreq
TT_Assert Abs(ttFq - thrHumPitchMax) < 1 And Abs(sndEngineAmp - thrHumAmpMax) < 0.005, "full demand: hum at the top pitch and level"
For ttI = 1 To 400 : SND_ThrusterFrame 0 : Next ttI
TT_Assert Abs(sndEngineFreq - thrHumPitchMin) < 1 And Abs(sndEngineAmp - thrHumAmpIdle) < 0.005, "released: hum back at idle pitch and level"

' rumble level follows demand
TT_Reset
For ttI = 1 To 200 : SND_ThrusterFrame 0 : Next ttI
ttRmsLo = TT_Run!(300, ttStepA)
For ttI = 1 To 200 : SND_ThrusterFrame 1 : Next ttI
ttRmsHi = TT_Run!(300, ttStepA)
TT_Assert ttRmsHi > ttRmsLo * 2 And ttRmsLo > 0.0005, "rumble is audible at idle and louder at full demand (" + Str$(ttRmsLo) + " -> " + Str$(ttRmsHi) + ")"
TT_Assert ttRmsHi < 0.2, "rumble stays well under full scale (" + Str$(ttRmsHi) + ")"

' quick taps: the largest step between samples stays near the steady-state step
TT_Reset
For ttI = 1 To 200 : SND_ThrusterFrame 1 : Next ttI
ttRms = TT_Run!(200, ttStepA)
For ttI = 1 To 30
    SND_ThrusterFrame 0 : ttRms = TT_Run!(16, ttStepB)
    If ttStepB > ttStepA Then ttStepA = ttStepB
    SND_ThrusterFrame 1 : ttRms = TT_Run!(16, ttStepB)
    If ttStepB > ttStepA Then ttStepA = ttStepB
Next ttI
TT_Assert ttStepA < 0.05, "30 stick taps in half a second: no sample step above 0.05 (" + Str$(ttStepA) + ")"

' every timbre: audible, bounded, level matches across device rates, and the same twice
Dim ttT As Integer, ttH1 As Double, ttH2 As Double, ttPk As Single
For ttT = 0 To THR_TIMBRES - 1
    thrTimbre = ttT
    ttH1 = 0
    For ttRun = 1 To 2
        AUD_SetRate 48000 : TT_Reset
        For ttI = 1 To 200 : SND_ThrusterFrame 1 : Next ttI
        ttRmsLo = TT_Run!(400, ttStepA)
        ttPk = ttStepA
        If ttRun = 1 Then ttH1 = ttRmsLo Else ttH2 = ttRmsLo
    Next ttRun
    TT_Assert ttH1 = ttH2, "timbre" + Str$(ttT) + ": two runs give the same samples"
    TT_Assert ttRmsLo > 0.01 And ttRmsLo < 0.2, "timbre" + Str$(ttT) + ": audible and under full scale at full demand (" + Str$(ttRmsLo) + ")"
    TT_Assert ttPk < 0.06, "timbre" + Str$(ttT) + ": no sample step above 0.06, so no crackle (" + Str$(ttPk) + ")"
    AUD_SetRate 96000 : TT_Reset
    For ttI = 1 To 200 : SND_ThrusterFrame 1 : Next ttI
    ttRmsHi = TT_Run!(400, ttStepA)
    TT_Assert ttRmsHi > ttRmsLo * 0.7 And ttRmsHi < ttRmsLo * 1.4, "timbre" + Str$(ttT) + ": level matches at 48000 and 96000 Hz (" + Str$(ttRmsLo) + " vs " + Str$(ttRmsHi) + ")"
Next ttT
AUD_SetRate 48000 : thrTimbre = 0

' device rate: the same level at 48000 and 96000 Hz
AUD_SetRate 48000 : TT_Reset
For ttI = 1 To 200 : SND_ThrusterFrame 1 : Next ttI
ttRmsLo = TT_Run!(500, ttStepA)
AUD_SetRate 96000 : TT_Reset
For ttI = 1 To 200 : SND_ThrusterFrame 1 : Next ttI
ttRmsHi = TT_Run!(500, ttStepA)
TT_Assert ttRmsHi > ttRmsLo * 0.8 And ttRmsHi < ttRmsLo * 1.25, "rumble level matches at 48000 and 96000 Hz (" + Str$(ttRmsLo) + " vs " + Str$(ttRmsHi) + ")"
AUD_SetRate 48000

' narration ducks the rumble
TT_Reset
For ttI = 1 To 200 : SND_ThrusterFrame 1 : Next ttI
ttRmsLo = TT_Run!(200, ttStepA)
spkSampleOut = 0.3
ttRmsHi = TT_Run!(200, ttStepA)
TT_Assert ttRmsHi < ttRmsLo * 0.6, "the rumble is ducked while narration speaks (" + Str$(ttRmsLo) + " -> " + Str$(ttRmsHi) + ")"

Print
Print Str$(ttPassed) + " passed," + Str$(ttFailed) + " failed"
If ttFailed > 0 Then System 1
System 0
