' seq_trace_test.bas -- headless state-machine tests for the game sequencer
'
' Scenario coverage:
'   1. Normal boot: prologue -> emperor -> title (seqIdx ladder)
'   2. GAME_NewGame from title position advances to chapter-1 crawl
'   3. BUG reproduction: ESC at emperor without SEQ_RewindToTitle -> NewGame restarts prologue
'   4. FIX verification: SEQ_RewindToTitle before title -> NewGame goes to chapter 1
'   5. FFWD+ESC path: skip prologue -> emperor -> SPACE -> title -> NewGame -> chapter 1
'   6. SEQ_RewindToTitle is idempotent when called from title position
'   7. Outro crawl completes -> highScore saved -> parked at first title
'   8. Beating the game updates highScore
'   9. Prologue never replays after game beaten
'
' Build: from repo root:
'   ./tools/buildqb tests/seq_trace_test.bas
' Run:   builds/seq_trace_test     (exit code 0 = all pass, 1 = any fail)

$CONSOLE:ONLY

' ── game-state constants (must match dims.bas) ───────────────────────────────
Const GS_TITLE     = 0
Const GS_PLAYING   = 1
Const GS_PLANET    = 3
Const GS_INTRO     = 5
Const GS_CRAWL     = 6
Const LEVEL_COMBAT   = 0
Const LEVEL_ASTEROID = 1
Const PLANET_COUNT   = 6
Const NERF_FACTOR    = 0.1
Const BOSS_WARN_FRAMES  = 120
Const DIFF_RAMP_DURATION = 600.0
Const DIFF_STAGE_COUNT   = 6.0
Const ASTFIELD_DURATION      = 120.0
Const ASTFIELD_FUEL_DRAIN_PT = 0.74
Const ASTFIELD_FUEL_FRAC     = 0.50
Const CAM_OFFSET_X = 6.5
Const CAM_OFFSET_Y = 2.0

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
Dim introTimer As Integer

' ── stubs ────────────────────────────────────────────────────────────────────
Sub MUS_SetCue(c As String)         : End Sub
Sub StarfieldReset(x As Single, y As Single, z As Single) : End Sub
Sub CRAWL_Prep(k As String, h As Single) : End Sub
Sub SETTINGS_Save()                 : End Sub
Sub BELT_Init(w As Single, h As Single) : End Sub
Sub SPK_Say(s As String)            : End Sub
Function GTEXT_Get$(k As String)    : GTEXT_Get$ = "" : End Function

' ── real sequencer ───────────────────────────────────────────────────────────
'$INCLUDE:'../src/sequence.bas'

' ── test sequence (matches assets/sequence.txt) ──────────────────────────────
' Sequence indices used by these tests:
'   0  CRAWL intro    (label=crawl0)
'   1  SEQ_EMPEROR    (label=emperor)
'   2  SEQ_TITLE      (label=title)       <- first title; NewGame advances from here
'   3  CRAWL stage1   (label=level1)      <- chapter-1 crawl
'   ...
'  24  CRAWL outro    (label=outro)
'  25  SEQ_TITLE      (label=outro)       <- final title; saves highScore
Dim Shared stSeqData As String
Sub ST_LoadSeq()
    Dim NL As String : NL = Chr$(10)
    stSeqData = "crawl:0"                                        + NL
    stSeqData = stSeqData + "    CRAWL txt=intro mus=crawl"      + NL + NL
    stSeqData = stSeqData + "emperor:"                           + NL
    stSeqData = stSeqData + "    CARD img=emperor mus=emperor"   + NL + NL
    stSeqData = stSeqData + "title:"                             + NL
    stSeqData = stSeqData + "    TITLE mus=title"                + NL + NL
    stSeqData = stSeqData + "level:1"                            + NL
    stSeqData = stSeqData + "    CRAWL txt=stage1 mus=crawl"     + NL
    stSeqData = stSeqData + "    PLAY type=combat mus=game trigger=10" + NL
    stSeqData = stSeqData + "    ARRIVE mus=planet"              + NL + NL
    stSeqData = stSeqData + "level:2"                            + NL
    stSeqData = stSeqData + "    CRAWL txt=stage2 mus=crawl"     + NL
    stSeqData = stSeqData + "    PLAY type=combat mus=game trigger=15" + NL
    stSeqData = stSeqData + "    ARRIVE mus=planet"              + NL + NL
    stSeqData = stSeqData + "level:3"                            + NL
    stSeqData = stSeqData + "    CRAWL txt=stage3 mus=crawl"     + NL
    stSeqData = stSeqData + "    PLAY type=combat mus=game trigger=10" + NL
    stSeqData = stSeqData + "    PLAY type=boss mus=boss"        + NL
    stSeqData = stSeqData + "    ARRIVE mus=planet"              + NL + NL
    stSeqData = stSeqData + "level:4"                            + NL
    stSeqData = stSeqData + "    CRAWL txt=stage4 mus=crawl"     + NL
    stSeqData = stSeqData + "    PLAY type=asteroid mus=asteroid" + NL
    stSeqData = stSeqData + "    ARRIVE mus=planet"              + NL + NL
    stSeqData = stSeqData + "level:5"                            + NL
    stSeqData = stSeqData + "    CRAWL txt=stage5 mus=crawl"     + NL
    stSeqData = stSeqData + "    PLAY type=combat mus=game trigger=15" + NL
    stSeqData = stSeqData + "    PLAY type=boss mus=boss"        + NL
    stSeqData = stSeqData + "    ARRIVE mus=planet"              + NL + NL
    stSeqData = stSeqData + "level:6"                            + NL
    stSeqData = stSeqData + "    CRAWL txt=stage6 mus=crawl"     + NL
    stSeqData = stSeqData + "    PLAY type=combat mus=game trigger=20" + NL
    stSeqData = stSeqData + "    PLAY type=boss mus=boss"        + NL
    stSeqData = stSeqData + "    ARRIVE mus=planet"              + NL + NL
    stSeqData = stSeqData + "outro:"                             + NL
    stSeqData = stSeqData + "    CRAWL txt=outro mus=crawl"      + NL
    stSeqData = stSeqData + "    TITLE mus=title"                + NL
    SEQ_Load stSeqData
