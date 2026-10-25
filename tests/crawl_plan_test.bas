' crawl_plan_test.bas — constant crawl scroll speed planning (src/2d/crawllayout.bas)
'
'   - CRAWL_PlanSpeed! on hand-computed cases (one and two paragraphs, clamps)
'   - every crawl block in gametext.txt, at narration OFF / SLOW / NORMAL / FAST:
'     the planned speed fits (every paragraph finishes before its last line reaches
'     the top fade), is in range, and is the fastest that fits
'   - SPK_TextSamples& measures text without disturbing the utterance in progress
'
' Build: ./tools/buildqb tests/crawl_plan_test.bas
' Run:   ./tests/crawl_plan_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

Const SAMPLE_RATE = 44100

$EMBED:'assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'assets/gametext.txt':'GAMETEXT'
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'

Sub DBG_Print(cptDbgMsg As String) : End Sub

'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/sys/gametext.bas'
'$INCLUDE:'../src/2d/crawllayout.bas'

' Same geometry CRAWL_Prep uses: 320x240 screen, text starts at the bottom edge.
Const CPT_START_Y = 240
Const CPT_TRIG_Y = 218 ' scrH - CRAWL_LINE_H
Const CPT_TOP_Y = 48 ' CRAWL_TOP_FADE

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

Function CPT_Near%(cpnA As Single, cpnB As Single)
    CPT_Near% = (Abs(cpnA - cpnB) < 0.02)
End Function

Function CPT_Plan!
    CPT_Plan! = CRAWL_PlanSpeed!(CPT_START_Y, CPT_TRIG_Y, CPT_TOP_Y)
End Function

Print "=== crawl_plan_test ==="
Print ""

SPK_Init
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")

Print "--- hand-computed cases ---"
' One paragraph on line 0: starts at (240-218)/v = 22/v, must end by that line reaching
' y=48 at (240-48)/v = 192/v, so d <= 170/v.
crawlParaCount = 1 : crawlParaLine(0) = 0 : crawlParaLastLine(0) = 0
crawlParaDur(0) = 2
ST_Assert CPT_Near%(CPT_Plan!, CRAWL_VEL_MAX), "short paragraph: capped at CRAWL_VEL_MAX"
crawlParaDur(0) = 20
ST_Assert CPT_Near%(CPT_Plan!, 8.5), "20 s paragraph: v = 170/20 = 8.5 px/s"
crawlParaDur(0) = 100
ST_Assert CPT_Near%(CPT_Plan!, CRAWL_VEL_MIN), "100 s paragraph: floors at CRAWL_VEL_MIN"
ST_Assert CRAWL_PlanFits%(CRAWL_VEL_MIN, CPT_START_Y, CPT_TRIG_Y, CPT_TOP_Y) = 0, "100 s paragraph: reported as not fitting"
' Two paragraphs: lines 0 and 2-3, 5 s each. Above v = 8.8 the second waits for the first,
' ending at 22/v + 10, due by (240 + 66 - 48)/v = 258/v, so v <= 236/10 = 23.6.
crawlParaCount = 2
crawlParaLine(0) = 0 : crawlParaLastLine(0) = 0 : crawlParaDur(0) = 5
crawlParaLine(1) = 2 : crawlParaLastLine(1) = 3 : crawlParaDur(1) = 5
ST_Assert CPT_Near%(CPT_Plan!, 23.6), "two paragraphs, second waits for first: v = 23.6 px/s"

Print "--- every crawl block, every narration setting ---"
Dim cptKeys As String, cptK As String, cptP As Integer, cptLvl As Integer, cptV As Single, cptRow As String
Dim cptName(0 To 3) As String
cptName(0) = "OFF" : cptName(1) = "SLOW" : cptName(2) = "NORMAL" : cptName(3) = "FAST"
cptKeys = "intro stage1 stage2 stage3 stage4 stage5 stage6 outro death_final "
Do While Len(cptKeys) > 0
    cptP = InStr(cptKeys, " ")
    cptK = Left$(cptKeys, cptP - 1) : cptKeys = Mid$(cptKeys, cptP + 1)
    CRAWL_Layout GTEXT_Get$(cptK)
    ST_Assert crawlParaCount > 0, cptK + ": laid out into paragraphs"
    cptRow = "      " + cptK + " px/s:"
    For cptLvl = 0 To 3
        CRAWL_PlanDurations cptLvl
        cptV = CPT_Plan!
        cptRow = cptRow + "  " + cptName(cptLvl) + Str$(Int(cptV * 10) / 10)
        ST_Assert CRAWL_PlanFits%(cptV, CPT_START_Y, CPT_TRIG_Y, CPT_TOP_Y), cptK + " " + cptName(cptLvl) + ": every paragraph finishes on screen"
        ST_Assert cptV >= CRAWL_VEL_MIN And cptV <= CRAWL_VEL_MAX, cptK + " " + cptName(cptLvl) + ": speed in range"
        ST_Assert cptV >= CRAWL_VEL_MAX Or CRAWL_PlanFits%(cptV * 1.01, CPT_START_Y, CPT_TRIG_Y, CPT_TOP_Y) = 0, cptK + " " + cptName(cptLvl) + ": fastest speed that fits"
    Next cptLvl
    Print cptRow
Loop

Print "--- SPK_TextSamples& leaves current speech alone ---"
Dim cptI As Long, cptIdx As Integer, cptCnt As Integer, cptPos As Integer, cptDur As Long, cptT As Long
SPK_Say GTEXT_Get$("speech_boss_warning")
For cptI = 1 To 20000 : SPK_Advance : Next cptI
cptIdx = spkPhoneIdx : cptCnt = spkPhoneCount : cptPos = spkSamplePos : cptDur = SPK_PhoneDur&(SPK_AA, 1)
cptT = SPK_TextSamples&(crawlParaText$(0), 3)
ST_Assert spkPhoneIdx = cptIdx And spkPhoneCount = cptCnt And spkSamplePos = cptPos, "queue position restored"
ST_Assert SPK_PhoneDur&(SPK_AA, 1) = cptDur, "speech speed restored"
SPK_Say crawlParaText$(0) : SPK_SetPreset 3
ST_Assert cptT = SPK_QueueSamples&, "measured length = queued length at the same preset"

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
