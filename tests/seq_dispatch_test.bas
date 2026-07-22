' seq_dispatch_test.bas -- dispatch system tests for the block-format sequencer
'
' Covers:
'   1.  Parser: block format -> seqCount, kinds, labels, svals
'   2.  SEQ_GetKV$: key extraction from key=val strings
'   3.  SEQ_JumpToScene: valid paths (crawl0, crawlN, playingN, bossN, title, emperor)
'   4.  SEQ_JumpToScene: invalid paths (boss on no-boss level, missing label, bad type)
'   5.  SEQ_JumpToScene: playing4 matches asteroid PLAY step
'   6.  SEQ_Advance boot flow: CRAWL -> EMPEROR -> TITLE
'   7.  SEQ_Advance level 1 (no boss): combat phase -> ARRIVE direct
'   8.  SEQ_Advance level 3 (boss): combat phase -> boss PLAY -> ARRIVE
'   9.  SEQ_Advance ARRIVE: GS_PLANET, planet indices increment, music cue
'  10.  SEQ_Advance stageScore: trigger * 100 normal; trigger * 100 * NERF_FACTOR nerf
'  11.  SEQ_Advance levelNum: only increments on combat or asteroid PLAY, not boss
'  12.  SEQ_Advance PLAY boss: stageScore=MAX, boss.warnTimer set, gameState stays PLAYING
'  13.  SEQ_Advance PLAY asteroid: levelType=LEVEL_ASTEROID, stageScore=MAX
'  14.  CARD task parses as SEQ_EMPEROR
'  15.  EMPEROR task parses as SEQ_EMPEROR (backward compat)
'  16.  outro: end-of-sequence falls back to title
'  17.  SEQ_RewindToTitle idempotent from title position
'
' Build: from repo root:
'   ./tools/buildqb tests/seq_dispatch_test.bas
' Run:   builds/seq_dispatch_test   (exit 0 = all pass)

$CONSOLE:ONLY
$EMBED:'assets/sequence.txt':'SEQTXT'

' ── game-state constants (must match dims.bas) ──────────────────────────────
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
Dim introTimer As Integer

' ── stubs ────────────────────────────────────────────────────────────────────
Sub MUS_SetCue(c As String)         : End Sub
Sub StarfieldReset(x As Single, y As Single, z As Single) : End Sub
Sub CRAWL_Prep(k As String, h As Single) : End Sub
Sub SETTINGS_Save()                 : End Sub
Sub BELT_Init(w As Single, h As Single) : End Sub
Sub SPK_Say(s As String)            : End Sub
Function GTEXT_Get$(k As String)    : GTEXT_Get$ = "" : End Function
Sub DBG_Print(s As String)          : End Sub
Sub TELEM_SessionEnd()              : End Sub

' ── real sequencer ───────────────────────────────────────────────────────────
'$INCLUDE:'../src/sys/sequence.bas'

' Reset all shared state to defaults before each scenario.
Sub ST_Reset()
    gameState    = GS_TITLE
    score        = 0
    highScore    = 0
    stageScore   = 0
    levelNum     = 0
    levelType    = 0
    bltActive    = 0
    settingNerf  = 0
    diffTime     = 0
    diffScale    = 0
    planetCurrent = PLANET_COUNT   ' mirrors dims.bas initializer
    planetNameIdx = PLANET_COUNT
    planetTimer  = 0
    boss.warnTimer = 0
    tt           = 0
    SEQ_Load _EMBEDDED$("SEQTXT")
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

' ── scenario helpers ─────────────────────────────────────────────────────────

' Jump to a scene by name and then advance once; returns the resulting seqIdx.
Function ST_Jump%(spec As String)
    If SEQ_JumpToScene(spec) < 0 Then ST_Jump% = -1 : Exit Function
    SEQ_Advance
    ST_Jump% = seqIdx
End Function

' Set seqIdx via SEQ_JumpToScene without checking the return value.
Sub ST_GoTo(spec As String)
    Dim stgR As Integer : stgR = SEQ_JumpToScene(spec)
