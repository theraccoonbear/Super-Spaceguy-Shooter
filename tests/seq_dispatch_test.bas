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
'  10.  SEQ_Advance stageKillTarget: trigger kills normal; trigger * NERF_FACTOR (at least 1) nerf
'  11.  SEQ_Advance levelNum: only increments on combat or asteroid PLAY, not boss
'  12.  SEQ_Advance PLAY boss: stageKillTarget=MAX, boss.warnTimer set, gameState stays PLAYING
'  13.  SEQ_Advance PLAY asteroid: levelType=LEVEL_ASTEROID, stageKillTarget=MAX
'  14.  CARD task parses as SEQ_EMPEROR
'  15.  EMPEROR task parses as SEQ_EMPEROR (backward compat)
'  16.  outro: end-of-sequence falls back to title
'  17.  SEQ_RewindToTitle idempotent from title position
'  18.  --scene boss3 regression: gameState=GS_PLAYING after cold-start boss dispatch (#187)
'  19.  PLAY boss mus= CSV: bossMusList$ populated with phase cues
'  20.  PLAY boss seek=: bossSeekStr parsed from sequence.txt
'  21.  PLAY boss maneuver=: bsmManeuverName set; defaults to "flyover"
'  22.  PLAY boss attack=: bossAttackList$ per boss (cumulative attack pool)
'  23.  stale arrival planetTimer cleared when the next combat/asteroid stage starts (#168)
'  24.  the stage ends on kills, not score; progress follows kills (#312)
'
' Build: from repo root:
'   ./tools/buildqb tests/seq_dispatch_test.bas
' Run:   builds/seq_dispatch_test   (exit 0 = all pass)

Option _Explicit
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
Sub DOCK_Enter()                    : gameState = 15 : End Sub   ' GS_DOCK
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
    stageKillTarget = 0
    stageKills   = 0
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
    bossMusCnt      = 0
    bossSpeechCnt   = 0
    bossManeuverCnt = 0
    bossAttackCnt   = 0
    bossSeekStr     = 0
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
'  4  PLAY  combat/12   label=level1
'  5  ARRIVE            label=level1
'  6  DOCK              label=level1
'  7  CRAWL stage2      label=level2
'  8  PLAY  combat/18   label=level2
'  9  ARRIVE            label=level2
' 10  DOCK              label=level2
' 11  CRAWL stage3      label=level3
' 12  PLAY  combat/12   label=level3
' 13  PLAY  boss        label=level3
' 14  ARRIVE            label=level3
' 15  DOCK              label=level3
' 16  CRAWL stage4      label=level4
' 17  PLAY  asteroid    label=level4
' 18  ARRIVE            label=level4
' 19  DOCK              label=level4
' 20  CRAWL stage5      label=level5
' 21  PLAY  combat/18   label=level5
' 22  PLAY  boss        label=level5
' 23  ARRIVE            label=level5
' 24  DOCK              label=level5
' 25  CRAWL stage6      label=level6
' 26  PLAY  combat/24   label=level6
' 27  PLAY  boss        label=level6
' 28  ARRIVE            label=level6   (no DOCK after the last stage)
' 29  CRAWL outro       label=outro

Print "=== seq_dispatch_test ==="
Print ""

