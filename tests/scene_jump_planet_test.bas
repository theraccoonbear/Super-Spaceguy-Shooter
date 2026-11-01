' scene_jump_planet_test.bas -- verify --scene playingN arrives at planet N, and --scene dockN
' opens the dock after stage N and then plays stage N+1 (#268)
'
' Regression: playing4 showed planet1 (Caldorinthia) instead of planet4 (Xeromith).
' This test simulates the exact sss.bas CLI flow: GAME_ResetState + levelNum=N-1 +
' SEQ_JumpToScene -> SEQ_Advance -> ARRIVE, then directly asserts planetCurrent = N.
'
' Build: from repo root:
'   ./tools/buildqb tests/scene_jump_planet_test.bas
' Run:   builds/scene_jump_planet_test   (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/sequence.txt':'SEQTXT'

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
Dim Shared bossAttackList$(0 To 7)
Dim Shared bossAttackCnt     As Integer
Dim Shared bossSeekStr     As Single
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
Sub SPK_Say(s As String)            : End Sub
Function GTEXT_Get$(k As String)    : GTEXT_Get$ = "" : End Function
Sub DBG_Print(s As String)          : End Sub
Sub TELEM_SessionEnd()              : End Sub

' ── real sequencer ───────────────────────────────────────────────────────────
Dim Shared tutorialRun As Integer   ' shared by sequence.bas / telemetry.bas / player.bas (dims.bas)
'$INCLUDE:'../src/sys/sequence.bas'

' ── test helpers ─────────────────────────────────────────────────────────────
Dim Shared stPassed As Integer, stFailed As Integer

Sub ST_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        stPassed = stPassed + 1
    Else
        Print "FAIL  " + testName
        stFailed = stFailed + 1
    End If
End Sub

' Simulate the exact sss.bas --scene playingN CLI flow, advancing until ARRIVE.
' Returns -1 on success (ARRIVE reached), 0 if jump failed or ARRIVE not found.
Function SimPlayingN%(spN As Integer)
    ' Mirror GAME_ResetState
    gameState    = GS_TITLE
    score        = 0 : highScore = 0 : stageKillTarget = 0
    levelNum     = 0 : levelType = 0 : bltActive = 0
    settingNerf  = 0 : diffTime = 0 : diffScale = 0
    planetCurrent = PLANET_COUNT : planetNameIdx = PLANET_COUNT
    planetTimer  = 0 : boss.warnTimer = 0 : tt = 0
    SEQ_Load _EMBEDDED$("SEQTXT")

    ' Mirror sss.bas CLI for --scene playingN
    levelNum = spN - 1
    If levelNum < 0 Then levelNum = 0
    If SEQ_JumpToScene("playing" + LTrim$(Str$(spN))) < 0 Then SimPlayingN% = 0 : Exit Function

    ' Advance through PLAY entries until ARRIVE fires (sets GS_PLANET).
    ' 5 steps covers the longest path: combat -> boss -> ARRIVE.
    Dim spI As Integer
    For spI = 1 To 5
        SEQ_Advance
        If gameState = GS_PLANET Then SimPlayingN% = -1 : Exit Function
    Next spI
    SimPlayingN% = 0
End Function

' ─────────────────────────────────────────────────────────────────────────────
Print "=== scene_jump_planet_test ==="
Print ""

Dim scN As Integer
For scN = 1 To PLANET_COUNT
    Dim scLabel As String : scLabel = "--scene playing" + LTrim$(Str$(scN))
    Dim scOk As Integer : scOk = SimPlayingN%(scN)
    ST_Assert scOk <> 0, scLabel + " reached ARRIVE"
    ST_Assert planetCurrent = scN, scLabel + " planetCurrent=" + LTrim$(Str$(scN))
    ST_Assert planetNameIdx = scN, scLabel + " planetNameIdx=" + LTrim$(Str$(scN))
    Print ""
Next scN

