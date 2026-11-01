' settings_dir_test.bas -- regression tests for issue #284
'
' Where settings live and when the telemetry CSV is written:
'   - SETTINGS_DirFor$ picks the per-user dir per OS (pure function)
'   - the probe block (settingsprobe.bas, the code sss.bas runs at startup) creates the dir,
'     migrates a launch-folder sss_settings.ini once, falls back to the launch folder and then
'     to read-only when a folder can't be made or written
'   - settings saved from one launch folder load from another
'   - telemetry rows stay in memory until TELEM_FlushCsv / TELEM_SessionEnd
'
' All files live under settings_dir_test_tmp/ in _STARTDIR$ and are removed afterwards.
' An "unwritable" folder is one whose parent is a regular file, so the test needs no chmod.
'
' Build: ./tools/buildqb tests/settings_dir_test.bas
' Run:   builds/settings_dir_test   (exit 0 = all pass)

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

Dim Shared tutorialRun As Integer   ' shared by sequence.bas / telemetry.bas / player.bas (dims.bas)
'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/telemetry.bas'
'$INCLUDE:'../src/sys/settingsio.bas'
'$INCLUDE:'../src/sys/settingsprobe.bas'

' --- test harness ---
Dim Shared tcPass As Integer, tcFail As Integer

Sub TC_Assert (condition As Integer, label As String)
    If condition Then
        Print "PASS  " + label
        tcPass = tcPass + 1
    Else
        Print "FAIL  " + label
        tcFail = tcFail + 1
    End If
End Sub

Sub SD_Write (sdwPath As String, sdwText As String)
    Dim sdwH As Integer
    sdwH = FreeFile
    Open sdwPath For Output As #sdwH
    Print #sdwH, sdwText
    Close #sdwH
End Sub

Function SD_Lines& (sdlPath As String)
    Dim sdlData As String, sdlI As Long, sdlN As Long
    If _FileExists(sdlPath) = 0 Then SD_Lines& = -1 : Exit Function
    sdlData = _ReadFile$(sdlPath)
    For sdlI = 1 To Len(sdlData)
        If Mid$(sdlData, sdlI, 1) = Chr$(10) Then sdlN = sdlN + 1
    Next sdlI
    SD_Lines& = sdlN
End Function

Sub SD_Rm (sdrPath As String)
    If _FileExists(sdrPath) Then
        Kill sdrPath
    ElseIf _DirExists(sdrPath) Then
        RmDir sdrPath
    End If
End Sub

Sub SD_Clean (sdcBase As String)
    SD_Rm sdcBase + "/cfg/sss/sss_settings.ini"
    SD_Rm sdcBase + "/cfg/sss"
    SD_Rm sdcBase + "/cfg"
    SD_Rm sdcBase + "/launch/sss_settings.ini"
    SD_Rm sdcBase + "/launch/sss_telemetry.csv"
    SD_Rm sdcBase + "/launch"
    SD_Rm sdcBase + "/other/sss_settings.ini"
    SD_Rm sdcBase + "/other"
    SD_Rm sdcBase + "/afile"
    SD_Rm sdcBase
End Sub

Sub SD_Reset
    ioDirs(1) = "" : ioDirs(2) = "" : ioMigrateWanted = 0
    settingsDir = "x" : telemCsvDir = "x"
End Sub

Print "=== settings_dir_test ==="
Print ""

Dim sdBase As String, sdCfg As String, sdLaunch As String, sdOther As String, sdFile As String
Dim sdIni As String, sdRows As Long
sdBase = _StartDir$ + "/settings_dir_test_tmp"
sdCfg = sdBase + "/cfg/sss"
sdLaunch = sdBase + "/launch"
sdOther = sdBase + "/other"
sdFile = sdBase + "/afile"
sdIni = "/sss_settings.ini"
SD_Clean sdBase
MkDir sdBase
MkDir sdLaunch
MkDir sdOther
SD_Write sdFile, "not a folder"