End Sub

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

' Mirrors GAME_NewGame's sequence decision without GAME_ResetState.
Sub ST_NewGame()
    If seqIdx >= 0 And seqIdx < seqCount And seqKind(seqIdx) = SEQ_TITLE Then
        SEQ_Advance
    Else
        ST_LoadSeq
        SEQ_Advance
    End If
End Sub

' ── test scenarios ────────────────────────────────────────────────────────────

Print "=== seq_trace_test ==="
Print ""

' 1. Normal boot: each SEQ_Advance lands on the expected scene
Print "--- scenario 1: normal boot flow ---"
ST_LoadSeq
SEQ_Advance
ST_Assert seqIdx = 0 And gameState = GS_CRAWL,  "1a  prologue crawl at seqIdx=0"
SEQ_Advance
ST_Assert seqIdx = 1 And gameState = GS_INTRO,  "1b  emperor at seqIdx=1"
SEQ_Advance
ST_Assert seqIdx = 2 And gameState = GS_TITLE,  "1c  title at seqIdx=2"
ST_Assert seqKind(seqIdx) = SEQ_TITLE,          "1d  seqKind(2) is SEQ_TITLE"

' 2. GAME_NewGame from correct title position advances to chapter-1 crawl
Print ""
Print "--- scenario 2: NewGame from title ---"
ST_NewGame
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,  "2   NewGame@title -> chapter-1 crawl (seqIdx=3)"

' 3. BUG reproduction: broken ESC-at-emperor (seqIdx left at 1) -> NewGame restarts prologue
Print ""
Print "--- scenario 3: ESC-at-emperor BUG reproduction ---"
ST_LoadSeq
SEQ_Advance : SEQ_Advance              ' seqIdx=1, emperor
gameState = GS_TITLE                   ' old broken handler: only changes gameState
ST_Assert seqIdx = 1,                                        "3a  seqIdx stays at 1 after broken ESC"
ST_NewGame
ST_Assert seqIdx = 0 And gameState = GS_CRAWL,              "3b  NewGame restarts prologue (the bug)"

' 4. FIX verification: SEQ_RewindToTitle before title -> NewGame goes to chapter 1
Print ""
Print "--- scenario 4: ESC-at-emperor FIX verification ---"
ST_LoadSeq
SEQ_Advance : SEQ_Advance              ' seqIdx=1, emperor
SEQ_RewindToTitle                      ' fix applied in sss.bas GS_INTRO ESC handler
gameState = GS_TITLE
ST_Assert seqIdx = 2 And seqKind(seqIdx) = SEQ_TITLE,       "4a  seqIdx=2 after SEQ_RewindToTitle"
ST_NewGame
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,              "4b  NewGame -> chapter-1 crawl (seqIdx=3)"

