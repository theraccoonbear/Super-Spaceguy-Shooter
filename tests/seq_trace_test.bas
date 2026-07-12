' seq_trace_test.bas — headless state-machine tests for the game sequencer
'
' Scenario coverage:
'   1. Normal boot: lead-in → prologue → emperor → title (seqIdx ladder)
'   2. GAME_NewGame from title position advances to chapter-1 crawl
'   3. BUG reproduction: ESC at emperor without SEQ_RewindToTitle → NewGame restarts prologue
'   4. FIX verification: SEQ_RewindToTitle before title → NewGame goes to chapter 1
'   5. FFWD+ESC path: skip prologue → emperor → SPACE → title → NewGame → chapter 1
'   6. SEQ_RewindToTitle is idempotent when called from title position
'   7. End-of-game title also transitions away (not stuck at final title)
'
' Build: from qb64pe install dir:
'   ./qb64pe -x <repo>/tests/seq_trace_test.bas -o <repo>/tests/seq_trace_test
' Run:   ./tests/seq_trace_test     (exit code 0 = all pass, 1 = any fail)

$CONSOLE:ONLY

' ── game-state constants (must match sss.bas) ───────────────────────────────
Const GS_TITLE     = 0
Const GS_PLAYING   = 1
Const GS_INTRO     = 5
Const GS_CRAWL     = 6
Const GS_LEADIN    = 9
Const CAM_OFFSET_X = 6.5
Const CAM_OFFSET_Y = 2.0

' ── shared vars referenced by sequence.bas ──────────────────────────────────
Dim Shared gameState  As Integer
Dim Shared score      As Long
Dim Shared highScore  As Long
Dim Shared stageScore As Long
Dim Shared scrH       As Single
Dim introTimer        As Integer   ' module-scope in sss.bas; not Shared

' ── stubs: silence all audio / render side-effects ──────────────────────────
Sub MUS_SetCue(musSCn$)
End Sub

Sub StarfieldReset(srX As Single, srY As Single, srZ As Single)
End Sub

Sub CRAWL_Prep(cpKey As String, cpStartY As Single)
End Sub

Sub SETTINGS_Save()
End Sub

' ── real sequencer logic ─────────────────────────────────────────────────────
'$INCLUDE:'../src/sequence.bas'

' ── test helpers ────────────────────────────────────────────────────────────
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

' Mirrors the sequence-decision branch of GAME_NewGame without GAME_ResetState.
' If GAME_NewGame's conditional changes, update this to match.
Sub ST_NewGame()
    If seqIdx >= 0 And seqIdx < seqCount And seqKind(seqIdx) = SEQ_TITLE Then
        SEQ_Advance
    Else
        SEQ_Init
        SEQ_Advance
    End If
End Sub

' ── test scenarios ───────────────────────────────────────────────────────────

Print "=== seq_trace_test ==="
Print ""

' 1. Normal boot: each SEQ_Advance lands on the expected scene
Print "--- scenario 1: normal boot flow ---"
SEQ_Init
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
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,  "2   NewGame@title → chapter-1 crawl (seqIdx=3)"

' 3. BUG reproduction: broken ESC-at-emperor (seqIdx left at 1) → NewGame restarts prologue
Print ""
Print "--- scenario 3: ESC-at-emperor BUG reproduction ---"
SEQ_Init
SEQ_Advance : SEQ_Advance              ' seqIdx=1, emperor
gameState = GS_TITLE                   ' old broken handler: only changes gameState
ST_Assert seqIdx = 1,                                        "3a  seqIdx stays at 1 after broken ESC"
ST_NewGame
ST_Assert seqIdx = 0 And gameState = GS_CRAWL,              "3b  NewGame restarts prologue (the loop)"

' 4. FIX verification: SEQ_RewindToTitle before title → NewGame goes to chapter 1
Print ""
Print "--- scenario 4: ESC-at-emperor FIX verification ---"
SEQ_Init
SEQ_Advance : SEQ_Advance              ' seqIdx=1, emperor
SEQ_RewindToTitle                      ' fix applied in sss.bas GS_INTRO ESC handler
gameState = GS_TITLE
ST_Assert seqIdx = 2 And seqKind(seqIdx) = SEQ_TITLE,       "4a  seqIdx=2 after SEQ_RewindToTitle"
ST_NewGame
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,              "4b  NewGame → chapter-1 crawl (seqIdx=3)"

' 5. FFWD+ESC path: skip prologue → SPACE at emperor → title → NewGame → chapter 1
Print ""
Print "--- scenario 5: FFWD+ESC then normal emperor → title → NewGame ---"
SEQ_Init
SEQ_Advance                            ' prologue
SEQ_Advance                            ' FFWD+ESC fires SEQ_Advance → emperor
ST_Assert seqIdx = 1 And gameState = GS_INTRO,               "5a  at emperor after FFWD+ESC (seqIdx=1)"
SEQ_Advance                            ' SPACE at emperor → title
ST_Assert seqIdx = 2 And gameState = GS_TITLE,               "5b  title after SPACE at emperor (seqIdx=2)"
ST_NewGame
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,               "5c  NewGame → chapter-1 crawl (seqIdx=3)"

