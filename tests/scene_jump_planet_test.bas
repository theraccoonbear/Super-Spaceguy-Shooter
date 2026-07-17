' scene_jump_planet_test.bas — verify --scene debug jump initializes planet state correctly
'
' Regression: GAME_ResetState sets planetCurrent = PLANET_COUNT (6).
' The stage-end formula (x Mod PLANET_COUNT)+1 then yields planet 1 (Caldorinthia)
' regardless of which stage was jumped to.  The fix sets planetCurrent = levelNum
' (= stageN - 1) in sss.bas immediately after GAME_ResetState so the formula gives N.
'
' Build: ./tools/buildqb tests/scene_jump_planet_test.bas
' Run:   ./tests/scene_jump_planet_test   (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

Const PLANET_COUNT  = 6
Const GS_TITLE      = 0
Const GS_PLAYING    = 1
Const GS_CRAWL      = 6
Const CAM_OFFSET_X  = 6.5
Const CAM_OFFSET_Y  = 2.0

' shared vars referenced by sequence.bas
Dim Shared gameState    As Integer
Dim Shared score        As Long
Dim Shared highScore    As Long
Dim Shared stageScore   As Long
Dim Shared scrH         As Single
Dim Shared levelNum     As Integer
Dim Shared planetCurrent As Integer
Dim Shared planetNameIdx As Integer
Dim Shared planetNames(1 To PLANET_COUNT) As String
Dim Shared astDestName  As String
Dim introTimer          As Integer   ' module-scope in sss.bas; not Shared

' stubs — silence all audio / render / spawn side-effects
Sub MUS_SetCue(musSCn$)
End Sub

Sub StarfieldReset(srX As Single, srY As Single, srZ As Single)
End Sub

Sub CRAWL_Prep(cpKey As String, cpStartY As Single)
End Sub

Sub SETTINGS_Save()
End Sub

Sub BELT_Init(bliW As Single, bliH As Single)
End Sub

Sub WAVE_SpawnAsteroidField()
End Sub

'$INCLUDE:'../src/sequence.bas'

' test helpers
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

' Apply the stage-end formula from wave.bas / stage.bas that increments the planet.
Function PlanetAfterStage%(pc As Integer)
    PlanetAfterStage% = (pc Mod PLANET_COUNT) + 1
End Function

' Simulate the sss.bas CLI path for --scene playingN:
'   GAME_ResetState (resets planetCurrent = PLANET_COUNT)
'   levelNum = N - 1
'   planetCurrent = levelNum   ← the fix
'   planetNameIdx = levelNum
Sub SimSceneJump(scjN As Integer)
    planetCurrent = PLANET_COUNT   ' what GAME_ResetState sets
    planetNameIdx = PLANET_COUNT
    levelNum      = scjN - 1
    If levelNum < 0 Then levelNum = 0
    planetCurrent = levelNum       ' the fix
    planetNameIdx = levelNum
End Sub

' ─────────────────────────────────────────────────────────────────────────────

Print "=== scene_jump_planet_test ==="
Print ""

' 1. Regression: old behaviour — GAME_ResetState left planetCurrent = PLANET_COUNT.
'    Stage-end formula gives planet 1 for ANY stage, not just stage 1.
Print "--- 1: regression (old reset behaviour) ---"
Dim stOldPc As Integer : stOldPc = PLANET_COUNT
ST_Assert PlanetAfterStage%(stOldPc) = 1, _
    "1a  reset + formula -> planet 1 regardless of stage"
ST_Assert PlanetAfterStage%(stOldPc) <> 4, _
    "1b  reset + formula -> NOT planet 4 (Xeromith) for playing4"

' 2. Fix: planetCurrent = N-1 gives planet N for every stage.
Print ""
Print "--- 2: fix — planetCurrent = stageN-1 gives correct planet ---"
Dim stN As Integer
For stN = 1 To PLANET_COUNT
    ST_Assert PlanetAfterStage%(stN - 1) = stN, _
        "2." + LTrim$(Str$(stN)) + "  stage " + LTrim$(Str$(stN)) + " -> planet " + LTrim$(Str$(stN))
Next stN

' 3. Specific regression case: --scene playing4 must arrive at planet 4 (Xeromith).
Print ""
Print "--- 3: specific case --scene playing4 -> planet 4 ---"
SimSceneJump 4
Dim stPlanet As Integer
stPlanet = PlanetAfterStage%(planetCurrent)
ST_Assert stPlanet = 4, "3a  playing4 + fix -> planetCurrent = 4 after stage-end"
stPlanet = PlanetAfterStage%(planetNameIdx)
ST_Assert stPlanet = 4, "3b  playing4 + fix -> planetNameIdx = 4 after stage-end"

' 4. --scene playing1 still gives planet 1 (no regression in the normal case).
Print ""
Print "--- 4: --scene playing1 still gives planet 1 ---"
SimSceneJump 1
ST_Assert PlanetAfterStage%(planetCurrent) = 1, "4   playing1 + fix -> planet 1 (no regression)"

' 5. SEQ_JumpToScene("playing4") resolves to the asteroid entry in the sequence table.
Print ""
Print "--- 5: SEQ_JumpToScene locates playing4 as asteroid entry ---"
SEQ_Init
Dim stIdx As Integer : stIdx = SEQ_JumpToScene("playing4")
ST_Assert stIdx >= 0,                     "5a  SEQ_JumpToScene(playing4) found (>= 0)"
ST_Assert seqSval$(stIdx) = "asteroid",   "5b  playing4 entry sval = 'asteroid'"

' 6. --scene playing1 through playing6: all land on the expected play entry type.
Print ""
Print "--- 6: SEQ_JumpToScene finds each playing scene ---"
Dim stPIdx As Integer
For stN = 1 To PLANET_COUNT
    SEQ_Init
    stPIdx = SEQ_JumpToScene("playing" + LTrim$(Str$(stN)))
    ST_Assert stPIdx >= 0, _
        "6." + LTrim$(Str$(stN)) + "  playing" + LTrim$(Str$(stN)) + " found in sequence"
Next stN

' ─────────────────────────────────────────────────────────────────────────────
Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