' 5. FFWD+ESC path: skip prologue -> SPACE at emperor -> title -> NewGame -> chapter 1
Print ""
Print "--- scenario 5: FFWD+ESC then normal emperor -> title -> NewGame ---"
ST_LoadSeq
SEQ_Advance                            ' prologue
SEQ_Advance                            ' FFWD+ESC fires SEQ_Advance -> emperor
ST_Assert seqIdx = 1 And gameState = GS_INTRO,               "5a  at emperor after FFWD+ESC (seqIdx=1)"
SEQ_Advance                            ' SPACE at emperor -> title
ST_Assert seqIdx = 2 And gameState = GS_TITLE,               "5b  title after SPACE at emperor (seqIdx=2)"
ST_NewGame
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,               "5c  NewGame -> chapter-1 crawl (seqIdx=3)"

' 6. SEQ_RewindToTitle is idempotent: calling from title stays at title
Print ""
Print "--- scenario 6: SEQ_RewindToTitle idempotent ---"
ST_LoadSeq
SEQ_Advance : SEQ_Advance : SEQ_Advance   ' seqIdx=2, title
Dim st6Before As Integer : st6Before = seqIdx
SEQ_RewindToTitle
ST_Assert seqIdx = st6Before And seqKind(seqIdx) = SEQ_TITLE, "6   RewindToTitle from title leaves seqIdx=2"

' 7. Outro crawl completes -> TITLE step saves highScore and parks at first title
Print ""
Print "--- scenario 7: outro crawl completes -> title parked at seqIdx=2 ---"
ST_LoadSeq
' find the outro CRAWL (one before the final TITLE)
Dim st7I As Integer
For st7I = seqCount - 1 To 0 Step -1
    If seqKind(st7I) = SEQ_TITLE Then seqIdx = st7I - 1 : Exit For
Next st7I
ST_Assert seqKind(seqIdx) = SEQ_CRAWL,                       "7a  seqIdx is on the outro crawl"
SEQ_Advance   ' outro CRAWL -> final SEQ_TITLE -> save highScore -> SEQ_RewindToTitle -> seqIdx=2
ST_Assert seqIdx = 2 And gameState = GS_TITLE,               "7b  parked at seqIdx=2 (first SEQ_TITLE)"
ST_NewGame
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,               "7c  NewGame from parked title -> chapter-1 crawl"

' 8. Beating the game updates and saves highScore via SEQ_TITLE transition
Print ""
Print "--- scenario 8: highScore saved when game is beaten ---"
ST_LoadSeq
Dim st8I As Integer
For st8I = seqCount - 1 To 0 Step -1
    If seqKind(st8I) = SEQ_TITLE Then seqIdx = st8I - 1 : Exit For
Next st8I
score = 5000 : highScore = 0
SEQ_Advance
ST_Assert gameState = GS_TITLE,   "8a  lands on GS_TITLE after outro"
ST_Assert highScore = 5000,        "8b  highScore updated when score beats it"

ST_LoadSeq
For st8I = seqCount - 1 To 0 Step -1
    If seqKind(st8I) = SEQ_TITLE Then seqIdx = st8I - 1 : Exit For
Next st8I
score = 1000 : highScore = 5000
SEQ_Advance
ST_Assert highScore = 5000,        "8c  highScore unchanged when score is lower"

' 9. Prologue never replays after game beaten
Print ""
Print "--- scenario 9: prologue never replays after game beaten ---"
ST_LoadSeq
SEQ_Advance   ' prologue crawl (seqIdx=0)
SEQ_Advance   ' emperor (seqIdx=1)
SEQ_Advance   ' first title (seqIdx->2, SEQ_RewindToTitle->2)
ST_Assert seqIdx = 2 And gameState = GS_TITLE,                "9a  parked at first SEQ_TITLE after boot"
ST_NewGame
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,                "9b  NewGame -> chapter-1 crawl"
Dim st9I As Integer
For st9I = seqCount - 1 To 0 Step -1
    If seqKind(st9I) = SEQ_TITLE Then seqIdx = st9I - 1 : Exit For
Next st9I
SEQ_Advance   ' outro -> final SEQ_TITLE -> SEQ_RewindToTitle -> seqIdx=2
ST_Assert seqIdx = 2 And gameState = GS_TITLE,                "9c  parked at seqIdx=2 after game beaten"
ST_NewGame
ST_Assert gameState = GS_CRAWL,                               "9d  NewGame after beating -> chapter-1 crawl"
ST_Assert seqIdx = 3,                                         "9e  seqIdx=3 (prologue at 0 was NOT replayed)"

' ── summary ──────────────────────────────────────────────────────────────────
Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