' ────────────────────────────────────────────────────────────────────────────
' 1. Parser: block format -> counts, kinds, labels, svals
' ────────────────────────────────────────────────────────────────────────────
Print "--- 1. parser ---"
ST_Reset
ST_Assert seqCount = 31,                                         "1.01  seqCount=31"
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
ST_Assert SEQ_GetKV$(seqSval$(4), "trigger") = "12",            "1.12  idx 4 trigger=12"
ST_Assert seqKind(5)  = SEQ_ARRIVE,                             "1.13  idx 5 is ARRIVE"
ST_Assert seqLabel$(5) = "level1",                              "1.14  idx 5 label=level1"
ST_Assert seqKind(13) = SEQ_PLAY,                               "1.15  idx 13 is PLAY"
ST_Assert SEQ_GetKV$(seqSval$(13), "type") = "boss",            "1.16  idx 13 type=boss"
ST_Assert seqLabel$(13) = "level3",                             "1.17  idx 13 label=level3"
ST_Assert seqKind(17) = SEQ_PLAY,                               "1.18  idx 17 is PLAY"
ST_Assert SEQ_GetKV$(seqSval$(17), "type") = "asteroid",        "1.19  idx 17 type=asteroid"
ST_Assert seqLabel$(17) = "level4",                             "1.20  idx 17 label=level4"
ST_Assert seqKind(29) = SEQ_CRAWL,                              "1.21  idx 29 is CRAWL (outro)"
ST_Assert seqLabel$(29) = "outro",                              "1.22  idx 29 label=outro"
ST_Assert seqKind(30) = SEQ_TITLE,                              "1.23  idx 30 is TITLE (outro)"
ST_Assert seqKind(6) = SEQ_DOCK And seqLabel$(6) = "level1",   "1.24  idx 6 is DOCK (level1, after ARRIVE)"
ST_Assert seqKind(24) = SEQ_DOCK And seqLabel$(24) = "level5", "1.25  idx 24 is DOCK (level5)"
ST_Assert seqKind(28) = SEQ_ARRIVE And seqKind(29) = SEQ_CRAWL, "1.26  no DOCK after the last stage"

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
ST_Assert ST_Jump%("crawl3") = 11,   "3.06  crawl3 -> idx 11 (level:3 CRAWL)"
ST_Reset
ST_Assert ST_Jump%("playing3") = 12, "3.07  playing3 -> idx 12 (level:3 combat)"
ST_Reset
ST_Assert ST_Jump%("boss3") = 13,    "3.08  boss3 -> idx 13 (level:3 boss PLAY)"
ST_Reset
ST_Assert ST_Jump%("playing4") = 17, "3.09  playing4 -> idx 17 (level:4 asteroid = playing)"
ST_Reset
ST_Assert ST_Jump%("boss5") = 22,    "3.10  boss5 -> idx 22 (level:5 boss PLAY)"
ST_Reset
ST_Assert ST_Jump%("playing6") = 26, "3.11  playing6 -> idx 26 (level:6 combat)"
ST_Reset
ST_Assert ST_Jump%("boss6") = 27,    "3.12  boss6 -> idx 27 (level:6 boss PLAY)"
ST_Reset
ST_Assert ST_Jump%("dock1") = 6,    "3.13  dock1 -> idx 6 (level:1 DOCK)"
ST_Assert gameState = 15,            "3.14  dock1 dispatches DOCK_Enter (GS_DOCK)"
ST_Reset
ST_Assert ST_Jump%("dock5") = 24,   "3.15  dock5 -> idx 24"
ST_Reset
ST_Assert SEQ_JumpToScene("dock6") = -1, "3.16  dock6 -> -1 (no dock after the last stage)"

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
' 6. SEQ_Advance: level 1 -- no boss, kill target -> ARRIVE
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
ST_Assert stageKillTarget = 12 And stageKills = 0,      "6.05  stageKillTarget=trigger=12, stageKills reset"
' simulate: kill target reached -> boss.bas calls SEQ_Advance
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
ST_Assert seqIdx = 12,                                   "7.01  at idx 12 (level:3 combat)"
ST_Assert levelNum = 3,                                  "7.02  levelNum=3"
ST_Assert stageKillTarget = 12,                        "7.03  stageKillTarget=trigger=12"
' kill target -> SEQ_Advance -> boss PLAY
SEQ_Advance   ' PLAY type=boss
ST_Assert seqIdx = 13,                                   "7.04  at idx 13 (boss PLAY)"
ST_Assert gameState = GS_PLAYING,                        "7.05  gameState stays GS_PLAYING during boss"
ST_Assert stageKillTarget = 2147483647,                  "7.06  stageKillTarget=MAX (combat trigger disabled)"
ST_Assert boss.warnTimer = BOSS_WARN_FRAMES,             "7.07  boss.warnTimer set"
' boss defeated -> SEQ_Advance -> ARRIVE
SEQ_Advance   ' ARRIVE
ST_Assert seqIdx = 14,                                   "7.08  at idx 14 (ARRIVE)"
ST_Assert gameState = GS_PLANET,                         "7.09  gameState=GS_PLANET after boss"
SEQ_Advance   ' DOCK
ST_Assert seqIdx = 15 And gameState = 15,                "7.10  ARRIVE -> DOCK (idx 15, GS_DOCK)"
ST_Assert stLastCue = "dock",                            "7.10b entering the dock switches to the dock cue"
SEQ_Advance   ' leaving the dock
ST_Assert gameState = GS_CRAWL And seqLabel$(seqIdx) = "level4", "7.11  DOCK -> next chapter crawl"
ST_Assert stLastCue = "crawl",                           "7.11b leaving the dock switches the music to the crawl cue"

