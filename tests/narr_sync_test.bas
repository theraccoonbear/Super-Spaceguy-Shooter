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
Function NS_Play& (nspKey As String, nspLock As Integer, nspFps As Single, nspRate As Single, nspFFAt As Long, nspFFLen As Long)
    Dim nspBuf As Long, nspN As Long, nspDrainAcc As Single, nspDrain As Long, nspFill As Long
    Dim nspS As Long, nspEvt As Integer, nspHeard As Long, nspLag As Single, nspOut As Long, nspDrained As Long
    SPK_Say ""
    spkAudioLock = nspLock : spkBuffered = 0 : spkOutTotal = 0 : spkSynthTotal = 0 : spkSayBase = 0 : spkClkTotal = 0
    CRAWL_Start GTEXT_Get$(nspKey), NS_LEVEL, NS_START_Y, NS_TRIG_Y
    nspBuf = 0 : nspN = 0 : nspDrainAcc = 0 : nsMaxLagMs = 0 : nsMaxLeadMs = 0 : nspOut = 0 : nspDrained = 0
    Do Until crawlScroll + crawlLineCount * CRAWL_LINE_H < -20 Or nspN >= NS_MAX_FRAMES
        nspEvt = CRAWL_Step%(nspFFAt > 0 And nspN >= nspFFAt And nspN < nspFFAt + nspFFLen, NS_LEVEL)
        nspDrainAcc = nspDrainAcc + nspRate / nspFps
        nspDrain = Int(nspDrainAcc) : nspDrainAcc = nspDrainAcc - nspDrain
        If nspDrain > nspBuf Then nspDrain = nspBuf
        nspBuf = nspBuf - nspDrain : nspDrained = nspDrained + nspDrain
        nspFill = NS_BUFFER - nspBuf
        For nspS = 1 To nspFill
            SPK_Advance
            nspOut = nspOut + 1 : nsSynthAt(nspOut And 16383) = spkSynthTotal
        Next nspS
        nspBuf = nspBuf + nspFill
        spkBuffered = nspBuf
        SPK_Tick
        nspHeard = 0
        If nspDrained > 0 Then nspHeard = nsSynthAt(nspDrained And 16383) - spkSayBase
        If nspHeard < 0 Then nspHeard = 0
        nspLag = (nspHeard - spkClkTotal) * 1000! / SAMPLE_RATE
        If nspLag > nsMaxLagMs Then nsMaxLagMs = nspLag
        If -nspLag > nsMaxLeadMs Then nsMaxLeadMs = -nspLag
        nspN = nspN + 1
    Loop
    NS_Play& = nspN
End Function

Sub NS_Case (nscName As String, nscFps As Single, nscRate As Single, nscFFAt As Long, nscFFLen As Long, nscDrifts As Integer)
    Dim nscN As Long, nscFreeMs As Single
    nscN = NS_Play&("intro", 0, nscFps, nscRate, nscFFAt, nscFFLen)
    nscFreeMs = nsMaxLagMs
    nscN = NS_Play&("intro", -1, nscFps, nscRate, nscFFAt, nscFFLen)
    ST_Assert nscN < NS_MAX_FRAMES, nscName + ": the crawl reaches its exit"
    ST_Assert nsMaxLagMs <= NS_LOCK_TOL_MS, nscName + ": audio lock keeps the highlight within" + Str$(NS_LOCK_TOL_MS) + " ms (worst" + Str$(Int(nsMaxLagMs)) + " ms)"
    Dim nscLead As Long : nscLead = NS_LEAD_TOL_MS : If nscFFAt > 0 Then nscLead = NS_LEAD_FF_TOL_MS
    ST_Assert nsMaxLeadMs <= nscLead, nscName + ": audio lock keeps the highlight no more than" + Str$(nscLead) + " ms ahead (worst" + Str$(Int(nsMaxLeadMs)) + " ms)"
    If nscDrifts Then
        ST_Assert nscFreeMs >= NS_FREE_MIN_MS, nscName + ": frame clock alone drifts (worst" + Str$(Int(nscFreeMs)) + " ms)"
    End If
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

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
