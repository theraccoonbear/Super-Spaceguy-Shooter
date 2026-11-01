' tutorial_gate_test.bas -- the first-play tutorial gate (#240)
'
' The first New Game on a fresh install starts the tutorial; finishing or skipping it records
' tutorial_done in the per-user settings (sss_settings.ini), so it is not forced again.
'   1. a fresh install (no settings file) is not done, and the gate is due
'   2. the answer round-trips through the settings file: not done stays not done, done stays done
'   3. a settings file with no tutorial_done line (every existing player's) counts as done
'   4. an explicit tutorial_done=0 / 1 is honoured; the rest of the file loads as before
'   5. a launch-folder settings file migrated into a new settings dir counts as done
'   6. scripted (--input-script) and --scene runs, and a session that cannot save, bypass the gate
'   7. what the tutorial's end writes (tutorial_done set, then saved) is read back as done
'
' The scripted full run, tests/tutorial/run.sh, covers the real finish and waiver paths (the
' file it leaves holds tutorial_done=1 and highscore=0).
'
' All files live under tutorial_gate_test_tmp/ in _STARTDIR$ and are removed afterwards.
'
' Build: tools/dev test (builds and runs every test)
' Run:   builds/tutorial_gate_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

Const VERSION$ = "0.0.0-test"
Const BUILD_KIND$ = "dev"
Const UN_MAX_LEN = 32
Const CAM_DEFAULT_PHI = 0.1545
Const CAM_DEFAULT_R   = 6.80

Type BossObj
    active  As Integer
    meshIdx As Integer
    px As Single : py As Single : pz As Single
    hp As Integer
    phase As Integer
End Type

Type CamFollow
    angleLocked AS INTEGER
    orbitTheta  AS SINGLE
    orbitPhi    AS SINGLE
    orbitR      AS SINGLE
End Type

Dim Shared DB_URL As String
Dim Shared DB_KEY As String
Dim Shared boss              As BossObj
Dim Shared camF              As CamFollow
Dim Shared ioReadOnly        As Integer
Dim Shared debugMode         As Integer
Dim Shared volMusic As Single, volSfx As Single, volSpeech As Single
Dim Shared settingNarration As Integer, settingNarrSpeed As Integer, settingFullscreen As Integer
Dim Shared highScore         As Long
Dim Shared telemOn           As Integer
Dim Shared telemSession      As String
Dim Shared telemPlayerID     As String
Dim Shared telemConsent      As Integer
Dim Shared telemKills        As Long
Dim Shared telemBossReached  As Integer
Dim Shared telemBossPhaseLog As Integer
Dim Shared telemDeathCause   As String
Dim Shared telemShotsFired   As Long
Dim Shared telemShotsHit     As Long
Dim Shared telemEscapes      As Long
Dim Shared telemBatch        As String
Dim Shared telemCsvDir       As String
Dim Shared telemCsvBuf       As String
Dim Shared settingsDir       As String
Dim Shared telemBatchRows    As Long
Dim Shared telemT0           As Long
Dim Shared gameFrame         As Long
Dim Shared telemFlags        As String
Dim Shared levelNum          As Integer
Dim Shared stageKills        As Long
Dim Shared stageKillTarget   As Long
Dim Shared gameState         As Integer
Function DBG_StateName$ (s As Integer) : DBG_StateName$ = "GS_TEST" : End Function
Dim Shared telemExitReason   As String
Dim Shared score             As Long
Dim Shared waveType          As Integer
Dim Shared leaderboardPlayerID As String
Dim Shared telemPlayerName     As String
Dim Shared settingNerf         As Integer
Dim Shared lives               As Integer
Dim Shared credits             As Long
Dim Shared creditsEarned       As Long
Dim Shared creditsSpent        As Long
Dim Shared fuelLevel           As Single
Dim Shared laserEnergy         As Single

Dim Shared roBindsWrites As Integer

Sub DBG_Print (msg As String) : End Sub
Sub HTTP_Post (u As String, k As String, b As String, t As String) : End Sub
Sub HTTP_Get  (u As String, k As String, t As String) : End Sub
Function JSON_Obj$ (s As String) : JSON_Obj$ = "{" + s + "}" : End Function
Function JSON_S$   (k As String, v As String) : JSON_S$ = k + ":" + v : End Function
Function JSON_N$   (k As String, v As String) : JSON_N$ = k + ":" + v : End Function
Sub E3D_BindsWrite (bwFH As Integer) : roBindsWrites = roBindsWrites + 1 : End Sub
Function E3D_BindsLoadLine% (blKey As String, blRaw As String) : E3D_BindsLoadLine% = 0 : End Function
Sub E3D_PadReselect : End Sub