End Sub

' ── sequence indices for the test data (count from 0) ───────────────────────
'  0  CRAWL intro       label=crawl0
'  1  EMPEROR           label=emperor
'  2  TITLE             label=title
'  3  CRAWL stage1      label=level1
'  4  PLAY  combat/10   label=level1
'  5  ARRIVE            label=level1
'  6  CRAWL stage2      label=level2
'  7  PLAY  combat/15   label=level2
'  8  ARRIVE            label=level2
'  9  CRAWL stage3      label=level3
' 10  PLAY  combat/10   label=level3
' 11  PLAY  boss        label=level3
' 12  ARRIVE            label=level3
' 13  CRAWL stage4      label=level4
' 14  PLAY  asteroid    label=level4
' 15  ARRIVE            label=level4
' 16  CRAWL stage5      label=level5
' 17  PLAY  combat/15   label=level5
' 18  PLAY  boss        label=level5
' 19  ARRIVE            label=level5
' 20  CRAWL stage6      label=level6
' 21  PLAY  combat/20   label=level6
' 22  PLAY  boss        label=level6
' 23  ARRIVE            label=level6
' 24  CRAWL outro       label=outro

Print "=== seq_dispatch_test ==="
Print ""

' ────────────────────────────────────────────────────────────────────────────
' 1. Parser: block format -> counts, kinds, labels, svals
' ────────────────────────────────────────────────────────────────────────────
Print "--- 1. parser ---"
ST_Reset
ST_Assert seqCount = 26,                                         "1.01  seqCount=26"
ST_Assert seqKind(0)  = SEQ_CRAWL,                              "1.02  idx 0 is CRAWL"
ST_Assert seqLabel$(0) = "crawl0",                              "1.03  idx 0 label=crawl0"
ST_Assert SEQ_GetKV$(seqSval$(0), "txt") = "intro",             "1.04  idx 0 txt=intro"
ST_Assert seqKind(1)  = SEQ_EMPEROR,                            "1.05  idx 1 (CARD) -> SEQ_EMPEROR"
ST_Assert seqLabel$(1) = "emperor",                             "1.06  idx 1 label=emperor"
ST_Assert seqKind(2)  = SEQ_TITLE,                              "1.07  idx 2 is TITLE"
ST_Assert seqLabel$(2) = "title",                               "1.08  idx 2 label=title"
ST_Assert seqKind(4)  = SEQ_PLAY,                               "1.09  idx 4 is PLAY"
ST_Assert seqLabel$(4) = "level1",                              "1.10  idx 4 label=level1"
ST_Assert SEQ_GetKV$(seqSval$(4), "type") = "combat",           "1.11  idx 4 type=combat"
ST_Assert SEQ_GetKV$(seqSval$(4), "trigger") = "10",            "1.12  idx 4 trigger=10"
ST_Assert seqKind(5)  = SEQ_ARRIVE,                             "1.13  idx 5 is ARRIVE"
ST_Assert seqLabel$(5) = "level1",                              "1.14  idx 5 label=level1"
ST_Assert seqKind(11) = SEQ_PLAY,                               "1.15  idx 11 is PLAY"
ST_Assert SEQ_GetKV$(seqSval$(11), "type") = "boss",            "1.16  idx 11 type=boss"
ST_Assert seqLabel$(11) = "level3",                             "1.17  idx 11 label=level3"
ST_Assert seqKind(14) = SEQ_PLAY,                               "1.18  idx 14 is PLAY"
ST_Assert SEQ_GetKV$(seqSval$(14), "type") = "asteroid",        "1.19  idx 14 type=asteroid"
ST_Assert seqLabel$(14) = "level4",                             "1.20  idx 14 label=level4"
ST_Assert seqKind(24) = SEQ_CRAWL,                              "1.21  idx 24 is CRAWL (outro)"
ST_Assert seqLabel$(24) = "outro",                              "1.22  idx 24 label=outro"
ST_Assert seqKind(25) = SEQ_TITLE,                              "1.23  idx 25 is TITLE (outro)"

