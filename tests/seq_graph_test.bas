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
'$INCLUDE:'../src/sys/failfast.bi'
$EMBED:'assets/sequence.txt':'SEQTXT'

'  22.  PLAY boss attack=: bossAttackList$ per boss (cumulative attack pool)
'  23.  stale arrival planetTimer cleared when the next combat/asteroid stage starts (#168)
'  24.  the stage ends on kills, not score; progress follows kills (#312)
'
' Build: from repo root:
'   ./tools/buildqb tests/seq_dispatch_test.bas
' Run:   builds/seq_dispatch_test   (exit 0 = all pass)



'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'seq_stubs.bi'
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
ST_Assert seqCount = 34,                                  "1.06  NEXT adds no task (34 tasks: the 33 before the credits crawl plus that one)"
ST_Assert SEQ_CrawlVoiced%("credits") = 0,                "1.07  the credits crawl is unvoiced (voice=0)"
ST_Assert SEQ_CrawlVoiced%("outro") = 1 And SEQ_CrawlVoiced%("stage1") = 1 And SEQ_CrawlVoiced%("death_final") = 1, "1.08  other crawls, and code-started ones, stay voiced"
ST_Assert SEQ_GetKV$(seqSval$(seqBlkFirst(SEQ_FindBlock%("outro")) + 1), "txt") = "credits" And seqKind(seqBlkFirst(SEQ_FindBlock%("outro")) + 2) = SEQ_TITLE, "1.09  the credits crawl follows the outro crawl, then the title"
ST_Assert SEQ_CrawlVoiced%("x") = 1, "1.10  an unknown key is voiced"

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
