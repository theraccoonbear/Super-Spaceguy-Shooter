' narr_sync_test.bas -- the crawl highlight follows the voice the listener hears (#393)
'
' Plays the intro crawl frame by frame against a model audio device: the fill tops the
' device buffer up to 0.1 s (as MUS_Fill does), the device drains DEVICE_RATE samples per
' second of wall time, and the game runs at FPS frames per second. Each frame the main
' loop's order is CRAWL_Step%, fill, SPK_Tick. Per frame it measures how far the game-time
' position (what the highlight reads) is from the synth position the listener hears
' (SPK_HeardSynth& of the device's queued samples), in milliseconds.
'   - with the audio lock on, the highlight stays within
'     NS_LOCK_TOL_MS behind and NS_LEAD_TOL_MS ahead of the voice, at 60 fps on a 44.1 kHz device, a slower frame rate, a 48 kHz device,
'     and across a fast-forward stretch
'   - across a pause (#426: the fill runs held, CRAWL_Step% and SPK_Tick are skipped) the voice is silent,
'     then continues from the sample it stopped on and says what an uninterrupted run says
'   - with the lock off (the frame clock alone) the same runs drift by seconds
'
' Build: ./tools/buildqb tests/narr_sync_test.bas
' Run:   ./tests/narr_sync_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
'$INCLUDE:'../src/sys/failfast.bi'

$EMBED:'assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'assets/gametext.txt':'GAMETEXT'
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'

