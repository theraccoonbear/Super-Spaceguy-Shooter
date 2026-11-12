' crawl_step_test.bas — frame-by-frame crawl playback (CRAWL_Step%, src/2d/crawllayout.bas)
'
' Drives CRAWL_Start / CRAWL_Step% for every named crawl with the real speech queue
' advanced one frame of speech time (SPK_Tick) per 60 fps frame, as the main loop does in game.
'   - normal play speaks every paragraph once, in order, and finishes before the crawl exits
'   - fast-forward runs scroll and narration CRAWL_FF_X times faster: early, mid and late in
'     each crawl, with the length rotating across crawls (all 9 start x length pairs covered),
'     every frame (during and after fast-forward) is speaking the same
'     paragraph and word as an uninterrupted run at the same point in crawl time, and every
'     paragraph is still spoken once, in order
'   - a pause (#426: held fill, CRAWL_Step% and SPK_Tick skipped) synthesises nothing, then the crawl picks up
'     at the same paragraph and word as an uninterrupted run
'
' Build: ./tools/buildqb tests/crawl_step_test.bas
' Run:   ./tests/crawl_step_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
'$INCLUDE:'../src/sys/failfast.bi'

$EMBED:'assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'assets/gametext.txt':'GAMETEXT'
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'
$EMBED:'assets/sequence.txt':'SEQTXT'