' ────────────────────────────────────────────────────────────────────────────
' 2. SEQ_GetKV$
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 2. SEQ_GetKV$ ---"
ST_Assert SEQ_GetKV$("txt=stage1 mus=crawl", "txt") = "stage1", "2.01  txt= extracted"
ST_Assert SEQ_GetKV$("txt=stage1 mus=crawl", "mus") = "crawl",  "2.02  mus= extracted"
ST_Assert SEQ_GetKV$("type=combat mus=game trigger=10", "trigger") = "10", "2.03  trigger= extracted"
ST_Assert SEQ_GetKV$("type=combat mus=game", "boss") = "",       "2.04  missing key -> empty"
ST_Assert SEQ_GetKV$("img=emperor mus=emperor", "img") = "emperor", "2.05  img= extracted"

' ────────────────────────────────────────────────────────────────────────────
' 3. SEQ_JumpToScene: valid paths
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 3. SEQ_JumpToScene valid ---"
ST_Reset
ST_Assert ST_Jump%("crawl0") = 0,    "3.01  crawl0 -> idx 0"
ST_Reset
ST_Assert ST_Jump%("emperor") = 1,   "3.02  emperor -> idx 1"
ST_Reset
ST_Assert ST_Jump%("title") = 2,     "3.03  title -> idx 2"
ST_Reset
ST_Assert ST_Jump%("crawl1") = 3,    "3.04  crawl1 -> idx 3 (level:1 CRAWL)"
ST_Reset
ST_Assert ST_Jump%("playing1") = 4,  "3.05  playing1 -> idx 4 (level:1 combat)"
ST_Reset
ST_Assert ST_Jump%("crawl3") = 9,    "3.06  crawl3 -> idx 9 (level:3 CRAWL)"
ST_Reset
ST_Assert ST_Jump%("playing3") = 10, "3.07  playing3 -> idx 10 (level:3 combat)"
ST_Reset
ST_Assert ST_Jump%("boss3") = 11,    "3.08  boss3 -> idx 11 (level:3 boss PLAY)"
ST_Reset
ST_Assert ST_Jump%("playing4") = 14, "3.09  playing4 -> idx 14 (level:4 asteroid = playing)"
ST_Reset
ST_Assert ST_Jump%("boss5") = 18,    "3.10  boss5 -> idx 18 (level:5 boss PLAY)"
ST_Reset
ST_Assert ST_Jump%("playing6") = 21, "3.11  playing6 -> idx 21 (level:6 combat)"
ST_Reset
ST_Assert ST_Jump%("boss6") = 22,    "3.12  boss6 -> idx 22 (level:6 boss PLAY)"

' ────────────────────────────────────────────────────────────────────────────
' 4. SEQ_JumpToScene: invalid paths
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 4. SEQ_JumpToScene invalid ---"
ST_Reset
Dim st4R As Integer
st4R = SEQ_JumpToScene("boss1")
ST_Assert st4R = -1,                                               "4.01  boss1 -> -1 (no boss in level:1)"
ST_Assert InStr(seqLastError, "level1") > 0,                       "4.02  error names level1"
ST_Assert InStr(LCase$(seqLastError), "boss") > 0,                 "4.03  error mentions boss"
st4R = SEQ_JumpToScene("boss2")
ST_Assert st4R = -1,                                               "4.04  boss2 -> -1 (no boss in level:2)"
st4R = SEQ_JumpToScene("boss4")
ST_Assert st4R = -1,                                               "4.05  boss4 -> -1 (level:4 is asteroid)"
ST_Assert InStr(seqLastError, "level4") > 0,                       "4.06  error names level4"
st4R = SEQ_JumpToScene("boss7")
ST_Assert st4R = -1,                                               "4.07  boss7 -> -1 (label level7 missing)"
ST_Assert InStr(seqLastError, "level7") > 0,                       "4.08  error names missing label"