Sub DBG_Print(nsDbgMsg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/audiorate.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/sys/gametext.bas'
'$INCLUDE:'../src/2d/crawllayout.bas'

Const NS_START_Y = 240
Const NS_TRIG_Y = 218
Const NS_LEVEL = 2
Const NS_MAX_FRAMES = 20000
Const NS_BUFFER = 4410 ' 0.1 s, AUDIO_BUFFER_TARGET
Const NS_LOCK_TOL_MS = 120 ' one 60 fps frame of quantisation plus the first-frame lead
Const NS_LEAD_TOL_MS = 150 ' the frame clock starts with the utterance, the voice one buffer (100 ms) later
Const NS_LEAD_FF_TOL_MS = 550 ' and for one buffer after fast-forward starts the frame clock runs 5x while the queued audio is still at 1x
Const NS_FREE_MIN_MS = 1000 ' the frame clock alone must drift at least this far in the drifting scenarios

Dim Shared stPassed As Integer, stFailed As Integer
Dim Shared nsMaxLagMs As Single, nsMaxLeadMs As Single
Dim Shared nsSpoken As Long, nsCheck As Double, nsPzMidSpeech As Integer, nsHeldNonZero As Long
Dim Shared nsPzSynth0 As Long, nsPzSynth1 As Long
Dim Shared nsSynthAt(0 TO 16383) As Long ' own record of the synth position per output sample

Sub ST_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        stPassed = stPassed + 1
    Else
        Print "FAIL  " + testName
        stFailed = stFailed + 1
    End If
End Sub

' Plays crawl nspKey; nspLock = audio lock on/off. Sets nsMaxLagMs to the largest amount
' the highlight position trailed the heard voice (ms of synth time) and returns the frame count.
Function NS_Play& (nspKey As String, nspLock As Integer, nspFps As Single, nspRate As Single, nspFFAt As Long, nspFFLen As Long, nspPzAt As Long, nspPzLen As Long)
    Dim nspBuf As Long, nspN As Long, nspDrainAcc As Single, nspDrain As Long, nspFill As Long
    Dim nspS As Long, nspEvt As Integer, nspHeard As Long, nspLag As Single, nspOut As Long, nspDrained As Long
    Dim nspPzDone As Long, nspPaused As Integer, nspPrevSynth As Long, nspW As Long
    SPK_Say ""
    spkHold = 0 : RNG_Seed 4242 ' the voice noise comes from a seeded stream: every run starts it afresh so runs compare sample for sample
    spkAudioLock = nspLock : spkBuffered = 0 : spkOutTotal = 0 : spkSynthTotal = 0 : spkSayBase = 0 : spkClkTotal = 0
    CRAWL_Start GTEXT_Get$(nspKey), NS_LEVEL, NS_START_Y, NS_TRIG_Y
    nspBuf = 0 : nspN = 0 : nspDrainAcc = 0 : nsMaxLagMs = 0 : nsMaxLeadMs = 0 : nspOut = 0 : nspDrained = 0
    nspPzDone = 0 : nspPrevSynth = 0 : nspW = 0 : nsSpoken = 0 : nsCheck = 0 : nsPzMidSpeech = 0
    Do Until crawlScroll + crawlLineCount * CRAWL_LINE_H < -20 Or nspN >= NS_MAX_FRAMES Or nspW >= NS_MAX_FRAMES
        nspPaused = (nspPzLen > 0 And nspN = nspPzAt And nspPzDone < nspPzLen)
        If nspPaused Then
            If nspPzDone = 0 Then nsPzMidSpeech = SPK_IsPlaying% : nsPzSynth0 = spkSynthTotal
            nspPzDone = nspPzDone + 1
            spkHold = -1
        Else
            spkHold = 0
            nspEvt = CRAWL_Step%(nspFFAt > 0 And nspN >= nspFFAt And nspN < nspFFAt + nspFFLen, NS_LEVEL)
        End If
        nspDrainAcc = nspDrainAcc + nspRate / nspFps
        nspDrain = Int(nspDrainAcc) : nspDrainAcc = nspDrainAcc - nspDrain
        If nspDrain > nspBuf Then nspDrain = nspBuf
        nspBuf = nspBuf - nspDrain : nspDrained = nspDrained + nspDrain
        nspFill = NS_BUFFER - nspBuf
        For nspS = 1 To nspFill
            SPK_Advance
            nspOut = nspOut + 1 : nsSynthAt(nspOut And 16383) = spkSynthTotal
            If spkSynthTotal <> nspPrevSynth Then
                nsSpoken = nsSpoken + 1
                nsCheck = nsCheck + spkSampleOut * ((spkSynthTotal Mod 1009) + 1)
                nspPrevSynth = spkSynthTotal
            End If
            If spkHold And spkSampleOut <> 0 Then nsHeldNonZero = nsHeldNonZero + 1
        Next nspS
        nspBuf = nspBuf + nspFill
        spkBuffered = nspBuf
        If nspPaused Then nsPzSynth1 = spkSynthTotal Else SPK_Tick
        nspHeard = 0
        If nspDrained > 0 Then nspHeard = nsSynthAt(nspDrained And 16383) - spkSayBase
        If nspHeard < 0 Then nspHeard = 0
        nspLag = (nspHeard - spkClkTotal) * 1000! / SAMPLE_RATE
        If nspPaused = 0 Then
            If nspLag > nsMaxLagMs Then nsMaxLagMs = nspLag
            If -nspLag > nsMaxLeadMs Then nsMaxLeadMs = -nspLag
            nspN = nspN + 1
        End If
        nspW = nspW + 1
    Loop
    spkHold = 0
    NS_Play& = nspN
End Function

Sub NS_Case (nscName As String, nscFps As Single, nscRate As Single, nscFFAt As Long, nscFFLen As Long, nscDrifts As Integer)
    Dim nscN As Long, nscFreeMs As Single
    nscN = NS_Play&("intro", 0, nscFps, nscRate, nscFFAt, nscFFLen, 0, 0)
    nscFreeMs = nsMaxLagMs
    nscN = NS_Play&("intro", -1, nscFps, nscRate, nscFFAt, nscFFLen, 0, 0)
    ST_Assert nscN < NS_MAX_FRAMES, nscName + ": the crawl reaches its exit"
    ST_Assert nsMaxLagMs <= NS_LOCK_TOL_MS, nscName + ": audio lock keeps the highlight within" + Str$(NS_LOCK_TOL_MS) + " ms (worst" + Str$(Int(nsMaxLagMs)) + " ms)"
    Dim nscLead As Long : nscLead = NS_LEAD_TOL_MS : If nscFFAt > 0 Then nscLead = NS_LEAD_FF_TOL_MS
    ST_Assert nsMaxLeadMs <= nscLead, nscName + ": audio lock keeps the highlight no more than" + Str$(nscLead) + " ms ahead (worst" + Str$(Int(nsMaxLeadMs)) + " ms)"
    If nscDrifts Then
        ST_Assert nscFreeMs >= NS_FREE_MIN_MS, nscName + ": frame clock alone drifts (worst" + Str$(Int(nscFreeMs)) + " ms)"
    End If
End Sub

' Pause menu open mid-crawl: the fill keeps running held while CRAWL_Step% and SPK_Tick are skipped (crawl.bas).
' The voice must stop, then pick up where it stopped, in step with the text, and say what an uninterrupted run says.
Sub NS_PauseCase (npcName As String, npcFps As Single, npcRate As Single, npcPzAt As Long, npcPzLen As Long)
    Dim npcN As Long, npcRefSpoken As Long, npcRefCheck As Double
    npcN = NS_Play&("intro", -1, npcFps, npcRate, 0, 0, 0, 0)
    npcRefSpoken = nsSpoken : npcRefCheck = nsCheck
    npcN = NS_Play&("intro", -1, npcFps, npcRate, 0, 0, npcPzAt, npcPzLen)
    ST_Assert npcN < NS_MAX_FRAMES, npcName + ": the crawl reaches its exit"
    ST_Assert nsPzMidSpeech <> 0, npcName + ": the pause opens while a line is being spoken"
    ST_Assert nsPzSynth1 = nsPzSynth0, npcName + ": no speech synthesised while paused (moved" + Str$(nsPzSynth1 - nsPzSynth0) + " samples)"
    ST_Assert nsHeldNonZero = 0, npcName + ": the fill mixes silence for speech while paused"
    ST_Assert nsSpoken = npcRefSpoken, npcName + ": same synth samples as an uninterrupted run (" + LTrim$(Str$(nsSpoken)) + " vs" + Str$(npcRefSpoken) + ")"
    ST_Assert nsCheck = npcRefCheck, npcName + ": same words, nothing skipped or repeated"
    ST_Assert nsMaxLagMs <= NS_LOCK_TOL_MS, npcName + ": after resume the highlight stays within" + Str$(NS_LOCK_TOL_MS) + " ms behind the voice (worst" + Str$(Int(nsMaxLagMs)) + " ms)"
    ST_Assert nsMaxLeadMs <= NS_LEAD_TOL_MS, npcName + ": after resume the highlight stays within" + Str$(NS_LEAD_TOL_MS) + " ms ahead of the voice (worst" + Str$(Int(nsMaxLeadMs)) + " ms)"
End Sub

Print "=== narr_sync_test ==="
Print ""

SPK_Init
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")

NS_Case "60 fps, 44.1 kHz device", 60, 44100, 0, 0, 0
NS_Case "45 fps, 44.1 kHz device", 45, 44100, 0, 0, -1
NS_Case "60 fps, 48 kHz device", 60, 48000, 0, 0, -1
NS_Case "45 fps, 48 kHz device", 45, 48000, 0, 0, -1
NS_Case "60 fps, 44.1 kHz device, fast-forward", 60, 44100, 600, 300, 0
NS_Case "50 fps, 48 kHz device, fast-forward", 50, 48000, 600, 300, -1
NS_PauseCase "60 fps, 44.1 kHz device, 2 s pause", 60, 44100, 300, 120
NS_PauseCase "45 fps, 48 kHz device, 3 s pause", 45, 48000, 500, 135
NS_PauseCase "60 fps, 44.1 kHz device, 1-frame pause", 60, 44100, 400, 1

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
