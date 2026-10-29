' music_test.bas — the music engine and assets/music.mus (#207): every cue loads and renders
' cleanly offline through the real mixer (no NaN, no clipping, notes start and end at zero,
' cue switches and drum retriggers don't step), and the data stays within the engine's limits.
'
' Build: ./tools/buildqb tests/music_test.bas
' Run:   ./builds/music_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/music.mus':'MUSICDATA'
$EMBED:'assets/sequence.txt':'SEQTXT'

Const SAMPLE_RATE = 44100
Const SND_UI_MOVE   = 1
Const SND_UI_DENY   = 2
Const SND_UI_PUP    = 3
Const SND_UI_TYPE   = 4
Const SND_UI_DEL    = 5
Const SND_UI_COLOR  = 6
Const SND_UI_SPIN   = 7
Const SND_UI_SPIN_N = 39

Dim Shared volMusic As Single, volSfx As Single, volSpeech As Single, spkSampleOut As Single
Sub SPK_Advance () : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/audio/snd.bas'
'$INCLUDE:'../src/audio/music.bas'

Dim Shared mtPassed As Integer, mtFailed As Integer

Sub MT_Assert (mtCond As Integer, mtName As String)
    If mtCond Then
        Print "PASS  " + mtName
        mtPassed = mtPassed + 1
    Else
        Print "FAIL  " + mtName
        mtFailed = mtFailed + 1
    End If
End Sub

Function MT_CueIdx% (mtCIn As String)
    Dim mtCIi As Integer
    MT_CueIdx% = -1
    For mtCIi = 0 To musCueCnt - 1
        If musCueN$(mtCIi) = mtCIn Then MT_CueIdx% = mtCIi
    Next mtCIi
End Function

' Steps one pass of a sequenced voice template takes.
Function MT_VoiceSteps& (mtVSc As Integer, mtVSv As Integer)
    Dim mtVSn As Integer, mtVSt As Long
    For mtVSn = 0 To musCueTmpl(mtVSc, mtVSv).seqLen - 1
        mtVSt = mtVSt + musND(musCueTmpl(mtVSc, mtVSv).seqBase + mtVSn)
    Next mtVSn
    MT_VoiceSteps& = mtVSt
End Function

' Steps of the cue's whole loop: its longest voice (or drum pattern).
Function MT_LoopSteps& (mtLSc As Integer)
    Dim mtLSv As Integer, mtLSt As Long, mtLSm As Long
    For mtLSv = 0 To musCueVCnt(mtLSc) - 1
        If musCueTmpl(mtLSc, mtLSv).isPad = 0 Then
            mtLSt = MT_VoiceSteps&(mtLSc, mtLSv)
            If mtLSt > mtLSm Then mtLSm = mtLSt
        End If
    Next mtLSv
    If musCueDrum(mtLSc) >= 0 Then
        If musDrumLen(musCueDrum(mtLSc)) > mtLSm Then mtLSm = musDrumLen(musCueDrum(mtLSc))
    End If
    MT_LoopSteps& = mtLSm
End Function

Sub MT_Silence
    MUS_Reset
End Sub

Print "=== music_test ==="
Print ""

Dim mtErr As Integer
On Error GoTo mtInitErr
SND_Init
GoTo mtAfterInit
mtInitErr:
mtErr = -1
Resume Next
mtAfterInit:
On Error GoTo 0
MT_Assert mtErr = 0, "SND_Init (and MUS_Load) completed without runtime error"

Print "--- parser ---"
If musLoadErrs > 0 Then Print "      first problem: " + musLoadErrMsg$
MT_Assert musLoadErrs = 0, "music.mus loads with no skipped or bad data (" + LTrim$(Str$(musLoadErrs)) + " problems)"
MT_Assert Abs(MUS_NoteFreq!("A4") - 440) < 0.01, "A4 = 440 Hz"
MT_Assert Abs(MUS_NoteFreq!("C#5") - 554.365) < 0.05 And Abs(MUS_NoteFreq!("Db5") - 554.365) < 0.05, "C#5 = Db5 = 554.37 Hz"
MT_Assert MUS_NoteFreq!("R") = 0, "R is a rest"
MT_Assert MUS_NoteFreq!("H4") < 0 And MUS_NoteFreq!("C") < 0 And MUS_NoteFreq!("C#45") < 0, "malformed notes are rejected"
MT_Assert MUS_DrumBits%("KX") < 0, "an unknown drum letter is rejected"
MT_Assert MUS_DrumBits%("KH") = 5 And MUS_DrumBits%(".") = 0, "K and H set their bits, . is a rest"
MT_Assert MUS_DrumBits%("t") = (8 Or 2048), "lowercase is the soft hit of the same drum"
MT_Assert musCueCnt >= 11, "all cues loaded (" + LTrim$(Str$(musCueCnt)) + " of max" + Str$(MUS_CUE_MAX) + ")"

