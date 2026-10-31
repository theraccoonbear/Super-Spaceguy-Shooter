' cam_default_test.bas -- issue #311: the fresh-settings camera angle
'
' The real SETTINGS_LoadFile (settingsio.bas): with no settings file the orbit
' starts at CAM_DEFAULT_PHI / CAM_DEFAULT_R and stays unlocked (the chase cam,
' framed by CAM_CHASE_X/Y, shows that same angle); a saved cam_phi / cam_r
' still wins. The CAM_* stubs below are checked against src/sys/dims.bas.
'
' Build: ./tools/buildqb tests/cam_default_test.bas
' Run:   builds/cam_default_test   (from the repo root; exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT
$EMBED:'assets/config/difficulty.ini':'CFGDIFFICULTY'

Const VERSION$ = "0.0.0-test"
Const BUILD_KIND$ = "dev"
Const UN_MAX_LEN = 32
Const CAM_DEFAULT_PHI = 0.1545
Const CAM_DEFAULT_R   = 6.80
Const CAM_CHASE_X     = CAM_DEFAULT_R * COS(CAM_DEFAULT_PHI)
Const CAM_CHASE_Y     = CAM_DEFAULT_R * SIN(CAM_DEFAULT_PHI)

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

Sub DBG_Print (msg As String) : End Sub
Sub HTTP_Post (u As String, k As String, b As String, t As String) : End Sub
Sub HTTP_Get  (u As String, k As String, t As String) : End Sub
Function JSON_Obj$ (s As String) : JSON_Obj$ = "{" + s + "}" : End Function
Function JSON_S$   (k As String, v As String) : JSON_S$ = k + ":" + v : End Function
Function JSON_N$   (k As String, v As String) : JSON_N$ = k + ":" + v : End Function
Sub E3D_BindsWrite (bwFH As Integer) : End Sub
Function E3D_BindsLoadLine% (blKey As String, blRaw As String) : E3D_BindsLoadLine% = 0 : End Function
Sub E3D_PadReselect : End Sub

'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/telemetry.bas'
'$INCLUDE:'../src/sys/settingsio.bas'

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

Function CD_Near% (cdA As Single, cdB As Single)
    CD_Near% = (Abs(cdA - cdB) < 0.0005)
End Function

' The right-hand side of "CONST <cdName> = ..." in src/sys/dims.bas, or "" if absent.
Function CD_DimsConst$ (cdName As String)
    Dim cdFH As Integer, cdLine As String, cdEq As Integer
    CD_DimsConst$ = ""
    If _FileExists(_StartDir$ + "/src/sys/dims.bas") = 0 Then Exit Function
    cdFH = FreeFile
    Open _StartDir$ + "/src/sys/dims.bas" For Input As #cdFH
    Do While Not EOF(cdFH)
        Line Input #cdFH, cdLine
        cdLine = LTrim$(cdLine)
        If UCase$(Left$(cdLine, 6)) = "CONST " Then
            cdEq = InStr(cdLine, "=")
            If cdEq > 0 Then
                If RTrim$(Mid$(cdLine, 7, cdEq - 7)) = cdName Then CD_DimsConst$ = LTrim$(RTrim$(Mid$(cdLine, cdEq + 1)))
            End If
        End If
    Loop
    Close #cdFH
End Function

Print "=== cam_default_test ==="
Print ""

Dim cdPath As String, cdFH As Integer
cdPath = _StartDir$ + "/cam_default_test_settings.ini"
If _FileExists(cdPath) Then Kill cdPath

Print "--- 1. constants ---"
TC_Assert CD_DimsConst$("CAM_DEFAULT_PHI") = "0.1545", "1.01  dims.bas CAM_DEFAULT_PHI = 0.1545 (" + CD_DimsConst$("CAM_DEFAULT_PHI") + ")"
TC_Assert CD_DimsConst$("CAM_DEFAULT_R") = "6.80", "1.02  dims.bas CAM_DEFAULT_R = 6.80 (" + CD_DimsConst$("CAM_DEFAULT_R") + ")"
TC_Assert CD_DimsConst$("CAM_CHASE_X") = "CAM_DEFAULT_R * COS(CAM_DEFAULT_PHI)", "1.03  dims.bas CAM_CHASE_X derives from the default angle"
TC_Assert CD_DimsConst$("CAM_CHASE_Y") = "CAM_DEFAULT_R * SIN(CAM_DEFAULT_PHI)", "1.04  dims.bas CAM_CHASE_Y derives from the default angle"
TC_Assert CD_Near%(_Atan2(CAM_CHASE_Y, CAM_CHASE_X), CAM_DEFAULT_PHI), "1.05  chase cam elevation = CAM_DEFAULT_PHI"
TC_Assert CD_Near%(Sqr(CAM_CHASE_X * CAM_CHASE_X + CAM_CHASE_Y * CAM_CHASE_Y), CAM_DEFAULT_R), "1.06  chase cam distance = CAM_DEFAULT_R"
Print ""