' ────────────────────────────────────────────────────────────────────────────
' 5. SEQ_Advance: boot flow CRAWL -> EMPEROR -> TITLE
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 5. boot flow ---"
ST_Reset
SEQ_Advance
ST_Assert seqIdx = 0 And gameState = GS_CRAWL,  "5.01  idx 0 -> GS_CRAWL (intro)"
SEQ_Advance
ST_Assert seqIdx = 1 And gameState = GS_INTRO,  "5.02  idx 1 -> GS_INTRO (emperor card)"
SEQ_Advance
ST_Assert seqIdx = 2 And gameState = GS_TITLE,  "5.03  idx 2 -> GS_TITLE"
ST_Assert seqKind(seqIdx) = SEQ_TITLE,          "5.04  parked on SEQ_TITLE node"

' ────────────────────────────────────────────────────────────────────────────
' 6. SEQ_Advance: level 1 -- no boss, score threshold -> ARRIVE
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 6. level 1 (no boss) ---"
ST_Reset
' jump to level:1 combat step
ST_GoTo "playing1"
score = 0 : levelNum = 0
SEQ_Advance   ' process PLAY type=combat
ST_Assert seqIdx = 4,                                    "6.01  at idx 4 after jump"
ST_Assert gameState = GS_PLAYING,                        "6.02  gameState=GS_PLAYING"
ST_Assert levelNum = 1,                                  "6.03  levelNum incremented to 1"
ST_Assert levelType = LEVEL_COMBAT,                      "6.04  levelType=LEVEL_COMBAT"
ST_Assert stageScore = 1000,                             "6.05  stageScore=trigger*100=1000"
' simulate: score threshold reached -> boss.bas calls SEQ_Advance
SEQ_Advance   ' should process ARRIVE (idx 5)
ST_Assert seqIdx = 5,                                    "6.06  at idx 5 (ARRIVE)"
ST_Assert gameState = GS_PLANET,                         "6.07  gameState=GS_PLANET (no boss)"
ST_Assert planetTimer = 1,                               "6.08  planetTimer=1"
ST_Assert planetCurrent = 1,                             "6.09  planetCurrent = levelNum = 1"
ST_Assert planetNameIdx = 1,                             "6.10  planetNameIdx = 1"

' ────────────────────────────────────────────────────────────────────────────
' 7. SEQ_Advance: level 3 -- combat -> boss -> ARRIVE
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 7. level 3 (boss) ---"
ST_Reset
ST_GoTo "playing3"
score = 0 : levelNum = 2   ' simulate levels 1+2 already done
SEQ_Advance   ' PLAY type=combat, level:3
ST_Assert seqIdx = 10,                                   "7.01  at idx 10 (level:3 combat)"
ST_Assert levelNum = 3,                                  "7.02  levelNum=3"
ST_Assert stageScore = 1000,                             "7.03  stageScore=trigger*100=1000"
' score threshold -> SEQ_Advance -> boss PLAY
SEQ_Advance   ' PLAY type=boss
ST_Assert seqIdx = 11,                                   "7.04  at idx 11 (boss PLAY)"
ST_Assert gameState = GS_PLAYING,                        "7.05  gameState stays GS_PLAYING during boss"
ST_Assert stageScore = 2147483647,                       "7.06  stageScore=MAX (combat trigger disabled)"
ST_Assert boss.warnTimer = BOSS_WARN_FRAMES,             "7.07  boss.warnTimer set"
' boss defeated -> SEQ_Advance -> ARRIVE
SEQ_Advance   ' ARRIVE
ST_Assert seqIdx = 12,                                   "7.08  at idx 12 (ARRIVE)"
ST_Assert gameState = GS_PLANET,                         "7.09  gameState=GS_PLANET after boss"

