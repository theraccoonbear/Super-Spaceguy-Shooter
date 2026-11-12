' audio_rate_test.bas -- the synthesized audio follows the device rate (#400) and, at the 48000 Hz
' reference rate, is the stream the game produced before it did.
'
' Every sound effect buffer, the UI voice, the engine hum, the narration blip, two fixed speech
' lines and four fixed music runs (cue switches, crossfades, drum retriggers) are rendered through
' the real modules from a fixed seed and reduced to a length and an FNV-1a hash of the raw Single
' bits. The golden table at the end was captured on Linux (the CI container) from the code before #400 and must be reproduced
' bit for bit at 48000 Hz. The two speech lines are rendered twice: with every clarity feature off
' (speechNatural, speechFast: still the pre-#400 hashes, so "off" is the old voice exactly) and with all of
' them on (speechClear, speechClearFast: captured from the #236 code). The hashes are only compared on Linux (_OS$ also reports [LINUX] on macOS, hence the [MAC check): sin and exp round differently in the Windows and macOS math libraries,
' so the lengths and the rate-to-rate checks are all that run there.
'
' At 44100, 96000 and 192000 Hz the same renders must last as long (within a sample), sound at the
' same pitch (zero crossings per second of the tonal sounds, the wavetable step, the music tempo)
' and pace the game the same (the game-time frame, crawl paragraph length, boss shield length).
' No sound device is involved: AUD_SetRate takes the rate directly.
'
' Run it with the argument "dump" to print the golden table in the DATA format instead of checking it.
'
' Build: ./tools/buildqb tests/audio_rate_test.bas
' Run:   ./builds/audio_rate_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
'$INCLUDE:'../src/sys/failfast.bi'
$EMBED:'assets/music.mus':'MUSICDATA'
$EMBED:'assets/sequence.txt':'SEQTXT'
$EMBED:'assets/speech_dict.txt':'SPEECHDICT'