' ────────────────────────────────────────────────────────────────────────────
' 8. stageKillTarget: normal vs nerf
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 8. stageKillTarget computation ---"
' normal mode: the target is the trigger, in kills, whatever the score
ST_Reset
score = 500 : stageKills = 7
ST_GoTo "playing1" : levelNum = 0
SEQ_Advance
ST_Assert stageKillTarget = 12 And stageKills = 0,      "8.01  normal: target=trigger=12, score ignored, kills reset"
ST_Reset
score = 3000 : levelNum = 5
ST_GoTo "playing6"
SEQ_Advance
ST_Assert stageKillTarget = 24,                         "8.02  normal level6: target=24"
' nerf mode: trigger * NERF_FACTOR, rounded, at least 1
ST_Reset
settingNerf = -1 : score = 0 : levelNum = 0
ST_GoTo "playing1"
SEQ_Advance
ST_Assert stageKillTarget = 1,                          "8.03  nerf level1: 12 x 0.1 -> 1"
ST_Reset
settingNerf = -1 : score = 0 : levelNum = 1
ST_GoTo "playing2"
SEQ_Advance
ST_Assert stageKillTarget = 2,                          "8.04  nerf level2: 18 x 0.1 -> 2"
ST_Reset
settingNerf = -1 : levelNum = 5
ST_GoTo "playing6"
SEQ_Advance
ST_Assert stageKillTarget = 2,                          "8.05  nerf level6: 24 x 0.1 -> 2"
ST_Reset
settingNerf = -1
SEQ_Load "level:1" + Chr$(10) + "    PLAY type=combat mus=game trigger=3" + Chr$(10)
SEQ_Advance
ST_Assert stageKillTarget = 1,                          "8.06  nerf: 3 x 0.1 rounds to 0, held at 1 kill"

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
SEQ_Advance            ' DOCK (seqIdx=6)
SEQ_Advance            ' CRAWL stage2 (seqIdx=7): levelNum unchanged
ST_Assert levelNum = 1,                                  "9.03  levelNum unchanged at CRAWL"
SEQ_Advance            ' PLAY combat level:2 (seqIdx=8)
ST_Assert levelNum = 2,                                  "9.04  levelNum=2 after level:2 combat"
SEQ_Advance : SEQ_Advance : SEQ_Advance   ' ARRIVE -> DOCK -> CRAWL stage3
SEQ_Advance            ' PLAY combat level:3 (seqIdx=12)
ST_Assert levelNum = 3,                                  "9.05  levelNum=3 after level:3 combat"
SEQ_Advance            ' PLAY boss level:3 (seqIdx=13): levelNum must NOT increment
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
ST_Assert seqIdx = 17,                                   "10.01  at idx 17 (asteroid PLAY)"
ST_Assert levelNum = 4,                                  "10.02  levelNum incremented to 4"
ST_Assert levelType = LEVEL_ASTEROID,                    "10.03  levelType=LEVEL_ASTEROID"
ST_Assert stageKillTarget = 2147483647,                  "10.04  stageKillTarget=MAX (no kill trigger)"
ST_Assert gameState = GS_PLAYING,                        "10.05  gameState=GS_PLAYING"
' simulate asteroid field completion -> ARRIVE
SEQ_Advance   ' idx 18: ARRIVE
ST_Assert seqIdx = 18,                                   "10.06  at idx 18 (ARRIVE)"
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
SEQ_Advance           ' idx 26: combat PLAY, levelNum -> 6
ST_Assert levelNum = 6,                                  "11.01  levelNum=6 after level:6 combat"
SEQ_Advance           ' idx 27: boss PLAY, levelNum unchanged
ST_Assert levelNum = 6,                                  "11.02  levelNum=6 unchanged on boss PLAY"
SEQ_Advance           ' idx 28: ARRIVE
ST_Assert seqIdx = 28,                                   "11.03  at idx 28 (level:6 ARRIVE)"
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
seqIdx = 28   ' position just before outro CRAWL (29)
SEQ_Advance   ' advance to outro CRAWL (idx 29)
ST_Assert seqIdx = 29 And gameState = GS_CRAWL,          "13.01  at outro CRAWL"
score = 7777 : highScore = 0 : seqRunActive = -1   ' a run was played (#331)
SEQ_Advance   ' outro CRAWL -> SEQ_TITLE (idx 30) -> save highScore -> rewind to first TITLE
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
' 15. --scene boss3 regression: gameState must be GS_PLAYING after boss dispatch
'     from a cold start (gameState=GS_TITLE).  Prior to the fix the Case "boss"
'     branch in SEQ_Advance was missing `gameState = GS_PLAYING`, so the game
'     looped on the title screen instead of entering combat.
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 15. --scene boss3 regression (issue #187) ---"
ST_Reset   ' gameState = GS_TITLE, boss.warnTimer = 0
Dim st15R As Integer : st15R = SEQ_JumpToScene("boss3")
ST_Assert st15R = 13,                                    "15.01  boss3 positioned at idx 13"
SEQ_Advance
ST_Assert gameState = GS_PLAYING,                        "15.02  gameState=GS_PLAYING after boss dispatch"
ST_Assert boss.warnTimer = BOSS_WARN_FRAMES,             "15.03  boss.warnTimer set"
ST_Assert stageKillTarget = 2147483647,                  "15.04  stageKillTarget=MAX (combat trigger disabled)"

' ────────────────────────────────────────────────────────────────────────────
' 16. PLAY boss mus= CSV populates phase music tickable
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 16. boss mus= CSV tickable ---"
ST_Reset
ST_GoTo "boss3"
SEQ_Advance   ' dispatch boss PLAY at level:3
ST_Assert bossMusCnt = 3,                        "16.01  bossMusCnt=3 from mus=boss,boss2,boss3"
ST_Assert bossMusList$(0) = "boss",              "16.02  phase 1 cue=boss"
ST_Assert bossMusList$(1) = "boss2",             "16.03  phase 2 cue=boss2"
ST_Assert bossMusList$(2) = "boss3",             "16.04  phase 3 cue=boss3"
ST_Assert bossSpeechCnt = 3,                     "16.05  bossSpeechCnt=3 from speech=,key2,key3"
ST_Assert bossSpeechList$(0) = "",               "16.06  phase 1 speech=empty (boss warning handles it)"
ST_Assert bossSpeechList$(1) = "speech_boss_phase2", "16.07  phase 2 speech key"
ST_Assert bossSpeechList$(2) = "speech_boss_phase3", "16.08  phase 3 speech key"

' ────────────────────────────────────────────────────────────────────────────
' 17. PLAY boss seek= populates bossSeekStr
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 17. boss seek= parsed into bossSeekStr ---"
' level:3 boss has seek=0.015
ST_Reset
ST_GoTo "boss3"
SEQ_Advance
ST_Assert bossSeekStr > 0.014 And bossSeekStr < 0.016, "17.01  level3 boss seek=0.015"
' level:5 boss has seek=0.035
ST_Reset
levelNum = 4
ST_GoTo "boss5"
SEQ_Advance
ST_Assert bossSeekStr > 0.034 And bossSeekStr < 0.036, "17.02  level5 boss seek=0.035"
' level:6 boss has seek=0.055
ST_Reset
levelNum = 5
ST_GoTo "boss6"
SEQ_Advance
ST_Assert bossSeekStr > 0.054 And bossSeekStr < 0.056, "17.03  level6 boss seek=0.055"

' ────────────────────────────────────────────────────────────────────────────
' 18. PLAY boss maneuver= populates bsmManeuverName; defaults to "flyover"
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 18. boss maneuver= parsed into bossManeuverList$ ---"
' level:3 boss has maneuver=boss-x-flight,boss-v-flight,attack-pass (three entries)
ST_Reset
ST_GoTo "boss3"
SEQ_Advance
ST_Assert bossManeuverCnt = 3,                     "18.01  level3 maneuver= -> count=3"
ST_Assert bossManeuverList$(0) = "boss-x-flight",  "18.02  level3 phase1=boss-x-flight"
' level:5 boss has maneuver=boss-x-flight,boss-v-flight,attack-pass (three entries)
ST_Reset
levelNum = 4
ST_GoTo "boss5"
SEQ_Advance
ST_Assert bossManeuverCnt = 3,                     "18.03  level5 maneuver= -> count=3"
ST_Assert bossManeuverList$(0) = "boss-x-flight",  "18.04  level5 phase1=boss-x-flight"
ST_Assert bossManeuverList$(1) = "boss-v-flight",  "18.05  level5 phase2=boss-v-flight"
' level:6 boss has maneuver=boss-x-flight,boss-v-flight,attack-pass (three entries)
ST_Reset
levelNum = 5
ST_GoTo "boss6"
SEQ_Advance
ST_Assert bossManeuverCnt = 3,                     "18.06  level6 maneuver= -> count=3"
ST_Assert bossManeuverList$(0) = "boss-x-flight",  "18.07  level6 phase1=boss-x-flight"
ST_Assert bossManeuverList$(1) = "boss-v-flight",  "18.08  level6 phase2=boss-v-flight"
ST_Assert bossManeuverList$(2) = "attack-pass",    "18.09  level6 phase3=attack-pass"
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 19. boss attack= parsed into bossAttackList$ (cumulative attack pool, #26) ---"
ST_Reset
ST_GoTo "boss3"
SEQ_Advance
ST_Assert bossAttackCnt = 2 And bossAttackList$(0) = "LASER" And bossAttackList$(1) = "SPORE", "19.01  level3 boss attack=laser,spore"
ST_Reset
levelNum = 4
ST_GoTo "boss5"
SEQ_Advance
ST_Assert bossAttackCnt = 3 And bossAttackList$(0) = "LASER" And bossAttackList$(1) = "SPORE" And bossAttackList$(2) = "CUT", "19.02  level5 boss attack=laser,spore,cut"
ST_Reset
levelNum = 5
ST_GoTo "boss6"
SEQ_Advance
ST_Assert bossAttackCnt = 4 And bossAttackList$(0) = "LASER" And bossAttackList$(1) = "SPORE" And bossAttackList$(2) = "CUT" And bossAttackList$(3) = "DEVOUR", "19.03  level6 boss attack=laser,spore,cut,devour"
ST_Assert bossMusCnt = 3 And bossMusList$(2) = "boss3", "19.04  shared CSV parser still fills mus= (boss3 last)"
ST_Assert bossSpeechCnt = 3 And bossSpeechList$(0) = "" And bossSpeechList$(1) = "speech_boss_phase2", "19.05  shared CSV parser keeps the empty first speech= entry"
' ────────────────────────────────────────────────────────────────────────────
' 20. #168: an arrival cut short (planetTimer still running, cinematic never
'     reached) must not carry the last chapter's planet into the next stage.
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "--- 20. stale arrival planet cleared on next stage (issue #168) ---"
ST_Reset
levelNum = 3
ST_GoTo "boss3"
SEQ_Advance                      ' boss3
SEQ_Advance                      ' ARRIVE level3
ST_Assert gameState = GS_PLANET And planetTimer = 1 And planetCurrent = 3, "20.01  boss3 -> ARRIVE planet3, planetTimer=1"
planetTimer = 75                 ' arrival interrupted before the cinematic (planetTimer < 120)
SEQ_Advance                      ' DOCK level3
SEQ_Advance                      ' CRAWL stage4
ST_Assert gameState = GS_CRAWL,                   "20.02  next step is the chapter 4 crawl"
SEQ_Advance                      ' PLAY asteroid
ST_Assert levelType = LEVEL_ASTEROID And levelNum = 4, "20.03  asteroid stage, levelNum=4"
ST_Assert planetTimer = 0,                        "20.04  asteroid PLAY clears stale planetTimer (no chapter 3 planet)"
SEQ_Advance                      ' ARRIVE level4
planetTimer = 75
SEQ_Advance                      ' DOCK level4
SEQ_Advance                      ' CRAWL stage5
SEQ_Advance                      ' PLAY combat
ST_Assert levelType = LEVEL_COMBAT And levelNum = 5, "20.05  combat stage, levelNum=5"
ST_Assert planetTimer = 0,                        "20.06  combat PLAY clears stale planetTimer (no chapter 4 planet)"

Print ""
Print "--- 21. SEQ_NextLeg: the leg after each dock (fuel need, #277) ---"
Dim st21K As Long, st21B As Integer, st21A As Integer, st21R As Integer
ST_Reset
st21R = ST_Jump%("dock1") : SEQ_NextLeg st21K, st21B, st21A
ST_Assert st21K = 18 And st21B = 0 And st21A = 0, "21.01  after dock1: chapter 2, an 18-kill combat"
ST_Reset
st21R = ST_Jump%("dock2") : SEQ_NextLeg st21K, st21B, st21A
ST_Assert st21K = 12 And st21B = 1 And st21A = 0, "21.02  after dock2: chapter 3, 12 kills and a boss"
ST_Reset
st21R = ST_Jump%("dock3") : SEQ_NextLeg st21K, st21B, st21A
ST_Assert st21K = 0 And st21B = 0 And st21A = 1, "21.03  after dock3: chapter 4, the asteroid field"
ST_Reset
st21R = ST_Jump%("dock5") : SEQ_NextLeg st21K, st21B, st21A
ST_Assert st21K = 24 And st21B = 1 And st21A = 0, "21.04  after dock5: chapter 6, 24 kills and a boss"
ST_Reset
st21R = ST_Jump%("boss6") : SEQ_Advance : SEQ_NextLeg st21K, st21B, st21A
ST_Assert st21K = 0 And st21B = 0 And st21A = 0, "21.05  after the last arrival: no leg ahead"

Print ""
Print "--- 24. the stage ends on kills, not score (#312) ---"
ST_Reset
st21R = ST_Jump%("playing1")
ST_Assert SEQ_StageCleared% = 0 And SEQ_StageProgress! = 0,          "24.01  stage start: not cleared, progress 0"
score = score + 500 + 250
ST_Assert SEQ_StageCleared% = 0 And SEQ_StageProgress! = 0,          "24.02  a gold star and an overflow bonus (+750 pts) don't move the stage"
stageKills = 3
ST_Assert SEQ_StageCleared% = 0 And Abs(SEQ_StageProgress! - 0.25) < 0.001, "24.03  3 of 12 kills: progress 0.25"
stageKills = 11
ST_Assert SEQ_StageCleared% = 0,                                     "24.04  11 of 12 kills: not cleared"
stageKills = 12
ST_Assert SEQ_StageCleared% <> 0 And SEQ_StageProgress! = 1,         "24.05  12 of 12 kills: cleared, progress 1"
stageKills = 15
ST_Assert SEQ_StageCleared% <> 0 And SEQ_StageProgress! = 1,         "24.06  overkill: still cleared, progress capped at 1"
SEQ_Advance : SEQ_Advance : SEQ_Advance : SEQ_Advance                ' ARRIVE, DOCK, CRAWL, PLAY combat level2
ST_Assert levelNum = 2 And stageKills = 0 And SEQ_StageCleared% = 0, "24.07  next combat stage starts from 0 kills"
ST_Reset
st21R = ST_Jump%("boss3")
stageKills = 1000
ST_Assert SEQ_StageCleared% = 0,                                     "24.08  boss fight: kills never re-fire the combat trigger"
ST_Reset
settingNerf = -1
st21R = ST_Jump%("playing2")
stageKills = 1
ST_Assert SEQ_StageCleared% = 0 And Abs(SEQ_StageProgress! - 0.5) < 0.001, "24.09  nerf level2: 1 of 2 kills, progress 0.5"
stageKills = 2
ST_Assert SEQ_StageCleared% <> 0,                                    "24.10  nerf level2: 2 kills clear it"
' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