Sub DBG_Print(cstDbgMsg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/audiorate.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'

' sequence.bas dependencies (same stubs as scene_jump_planet_test)
Sub MUS_SetCue(c As String)         : End Sub
Sub CRAWL_Prep(k As String, h As Single) : End Sub
Sub SETTINGS_Save()                 : End Sub
Sub CR_StageClear()                 : End Sub
Sub CR_CashOutWin()                 : End Sub
Sub DOCK_Enter()                    : gameState = GS_DOCK : End Sub
Sub TELEM_SessionEnd()              : End Sub

'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/sys/gametext.bas'
'$INCLUDE:'../src/2d/crawllayout.bas'
'$INCLUDE:'../src/sys/sequence.bas'

Const CST_START_Y = 240 ' scrH, as CRAWL_Prep passes
Const CST_TRIG_Y = 218 ' scrH - CRAWL_LINE_H
Const CST_LEVEL = 2 ' NORMAL
Const CST_MAX_TICKS = 20000
Const CST_TOL = 6 ' ticks of slack when matching the reference (a paragraph can start up to one fast-forward frame late)

Dim Shared stPassed As Integer, stFailed As Integer
Dim Shared cstSaid(0 To 127) As Integer, cstSaidN As Integer, cstSeen As Integer
Dim Shared cstRefPara(0 To CST_MAX_TICKS) As Integer, cstRefWord(0 To CST_MAX_TICKS) As Integer, cstRefN As Long
Dim Shared cstTick As Long ' crawl time in ticks (fast-forward frames count CRAWL_FF_X)
Dim Shared cstLvl As Integer ' narration level handed to the crawl: CST_LEVEL, or 0 for a voice=0 crawl

Sub ST_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        stPassed = stPassed + 1
    Else
        Print "FAIL  " + testName
        stFailed = stFailed + 1
    End If
End Sub

Sub CST_Begin(cbKey As String)
    SPK_Say ""
    cstLvl = CST_LEVEL * SEQ_CrawlVoiced%(cbKey)
    CRAWL_Start GTEXT_Get$(cbKey), cstLvl, CST_START_Y, CST_TRIG_Y
    cstSaidN = 0 : cstSeen = 0 : cstTick = 0
End Sub

' Paragraph being spoken (-1 = silent) and the word within it (-1 = between words).
Function CST_NowPara%
    If SPK_IsPlaying% Then CST_NowPara% = crawlSaidIdx Else CST_NowPara% = -1
End Function
Function CST_NowWord%
    Dim cnwW As Integer
    CST_NowWord% = -1
    If SPK_IsPlaying% = 0 Then Exit Function
    For cnwW = 0 To spkWordCount - 1
        If spkClkIdx >= spkWordStart(cnwW) And spkClkIdx <= spkWordEnd(cnwW) Then CST_NowWord% = cnwW : Exit Function
    Next cnwW
End Function

' One frame: step the crawl, note any paragraph it started, then a frame of speech time.
Sub CST_Frame(cfFF As Integer)
    Dim cfEvt As Integer
    cfEvt = CRAWL_Step%(cfFF, cstLvl)
    If cfFF Then cstTick = cstTick + CRAWL_FF_X Else cstTick = cstTick + 1
    If crawlSaidCount <> cstSeen Then
        cstSaid(cstSaidN) = crawlSaidIdx : cstSaidN = cstSaidN + 1 : cstSeen = crawlSaidCount
    End If
    SPK_Tick
End Sub

' Same exit test as GS_CRAWL_Update.
Function CST_Done%
    CST_Done% = (crawlScroll + crawlLineCount * CRAWL_LINE_H < -20)
End Function

' Is (para, word) what the reference run was saying within CST_TOL ticks of crawl time t?
Function CST_InSync%(cisT As Long)
    Dim cisJ As Long, cisP As Integer, cisW As Integer
    cisP = CST_NowPara% : cisW = CST_NowWord%
    For cisJ = cisT - CST_TOL To cisT + CST_TOL
        If cisJ >= 0 And cisJ < cstRefN Then
            If cstRefPara(cisJ) = cisP And cstRefWord(cisJ) = cisW Then CST_InSync% = -1 : Exit Function
        End If
    Next cisJ
    CST_InSync% = 0
End Function

' True if cstSaid() is exactly 0, 1, .. crawlParaCount-1.
Function CST_AllSaidInOrder%
    Dim cfrI As Integer
    If cstSaidN <> crawlParaCount Then CST_AllSaidInOrder% = 0 : Exit Function
    For cfrI = 0 To cstSaidN - 1
        If cstSaid(cfrI) <> cfrI Then CST_AllSaidInOrder% = 0 : Exit Function
    Next cfrI
    CST_AllSaidInOrder% = -1
End Function


' A voice=0 crawl: scrolls to its exit, at one speed, with nothing ever handed to the speech queue,
' in normal play and with fast-forward held.
Sub CST_CheckUnvoiced(cuKey As String)
    Dim cuPass As Integer, cuN As Long, cuSpoke As Integer, cuVel As Single
    For cuPass = 0 To 1
        CST_Begin cuKey
        cuVel = crawlVel : cuSpoke = 0 : cuN = 0
        Do Until CST_Done% Or cuN > CST_MAX_TICKS
            CST_Frame (cuPass = 1 And cuN > 60 And cuN < 400)
            If SPK_IsPlaying% Or crawlSaidCount <> 0 Then cuSpoke = -1
            cuN = cuN + 1
        Loop
        ST_Assert CST_Done%, cuKey + ": unvoiced crawl reaches its exit" + Mid$(" with fast-forward", 1, 18 * cuPass)
        ST_Assert cuSpoke = 0, cuKey + ": never speaks" + Mid$(" with fast-forward", 1, 18 * cuPass)
        ST_Assert crawlVel = cuVel, cuKey + ": scroll speed constant" + Mid$(" with fast-forward", 1, 18 * cuPass)
    Next cuPass
    CST_Begin cuKey
    ST_Assert cstLvl = 0, cuKey + ": level handed to the crawl is 0 whatever the narration setting"
End Sub

' The pause menu opens mid-speech (#426): the fill runs held (SPK_Advance, 735 samples a frame) while CRAWL_Step% and
' SPK_Tick are skipped. Nothing may be synthesised meanwhile, and after the resume the crawl says the same paragraph and
' word as the uninterrupted reference at every tick, queueing each next paragraph at the same scroll point.
Sub CST_CheckPause(cpKey As String, cpAt As Long, cpFrames As Long)
    Dim cpN As Long, cpF As Long, cpS As Long, cpSynth0 As Long, cpBad As Long, cpLoud As Long, cpVel As Single, cpScroll As Single
    CST_Begin cpKey
    cpBad = 0 : cpN = 0
    Do Until CST_Done% Or cpN > CST_MAX_TICKS
        If cpN = cpAt Then
            cpSynth0 = spkSynthTotal : cpVel = crawlVel : cpScroll = crawlScroll : cpLoud = 0
            spkHold = -1
            For cpF = 1 To cpFrames
                For cpS = 1 To 735 : SPK_Advance : If spkSampleOut <> 0 Then cpLoud = cpLoud + 1
                Next cpS
            Next cpF
            spkHold = 0
            ST_Assert SPK_IsPlaying%, cpKey + ": pause at tick" + Str$(cpAt) + " opens mid-speech"
            ST_Assert spkSynthTotal = cpSynth0, cpKey + ": paused" + Str$(cpFrames) + " frames, no speech synthesised"
            ST_Assert cpLoud = 0, cpKey + ": paused, the fill mixes no speech"
            ST_Assert crawlVel = cpVel And crawlScroll = cpScroll, cpKey + ": the pause leaves the scroll where it was"
        End If
        CST_Frame 0
        If cstTick < cstRefN Then
            If CST_InSync%(cstTick - 1) = 0 Then cpBad = cpBad + 1
        End If
        cpN = cpN + 1
    Loop
    ST_Assert CST_Done%, cpKey + ": crawl with a pause reaches its exit"
    ST_Assert cpBad = 0, cpKey + ": after the pause, same paragraph and word as an uninterrupted run every tick (" + LTrim$(Str$(cpBad)) + " misses)"
    ST_Assert CST_AllSaidInOrder%, cpKey + ": with a pause, every paragraph spoken once, in order"
End Sub

Print "=== crawl_step_test ==="
Print ""

SPK_Init
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")
SEQ_Load _EMBEDDED$("SEQTXT")
SEQ_ListCrawls
ST_Assert seqCrawlCount >= 3, "at least 3 crawls, so the rotating fast-forward lengths cover every start x length pair"

Dim cstC As Integer, cstK As String, cstA As Integer, cstB As Integer, cstF As Long
Dim cstFFAt As Long, cstFFLen As Long, cstBad As Long, cstFirstBad As Long, cstName As String, cstPaused As Integer
For cstC = 0 To seqCrawlCount - 1
    cstK = seqCrawlKey$(cstC)
    Print "--- " + cstK + " ---"
    If SEQ_CrawlVoiced%(cstK) = 0 Then CST_CheckUnvoiced cstK : Print "" : _Continue

    ' reference: uninterrupted play, recording what is being said each tick
    CST_Begin cstK
    cstRefN = 0
    Do Until CST_Done% Or cstRefN >= CST_MAX_TICKS
        CST_Frame 0
        cstRefPara(cstRefN) = CST_NowPara% : cstRefWord(cstRefN) = CST_NowWord%
        cstRefN = cstRefN + 1
    Loop
    ST_Assert CST_Done%, cstK + ": crawl reaches its exit"
    ST_Assert CST_AllSaidInOrder%, cstK + ": every paragraph spoken once, in order"
    ST_Assert SPK_IsPlaying% = 0, cstK + ": last paragraph finished before the crawl exits"
    If cstPaused = 0 Then CST_CheckPause cstK, cstRefN \ 3, 200 : cstPaused = -1

    ' fast-forward early, mid and late in the crawl. The length (15/60/135 frames) rotates
    ' crawl to crawl, so every start x length pair is covered across any 3 consecutive
    ' crawls at a third of the cost of all 9 per crawl (this test dominated suite time, #239)
    For cstA = 1 To 3
        cstB = ((cstA + cstC) Mod 3) + 1
        cstFFAt = cstRefN * cstA \ 5 : cstFFLen = 15 * cstB * cstB
        CST_Begin cstK
        cstBad = 0 : cstFirstBad = -1 : cstF = 0
        Do Until CST_Done% Or cstF > CST_MAX_TICKS
            CST_Frame (cstTick >= cstFFAt And cstTick < cstFFAt + cstFFLen * CRAWL_FF_X)
            If cstTick < cstRefN Then
                If CST_InSync%(cstTick - 1) = 0 Then
                    cstBad = cstBad + 1
                    If cstFirstBad < 0 Then cstFirstBad = cstTick
                End If
            End If
            cstF = cstF + 1
        Loop
        cstName = cstK + ": FF at tick" + Str$(cstFFAt) + " for" + Str$(cstFFLen) + " frames"
        ST_Assert cstBad = 0, cstName + ": in sync with normal play every frame" + Mid$(" (first miss at tick" + Str$(cstFirstBad) + ")", 1, 40 * -(cstBad > 0))
        ST_Assert CST_AllSaidInOrder%, cstName + ": every paragraph spoken once, in order"
        If crawlFFActive = 0 Then ST_Assert spkTimeScale = 1, cstName + ": speech back to normal speed after release"
    Next cstA
    Print ""
Next cstC

Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