Sub DBG_Print (arMsg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/audiorate.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/audio/snd.bas'
'$INCLUDE:'../src/audio/music.bas'

Const AR_MAX = 40
Const AR_GOLDEN = 31          ' the first AR_GOLDEN renders have a golden hash; the rest are only compared across rates
Const AR_PH_MAX = 256

Type AR_Result
    nm As String * 16
    n As Long                 ' samples rendered
    h As _Integer64           ' FNV-1a of the raw Single bits
    zc As Long                ' zero crossings
End Type

Dim Shared arRes(0 To AR_MAX - 1) As AR_Result
Dim Shared arRef(0 To AR_MAX - 1) As AR_Result     ' the 48000 Hz render, for the other rates to match
Dim Shared arN As Integer
Dim Shared arHv As _Integer64, arCnt As Long, arZc As Long, arPrevNeg As Integer

' Other things one run measures, for the rate-to-rate checks.
Type AR_Probe
    blipBad As Integer        ' narration blips whose length or noise burst fell outside the scaled range
    stepDur As Long           ' musStepDur of the "game" cue
    wave0 As Single           ' spkWaveStep for unstressed, primary and secondary stress
    wave1 As Single
    wave2 As Single
    phN As Integer            ' phonemes of the natural-speed line
    queue As Long             ' SPK_QueueSamples& of that line
    frame As Long             ' AUD_FrameSamples&
    para As Single            ' its crawl paragraph length, seconds (SPK_QueueSamples& / audTune)
    shield As Long            ' boss shield frames for it (as BHP_ShieldFrames& counts them, ceil(samples / frame))
End Type
Dim Shared arPr As AR_Probe, arPrRef As AR_Probe
Dim Shared arPhDur(0 To AR_PH_MAX - 1) As Long, arPhDurRef(0 To AR_PH_MAX - 1) As Long

Sub AR_HashBegin
    arHv = 2166136261
    arCnt = 0 : arZc = 0 : arPrevNeg = 0
End Sub

' Count a zero crossing of arV without hashing it.
Sub AR_ZcOnly (arV As Single)
    If arV < 0 Then
        If arPrevNeg = 0 And arCnt > 0 Then arZc = arZc + 1
        arPrevNeg = -1
    ElseIf arV > 0 Then
        If arPrevNeg <> 0 Then arZc = arZc + 1
        arPrevNeg = 0
    End If
End Sub

Sub AR_HashAdd (arV As Single)
    Dim arB As String, arI As Integer
    arB = MKS$(arV)
    For arI = 1 To 4
        arHv = ((arHv Xor Asc(Mid$(arB, arI, 1))) * 16777619) And 4294967295
    Next arI
    AR_ZcOnly arV
    arCnt = arCnt + 1
End Sub

Sub AR_Record (arNm As String)
    arRes(arN).nm = arNm : arRes(arN).n = arCnt : arRes(arN).h = arHv : arRes(arN).zc = arZc
    arN = arN + 1
End Sub

' Samples to render for arC samples at the reference rate.
Function AR_Count& (arC As Long)
    AR_Count& = AUD_N&(arC)
End Function

Sub AR_Run
    Dim arK As Long, arI As Integer

    arN = 0
    RNG_Seed 20260401
    SND_Init

    AR_HashBegin : For arK = 0 To SND_SHOOT_LEN - 1 : AR_HashAdd sndShoot(arK) : Next arK : AR_Record "shoot"
    AR_HashBegin : For arK = 0 To SND_BOOM_LEN - 1 : AR_HashAdd sndBoom(arK) : Next arK : AR_Record "boom"
    AR_HashBegin : For arK = 0 To SND_HIT_LEN - 1 : AR_HashAdd sndHit(arK) : Next arK : AR_Record "hit"
    AR_HashBegin : For arK = 0 To SND_PUP_LEN - 1 : AR_HashAdd sndPup(arK) : Next arK : AR_Record "pup"
    AR_HashBegin : For arK = 0 To SND_WHOOSH_LEN - 1 : AR_HashAdd sndWhoosh(arK) : Next arK : AR_Record "whoosh"
    AR_HashBegin : For arK = 0 To SND_WHOOSH_LEN - 1 : AR_HashAdd sndWhooshMd(arK) : Next arK : AR_Record "whooshMd"
    AR_HashBegin : For arK = 0 To SND_WHOOSH_LEN - 1 : AR_HashAdd sndWhooshLg(arK) : Next arK : AR_Record "whooshLg"
    AR_HashBegin : For arK = 0 To SND_KICK_LEN - 1 : AR_HashAdd sndKick(arK) : Next arK : AR_Record "kick"
    AR_HashBegin : For arK = 0 To SND_SNARE_LEN - 1 : AR_HashAdd sndSnare(arK) : Next arK : AR_Record "snare"
    AR_HashBegin : For arK = 0 To SND_HIHAT_LEN - 1 : AR_HashAdd sndHihat(arK) : Next arK : AR_Record "hihat"
    AR_HashBegin : For arK = 0 To SND_TOM_LEN - 1 : AR_HashAdd sndTom(arK) : Next arK : AR_Record "tom"
    AR_HashBegin : For arK = 0 To SND_CRASH_LEN - 1 : AR_HashAdd sndCrash(arK) : Next arK : AR_Record "crash"
    AR_HashBegin : For arK = 0 To SND_OHAT_LEN - 1 : AR_HashAdd sndOHat(arK) : Next arK : AR_Record "ohat"
    AR_HashBegin : For arK = 0 To SND_DEATH_LEN - 1 : AR_HashAdd sndDeath(arK) : Next arK : AR_Record "death"
    AR_HashBegin : For arK = 0 To SND_UIMOVE_LEN - 1 : AR_HashAdd sndUiMove(arK) : Next arK : AR_Record "uiMove"
    AR_HashBegin : For arK = 0 To SND_UIDENY_LEN - 1 : AR_HashAdd sndUiDeny(arK) : Next arK : AR_Record "uiDeny"
    AR_HashBegin : For arK = 0 To SND_UITYPE_LEN - 1 : AR_HashAdd sndUiType(arK) : Next arK : AR_Record "uiType"
    AR_HashBegin : For arK = 0 To SND_UIDEL_LEN - 1 : AR_HashAdd sndUiDel(arK) : Next arK : AR_Record "uiDel"
    AR_HashBegin : For arK = 0 To SND_UICOL_LEN - 1 : AR_HashAdd sndUiCol(arK) : Next arK : AR_Record "uiCol"
    AR_HashBegin
    For arI = 0 To SND_UI_SPIN_N - 1
        For arK = 0 To SND_UISPIN_LEN - 1 : AR_HashAdd sndUiSpin(arI, arK) : Next arK
    Next arI
    AR_Record "uiSpin"

    ' the UI voice: a chime, retriggered mid-sound by a deny buzz (the old one fades out)
    AR_HashBegin
    SND_UiPlay SND_UI_PUP
    For arK = 0 To AR_Count&(1500) - 1 : AR_HashAdd SND_UiNext! : Next arK
    SND_UiPlay SND_UI_DENY
    For arK = 0 To AR_Count&(7000) - 1 : AR_HashAdd SND_UiNext! : Next arK
    AR_Record "uiVoice"

    ' engine hum phase, at the idle and the manoeuvre pitch (its zero crossings are those of its sine)
    AR_HashBegin
    sndEnginePhase = 0
    sndEngineFreq = 75.0
    For arK = 0 To AR_Count&(3000) - 1 : SND_EngineStep : AR_HashAdd sndEnginePhase : Next arK
    sndEngineFreq = 150.0
    For arK = 0 To AR_Count&(3000) - 1 : SND_EngineStep : AR_HashAdd sndEnginePhase : Next arK
    AR_Record "engine"

    ' narration blips: the length and plosive draws come from RNG_AUDIO
    AR_HashBegin
    RNG_Seed 777 : arPr.blipBad = 0
    For arI = 1 To 6
        SND_Blip 180.0 + 45.0 * arI
        If sndBlipLen < AUD_N&(1323) Or sndBlipLen > AUD_N&(1323) + AUD_N&(2205) Then arPr.blipBad = arPr.blipBad + 1
        If sndBlipPlosLen <> 0 And (sndBlipPlosLen < AUD_N&(441) Or sndBlipPlosLen > AUD_N&(441) + AUD_N&(441)) Then arPr.blipBad = arPr.blipBad + 1
        Do While sndBlipTimer > 0 : AR_HashAdd SND_BlipNext! : Loop
    Next arI
    AR_Record "blip"

    ' music: cue runs through the real mixer function
    MUS_Reset
    AR_HashBegin
    MUS_SetCue "title"
    For arK = 0 To AR_Count&(120000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    AR_Record "musTitle"
    AR_HashBegin
    MUS_SetCue "game"
    arPr.stepDur = musStepDur
    For arK = 0 To AR_Count&(120000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    AR_Record "musGame"
    AR_HashBegin
    MUS_SetCue "boss3"
    For arK = 0 To AR_Count&(60000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    AR_Record "musBoss3"
    ' a switch while the previous crossfade is still running, then another
    AR_HashBegin
    MUS_SetCue "emperor"
    For arK = 0 To AR_Count&(1000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    MUS_SetCue "planet"
    For arK = 0 To AR_Count&(500) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    MUS_SetCue "crawl"
    For arK = 0 To AR_Count&(100000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    AR_Record "musSwitch"

    ' speech: two fixed lines, one at natural speed and one at the FAST narration preset, first with every
    ' clarity feature off (#236: the voice from before, bit for bit), then with all of them on
    RNG_Seed 4242
    SPK_Init
    For arI = 0 To SPK_FX_N - 1 : spkFx(arI) = 0 : Next arI
    AR_HashBegin
    SPK_Say "Attention all pilots. The fleet departs at dawn."
    arPr.phN = spkPhoneCount
    For arI = 0 To spkPhoneCount - 1 : arPhDur(arI) = SPK_PhoneDur&(spkPhones(arI), spkStress(arI)) : Next arI
    arPr.queue = SPK_QueueSamples&
    arPr.frame = AUD_FrameSamples&
    arPr.para = arPr.queue / audTune
    arPr.shield = (arPr.queue + arPr.frame - 1) \ arPr.frame
    Do While spkPhoneIdx < spkPhoneCount : SPK_Advance : AR_HashAdd spkSampleOut : Loop
    AR_Record "speechNatural"
    AR_HashBegin
    SPK_Say "Shields are holding, but the cruiser is closing fast."
    SPK_SetPreset 3
    Do While spkPhoneIdx < spkPhoneCount : SPK_Advance : AR_HashAdd spkSampleOut : Loop
    AR_Record "speechFast"
    For arI = 0 To SPK_FX_N - 1 : spkFx(arI) = -1 : Next arI
    AR_HashBegin
    SPK_Say "Attention all pilots. The fleet departs at dawn."
    Do While spkPhoneIdx < spkPhoneCount : SPK_Advance : AR_HashAdd spkSampleOut : Loop
    AR_Record "speechClear"
    AR_HashBegin
    SPK_Say "Shields are holding, but the cruiser is closing fast."
    SPK_SetPreset 3
    Do While spkPhoneIdx < spkPhoneCount : SPK_Advance : AR_HashAdd spkSampleOut : Loop
    AR_Record "speechClearFast"

    ' the wavetable step per phoneme stress (voice pitch)
    SPK_BuildWave SPK_AA, 0 : arPr.wave0 = spkWaveStep
    SPK_BuildWave SPK_AA, 1 : arPr.wave1 = spkWaveStep
    SPK_BuildWave SPK_AA, 2 : arPr.wave2 = spkWaveStep

    ' extras, compared across rates only. The sines of the engine phase and a pad-only cue give the pitch.
    AR_HashBegin
    sndEnginePhase = 0 : sndEngineFreq = 75.0
    For arK = 0 To AR_Count&(24000) - 1 : SND_EngineStep : AR_ZcOnly Sin(sndEnginePhase) : arCnt = arCnt + 1 : Next arK
    AR_Record "engineSine"
    MUS_Reset
    AR_HashBegin
    MUS_SetCue "emperor"
    For arK = 0 To AR_Count&(144000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    AR_Record "musEmperor"
End Sub

Dim Shared arPassed As Integer, arFailed As Integer

Sub AR_Assert (arCond As Integer, arTestName As String)
    If arCond Then
        Print "PASS  " + arTestName
        arPassed = arPassed + 1
    Else
        Print "FAIL  " + arTestName
        arFailed = arFailed + 1
    End If
End Sub

Function AR_Abs# (arX As Double)
    If arX < 0 Then AR_Abs# = -arX Else AR_Abs# = arX
End Function

Function AR_Tonal% (arNm As String)
    Select Case arNm
        Case "shoot", "hit", "pup", "kick", "uiMove", "uiDeny", "uiDel", "uiCol", "uiSpin", "engineSine", "musEmperor"
            AR_Tonal% = -1
    End Select
End Function

' One non-reference rate against the 48000 Hz render in arRef().
Sub AR_CheckRate (arR As Long)
    Dim arI As Integer, arScale As Double, arZr As Double, arZ0 As Double, arTag As String, arD As Double, arName As String, arTol As Double
    arTag = Str$(arR) + " Hz:"
    arScale = arR / 48000#

    For arI = 0 To arN - 1
        arName = RTrim$(arRes(arI).nm)
        ' every render lasts as long (within a sample per section); lengths scale, they do not drift
        arTol = 1.0001
        Select Case arName
            Case "uiSpin" : arTol = 39
            Case "musSwitch" : arTol = 3
            Case "uiVoice", "engine" : arTol = 2
            Case "speechNatural", "speechFast", "speechClear", "speechClearFast" : arTol = arPr.phN + 1
            Case "blip" : arTol = 1E9     ' random lengths from a stream the plosive bursts also draw on; the draws are range-checked below
        End Select
        AR_Assert AR_Abs#(arRes(arI).n - arRef(arI).n * arScale) <= arTol, arTag + " " + arName + " lasts as long (" + Str$(arRes(arI).n) + " vs" + Str$(CLng(arRef(arI).n * arScale)) + ")"
        If AR_Tonal%(arName) Then
            arZ0 = arRef(arI).zc * 48000# / arRef(arI).n
            arZr = arRes(arI).zc * arR / arRes(arI).n
            AR_Assert AR_Abs#(arZr / arZ0 - 1) < 0.02, arTag + " " + arName + " has the same pitch (" + Str$(CLng(arZr)) + " vs" + Str$(CLng(arZ0)) + " crossings/s)"
        End If
    Next arI

    ' speech: every phoneme lasts as long (within a sample), the voice has the same pitch, the line the same length
    arD = 0
    For arI = 0 To arPr.phN - 1
        If AR_Abs#(arPhDur(arI) - arPhDurRef(arI) * arScale) > arD Then arD = AR_Abs#(arPhDur(arI) - arPhDurRef(arI) * arScale)
    Next arI
    AR_Assert arPr.phN = arPrRef.phN And arD <= 1, arTag + " each phoneme lasts as long, within a sample (worst" + Str$(arD) + ")"
    AR_Assert AR_Abs#(arPr.wave0 * arR / (arPrRef.wave0 * 48000#) - 1) < 0.0001 And AR_Abs#(arPr.wave1 * arR / (arPrRef.wave1 * 48000#) - 1) < 0.0001 And AR_Abs#(arPr.wave2 * arR / (arPrRef.wave2 * 48000#) - 1) < 0.0001, arTag + " voice pitch (wavetable steps per second) is unchanged"

    AR_Assert arPr.blipBad = 0, arTag + " narration blips (30-80 ms, 10-20 ms noise burst) stay in their scaled range"

    ' tempo: a music step lasts the same time
    AR_Assert AR_Abs#(arPr.stepDur / CDbl(arR) - arPrRef.stepDur / 48000#) <= 1.5 / arR, arTag + " a music step lasts as long (" + Str$(arPr.stepDur) + " vs" + Str$(arPrRef.stepDur) + " samples)"

    ' game timing counts the same frames and seconds whatever the rate
    AR_Assert AR_Abs#(arPr.frame - arPrRef.frame * arScale) <= 1, arTag + " the game-time frame is" + Str$(arPr.frame) + " samples (" + Str$(arPrRef.frame) + " at 48000 Hz)"
    AR_Assert AR_Abs#(arPr.para - arPrRef.para) < 0.002, arTag + " a crawl paragraph is as long (" + Str$(arPr.para) + " s vs" + Str$(arPrRef.para) + " s)"
    AR_Assert AR_Abs#(arPr.shield - arPrRef.shield) <= 1, arTag + " a boss shield lasts as many frames (" + Str$(arPr.shield) + " vs" + Str$(arPrRef.shield) + ")"

    ' decays and smoothing keep their per-second behaviour
    AR_Assert AR_Abs#(AUD_Decay#(0.995#) ^ arR / (0.995# ^ 48000#) - 1) < 0.000001, arTag + " a per-sample decay falls as fast per second (" + Str$(AUD_Decay#(0.995#) ^ arR) + " vs" + Str$(0.995# ^ 48000#) + ")"
    AR_Assert AR_Abs#((1# - CDbl(AUD_Smooth!(0.004))) ^ arR / ((1# - CDbl(0.004!)) ^ 48000#) - 1) < 0.0002, arTag + " a per-sample smoothing approaches as fast per second (" + Str$((1# - CDbl(AUD_Smooth!(0.004))) ^ arR) + " vs" + Str$((1# - CDbl(0.004!)) ^ 48000#) + ")"
End Sub

Print "=== audio_rate_test ==="

AUD_SetRate 48000
AR_Run

If Command$ = "dump" Then
    Dim arD As Integer
    For arD = 0 To AR_GOLDEN - 1
        Print "Data " + Chr$(34) + RTrim$(arRes(arD).nm) + Chr$(34) + "," + Str$(arRes(arD).n) + "," + Str$(arRes(arD).h)
    Next arD
    System 0
End If

Dim arG As Integer, arGn As String, arGl As Long, arGh As _Integer64
Restore GoldenTable
AR_Assert arN >= AR_GOLDEN, "all" + Str$(AR_GOLDEN) + " golden renders are made"
For arG = 0 To AR_GOLDEN - 1
    Read arGn, arGl, arGh
    AR_Assert RTrim$(arRes(arG).nm) = arGn, "table order: " + arGn
    AR_Assert arRes(arG).n = arGl, arGn + ": length" + Str$(arRes(arG).n) + " = golden" + Str$(arGl)
    If InStr(_OS$, "[LINUX]") > 0 And InStr(_OS$, "[MAC") = 0 Then
        AR_Assert arRes(arG).h = arGh, arGn + ": samples are bit-identical to the golden"
    End If
Next arG

' the 48000 Hz render is the reference for the other rates
Dim arI2 As Integer
For arI2 = 0 To arN - 1 : arRef(arI2) = arRes(arI2) : Next arI2
arPrRef = arPr
For arI2 = 0 To arPr.phN - 1 : arPhDurRef(arI2) = arPhDur(arI2) : Next arI2

Dim arRates(0 To 2) As Long
arRates(0) = 44100 : arRates(1) = 96000 : arRates(2) = 192000
For arI2 = 0 To 2
    AUD_SetRate arRates(arI2)
    AR_Assert SAMPLE_RATE = arRates(arI2), Str$(arRates(arI2)) + " Hz: AUD_SetRate sets the synthesis rate"
    AR_Run
    AR_CheckRate arRates(arI2)
Next arI2

AUD_SetRate 0
AR_Assert SAMPLE_RATE = AUTHOR_RATE And audK = 1 And audTune = 44100, "no sound device (rate 0) keeps the 48000 Hz reference"

Print
Print "audio_rate_test:"; arPassed; "passed,"; arFailed; "failed"
If arFailed > 0 Then System 1
System 0

GoldenTable:
    Data "shoot", 2205, 4030601151
    Data "boom", 11025, 2693777716
    Data "hit", 8820, 2947879989
    Data "pup", 4410, 3434124993
    Data "whoosh", 22050, 3099864726
    Data "whooshMd", 22050, 2077622330
    Data "whooshLg", 22050, 3386246824
    Data "kick", 11025, 2087685240
    Data "snare", 4410, 3500971108
    Data "hihat", 2205, 125681085
    Data "tom", 19845, 3762369430
    Data "crash", 30870, 190447902
    Data "ohat", 11025, 1783914197
    Data "death", 32760, 19814737
    Data "uiMove", 1764, 4152414332
    Data "uiDeny", 5292, 1048475147
    Data "uiType", 1102, 191015633
    Data "uiDel", 3087, 3027762150
    Data "uiCol", 4851, 3257485782
    Data "uiSpin", 51597, 2901996156
    Data "uiVoice", 8500, 2494549898
    Data "engine", 6000, 1171652785
    Data "blip", 16286, 145993343
    Data "musTitle", 120000, 3701441537
    Data "musGame", 120000, 745643780
    Data "musBoss3", 60000, 587591859
    Data "musSwitch", 101500, 3518089085
    Data "speechNatural", 571752, 1302666785
    Data "speechFast", 170178, 771496315
    Data "speechClear", 571752, 3123539111
    Data "speechClearFast", 170178, 2594939230