' every cue the code or sequence.txt asks for exists
Print "--- every referenced cue exists ---"
Dim mtNeed As String, mtNeedP As Integer, mtOne As String, mtMissing As Integer
mtNeed = "title,gameover,crawl,emperor,planet,game,dock,"
Dim mtSeqRest As String, mtSeqLn As String, mtSeqP As Integer, mtSeqMus As String
mtSeqRest = _EMBEDDED$("SEQTXT")
Do While Len(mtSeqRest) > 0
    mtSeqP = InStr(mtSeqRest, Chr$(10))
    If mtSeqP > 0 Then mtSeqLn = Left$(mtSeqRest, mtSeqP - 1) : mtSeqRest = Mid$(mtSeqRest, mtSeqP + 1) Else mtSeqLn = mtSeqRest : mtSeqRest = ""
    mtSeqLn = LTrim$(RTrim$(mtSeqLn))
    If Left$(mtSeqLn, 1) <> ";" Then
        mtSeqP = InStr(mtSeqLn, "mus=")
        If mtSeqP > 0 Then
            mtSeqMus = Mid$(mtSeqLn, mtSeqP + 4)
            If InStr(mtSeqMus, " ") > 0 Then mtSeqMus = Left$(mtSeqMus, InStr(mtSeqMus, " ") - 1)
            If Right$(mtSeqMus, 1) = Chr$(13) Then mtSeqMus = Left$(mtSeqMus, Len(mtSeqMus) - 1)
            mtNeed = mtNeed + mtSeqMus + ","
        End If
    End If
Loop
Do While Len(mtNeed) > 0
    mtNeedP = InStr(mtNeed, ",")
    mtOne = Left$(mtNeed, mtNeedP - 1) : mtNeed = Mid$(mtNeed, mtNeedP + 1)
    If Len(mtOne) > 0 And MT_CueIdx%(mtOne) < 0 Then mtMissing = mtMissing + 1 : Print "      missing cue: " + mtOne
Loop
MT_Assert mtMissing = 0, "every cue named in sequence.txt and the code is in music.mus"

' ── static checks per cue ──
Print "--- cue data within limits ---"
Dim mtC As Integer, mtV As Integer, mtN As Integer, mtF As Single, mtBadNote As Integer
Dim mtLoop As Long, mtSteps As Long, mtSeam As Integer, mtStepSec As Single, mtLoopS As Single
For mtC = 0 To musCueCnt - 1
    mtBadNote = 0 : mtSeam = -1
    mtLoop = MT_LoopSteps&(mtC)
    For mtV = 0 To musCueVCnt(mtC) - 1
        If musCueTmpl(mtC, mtV).isPad = 0 Then
            For mtN = 0 To musCueTmpl(mtC, mtV).seqLen - 1
                mtF = musNF(musCueTmpl(mtC, mtV).seqBase + mtN)
                If mtF <> 0 And (mtF < 27.5 Or mtF > 4200) Then mtBadNote = mtBadNote + 1
                If musNV(musCueTmpl(mtC, mtV).seqBase + mtN) <= 0 Or musNV(musCueTmpl(mtC, mtV).seqBase + mtN) > 1.5 Then mtBadNote = mtBadNote + 1
            Next mtN
            mtSteps = MT_VoiceSteps&(mtC, mtV)
            If mtLoop Mod mtSteps <> 0 Then mtSeam = 0
        ElseIf musCueTmpl(mtC, mtV).freq < 27.5 Or musCueTmpl(mtC, mtV).freq > 4200 Then
            mtBadNote = mtBadNote + 1
        End If
    Next mtV
    If musCueDrum(mtC) >= 0 Then
        If mtLoop Mod musDrumLen(musCueDrum(mtC)) <> 0 Then mtSeam = 0
    End If
    mtStepSec = 60 / (musCueBPM(mtC) * musCueDiv(mtC))
    mtLoopS = mtLoop * mtStepSec
    MT_Assert musCueVCnt(mtC) >= 1 And musCueVCnt(mtC) <= MUS_CUE_VMAX And musCueVCnt(mtC) <= MUS_VOICE_MAX, musCueN$(mtC) + ": 1.." + LTrim$(Str$(MUS_CUE_VMAX)) + " voices (" + LTrim$(Str$(musCueVCnt(mtC))) + ")"
    MT_Assert mtBadNote = 0, musCueN$(mtC) + ": every note between A0 and C8, velocity in range"
    MT_Assert mtSeam, musCueN$(mtC) + ": every voice and the drums loop a whole number of times per " + LTrim$(Str$(mtLoop)) + "-step loop"
    MT_Assert mtStepSec >= 0.04 And mtStepSec <= 1.5, musCueN$(mtC) + ": step length sane (" + LTrim$(Str$(Int(mtStepSec * 1000))) + " ms)"
    MT_Assert mtLoopS >= 1 And mtLoopS <= 90, musCueN$(mtC) + ": loop length 1..90 s (" + LTrim$(Str$(Int(mtLoopS))) + " s)"