' 6. SEQ_RewindToTitle is idempotent: calling from title stays at title
Print ""
Print "--- scenario 6: SEQ_RewindToTitle idempotent ---"
SEQ_Init
SEQ_Advance : SEQ_Advance : SEQ_Advance   ' seqIdx=2, title
Dim st6Before As Integer : st6Before = seqIdx
SEQ_RewindToTitle
ST_Assert seqIdx = st6Before And seqKind(seqIdx) = SEQ_TITLE, "6   RewindToTitle from title leaves seqIdx=2"

' 7. End-of-game: outro crawl completes via SEQ_Advance (not GAME_NewGame),
'    parks seqIdx at first SEQ_TITLE so the next GAME_NewGame → chapter 1.
Print ""
Print "--- scenario 7: outro crawl completes → title parked at seqIdx=2 ---"
SEQ_Init
' Jump seqIdx to the outro crawl (one before the final SEQ_TITLE)
Dim st7I As Integer
For st7I = seqCount - 1 To 0 Step -1
    If seqKind(st7I) = SEQ_TITLE Then seqIdx = st7I - 1 : Exit For
Next st7I
ST_Assert seqKind(seqIdx) = SEQ_CRAWL,                       "7a  seqIdx is on the outro crawl"
SEQ_Advance   ' crawl ends → final SEQ_TITLE → SEQ_RewindToTitle → seqIdx=2
ST_Assert seqIdx = 2 And gameState = GS_TITLE,               "7b  outro advance parks at seqIdx=2 (first SEQ_TITLE)"
ST_NewGame
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,               "7c  NewGame from parked title → chapter-1 crawl"

' 8. Beating the game updates and saves highScore via SEQ_TITLE transition
Print ""
Print "--- scenario 8: highScore saved when game is beaten ---"
SEQ_Init
' Jump to the outro crawl (one step before the final SEQ_TITLE)
Dim st8I As Integer
For st8I = seqCount - 1 To 0 Step -1
    If seqKind(st8I) = SEQ_TITLE Then seqIdx = st8I - 1 : Exit For
Next st8I
score = 5000 : highScore = 0
SEQ_Advance   ' outro crawl → final SEQ_TITLE
ST_Assert gameState = GS_TITLE,   "8a  lands on GS_TITLE after outro"
ST_Assert highScore = 5000,        "8b  highScore updated when score beats it"

' new high score only: score below existing highScore must not overwrite
SEQ_Init
For st8I = seqCount - 1 To 0 Step -1
    If seqKind(st8I) = SEQ_TITLE Then seqIdx = st8I - 1 : Exit For
Next st8I
score = 1000 : highScore = 5000
SEQ_Advance
ST_Assert highScore = 5000,        "8c  highScore unchanged when score is lower"

' 9. Prologue never replays after being seen once in a session
Print ""
Print "--- scenario 9: prologue never replays after game beaten ---"
' Simulate full boot: prologue → emperor → title
SEQ_Init
SEQ_Advance   ' prologue crawl (seqIdx=0)
SEQ_Advance   ' emperor (seqIdx=1)
SEQ_Advance   ' first title (seqIdx→2, SEQ_RewindToTitle→2, parked at 2)
ST_Assert seqIdx = 2 And gameState = GS_TITLE,                "9a  parked at first SEQ_TITLE after boot"
' New game → chapter 1
ST_NewGame
ST_Assert seqIdx = 3 And gameState = GS_CRAWL,                "9b  NewGame → chapter-1 crawl"
' Simulate playing through all 6 stages to the final SEQ_TITLE
' Jump seqIdx to just before the final SEQ_TITLE (the outro crawl)
Dim st9I As Integer
For st9I = seqCount - 1 To 0 Step -1
    If seqKind(st9I) = SEQ_TITLE Then seqIdx = st9I - 1 : Exit For
Next st9I
SEQ_Advance   ' outro → final SEQ_TITLE → SEQ_RewindToTitle → seqIdx=2
ST_Assert seqIdx = 2 And gameState = GS_TITLE,                "9c  parked at seqIdx=2 after game beaten"
' New game from title must go to chapter 1, not prologue
ST_NewGame
ST_Assert gameState = GS_CRAWL,                               "9d  NewGame after beating → chapter-1 crawl"
ST_Assert seqIdx = 3,                                         "9e  seqIdx=3, confirming prologue (0) was NOT replayed"

' ── summary ─────────────────────────────────────────────────────────────────
Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
