' crawl_step_test.bas — frame-by-frame crawl playback (CRAWL_Step%, src/2d/crawllayout.bas)
'
' Drives CRAWL_Start / CRAWL_Step% for every named crawl with the real speech queue
' advanced 735 samples per 60 fps frame, as the audio fill does in game:
'   - normal play speaks every paragraph once, in order, and finishes before the crawl exits
'   - fast-forward then release mid-crawl resumes at the first paragraph not yet at the
'     trigger line, speaks every paragraph after it, and never speaks one scrolled past
'   - fast-forward past the last paragraph: nothing is spoken after release
'
' Build: ./tools/buildqb tests/crawl_step_test.bas
' Run:   ./tests/crawl_step_test    (exit 0 = pass, exit 1 = any failure)

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
Const PLANET_COUNT       = 6
Const NERF_FACTOR        = 0.1
Const BOSS_WARN_FRAMES   = 120
Const DIFF_RAMP_DURATION = 600.0
Const DIFF_STAGE_COUNT   = 6.0
Const ASTFIELD_DURATION      = 120.0
Const ASTFIELD_FUEL_DRAIN_PT = 0.74
Const ASTFIELD_FUEL_FRAC     = 0.563
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
Dim Shared stageScore   As Long
Dim Shared levelNum     As Integer
Dim Shared levelType    As Integer
Dim Shared bltActive    As Integer
Dim Shared settingNerf  As Integer
Dim Shared diffTime     As Single
Dim Shared diffScale    As Single
Dim Shared astFieldStart As Single
Dim Shared astDestName  As String
Dim Shared fuelLevel    As Single
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
Dim Shared bossSeekStr     As Single
Dim Shared bsmManeuverName As String
Dim introTimer As Integer

' ── stubs ────────────────────────────────────────────────────────────────────
Sub MUS_SetCue(c As String)         : End Sub
Sub StarfieldReset(x As Single, y As Single, z As Single) : End Sub
Sub CRAWL_Prep(k As String, h As Single) : End Sub
Sub SETTINGS_Save()                 : End Sub
Sub BELT_Init(w As Single, h As Single) : End Sub
Sub TELEM_SessionEnd()              : End Sub


'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/sys/gametext.bas'
'$INCLUDE:'../src/2d/crawllayout.bas'
'$INCLUDE:'../src/sys/sequence.bas'

Const CST_START_Y = 240 ' scrH, as CRAWL_Prep passes
Const CST_TRIG_Y = 218 ' scrH - CRAWL_LINE_H
Const CST_SPF = 735 ' audio samples per 60 fps frame (44100 / 60)
Const CST_LEVEL = 2 ' NORMAL
Const CST_MAX_FRAMES = 60 * 600

Dim Shared stPassed As Integer, stFailed As Integer
Dim Shared cstSaid(0 To 127) As Integer, cstSaidN As Integer, cstSeen As Integer

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
    cstSaidN = 0 : cstSeen = 0
End Sub

' One frame: step the crawl, note any paragraph it started speaking, run a frame of audio.
Sub CST_Frame(cfFF As Integer)
    Dim cfEvt As Integer, cfS As Integer
    cfEvt = CRAWL_Step%(cfFF, CST_LEVEL)
    If crawlSaidCount <> cstSeen Then
        cstSaid(cstSaidN) = crawlSaidIdx : cstSaidN = cstSaidN + 1 : cstSeen = crawlSaidCount
    End If
    For cfS = 1 To CST_SPF : SPK_Advance : Next cfS
End Sub

' Same exit test as GS_CRAWL_Update.
Function CST_Done%
    CST_Done% = (crawlScroll + crawlLineCount * CRAWL_LINE_H < -20)
End Function

Sub CST_RunToEnd
    Dim crF As Long
    Do Until CST_Done% Or crF > CST_MAX_FRAMES
        CST_Frame 0
        crF = crF + 1
    Loop
End Sub

' First paragraph whose first line is still below the trigger line.
Function CST_NextUntriggered%
    Dim cnP As Integer
    For cnP = 0 To crawlParaCount - 1
        If crawlScroll + crawlParaLine(cnP) * CRAWL_LINE_H > CST_TRIG_Y Then CST_NextUntriggered% = cnP : Exit Function
    Next cnP
    CST_NextUntriggered% = crawlParaCount
End Function

' True if cstSaid(cfrFrom..) is exactly cfrFirst, cfrFirst+1, .. crawlParaCount-1.
Function CST_SaidRun%(cfrFrom As Integer, cfrFirst As Integer)
    Dim cfrI As Integer
    If cstSaidN - cfrFrom <> crawlParaCount - cfrFirst Then CST_SaidRun% = 0 : Exit Function
    For cfrI = cfrFrom To cstSaidN - 1
        If cstSaid(cfrI) <> cfrFirst + (cfrI - cfrFrom) Then CST_SaidRun% = 0 : Exit Function
    Next cfrI
    CST_SaidRun% = -1
End Function

Print "=== crawl_step_test ==="
Print ""

SPK_Init
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")
SEQ_Load _EMBEDDED$("SEQTXT")
SEQ_ListCrawls

Dim cstC As Integer, cstK As String, cstF As Long, cstMark As Integer, cstR As Integer, cstPend As Integer
For cstC = 0 To seqCrawlCount - 1
    cstK = seqCrawlKey$(cstC)
    Print "--- " + cstK + " ---"

    ' normal play
    CST_Begin cstK
    CST_RunToEnd
    ST_Assert CST_Done%, cstK + ": crawl reaches its exit"
    ST_Assert CST_SaidRun%(0, 0), cstK + ": every paragraph spoken once, in order (" + LTrim$(Str$(cstSaidN)) + " of" + Str$(crawlParaCount) + ")"
    ST_Assert SPK_IsPlaying% = 0, cstK + ": last paragraph finished before the crawl exits"

    ' fast-forward, then release with paragraphs still to come
    If crawlParaCount >= 3 Then
        CST_Begin cstK
        cstF = 0
        Do Until crawlSaidCount >= 2 Or cstF > CST_MAX_FRAMES : CST_Frame 0 : cstF = cstF + 1 : Loop
        For cstF = 1 To 30 : CST_Frame 0 : Next cstF
        ' hold fast-forward until the paragraph that was due next has scrolled past the trigger line
        cstPend = crawlParaIdx : cstF = 0
        Do Until CST_NextUntriggered% > cstPend Or cstF > CST_MAX_FRAMES : CST_Frame -1 : cstF = cstF + 1 : Loop
        cstR = CST_NextUntriggered%
        cstMark = cstSaidN
        CST_RunToEnd
        If cstR < crawlParaCount Then
            ST_Assert cstSaidN > cstMark And cstSaid(cstMark) = cstR, cstK + ": after release, narration resumes at paragraph" + Str$(cstR)
        End If
        ST_Assert CST_SaidRun%(cstMark, cstR), cstK + ": after release, every later paragraph spoken in order, none scrolled past"
    End If

    ' fast-forward until every paragraph has passed the trigger line, then release
    CST_Begin cstK
    For cstF = 1 To 61 : CST_Frame 0 : Next cstF
    cstF = 0
    Do Until CST_NextUntriggered% >= crawlParaCount Or cstF > CST_MAX_FRAMES : CST_Frame -1 : cstF = cstF + 1 : Loop
    cstMark = cstSaidN
    CST_RunToEnd
    ST_Assert cstSaidN = cstMark, cstK + ": released past the last paragraph, nothing re-spoken"
    Print ""
Next cstC

Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