Next mtC

' ── offline render of every cue through the real mixer ──
' Each sequenced voice's last 3 samples before it falls silent, and first 3 of a new note,
' must be within 0.003 of zero: the envelope closed, so no note starts or stops with a click.
Print "--- every cue renders cleanly ---"
Dim mtK As Long, mtLen As Long, mtS As Single, mtPk As Single, mtSum As Double, mtNaN As Long
Dim mtRms(0 To MUS_CUE_MAX - 1) As Single
Dim mtPrevSnd(0 To MUS_VOICE_MAX - 1) As Integer, mtPrevIdx(0 To MUS_VOICE_MAX - 1) As Integer
Dim mtH1(0 To MUS_VOICE_MAX - 1) As Single, mtH2(0 To MUS_VOICE_MAX - 1) As Single
Dim mtSince(0 To MUS_VOICE_MAX - 1) As Long
Dim mtSnd As Integer, mtEdgeBad As Long, mtEdgeWorst As Single, mtEdges As Long, mtO As Single
Dim mtRngBefore As _Unsigned Long
mtRngBefore = rngState(RNG_AUDIO)
For mtC = 0 To musCueCnt - 1
    MT_Silence
    MUS_SetCue musCueN$(mtC)
    mtLoopS = MT_LoopSteps&(mtC) * musStepDur / SAMPLE_RATE
    mtLen = CLng((mtLoopS + 1) * SAMPLE_RATE)
    If mtLen > 70 * SAMPLE_RATE Then mtLen = 70 * SAMPLE_RATE
    mtPk = 0 : mtSum = 0 : mtNaN = 0 : mtEdgeBad = 0 : mtEdgeWorst = 0 : mtEdges = 0
    For mtV = 0 To musVoiceCnt - 1
        mtPrevSnd(mtV) = 0 : mtPrevIdx(mtV) = musVoice(mtV).noteIdx : mtH1(mtV) = 0 : mtH2(mtV) = 0 : mtSince(mtV) = 99
    Next mtV
    For mtK = 0 To mtLen - 1
        mtS = MUS_MusicSample!
        If (Abs(mtS) <= 10) = 0 Then mtNaN = mtNaN + 1
        If Abs(mtS) > mtPk Then mtPk = Abs(mtS)
        If mtK >= SAMPLE_RATE Then mtSum = mtSum + CDbl(mtS) * mtS
        For mtV = 0 To musVoiceCnt - 1
            If musVoice(mtV).isPad = 0 Then
                mtO = musVoice(mtV).lastOut
                mtSnd = (musVoice(mtV).count > musVoice(mtV).gateOff And musVoice(mtV).freq > 0)
                If musVoice(mtV).noteIdx <> mtPrevIdx(mtV) Or (mtPrevSnd(mtV) <> 0 And mtSnd = 0) Then
                    ' a note just ended (gate-off or the next note started): its last samples
                    mtEdges = mtEdges + 1
                    If Abs(mtH1(mtV)) > mtEdgeWorst Then mtEdgeWorst = Abs(mtH1(mtV))
                    If Abs(mtH2(mtV)) > mtEdgeWorst Then mtEdgeWorst = Abs(mtH2(mtV))
                    If Abs(mtH1(mtV)) > 0.003 Or Abs(mtH2(mtV)) > 0.003 Then mtEdgeBad = mtEdgeBad + 1
                End If
                If musVoice(mtV).noteIdx <> mtPrevIdx(mtV) Then mtSince(mtV) = 0
                If mtSince(mtV) < 3 Then
                    If Abs(mtO) > mtEdgeWorst Then mtEdgeWorst = Abs(mtO)
                    If Abs(mtO) > 0.003 Then mtEdgeBad = mtEdgeBad + 1
                End If
                mtSince(mtV) = mtSince(mtV) + 1
                mtH2(mtV) = mtH1(mtV) : mtH1(mtV) = mtO
                mtPrevSnd(mtV) = mtSnd : mtPrevIdx(mtV) = musVoice(mtV).noteIdx
            End If
        Next mtV
    Next mtK
    mtRms(mtC) = Sqr(mtSum / (mtLen - SAMPLE_RATE))
    Print "      " + musCueN$(mtC) + String$(10 - Len(musCueN$(mtC)), " ") + Str$(musCueBPM(mtC)) + " bpm  " + LTrim$(Str$(musCueVCnt(mtC))) + " voices  peak" + Str$(mtPk) + "  rms" + Str$(mtRms(mtC)) + "  loop" + Str$(Int(mtLoopS * 10) / 10) + " s  note edges" + Str$(mtEdges)
    MT_Assert mtNaN = 0, musCueN$(mtC) + ": no NaN or runaway samples"
    MT_Assert mtPk < 1.0, musCueN$(mtC) + ": peak under full scale before volMusic (" + LTrim$(Str$(mtPk)) + ")"
    MT_Assert mtRms(mtC) > 0.025 And mtRms(mtC) < 0.12, musCueN$(mtC) + ": loudness in the old mix's range, RMS 0.025..0.12 (" + LTrim$(Str$(mtRms(mtC))) + ")"
    MT_Assert mtEdgeBad = 0, musCueN$(mtC) + ": every note starts and ends at zero (worst edge sample" + Str$(mtEdgeWorst) + ")"