' ────────────────────────────────────────────────────────────────────────────
' 8. stageScore: normal vs nerf
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 8. stageScore computation ---"
' normal mode, level:1 trigger=10 -> 10*100=1000
ST_Reset
score = 500
ST_GoTo "playing1" : levelNum = 0
SEQ_Advance
ST_Assert stageScore = 1500,                             "8.01  normal: stageScore=score+trigger*100"
' normal mode, level:6 trigger=20 -> 20*100=2000
ST_Reset
score = 3000 : levelNum = 5
ST_GoTo "playing6"
SEQ_Advance
ST_Assert stageScore = 5000,                             "8.02  normal level6: score+20*100"
' nerf mode, level:1 trigger=10 -> 10*100*0.1=100
ST_Reset
settingNerf = -1 : score = 0 : levelNum = 0
ST_GoTo "playing1"
SEQ_Advance
ST_Assert stageScore = 100,                              "8.03  nerf: stageScore=trigger*100*NERF_FACTOR"
' nerf mode, level:2 trigger=15 -> 15*100*0.1=150
ST_Reset
settingNerf = -1 : score = 0 : levelNum = 1
ST_GoTo "playing2"
SEQ_Advance
ST_Assert stageScore = 150,                              "8.04  nerf level2: trigger*100*NERF_FACTOR"

' ────────────────────────────────────────────────────────────────────────────
' 9. levelNum: only increments on combat/asteroid PLAY, not boss
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 9. levelNum increments ---"
ST_Reset
levelNum = 0
' advance through level:1 full: crawl -> combat -> arrive -> crawl -> combat
Dim st9j As Integer : st9j = ST_Jump%("playing1")   ' idx=4, levelNum=1
ST_Assert levelNum = 1,                                  "9.01  levelNum=1 after level:1 combat"
SEQ_Advance            ' ARRIVE (seqIdx=5): levelNum unchanged
ST_Assert levelNum = 1,                                  "9.02  levelNum unchanged at ARRIVE"
SEQ_Advance            ' CRAWL stage2 (seqIdx=6): levelNum unchanged
ST_Assert levelNum = 1,                                  "9.03  levelNum unchanged at CRAWL"
SEQ_Advance            ' PLAY combat level:2 (seqIdx=7)
ST_Assert levelNum = 2,                                  "9.04  levelNum=2 after level:2 combat"
SEQ_Advance : SEQ_Advance   ' ARRIVE -> CRAWL stage3
SEQ_Advance            ' PLAY combat level:3 (seqIdx=10)
ST_Assert levelNum = 3,                                  "9.05  levelNum=3 after level:3 combat"
SEQ_Advance            ' PLAY boss level:3 (seqIdx=11): levelNum must NOT increment
ST_Assert levelNum = 3,                                  "9.06  levelNum unchanged on boss PLAY"

' ────────────────────────────────────────────────────────────────────────────
' 10. PLAY type=asteroid
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 10. asteroid PLAY ---"
ST_Reset
levelNum = 3
ST_GoTo "playing4"
SEQ_Advance
ST_Assert seqIdx = 14,                                   "10.01  at idx 14 (asteroid PLAY)"
ST_Assert levelNum = 4,                                  "10.02  levelNum incremented to 4"
ST_Assert levelType = LEVEL_ASTEROID,                    "10.03  levelType=LEVEL_ASTEROID"
ST_Assert stageScore = 2147483647,                       "10.04  stageScore=MAX (no score trigger)"
ST_Assert gameState = GS_PLAYING,                        "10.05  gameState=GS_PLAYING"
' simulate asteroid field completion -> ARRIVE
SEQ_Advance   ' idx 15: ARRIVE
ST_Assert seqIdx = 15,                                   "10.06  at idx 15 (ARRIVE)"
ST_Assert gameState = GS_PLANET,                         "10.07  gameState=GS_PLANET"
ST_Assert planetCurrent = 4,                             "10.08  planetCurrent=levelNum=4 (playing4->planet4)"
ST_Assert planetNameIdx = 4,                             "10.09  planetNameIdx=4"

