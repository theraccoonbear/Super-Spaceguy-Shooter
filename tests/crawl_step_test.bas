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
'
' Build: ./tools/buildqb tests/crawl_step_test.bas
' Run:   ./tests/crawl_step_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

Const SAMPLE_RATE = 44100

$EMBED:'assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'assets/gametext.txt':'GAMETEXT'
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'
$EMBED:'assets/sequence.txt':'SEQTXT'

Sub DBG_Print(cstDbgMsg As String) : End Sub

' sequence.bas dependencies (same stubs as scene_jump_planet_test)
' ── game-state constants (must match dims.bas) ──────────────────────────────
Const GS_TITLE           = 0
Const GS_PLAYING         = 1
Const GS_PLANET          = 3
Const GS_INTRO           = 5
Const GS_CRAWL           = 6
Const LEVEL_COMBAT       = 0
Const LEVEL_ASTEROID     = 1
Const LEVEL_BOSS         = 2
Const PLANET_COUNT       = 6
Const NERF_FACTOR        = 0.1
Const BOSS_WARN_FRAMES   = 120
Const DIFF_RAMP_DURATION = 600.0
Const DIFF_STAGE_COUNT   = 6.0
Const ASTFIELD_DURATION      = 120.0
Const CAM_OFFSET_X = 6.5
Const CAM_OFFSET_Y = 2.0

' ── boss state stub ─────────────────────────────────────────────────────────
Type BossState
    warnTimer As Integer
End Type

' ── shared vars referenced by sequence.bas ──────────────────────────────────
Dim Shared gameState    As Integer
Dim Shared score        As Long
Dim Shared highScore    As Long
Dim Shared stageKillTarget As Long
Dim Shared levelNum     As Integer
Dim Shared levelType    As Integer
Dim Shared bltActive    As Integer
Dim Shared settingNerf  As Integer
Dim Shared diffTime     As Single
Dim Shared diffScale    As Single
Dim Shared spawnTimer   As Single
Dim Shared waveStageN   As Integer
Dim Shared bossCfgHp    As Integer
Dim Shared astFieldStart As Single
Dim Shared astDestName  As String
Dim Shared planetCurrent As Integer
Dim Shared planetNameIdx As Integer
Dim Shared planetTimer  As Integer
Dim Shared scrH         As Single
Dim Shared boss         As BossState
Dim Shared tt           As Single
Dim Shared planetNames(1 To PLANET_COUNT) As String
Dim Shared telemExitReason As String
Dim Shared bossMusList$(0 To 7)
Dim Shared bossMusCnt        As Integer
Dim Shared bossSpeechList$(0 To 7)
Dim Shared bossSpeechCnt     As Integer
Dim Shared bossManeuverList$(0 To 7)
Dim Shared bossManeuverCnt   As Integer
Dim Shared bossAttackList$(0 To 7)
Dim Shared bossAttackCnt     As Integer
Dim Shared bossSeekStr     As Single
Dim Shared bsmManeuverName As String
Dim Shared introTimer As Integer
Dim Shared stageKills     As Long
Dim Shared scrW         As Single
Dim Shared planetR       As Single
Dim Shared planetBgR     As Single
Dim Shared planetBgAlpha As Single
Dim Shared astParsecs    As Integer
Type GameObj
    px As Single
End Type
Dim Shared player       As GameObj

' ── stubs ────────────────────────────────────────────────────────────────────
Sub MUS_SetCue(c As String)         : End Sub
Sub StarfieldReset(x As Single, y As Single, z As Single) : End Sub
Sub CRAWL_Prep(k As String, h As Single) : End Sub
Sub SETTINGS_Save()                 : End Sub
Sub BELT_Init(w As Single, h As Single) : End Sub
Sub CR_StageClear()                 : End Sub
Sub CR_CashOutWin()                 : End Sub
Sub DOCK_Enter()                    : gameState = 15 : End Sub   ' GS_DOCK
Sub TELEM_SessionEnd()              : End Sub


'$INCLUDE:'../src/sys/rng.bas'
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
    CRAWL_Start GTEXT_Get$(cbKey), CST_LEVEL, CST_START_Y, CST_TRIG_Y
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
    cfEvt = CRAWL_Step%(cfFF, CST_LEVEL)
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

Print "=== crawl_step_test ==="
Print ""

SPK_Init
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")
SEQ_Load _EMBEDDED$("SEQTXT")
SEQ_ListCrawls
ST_Assert seqCrawlCount >= 3, "at least 3 crawls, so the rotating fast-forward lengths cover every start x length pair"

Dim cstC As Integer, cstK As String, cstA As Integer, cstB As Integer, cstF As Long
Dim cstFFAt As Long, cstFFLen As Long, cstBad As Long, cstFirstBad As Long, cstName As String
For cstC = 0 To seqCrawlCount - 1
    cstK = seqCrawlKey$(cstC)
    Print "--- " + cstK + " ---"

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