Next mtC
MT_Assert rngState(RNG_AUDIO) = mtRngBefore, "rendering music draws nothing from RNG_AUDIO (speech/blip randomness untouched)"

' the same cue rendered twice is the same audio
Dim mtA As Single, mtSame As Integer
mtSame = -1
MT_Silence : MUS_SetCue "boss3"
Dim mtFirst(0 To 9999) As Single
For mtK = 0 To 9999 : mtFirst(mtK) = MUS_MusicSample! : Next mtK
MT_Silence : MUS_SetCue "boss3"
For mtK = 0 To 9999
    mtA = MUS_MusicSample!
    If mtA <> mtFirst(mtK) Then mtSame = 0
Next mtK
MT_Assert mtSame, "a cue renders identically every time (deterministic)"

' ── context: tension matches where the cue plays ──
Print "--- the cues fit their scenes ---"
Dim mtB1 As Integer, mtB2 As Integer, mtB3 As Integer, mtGo As Integer, mtDock As Integer, mtGame As Integer
mtB1 = MT_CueIdx%("boss") : mtB2 = MT_CueIdx%("boss2") : mtB3 = MT_CueIdx%("boss3")
mtGo = MT_CueIdx%("gameover") : mtDock = MT_CueIdx%("dock") : mtGame = MT_CueIdx%("game")
If mtB1 >= 0 And mtB2 >= 0 And mtB3 >= 0 And mtGo >= 0 And mtDock >= 0 And mtGame >= 0 Then
    MT_Assert musCueBPM(mtB1) < musCueBPM(mtB2) And musCueBPM(mtB2) < musCueBPM(mtB3), "boss phases speed up (" + LTrim$(Str$(musCueBPM(mtB1))) + "," + Str$(musCueBPM(mtB2)) + "," + Str$(musCueBPM(mtB3)) + " bpm)"
    MT_Assert mtRms(mtB1) < mtRms(mtB2) And mtRms(mtB2) < mtRms(mtB3), "boss phases get louder"
    MT_Assert mtRms(mtB3) > mtRms(mtDock) And mtRms(mtGame) > mtRms(mtDock), "the dock is calmer than combat and the boss"
    MT_Assert musCueBPM(mtGo) <= 80 And mtRms(mtGo) < mtRms(mtGame), "game over is slow and quieter than combat"
    MT_Assert mtRms(MT_CueIdx%("crawl")) <= 0.048, "the crawl, under the narration, is no louder than it was before #207 (RMS" + Str$(mtRms(MT_CueIdx%("crawl"))) + " <= 0.048)"
