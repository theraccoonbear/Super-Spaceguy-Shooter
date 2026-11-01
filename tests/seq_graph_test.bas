' seq_graph_test.bas -- the sequence is a graph of named blocks: static checks and block-to-block flow
'
' Covers:
'   1.  the shipped assets/sequence.txt loads clean and passes SEQ_Validate$ (no overflow, no
'       dangling NEXT, no dead end, no unreachable non-secret block)
'   2.  each failure SEQ_Validate$ must catch, proven on inline data
'   3.  SEQ_Advance and SEQ_NextLeg follow NEXT, not file order; a secret block is entered
'       only by an explicit jump
'
' Build: tools/dev test (the runner builds it)
' Run:   builds/seq_graph_test   (exit 0 = all pass)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/sequence.txt':'SEQTXT'

'  21.  PLAY boss maneuver=: bsmManeuverName set; defaults to "flyover"
'  22.  PLAY boss attack=: bossAttackList$ per boss (cumulative attack pool)
'  23.  stale arrival planetTimer cleared when the next combat/asteroid stage starts (#168)
'  24.  the stage ends on kills, not score; progress follows kills (#312)
'
' Build: from repo root:
'   ./tools/buildqb tests/seq_dispatch_test.bas
' Run:   builds/seq_dispatch_test   (exit 0 = all pass)



' ── game-state constants (must match dims.bas) ──────────────────────────────
Const GS_TITLE     = 0
Const GS_PLAYING   = 1
Const GS_PLANET    = 3
Const GS_INTRO     = 5
Const GS_CRAWL     = 6
Const LEVEL_COMBAT   = 0
Const LEVEL_ASTEROID = 1
Const LEVEL_BOSS     = 2
Const PLANET_COUNT   = 6
Const NERF_FACTOR    = 0.1
Const BOSS_WARN_FRAMES  = 120
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
Dim Shared stLastCue As String
Sub MUS_SetCue(c As String)         : stLastCue = c : End Sub
Sub StarfieldReset(x As Single, y As Single, z As Single) : End Sub
Sub CRAWL_Prep(k As String, h As Single) : End Sub
Sub SETTINGS_Save()                 : End Sub
Sub BELT_Init(w As Single, h As Single) : End Sub
Sub CR_StageClear()                 : End Sub
Sub CR_CashOutWin()                 : End Sub
Sub DOCK_Enter()                    : gameState = 15 : End Sub
Sub SPK_Say(s As String)            : End Sub
Function GTEXT_Get$(k As String)    : GTEXT_Get$ = "" : End Function
Sub DBG_Print(s As String)          : End Sub
Sub TELEM_SessionEnd()              : End Sub

Dim Shared tutorialRun As Integer   ' shared by sequence.bas / telemetry.bas / player.bas (dims.bas)
'$INCLUDE:'../src/sys/sequence.bas'

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

Function SG_Has%(sghText As String, sghPart As String)
    SG_Has% = (InStr(sghText, sghPart) > 0)
End Function

Dim Shared sgNL As String
sgNL = Chr$(10)

Print "=== seq_graph_test ==="
Print ""
Dim sgP As String, sgData As String, sgI As Integer, sgR As Integer

Print "--- 1. the shipped sequence.txt ---"
SEQ_Load _EMBEDDED$("SEQTXT")
ST_Assert seqLoadErr = "",                                "1.01  loads with no error"
ST_Assert seqCount < SEQ_MAX,                             "1.02  task table has headroom (" + LTrim$(Str$(seqCount)) + " of" + Str$(SEQ_MAX) + ")"
ST_Assert seqBlkCount < SEQ_BLK_MAX,                      "1.03  block table has headroom (" + LTrim$(Str$(seqBlkCount)) + " of" + Str$(SEQ_BLK_MAX) + ")"
sgP = SEQ_Validate$
If sgP <> "" Then Print sgP
ST_Assert sgP = "",                                       "1.04  no dangling next, dead end or unreachable block"
ST_Assert seqBlkNext$(SEQ_FindBlock%("outro")) = "end",   "1.05  the outro is the deliberate terminal"
ST_Assert seqCount = 33,                                  "1.06  NEXT adds no task (33 tasks: the 31 before plus the tutorial block's 2)"

Print "--- 2. failures are detected ---"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT b" + sgNL + "b:" + sgNL + "    CRAWL txt=x" + sgNL + "    NEXT end" + sgNL
ST_Assert SEQ_Validate$ = "" And seqCount = 2,            "2.01  a sound two-block graph passes; NEXT adds no task"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT zzz" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "dangling next"),        "2.02  dangling NEXT is reported"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT b" + sgNL + "b:" + sgNL + "    CRAWL txt=x" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "dead end"),             "2.03  a block with no NEXT is a dead end"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT end" + sgNL + "orphan:" + sgNL + "    CRAWL txt=x" + sgNL + "    NEXT end" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "unreachable: block 'orphan'"), "2.04  an unreachable non-secret block is reported"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT end" + sgNL + "orphan: secret" + sgNL + "    CRAWL txt=x" + sgNL + "    NEXT end" + sgNL
ST_Assert SEQ_Validate$ = "",                             "2.05  the same block marked secret passes"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT end" + sgNL + "orphan: secret" + sgNL + "    CRAWL txt=x" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "dead end"),             "2.06  a secret block still needs a NEXT"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT end" + sgNL + "orphan: secret" + sgNL + "    CRAWL txt=x" + sgNL + "    NEXT nowhere" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "dangling next"),        "2.07  a secret block still needs a valid NEXT"
SEQ_Load "a:" + sgNL + "    NEXT end" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "has no tasks"),         "2.08  a block with no tasks is reported"
SEQ_Load "    TITLE" + sgNL + "a:" + sgNL + "    TITLE" + sgNL + "    NEXT end" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "before any block"),     "2.09  a task outside any block is reported"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT end" + sgNL + "a:" + sgNL + "    TITLE" + sgNL + "    NEXT end" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "duplicate block"),      "2.10  a duplicate block name is reported"
SEQ_Load "a: nxt=end" + sgNL + "    TITLE" + sgNL + "    NEXT end" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "unknown header field"), "2.11  a misspelled header field is reported"
SEQ_Load "a:" + sgNL + "    TELEPORT" + sgNL + "    NEXT end" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "unknown task type"),    "2.12  an unknown task type is reported"
sgData = "a:" + sgNL
For sgI = 1 To SEQ_MAX + 1
    sgData = sgData + "    ARRIVE" + sgNL