Print "--- 1. per-OS location ---"
TC_Assert SETTINGS_DirFor$("[LINUX][64BIT]", "/xdg/conf", "", "/home/p") = "/xdg/conf/sss", "1.01  Linux: $XDG_CONFIG_HOME/sss"
TC_Assert SETTINGS_DirFor$("[LINUX][64BIT]", "", "", "/home/p") = "/home/p/.config/sss", "1.02  Linux: ~/.config/sss by default"
TC_Assert SETTINGS_DirFor$("[LINUX][64BIT]", "rel/conf", "", "/home/p") = "/home/p/.config/sss", "1.03  Linux: a relative XDG_CONFIG_HOME is ignored"
TC_Assert SETTINGS_DirFor$("[LINUX][64BIT]", "/xdg/conf/", "", "/home/p") = "/xdg/conf/sss", "1.04  Linux: trailing slash trimmed"
TC_Assert SETTINGS_DirFor$("[LINUX][64BIT]", "", "", "") = "", "1.05  Linux: no HOME, no location"
TC_Assert SETTINGS_DirFor$("[MACOSX][64BIT]", "/ignored", "", "/Users/p") = "/Users/p/Library/Application Support/sss", "1.06  macOS: Application Support"
TC_Assert SETTINGS_DirFor$("[MACOSX][64BIT]", "", "", "") = "", "1.07  macOS: no HOME, no location"
TC_Assert SETTINGS_DirFor$("[WINDOWS][64BIT]", "", "C:\Users\p\AppData\Roaming", "") = "C:\Users\p\AppData\Roaming\sss", "1.08  Windows: %APPDATA%\sss"
TC_Assert SETTINGS_DirFor$("[WINDOWS][64BIT]", "", "C:\Roaming\", "") = "C:\Roaming\sss", "1.09  Windows: trailing backslash trimmed"
TC_Assert SETTINGS_DirFor$("[WINDOWS][64BIT]", "", "", "C:\Users\p") = "", "1.10  Windows: no APPDATA, no location"
TC_Assert SETTINGS_Parent$("/a/b/c") = "/a/b", "1.11  parent of /a/b/c"
TC_Assert SETTINGS_Parent$("C:\a\b") = "C:\a", "1.12  parent of C:\a\b"
TC_Assert SETTINGS_Parent$("/a") = "", "1.13  parent of /a is the root"
Print ""

Print "--- 2. first run: dir created, settings migrated ---"
SD_Reset
ioDirs(1) = sdCfg : ioDirs(2) = sdLaunch : ioMigrateWanted = -1
SD_Write sdLaunch + sdIni, "music=0.25"
GOSUB ioProbeRun
TC_Assert settingsDir = sdCfg, "2.01  settings dir is the per-user dir"
TC_Assert _DirExists(sdCfg), "2.02  missing dir and its parents were created"
TC_Assert ioReadOnly = 0, "2.03  not read-only"
TC_Assert ioMigrated <> 0, "2.04  reported as migrated"
TC_Assert InStr(_ReadFile$(sdCfg + sdIni), "music=0.25") > 0, "2.05  launch-folder settings copied over"
TC_Assert _FileExists(sdLaunch + sdIni), "2.06  original left in the launch folder"
TC_Assert telemCsvDir = sdLaunch, "2.07  telemetry CSV stays in the launch folder"
TC_Assert _FileExists(sdCfg + "/sss_write_probe.tmp") = 0 And _FileExists(sdLaunch + "/sss_write_probe.tmp") = 0, "2.08  probe files cleaned up"
SD_Write sdCfg + sdIni, "music=0.75"
GOSUB ioProbeRun
TC_Assert ioMigrated = 0, "2.09  second run does not migrate again"
TC_Assert InStr(_ReadFile$(sdCfg + sdIni), "music=0.75") > 0, "2.10  existing per-user settings are not overwritten"
SD_Reset
ioDirs(1) = sdCfg : ioDirs(2) = sdLaunch : ioMigrateWanted = 0
GOSUB ioProbeRun
TC_Assert ioMigrated = 0 And settingsDir = sdCfg, "2.11  pinned/scripted run (migration off) uses the dir, copies nothing"
Print ""

Print "--- 3. fallbacks ---"
SD_Reset
ioDirs(1) = sdFile + "/sss" : ioDirs(2) = sdLaunch : ioMigrateWanted = -1
GOSUB ioProbeRun
TC_Assert settingsDir = sdLaunch And ioReadOnly = 0, "3.01  per-user dir can't be made: falls back to the launch folder"
TC_Assert ioMigrated = 0, "3.02  nothing migrated into the launch folder itself"
SD_Reset
ioDirs(1) = "" : ioDirs(2) = sdLaunch
GOSUB ioProbeRun
TC_Assert settingsDir = sdLaunch, "3.03  no per-user location known: launch folder"
SD_Reset
ioDirs(1) = sdFile + "/sss" : ioDirs(2) = sdFile + "/launch"
GOSUB ioProbeRun
TC_Assert ioReadOnly <> 0 And settingsDir = "", "3.04  neither writable: read-only session (#283)"
TC_Assert telemCsvDir = "", "3.05  no local CSV when the launch folder is unwritable"
SD_Reset
ioDirs(1) = sdCfg : ioDirs(2) = sdFile + "/launch"
GOSUB ioProbeRun
TC_Assert settingsDir = sdCfg And telemCsvDir = "", "3.06  settings saved, CSV skipped when only the launch folder is unwritable"
Print ""

Print "--- 4. settings survive launching from another folder ---"
SD_Reset
ioDirs(1) = sdCfg : ioDirs(2) = sdLaunch : ioMigrateWanted = 0
GOSUB ioProbeRun
Kill sdCfg + sdIni
volMusic = 0.4 : settingNarrSpeed = 3
telemPlayerID = "" : leaderboardPlayerID = ""
SETTINGS_Load
Dim sdId As String : sdId = telemPlayerID
SETTINGS_Save
TC_Assert _FileExists(sdCfg + sdIni), "4.01  SETTINGS_Save writes into the per-user dir"
TC_Assert _FileExists(sdLaunch + sdIni) = 0 Or InStr(_ReadFile$(sdLaunch + sdIni), "music=0.4") = 0, "4.02  nothing new written to the launch folder"
volMusic = 1 : settingNarrSpeed = 2 : telemPlayerID = ""
SD_Reset
ioDirs(1) = sdCfg : ioDirs(2) = sdOther : ioMigrateWanted = -1
GOSUB ioProbeRun
SETTINGS_Load
TC_Assert settingsDir = sdCfg, "4.03  second launch from another folder finds the same dir"
TC_Assert Abs(volMusic - 0.4) < 0.001 And settingNarrSpeed = 3, "4.04  volume and narration speed remembered"
TC_Assert telemPlayerID = sdId And Len(sdId) >= 32, "4.05  player ID remembered"
Print ""

Print "--- 5. telemetry CSV is written once, at session end ---"
SD_Rm sdLaunch + "/sss_telemetry.csv"
telemOn = -1 : DB_URL = "" : telemCsvDir = sdLaunch : telemCsvBuf = ""
telemSession = "20260101000000" : telemExitReason = "quit"
TELEM_Init
TC_Assert _FileExists(sdLaunch + "/sss_telemetry.csv") = 0, "5.01  TELEM_Init creates no file"
TELEM_Row "enemy_killed", "score=100"
TELEM_Row "enemy_killed", "score=200"
TELEM_Row "enemy_killed", "score=300"
TC_Assert _FileExists(sdLaunch + "/sss_telemetry.csv") = 0, "5.02  no CSV writes while rows are logged"
TC_Assert InStr(telemCsvBuf, "score=300") > 0, "5.03  rows wait in memory"
TELEM_SessionEnd
sdRows = SD_Lines&(sdLaunch + "/sss_telemetry.csv")
TC_Assert sdRows >= 5, "5.04  session end writes header + 3 kills + credits_earned + session_end (lines:" + Str$(sdRows) + ")"
TC_Assert InStr(_ReadFile$(sdLaunch + "/sss_telemetry.csv"), "time,session,event,data") = 1, "5.05  header first"
TC_Assert InStr(_ReadFile$(sdLaunch + "/sss_telemetry.csv"), ",session_end,exit=quit") > 0, "5.06  session_end row present"
TC_Assert telemCsvBuf = "", "5.07  buffer emptied"
telemSession = "20260101000001"
TELEM_Row "enemy_killed", "score=400"
TELEM_FlushCsv
TC_Assert SD_Lines&(sdLaunch + "/sss_telemetry.csv") = sdRows + 1, "5.08  flush on quit appends the pending row, no second header"
TELEM_FlushCsv
TC_Assert SD_Lines&(sdLaunch + "/sss_telemetry.csv") = sdRows + 1, "5.09  flushing an empty buffer writes nothing"
telemCsvDir = ""
TELEM_Row "enemy_killed", "score=500"
TC_Assert telemCsvBuf = "", "5.10  no buffering when there's no CSV folder"
telemCsvDir = sdLaunch
telemOn = 0
TELEM_Row "enemy_killed", "score=600"
TC_Assert telemCsvBuf = "", "5.11  --no-telem logs nothing"
Print ""

SD_Clean sdBase

Print "=== " + LTrim$(Str$(tcPass + tcFail)) + " tests: " _
    + LTrim$(Str$(tcPass)) + " passed, " + LTrim$(Str$(tcFail)) + " failed ==="
If tcFail > 0 Then System 1 Else System 0