Else
    MT_Assert 0, "boss, boss2, boss3, gameover, dock and game cues exist"
End If

' ── a cue switch mid-note doesn't step the output (voices only: a drum hit's onset is its own transient) ──
Print "--- cue switches and drum retriggers don't click ---"
Dim mtFrom As Integer, mtTo As Integer, mtPrevS As Single, mtWorstNear As Single, mtJump As Single, mtSwBad As Integer
Dim mtSwWorst As Single
For mtFrom = 0 To musCueCnt - 1
    mtTo = (mtFrom + 3) Mod musCueCnt
    MT_Silence : MUS_SetCue musCueN$(mtFrom)
    mtWorstNear = 0
    For mtK = 0 To CLng(SAMPLE_RATE * 1.37)
        mtS = MUS_MusicSample! : mtS = musLastVox + musTail
        If mtK > SAMPLE_RATE * 1.37 - 2000 And Abs(mtS - mtPrevS) > mtWorstNear Then mtWorstNear = Abs(mtS - mtPrevS)
        mtPrevS = mtS
    Next mtK
    MUS_SetCue musCueN$(mtTo)
    mtS = MUS_MusicSample! : mtS = musLastVox + musTail
    mtJump = Abs(mtS - mtPrevS)
    If mtJump > mtSwWorst Then mtSwWorst = mtJump
    If mtJump > mtWorstNear * 1.5 + 0.005 Then mtSwBad = mtSwBad + 1 : Print "      " + musCueN$(mtFrom) + " -> " + musCueN$(mtTo) + " steps" + Str$(mtJump) + " (signal's own worst" + Str$(mtWorstNear) + ")"
Next mtFrom
MT_Assert mtSwBad = 0, "switching cues mid-play never steps the output (worst" + Str$(mtSwWorst) + ")"
MT_Silence

' each drum: retriggered every ~10 ms at shifting offsets, never steps more than its own hit does
Dim mtDk As Integer, mtBase As Single, mtStep As Single, mtHit As Integer, mtD As Long
musVoiceCnt = 0 : musDrumIdx = -1
For mtDk = 0 To MUS_DK_N - 1
    MT_Silence : mtPrevS = 0 : mtBase = 0
    MUS_DrumHit mtDk, 1
    For mtK = 0 To MUS_DkLen&(mtDk) + 10
        mtS = MUS_MusicSample!
        If Abs(mtS - mtPrevS) > mtBase Then mtBase = Abs(mtS - mtPrevS)
        mtPrevS = mtS
    Next mtK
    MT_Silence : mtPrevS = 0 : mtStep = 0
    For mtHit = 1 To 12
        MUS_DrumHit mtDk, 1
        For mtD = 1 To 441 + mtHit * 37
            mtS = MUS_MusicSample!
            If Abs(mtS - mtPrevS) > mtStep Then mtStep = Abs(mtS - mtPrevS)
            mtPrevS = mtS
        Next mtD
    Next mtHit
    MT_Assert mtStep <= mtBase * 1.5 + 0.01, "drum" + Str$(mtDk) + ": retriggering mid-hit adds no step (worst" + Str$(mtStep) + " vs own" + Str$(mtBase) + ")"
Next mtDk
MT_Assert sndTom(0) = 0 And sndTom(SND_TOM_LEN - 1) = 0 And sndCrash(0) = 0 And sndCrash(SND_CRASH_LEN - 1) = 0 And sndOHat(0) = 0 And sndOHat(SND_OHAT_LEN - 1) = 0, "tom, crash and open hat start and end at exactly 0"

' ── the launch flow at the mixer: sss.bas starts "crawl" at launch (consent, callsign, lead-in
' cards), the sequencer's intro CRAWL step and crawl.bas set it again, then the emperor card,
' the title, a return from About, and P into the stage 1 crawl. No silent gap, no restart of
' the playing cue, no step at any switch.
Print "--- launch -> title -> crawl plays through ---"
Dim mtLCue(0 To 6) As String, mtLSec(0 To 6) As Single, mtLI As Integer, mtLWin As Double, mtLWinN As Long
Dim mtLGap As Long, mtLGapMax As Long, mtLSame As Integer, mtLIdx As Integer, mtLCnt As Long, mtLStepBad As Integer
mtLCue(0) = "crawl" : mtLSec(0) = 6
mtLCue(1) = "crawl" : mtLSec(1) = 0.02
mtLCue(2) = "crawl" : mtLSec(2) = 8
mtLCue(3) = "emperor" : mtLSec(3) = 6
mtLCue(4) = "title" : mtLSec(4) = 6
mtLCue(5) = "title" : mtLSec(5) = 4
mtLCue(6) = "crawl" : mtLSec(6) = 8
MT_Silence
mtLSame = -1 : mtPrevS = 0
For mtLI = 0 To 6
    If mtLI > 0 Then
        mtLIdx = musVoice(0).noteIdx : mtLCnt = musVoice(0).count
    End If
    MUS_SetCue mtLCue(mtLI)
    If mtLI > 0 Then
        If mtLCue(mtLI) = mtLCue(mtLI - 1) And (musVoice(0).noteIdx <> mtLIdx Or musVoice(0).count <> mtLCnt Or musXfT < musXfN) Then mtLSame = 0
    End If
    For mtK = 0 To CLng(mtLSec(mtLI) * SAMPLE_RATE) - 1
        mtS = MUS_MusicSample!
        mtA = musLastVox + musTail
        If mtK = 0 And mtLI > 0 Then
            If Abs(mtA - mtPrevS) > mtWorstNear * 1.5 + 0.005 Then mtLStepBad = mtLStepBad + 1 : Print "      step at the switch to " + mtLCue(mtLI) + ":" + Str$(Abs(mtA - mtPrevS))
        End If
        mtPrevS = mtA
        mtLWin = mtLWin + CDbl(mtS) * mtS : mtLWinN = mtLWinN + 1
        If mtLWinN = 2205 Then
            ' (the first second is the launch fade-in from nothing)
            If Sqr(mtLWin / mtLWinN) < 0.002 And (mtLI > 0 Or mtK > SAMPLE_RATE) Then mtLGap = mtLGap + 1 Else mtLGap = 0
            If mtLGap > mtLGapMax Then mtLGapMax = mtLGap
            mtLWin = 0 : mtLWinN = 0
        End If
    Next mtK
    ' the worst step the music makes by itself just before the next switch
    mtWorstNear = 0
    For mtK = 0 To 1999
        mtS = MUS_MusicSample!
        mtA = musLastVox + musTail
        If Abs(mtA - mtPrevS) > mtWorstNear Then mtWorstNear = Abs(mtA - mtPrevS)
        mtPrevS = mtA
    Next mtK
Next mtLI
MT_Assert mtLGapMax <= 1, "no silence over 50 ms anywhere from launch to the stage crawl (longest" + Str$(mtLGapMax * 50) + " ms)"
MT_Assert mtLSame, "setting the cue already playing (intro crawl, back from About) doesn't restart it"
MT_Assert mtLStepBad = 0, "no step at any switch on the way"
MT_Assert musCueXf(MT_CueIdx%("crawl")) >= 500 And musCueXf(MT_CueIdx%("emperor")) >= 500 And musCueXf(MT_CueIdx%("title")) >= 500, "the launch-flow cues (crawl, emperor, title) crossfade over at least 0.5 s"

' ── cost: the mixer runs this every sample, so the heaviest cue must render far faster than real time ──
Print "--- cost ---"
Dim mtT0 As Double, mtT1 As Double, mtHeavy As Integer, mtMost As Integer
For mtC = 0 To musCueCnt - 1
    If musCueVCnt(mtC) > mtMost Then mtMost = musCueVCnt(mtC) : mtHeavy = mtC
Next mtC
MT_Silence : MUS_SetCue musCueN$(mtHeavy)
mtT0 = Timer(0.001)
For mtK = 0 To 10 * SAMPLE_RATE - 1 : mtS = MUS_MusicSample! : Next mtK
mtT1 = Timer(0.001)
If mtT1 < mtT0 Then mtT1 = mtT1 + 86400
Print "      10 s of '" + musCueN$(mtHeavy) + "' (" + LTrim$(Str$(mtMost)) + " voices) rendered in" + Str$(Int((mtT1 - mtT0) * 1000)) + " ms"
MT_Assert mtT1 - mtT0 < 5, "the heaviest cue renders at least 2x faster than real time"

Print ""
Print "=== " + LTrim$(Str$(mtPassed + mtFailed)) + " tests: " + LTrim$(Str$(mtPassed)) + " passed, " + LTrim$(Str$(mtFailed)) + " failed ==="
If mtFailed > 0 Then System 1 Else System 0