' ────────────────────────────────────────────────────────────────────────────
' 11. ARRIVE: planet = levelNum (direct mapping, no wraparound)
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 11. ARRIVE planet = levelNum ---"
' level 6: combat -> boss -> ARRIVE
ST_Reset
levelNum = 5
ST_GoTo "playing6"
SEQ_Advance           ' idx 21: combat PLAY, levelNum -> 6
ST_Assert levelNum = 6,                                  "11.01  levelNum=6 after level:6 combat"
SEQ_Advance           ' idx 22: boss PLAY, levelNum unchanged
ST_Assert levelNum = 6,                                  "11.02  levelNum=6 unchanged on boss PLAY"
SEQ_Advance           ' idx 23: ARRIVE
ST_Assert seqIdx = 23,                                   "11.03  at idx 23 (level:6 ARRIVE)"
ST_Assert planetCurrent = 6,                             "11.04  planetCurrent=levelNum=6"
ST_Assert planetNameIdx = 6,                             "11.05  planetNameIdx=6"
' level 3: combat -> boss -> ARRIVE
ST_Reset
levelNum = 2
ST_GoTo "playing3"
SEQ_Advance           ' combat, levelNum -> 3
SEQ_Advance           ' boss
SEQ_Advance           ' ARRIVE
ST_Assert planetCurrent = 3,                             "11.06  planetCurrent=levelNum=3 for level:3"

' ────────────────────────────────────────────────────────────────────────────
' 12. CARD / EMPEROR backward compat
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 12. CARD and EMPEROR backward compat ---"
' CARD img=emperor parses as SEQ_EMPEROR (tested in scenario 1, verify behavior)
ST_Reset
ST_Assert seqKind(1) = SEQ_EMPEROR,                      "12.01  CARD -> SEQ_EMPEROR kind"
ST_Assert SEQ_GetKV$(seqSval$(1), "img") = "emperor",    "12.02  img=emperor stored in sval"
' EMPEROR keyword also parses as SEQ_EMPEROR
Dim st12Data As String
Dim st12NL As String : st12NL = Chr$(10)
st12Data = "compat:" + st12NL + "    EMPEROR mus=emperor" + st12NL
SEQ_Load st12Data
ST_Assert seqCount = 1,                                  "12.03  EMPEROR alias produces 1 entry"
ST_Assert seqKind(0) = SEQ_EMPEROR,                      "12.04  EMPEROR alias -> SEQ_EMPEROR kind"

' ────────────────────────────────────────────────────────────────────────────
' 13. End-of-sequence falls back to title (outro CRAWL -> rewind)
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 13. outro -> title fallback ---"
ST_Reset
seqIdx = 23   ' position just before outro CRAWL (24)
SEQ_Advance   ' advance to outro CRAWL (idx 24)
ST_Assert seqIdx = 24 And gameState = GS_CRAWL,          "13.01  at outro CRAWL"
score = 7777 : highScore = 0
SEQ_Advance   ' outro CRAWL -> SEQ_TITLE (idx 25) -> save highScore -> rewind to first TITLE
ST_Assert gameState = GS_TITLE,                          "13.02  outro TITLE -> GS_TITLE"
ST_Assert seqKind(seqIdx) = SEQ_TITLE,                   "13.03  parked on first SEQ_TITLE node"
ST_Assert highScore = 7777,                              "13.04  highScore saved via outro TITLE"

' ────────────────────────────────────────────────────────────────────────────
' 14. SEQ_RewindToTitle idempotent
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 14. SEQ_RewindToTitle idempotent ---"
ST_Reset
SEQ_Advance : SEQ_Advance : SEQ_Advance   ' -> title (idx=2)
ST_Assert seqIdx = 2 And seqKind(seqIdx) = SEQ_TITLE,   "14.01  at title (idx=2)"
SEQ_RewindToTitle
ST_Assert seqIdx = 2,                                   "14.02  RewindToTitle from title is idempotent"

' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