Function GTEXT_Get$ (k As String) : GTEXT_Get$ = "" : End Function
Dim Shared tutorialRun As Integer   ' shared by sequence.bas / telemetry.bas / player.bas (dims.bas)
'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/telemetry.bas'
'$INCLUDE:'../src/sys/settingsio.bas'
'$INCLUDE:'../src/sys/tutorial.bas'

Dim Shared tgPass As Integer, tgFail As Integer

Sub TG_Assert (condition As Integer, label As String)
    If condition Then
        Print "PASS  " + label
        tgPass = tgPass + 1
    Else
        Print "FAIL  " + label
        tgFail = tgFail + 1
    End If
End Sub

Sub TG_Write (tgwPath As String, tgwText As String)
    Dim tgwH As Integer
    tgwH = FreeFile
    Open tgwPath For Output As #tgwH
    Print #tgwH, tgwText;
    Close #tgwH
End Sub

Function TG_Has% (tghPath As String, tghLine As String)
    Dim tghData As String
    tghData = _ReadFile$(tghPath)
    tghData = Chr$(10) + tghData
    Dim tghI As Long
    For tghI = 1 To Len(tghData)
        If Mid$(tghData, tghI, 1) = Chr$(13) Then Mid$(tghData, tghI, 1) = " "
    Next tghI
    TG_Has% = (InStr(tghData, Chr$(10) + tghLine + " " + Chr$(10)) > 0 Or InStr(tghData, Chr$(10) + tghLine + Chr$(10)) > 0)
End Function

Sub TG_Rm (tgrPath As String)
    If _FileExists(tgrPath) Then
        Kill tgrPath
    ElseIf _DirExists(tgrPath) Then
        RmDir tgrPath
    End If
End Sub

' The state a launch starts in, before SETTINGS_Load runs
Sub TG_Boot
    settingTutorialDone = 99
    highScore = 0 : volMusic = 0.3 : settingNarrSpeed = 2 : settingNarration = 1
    telemPlayerID = "" : leaderboardPlayerID = "" : telemPlayerName = "" : telemConsent = 0
    ioReadOnly = 0 : settingsDir = ""
End Sub

Print "=== tutorial_gate_test ==="
Print ""

Dim tgBase As String, tgFile As String, tgOld As String, tgDst As String
tgBase = _StartDir$ + "/tutorial_gate_test_tmp"
tgFile = tgBase + "/sss_settings.ini"
tgOld = tgBase + "/old_settings.ini"
tgDst = tgBase + "/new_dir_settings.ini"
TG_Rm tgFile : TG_Rm tgOld : TG_Rm tgDst : TG_Rm tgBase
MkDir tgBase

Print "--- 1. a fresh install ---"
TG_Boot
SETTINGS_LoadFile tgFile
TG_Assert _FileExists(tgFile) = 0,               "1.01  there is no settings file on a fresh install"
TG_Assert settingTutorialDone = 0,               "1.02  the tutorial is not done"
TG_Assert TUT_GateDue%(settingTutorialDone, 0, "", 0) <> 0, "1.03  the gate is due: the first New Game starts the tutorial"
TG_Boot
SETTINGS_LoadFile ""
TG_Assert settingTutorialDone = 0,               "1.04  no settings path at all: not done either"
Print ""

Print "--- 2. the answer round-trips ---"
TG_Boot
SETTINGS_LoadFile tgFile
SETTINGS_SaveFile tgFile
TG_Assert TG_Has%(tgFile, "tutorial_done=0"),    "2.01  the first save writes tutorial_done=0"
TG_Boot
SETTINGS_LoadFile tgFile
TG_Assert settingTutorialDone = 0,               "2.02  a file saved before the tutorial was done loads as not done: still gated on the next launch"
settingTutorialDone = -1
SETTINGS_SaveFile tgFile
TG_Assert TG_Has%(tgFile, "tutorial_done=1"),    "2.03  finishing or skipping saves tutorial_done=1"
TG_Boot
SETTINGS_LoadFile tgFile
TG_Assert settingTutorialDone <> 0,              "2.04  it loads as done"
TG_Assert TUT_GateDue%(settingTutorialDone, 0, "", 0) = 0, "2.05  the gate is not due again"
SETTINGS_SaveFile tgFile
TG_Boot
SETTINGS_LoadFile tgFile
TG_Assert settingTutorialDone <> 0,              "2.06  saving again keeps it"
Print ""