' ── --scene crawl:<key> and the named-crawl list ─────────────────────────────
Print "--- named crawls ---"
Dim scCI As Integer, scAt As Integer, scSeqCrawls As Integer
SEQ_Load _EMBEDDED$("SEQTXT")
SEQ_ListCrawls
For scCI = 0 To seqCount - 1
    If seqKind(scCI) = SEQ_CRAWL Then scSeqCrawls = scSeqCrawls + 1
Next scCI
ST_Assert seqCrawlCount = scSeqCrawls + 2, "list = every sequence CRAWL task + death_final + stranded_final (" + LTrim$(Str$(seqCrawlCount)) + ")"
ST_Assert seqCrawlKey$(0) = "intro" And seqCrawlKey$(seqCrawlCount - 3) = "outro", "sequence crawls listed in play order (intro .. outro)"
ST_Assert seqCrawlKey$(seqCrawlCount - 2) = SEQ_CRAWL_DEATH And seqCrawlAt(seqCrawlCount - 2) = -1, "death_final listed as code-started"
ST_Assert seqCrawlKey$(seqCrawlCount - 1) = SEQ_CRAWL_STRANDED And seqCrawlAt(seqCrawlCount - 1) = -1, "stranded_final listed as code-started (#277)"

scAt = SEQ_JumpToScene("crawl:stage3")
ST_Assert scAt >= 0 And seqKind(scAt) = SEQ_CRAWL And SEQ_GetKV$(seqSval$(scAt), "txt") = "stage3", "crawl:stage3 lands on the stage3 CRAWL task"
ST_Assert seqIdx = scAt - 1 And seqJumpCrawl$ = "", "crawl:stage3 resumes the sequence (seqIdx before it)"
ST_Assert SEQ_JumpToScene("crawl3") = scAt, "crawl3 alias reaches the same task"
scAt = SEQ_JumpToScene("crawl:outro")
ST_Assert scAt >= 0 And seqLabel$(scAt) = "outro", "crawl:outro lands on the outro crawl"
scAt = SEQ_JumpToScene("crawl:death_final")
ST_Assert seqJumpCrawl$ = SEQ_CRAWL_DEATH, "crawl:death_final is played directly"
ST_Assert scAt >= 0 And seqKind(scAt) = SEQ_TITLE And seqIdx = scAt - 1, "crawl:death_final then continues at the title"
ST_Assert SEQ_JumpToScene("crawl:nope") < 0 And InStr(seqLastError, "nope") > 0, "unknown crawl: clear error"
ST_Assert SEQ_JumpToScene("crawl:Stage3") >= 0, "crawl:<key> is case-insensitive"
Print ""


' ── --scene dockN: the dock after stage N, then on to stage N+1 (#268) ───────
' Mirrors sss.bas: GAME_ResetState, levelNum = N, planetCurrent = N, jump, advance.
Print "--- --scene dockN ---"
Dim sdN As Integer, sdAt As Integer
For sdN = 1 To 5
    gameState = GS_TITLE : levelNum = sdN : planetCurrent = sdN : planetNameIdx = sdN
    SEQ_Load _EMBEDDED$("SEQTXT")
    sdAt = SEQ_JumpToScene("dock" + LTrim$(Str$(sdN)))
    ST_Assert sdAt >= 0 And seqKind(sdAt) = SEQ_DOCK And seqLabel$(sdAt) = "level" + LTrim$(Str$(sdN)), "dock" + LTrim$(Str$(sdN)) + " lands on the level" + LTrim$(Str$(sdN)) + " DOCK task"
    SEQ_Advance
    ST_Assert gameState = 15 And seqIdx = sdAt, "dock" + LTrim$(Str$(sdN)) + " opens the dock (GS_DOCK)"
    SEQ_Advance
    ST_Assert gameState = GS_CRAWL And seqLabel$(seqIdx) = "level" + LTrim$(Str$(sdN + 1)), "leaving dock" + LTrim$(Str$(sdN)) + " goes to the stage " + LTrim$(Str$(sdN + 1)) + " crawl"
    SEQ_Advance
    ST_Assert gameState = GS_PLAYING And levelNum = sdN + 1, "then stage " + LTrim$(Str$(sdN + 1)) + " plays (levelNum=" + LTrim$(Str$(levelNum)) + ")"