Print "--- 2. fresh settings ---"
camF.orbitPhi = 1.2 : camF.orbitR = 2 : camF.orbitTheta = 0 : camF.angleLocked = -1
SETTINGS_LoadFile cdPath
TC_Assert CD_Near%(camF.orbitPhi, CAM_DEFAULT_PHI), "2.01  orbitPhi = CAM_DEFAULT_PHI (" + LTrim$(Str$(camF.orbitPhi)) + ")"
TC_Assert CD_Near%(camF.orbitR, CAM_DEFAULT_R), "2.02  orbitR = CAM_DEFAULT_R (" + LTrim$(Str$(camF.orbitR)) + ")"
TC_Assert CD_Near%(camF.orbitTheta, _Pi(1.0)), "2.03  orbitTheta = pi (behind the ship)"
TC_Assert camF.angleLocked = 0, "2.04  not locked: the chase cam shows the default angle"
Print ""

Print "--- 3. saved angle wins ---"
cdFH = FreeFile
Open cdPath For Output As #cdFH
Print #cdFH, "music=0.5"
Print #cdFH, "cam_phi=0.4"
Print #cdFH, "cam_r=9.25"
Close #cdFH
SETTINGS_LoadFile cdPath
TC_Assert CD_Near%(camF.orbitPhi, 0.4), "3.01  saved cam_phi wins (" + LTrim$(Str$(camF.orbitPhi)) + ")"
TC_Assert CD_Near%(camF.orbitR, 9.25), "3.02  saved cam_r wins (" + LTrim$(Str$(camF.orbitR)) + ")"
TC_Assert camF.angleLocked = -1, "3.03  saved angle is locked in"
TC_Assert CD_Near%(volMusic, 0.5), "3.04  other settings still load"

Kill cdPath
SETTINGS_LoadFile cdPath
TC_Assert CD_Near%(camF.orbitPhi, CAM_DEFAULT_PHI) And camF.angleLocked = 0, "3.05  settings file gone: back to the default"
Print ""

Print "--- 4. difficulty level (#102) ---"
Dim cdLv As Integer, cdLvl As String, cdAll As Integer, cdReal As String, cdLine As String, cdSeen As Integer
cfgDifficulty = CFG_Parse$(_EMBEDDED$("CFGDIFFICULTY"))
TC_Assert DLV_Load% <> 0, "4.01  difficulty.ini loads " + dlvLoadErr
cdFH = FreeFile
Open cdPath For Output As #cdFH
Print #cdFH, "difficulty=hard"
Close #cdFH
settingDifficulty = ""
SETTINGS_LoadFile cdPath
TC_Assert settingDifficulty = "hard", "4.02  difficulty=hard loads (" + settingDifficulty + ")"
Open cdPath For Output As #cdFH
Print #cdFH, "difficulty=nightmare"
Close #cdFH
SETTINGS_LoadFile cdPath
TC_Assert settingDifficulty = "normal", "4.03  an unknown level loads as the default (" + settingDifficulty + ")"
Open cdPath For Output As #cdFH
Print #cdFH, "difficulty=1"
Close #cdFH
SETTINGS_LoadFile cdPath
TC_Assert settingDifficulty = "normal" And CD_Near%(volMusic, 0.5), "4.04  a number isn't a level, and doesn't reach the volume settings"
Kill cdPath

cdReal = cdPath
cdAll = -1
For cdLv = 1 To DLV_Count%
    cdLvl = DLV_LevelAt$(cdLv)
    settingDifficulty = cdLvl
    SETTINGS_SaveFile cdReal
    cdSeen = 0
    Open cdReal For Input As #cdFH
    Do While Not EOF(cdFH)
        Line Input #cdFH, cdLine
        If cdLine = "difficulty=" + cdLvl Then cdSeen = cdSeen + 1
    Loop
    Close #cdFH
    settingDifficulty = ""
    SETTINGS_LoadFile cdReal
    If settingDifficulty <> cdLvl Or cdSeen <> 1 Then cdAll = 0 : Print "  " + cdLvl + " came back as '" + settingDifficulty + "'"
Next cdLv
TC_Assert cdAll, "4.05  every level saves as difficulty=<level> and loads back"
settingDifficulty = ""
SETTINGS_SaveFile cdReal
SETTINGS_LoadFile cdReal
TC_Assert settingDifficulty = "normal", "4.06  no level chosen yet: saved and loaded as the default"
Kill cdReal
Print ""

Print "=== " + LTrim$(Str$(tcPass + tcFail)) + " tests: " _
    + LTrim$(Str$(tcPass)) + " passed, " + LTrim$(Str$(tcFail)) + " failed ==="
If tcFail > 0 Then System 1 Else System 0