Print "--- 3. an existing player's settings file ---"
TG_Write tgOld, "music=0.5" + Chr$(10) + "sfx=0.9" + Chr$(10) + "speech=0.4" + Chr$(10) + "narration=1" + Chr$(10) + "narration_speed=2" + Chr$(10) + "fullscreen=0" + Chr$(10) + "difficulty=hard" + Chr$(10) + "highscore=4200" + Chr$(10) + "player_name=ace" + Chr$(10)
TG_Boot
SETTINGS_LoadFile tgOld
TG_Assert settingTutorialDone <> 0,              "3.01  no tutorial_done line: counts as done"
TG_Assert TUT_GateDue%(settingTutorialDone, 0, "", 0) = 0, "3.02  existing players are not gated"
TG_Assert highScore = 4200 And Abs(volMusic - 0.5) < 0.001, "3.03  the rest of the file loads as before"
SETTINGS_SaveFile tgOld
TG_Assert TG_Has%(tgOld, "tutorial_done=1"),     "3.04  the next save writes tutorial_done=1 for them"
TG_Write tgOld, ""
TG_Boot
SETTINGS_LoadFile tgOld
TG_Assert settingTutorialDone <> 0,              "3.05  an empty settings file that exists counts as done"
Print ""

Print "--- 4. explicit values ---"
TG_Write tgOld, "highscore=10" + Chr$(10) + "tutorial_done=0" + Chr$(10)
TG_Boot
SETTINGS_LoadFile tgOld
TG_Assert settingTutorialDone = 0 And highScore = 10, "4.01  tutorial_done=0: not done"
TG_Write tgOld, "tutorial_done=1" + Chr$(10) + "highscore=10" + Chr$(10)
TG_Boot
SETTINGS_LoadFile tgOld
TG_Assert settingTutorialDone <> 0 And highScore = 10, "4.02  tutorial_done=1: done"
TG_Write tgOld, "tutorial_done=7" + Chr$(10)
TG_Boot
SETTINGS_LoadFile tgOld
TG_Assert settingTutorialDone <> 0,              "4.03  any non-zero value is done"
Print ""

Print "--- 5. a migrated launch-folder file ---"
TG_Write tgOld, "highscore=300" + Chr$(10) + "player_name=ace" + Chr$(10)
TG_Assert SETTINGS_Migrate%(tgOld, tgDst) <> 0,  "5.01  the old file is copied into the new settings dir"
TG_Boot
SETTINGS_LoadFile tgDst
TG_Assert settingTutorialDone <> 0 And highScore = 300, "5.02  it counts as done"
Print ""

Print "--- 6. bypasses ---"
TG_Boot
SETTINGS_LoadFile tgBase + "/missing.ini"
TG_Assert TUT_GateDue%(settingTutorialDone, 0, "", 0) <> 0, "6.01  baseline: a fresh install is gated"
TG_Assert TUT_GateDue%(settingTutorialDone, -1, "", 0) = 0, "6.02  --input-script (iscActive): bypassed, so tests/playthrough/expected.txt does not change"
TG_Assert TUT_GateDue%(settingTutorialDone, 0, "tutorial", 0) = 0, "6.03  --scene tutorial: bypassed"
TG_Assert TUT_GateDue%(settingTutorialDone, 0, "playing1", 0) = 0, "6.04  --scene playing1: bypassed"
TG_Assert TUT_GateDue%(settingTutorialDone, -1, "boss3", 0) = 0, "6.05  both: bypassed"
TG_Assert TUT_GateDue%(settingTutorialDone, 0, "", -1) = 0, "6.06  a session that cannot save settings: not gated every launch"
ioReadOnly = -1
TG_Rm tgFile
SETTINGS_SaveFile tgFile
TG_Assert _FileExists(tgFile) = 0,               "6.07  read-only: nothing is written"
ioReadOnly = 0
Print ""

Print "--- 7. finishing the tutorial ---"
TG_Boot
SETTINGS_LoadFile tgFile
TG_Assert TUT_GateDue%(settingTutorialDone, 0, "", 0) <> 0, "7.01  fresh: gated"
settingTutorialDone = -1 : SETTINGS_SaveFile tgFile   ' TUT_Finish: settingTutorialDone = -1 : SETTINGS_Save
TG_Boot
SETTINGS_LoadFile tgFile
TG_Assert TUT_GateDue%(settingTutorialDone, 0, "", 0) = 0, "7.02  the next launch: not gated"
TG_Boot
SETTINGS_LoadFile tgFile
settingTutorialDone = -1 : SETTINGS_SaveFile tgFile  ' TUT_Abandon (pause-menu retreat): counts as skipped
TG_Assert TG_Has%(tgFile, "tutorial_done=1"),    "7.03  a retreat from the tutorial is saved the same way"
Print ""

TG_Rm tgFile : TG_Rm tgOld : TG_Rm tgDst : TG_Rm tgBase

Print "=== " + LTrim$(Str$(tgPass + tgFail)) + " tests: " _
    + LTrim$(Str$(tgPass)) + " passed, " + LTrim$(Str$(tgFail)) + " failed ==="
If tgFail > 0 Then System 1 Else System 0