Next sdN
SEQ_Load _EMBEDDED$("SEQTXT")
ST_Assert SEQ_JumpToScene("dock6") < 0 And InStr(seqLastError, "no DOCK") > 0, "dock6: error, no dock after the last stage"
ST_Assert SEQ_JumpToScene("dock7") < 0 And InStr(seqLastError, "level7") > 0, "dock7: error names the missing label"
ST_Assert SEQ_JumpToScene("dock0") < 0, "dock0: error"
Print ""

' ── every scene --help lists is one --scene accepts (#334) ───────────────────
' Mirrors CLI_Parse (SEQ_SceneType$ + SEQ_SceneTypeOk%) and sss.bas (SEQ_JumpToScene
' for everything but consent/username, which sss.bas starts itself).
Print "--- --help scene list vs --scene ---"
Dim slList As String, slLine As String, slPos As Integer, slName As String
Dim slType As String, slCount As Integer, slSawEmp As Integer
SEQ_Load _EMBEDDED$("SEQTXT")
slList = SEQ_SceneList$
Do While slList <> ""
    slPos = InStr(slList, Chr$(10))
    slLine = LTrim$(Left$(slList, slPos - 1))
    slList = Mid$(slList, slPos + 1)
    If InStr(slLine, " ") > 0 Then slLine = Left$(slLine, InStr(slLine, " ") - 1)
    ' crawl[0-6] -> crawl0, dock[1,2] -> dock1: the first name each entry stands for
    slName = slLine
    slPos = InStr(slLine, "[")
    If slPos > 0 Then
        slName = Left$(slLine, slPos - 1) + Mid$(slLine, slPos + 1)
        slPos = InStr(slPos, slName, "-")
        If slPos = 0 Then slPos = InStr(slName, ",")
        If slPos = 0 Then slPos = InStr(slName, "]")
        slName = Left$(slName, slPos - 1)
    End If
    slType = SEQ_SceneType$(slName)
    slCount = slCount + 1
    If slName = "emperor" Then slSawEmp = -1
    ST_Assert SEQ_SceneTypeOk%(slType), "--help lists '" + slLine + "': CLI accepts type '" + slType + "'"
    If slType <> "consent" And slType <> "username" Then
        ST_Assert SEQ_JumpToScene(slName) >= 0, "--help lists '" + slLine + "': --scene " + slName + " resolves"
    End If
Loop
ST_Assert slCount > 0, "--help scene list is not empty"
ST_Assert slSawEmp, "--help lists emperor"
ST_Assert SEQ_SceneTypeOk%(SEQ_SceneType$("Emperor")), "--scene Emperor: type accepted (case-insensitive)"
ST_Assert SEQ_SceneTypeOk%(SEQ_SceneType$("nope")) = 0, "--scene nope: unknown type rejected"
ST_Assert SEQ_SceneTypeOk%(SEQ_SceneType$("42")) = 0, "--scene 42: empty type rejected"

gameState = GS_TITLE
SEQ_Load _EMBEDDED$("SEQTXT")
scAt = SEQ_JumpToScene("emperor")
ST_Assert scAt >= 0 And seqKind(scAt) = SEQ_EMPEROR, "emperor lands on the emperor CARD"
SEQ_Advance
ST_Assert gameState = GS_INTRO And seqIdx = scAt, "--scene emperor opens the emperor card (GS_INTRO)"
SEQ_Advance
ST_Assert seqKind(seqIdx) = SEQ_TITLE, "leaving the emperor card goes to the title"
Print ""
' ─────────────────────────────────────────────────────────────────────────────
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