Next sgI
SEQ_Load sgData + "    NEXT end" + sgNL
ST_Assert seqCount = SEQ_MAX And SG_Has%(SEQ_Validate$, "SEQ_MAX"), "2.13  task overflow is reported, not silently dropped"
sgData = ""
For sgI = 0 To SEQ_BLK_MAX
    sgData = sgData + "b" + LTrim$(Str$(sgI)) + ":" + sgNL + "    ARRIVE" + sgNL + "    NEXT end" + sgNL
Next sgI
SEQ_Load sgData
ST_Assert SG_Has%(SEQ_Validate$, "SEQ_BLK_MAX"),          "2.14  block overflow is reported"
SEQ_Load "a: next=end" + sgNL + "    TITLE" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "next= on a header"),    "2.15  the old header next= is a load error"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT end" + sgNL + "    ARRIVE" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "task after NEXT"),      "2.16  a task after NEXT is reported"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT end" + sgNL + "    NEXT end" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "second NEXT"),          "2.17  a second NEXT is reported"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    NEXT" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "NEXT with no target"),  "2.18  a NEXT with no target is reported"
SEQ_Load "    NEXT end" + sgNL
ST_Assert SG_Has%(SEQ_Validate$, "NEXT before any block"), "2.19  a NEXT outside any block is reported"
SEQ_Load "a:" + sgNL + "    TITLE" + sgNL + "    next level:2" + sgNL + "level2:" + sgNL + "    CRAWL txt=x" + sgNL + "    NEXT end" + sgNL
ST_Assert SEQ_Validate$ = "",                             "2.20  NEXT is case-insensitive and level:2 names level2"

Print "--- 3. flow follows NEXT ---"
' File order is deliberately not flow order: a -> c -> b; s is secret.
SEQ_Load "a:" + sgNL + "    CRAWL txt=one mus=m1" + sgNL + "    ARRIVE" + sgNL + "    NEXT c" + sgNL + _
         "b:" + sgNL + "    CRAWL txt=three" + sgNL + "    NEXT end" + sgNL + _
         "s: secret" + sgNL + "    CRAWL txt=hidden" + sgNL + "    NEXT b" + sgNL + _
         "c:" + sgNL + "    DOCK" + sgNL + "    PLAY type=combat mus=game trigger=7" + sgNL + _
         "    PLAY type=boss secs=9" + sgNL + "    ARRIVE" + sgNL + "    NEXT b" + sgNL
ST_Assert SEQ_Validate$ = "",                             "3.01  the test graph is valid"
gameState = GS_TITLE
SEQ_Advance
ST_Assert seqIdx = 0 And gameState = GS_CRAWL,            "3.02  starts at the first block"
SEQ_Advance
ST_Assert seqIdx = 1 And gameState = GS_PLANET,           "3.03  tasks in a block run in order"
SEQ_Advance
ST_Assert seqLabel$(seqIdx) = "c" And seqKind(seqIdx) = SEQ_DOCK, "3.04  a's NEXT (c) is entered, not the block after it in the file"
Dim sgK As Long, sgS As Single, sgB As Integer, sgA As Integer
SEQ_NextLeg sgK, sgS, sgB, sgA
ST_Assert sgK = 7 And sgS = 9 And sgB = 0 And sgA = 0,    "3.05  NextLeg sums the PLAYs up to the ARRIVE"
SEQ_Advance : SEQ_Advance : SEQ_Advance
ST_Assert seqKind(seqIdx) = SEQ_ARRIVE,                   "3.06  c runs to its ARRIVE"
SEQ_Advance
ST_Assert seqLabel$(seqIdx) = "b" And gameState = GS_CRAWL, "3.07  c's NEXT (b) is entered after c"
seqRunActive = -1
SEQ_Advance
ST_Assert gameState = GS_TITLE And seqRunActive = 0,      "3.08  NEXT end after the last task ends the run and shows the title"
sgR = SEQ_JumpToScene("crawl:hidden")
ST_Assert sgR = 3 And seqLabel$(sgR) = "s",               "3.09  an explicit jump reaches the secret block"
SEQ_Advance
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,            "3.10  the jump lands on the secret block's first task"
SEQ_Advance
ST_Assert seqLabel$(seqIdx) = "b",                        "3.11  the secret block continues through its NEXT"

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
