' settings_test.bas -- SETTINGS_Parse / SETTINGS_Serialize$ (settingslogic.bas, #291)
'
' The text form of sss_settings.ini, without touching a file: a round trip through every saved
' value, missing keys (the variable keeps its value), garbage values (clamped or ignored), the
' older file shapes still in players' folders, line endings, and the keys= / padbind= lines
' that go through E3D_BindsLoadLine%.
'
' Build: ./tools/buildqb tests/settings_test.bas
' Run:   builds/settings_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT
$EMBED:'assets/config/difficulty.ini':'CFGDIFFICULTY'

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'

Const VERSION$ = "0.0.0-test"
Const BUILD_KIND$ = "dev"

Dim Shared DB_URL As String
Dim Shared DB_KEY As String
Function DBG_StateName$ (s As Integer) : DBG_StateName$ = "GS_TEST" : End Function

Sub DBG_Print (msg As String) : End Sub
Sub HTTP_Post (u As String, k As String, b As String, t As String) : End Sub
Sub HTTP_Get  (u As String, k As String, t As String) : End Sub
Function JSON_Obj$ (s As String) : JSON_Obj$ = "{" + s + "}" : End Function
Function JSON_S$   (k As String, v As String) : JSON_S$ = k + ":" + v : End Function
Function JSON_N$   (k As String, v As String) : JSON_N$ = k + ":" + v : End Function

'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/sys/settingslogic.bas'

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

Function ST_Near% (stA As Single, stB As Single)
    ST_Near% = (Abs(stA - stB) < 0.0005)
End Function

' Every saved value to a known state, so a parse that skips a key shows.
Sub ST_Reset
    Dim stI As Integer
    volMusic = 0.5 : volSfx = 0.5 : volSpeech = 0.5
    settingNarration = 1 : settingNarrSpeed = 2 : settingFullscreen = 0
    settingDifficulty = DLV_Default$ : highScore = 0 : settingTutorialDone = 0
    telemPlayerID = "" : leaderboardPlayerID = "" : telemPlayerName = "" : telemConsent = 0
    camF.orbitTheta = 0 : camF.orbitPhi = CAM_DEFAULT_PHI : camF.orbitR = CAM_DEFAULT_R : camF.angleLocked = 0
    E3D_KeyDefaults
    For stI = 1 To padSavedN
        padSavedName$(stI) = "" : padSavedBinds$(stI) = ""
    Next stI
    padSavedN = 0
End Sub

Dim stLf As String, stId As String, stId2 As String, stText As String, stBack As String
Dim stKeys As String, stLine As String, stI As Integer

stLf = Chr$(10)
stId = String$(32, "a")
stId2 = String$(36, "b")

Print "=== settings_test ==="
Print ""

cfgDifficulty = CFG_Parse$(_EMBEDDED$("CFGDIFFICULTY"))
TC_Assert DLV_Load% <> 0, "0.01  difficulty.ini loads " + dlvLoadErr

Print "--- 1. round trip ---"
ST_Reset
volMusic = 0.3 : volSfx = 0.7 : volSpeech = 0.1
settingNarration = 1 : settingNarrSpeed = 3 : settingFullscreen = 1
settingDifficulty = "hard" : highScore = 123456 : settingTutorialDone = -1
telemPlayerID = stId : leaderboardPlayerID = stId2 : telemPlayerName = "ACE" : telemConsent = -1
camF.angleLocked = -1 : camF.orbitPhi = 0.25 : camF.orbitR = 9.5
keyBind(E3D_ACT_FIRE) = E3D_KEY_ENTER
padSavedN = 1 : padSavedName$(1) = "PAD|X" : padSavedBinds$(1) = "1,2,3"
stText = SETTINGS_Serialize$
stKeys = E3D_BindsStr$(E3D_BIND_KEY)

ST_Reset
SETTINGS_Parse stText
TC_Assert ST_Near%(volMusic, 0.3) And ST_Near%(volSfx, 0.7) And ST_Near%(volSpeech, 0.1), "1.01  volumes survive"
TC_Assert settingNarration = 1 And settingNarrSpeed = 3 And settingFullscreen = 1, "1.02  narration, speed and fullscreen survive"
TC_Assert settingDifficulty = "hard", "1.03  difficulty survives"
TC_Assert highScore = 123456, "1.04  high score survives"
TC_Assert settingTutorialDone = -1, "1.05  tutorial_done survives"
TC_Assert telemPlayerID = stId And leaderboardPlayerID = stId2, "1.06  player ids survive"
TC_Assert telemPlayerName = "ACE" And telemConsent <> 0, "1.07  callsign and consent survive"
TC_Assert camF.angleLocked <> 0 And ST_Near%(camF.orbitPhi, 0.25) And ST_Near%(camF.orbitR, 9.5), "1.08  locked camera survives"
TC_Assert E3D_BindsStr$(E3D_BIND_KEY) = stKeys, "1.09  key bindings survive"
TC_Assert padSavedN = 1 And padSavedName$(1) = "PAD|X" And padSavedBinds$(1) = "1,2,3", "1.10  per-pad bindings survive (name may hold a |)"
stBack = SETTINGS_Serialize$
TC_Assert stBack = stText, "1.11  serialize -> parse -> serialize is stable"
TC_Assert Right$(stText, 1) = stLf And InStr(stText, Chr$(13)) = 0, "1.12  LF-terminated lines"

ST_Reset
stText = SETTINGS_Serialize$
TC_Assert InStr(stText, "cam_phi=") = 0 And InStr(stText, "cam_r=") = 0, "1.13  unlocked camera writes no cam_ lines"
TC_Assert InStr(stText, "telem_consent") = 0 And InStr(stText, "player_name") = 0 And InStr(stText, "player_id") = 0, "1.14  empty id, name and consent write no lines"
TC_Assert Left$(stText, 10) = "music=0.5" + stLf, "1.15  music comes first"
Print ""

Print "--- 2. missing keys ---"
ST_Reset
volMusic = 0.9 : highScore = 77 : settingDifficulty = "easy" : telemPlayerName = "KEEP"
SETTINGS_Parse "sfx=0.2" + stLf
TC_Assert ST_Near%(volSfx, 0.2), "2.01  the key present is read"
TC_Assert ST_Near%(volMusic, 0.9) And highScore = 77 And settingDifficulty = "easy" And telemPlayerName = "KEEP", "2.02  keys not in the file keep their value"
TC_Assert settingTutorialDone = -1, "2.03  a file with no tutorial_done counts as done"
TC_Assert camF.angleLocked = 0 And ST_Near%(camF.orbitPhi, CAM_DEFAULT_PHI) And ST_Near%(camF.orbitR, CAM_DEFAULT_R), "2.04  no cam lines: default unlocked orbit"
ST_Reset
camF.angleLocked = -1 : camF.orbitPhi = 1 : camF.orbitR = 3
SETTINGS_Parse ""
TC_Assert camF.angleLocked = 0 And ST_Near%(camF.orbitPhi, CAM_DEFAULT_PHI), "2.05  empty text resets the camera"
ST_Reset
SETTINGS_Parse "cam_r=4" + stLf
TC_Assert ST_Near%(camF.orbitR, 4) And camF.angleLocked = 0, "2.06  cam_r alone does not lock the angle"
Print ""

Print "--- 3. garbage values ---"
ST_Reset
SETTINGS_Parse "music=7" + stLf + "sfx=-3" + stLf + "speech=abc" + stLf
TC_Assert ST_Near%(volMusic, 1) And ST_Near%(volSfx, 0) And ST_Near%(volSpeech, 0), "3.01  volumes clamp to 0..1, text reads as 0"
ST_Reset
SETTINGS_Parse "narration_speed=9" + stLf
TC_Assert settingNarrSpeed = 2, "3.02  narration speed out of range: NORMAL"
ST_Reset
SETTINGS_Parse "narration_speed=0" + stLf
TC_Assert settingNarrSpeed = 2, "3.03  narration speed 0: NORMAL"
ST_Reset
SETTINGS_Parse "difficulty=nightmare" + stLf
TC_Assert settingDifficulty = DLV_Default$, "3.04  unknown difficulty: the default"
ST_Reset
SETTINGS_Parse "cam_phi=9" + stLf + "cam_r=0.01" + stLf
TC_Assert ST_Near%(camF.orbitPhi, 1.5) And ST_Near%(camF.orbitR, 0.5) And camF.angleLocked <> 0, "3.05  camera angle and distance clamp"
ST_Reset
SETTINGS_Parse "cam_phi=-9" + stLf
TC_Assert ST_Near%(camF.orbitPhi, -1.5), "3.06  camera angle clamps low"
ST_Reset
SETTINGS_Parse "highscore=-5" + stLf
TC_Assert highScore = 0, "3.07  negative high score ignored"
ST_Reset
SETTINGS_Parse "player_id=short" + stLf + "lb_player_id=" + stLf + "player_name=" + String$(UN_MAX_LEN + 1, "x") + stLf
TC_Assert telemPlayerID = "" And leaderboardPlayerID = "" And telemPlayerName = "", "3.08  short ids and an over-long or empty name ignored"
ST_Reset
SETTINGS_Parse "player_name=" + String$(UN_MAX_LEN, "x") + stLf
TC_Assert Len(telemPlayerName) = UN_MAX_LEN, "3.09  a name of exactly UN_MAX_LEN is kept"
ST_Reset
SETTINGS_Parse "no equals sign here" + stLf + "=novalue" + stLf + "mystery=1" + stLf + "fullscreen=1" + stLf
TC_Assert settingFullscreen = 1, "3.10  junk lines and unknown keys are skipped, later lines still read"
ST_Reset
SETTINGS_Parse "telem_consent=1" + stLf + "narration=0.4" + stLf
TC_Assert telemConsent <> 0 And settingNarration = 0, "3.11  consent on; narration rounds to a flag"
ST_Reset
SETTINGS_Parse "tutorial_done=0" + stLf
TC_Assert settingTutorialDone = 0, "3.12  tutorial_done=0 stays 0"
Print ""

Print "--- 4. older files ---"
ST_Reset
SETTINGS_Parse "music=0.4" + stLf + "sfx=0.6" + stLf + "speech=0.8" + stLf + "narration=1" + stLf + "fullscreen=0" + stLf
TC_Assert ST_Near%(volMusic, 0.4) And ST_Near%(volSfx, 0.6) And ST_Near%(volSpeech, 0.8), "4.01  volumes-only file (before difficulty, ids, bindings) loads"
TC_Assert settingNarrSpeed = 2 And settingDifficulty = DLV_Default$ And settingTutorialDone = -1, "4.02  its missing keys keep the defaults; tutorial counts as done"
ST_Reset
SETTINGS_Parse "music=0.4" + stLf + "highscore=900" + stLf + "player_id=" + stId + stLf + "cam_phi=0.3" + stLf + "cam_r=7" + stLf
TC_Assert highScore = 900 And telemPlayerID = stId And camF.angleLocked <> 0, "4.03  file from before narration_speed / difficulty / keys loads"
ST_Reset
stKeys = E3D_BindsStr$(E3D_BIND_KEY)
SETTINGS_Parse "music=0.4" + stLf + "keys=0" + stLf
TC_Assert Mid$(E3D_BindsStr$(E3D_BIND_KEY), InStr(E3D_BindsStr$(E3D_BIND_KEY), ",")) = Mid$(stKeys, InStr(stKeys, ",")), "4.04  a keys= line shorter than the action list leaves the rest alone"
ST_Reset
stKeys = E3D_BindsStr$(E3D_BIND_KEY)
SETTINGS_Parse "music=0.4" + stLf
TC_Assert E3D_BindsStr$(E3D_BIND_KEY) = stKeys And padSavedN = 0, "4.05  no binding lines: bindings stay at their defaults"
Print ""

Print "--- 5. line endings ---"
ST_Reset
SETTINGS_Parse "music=0.2" + Chr$(13) + stLf + "sfx=0.4" + Chr$(13) + stLf + "speech=0.6"
TC_Assert ST_Near%(volMusic, 0.2) And ST_Near%(volSfx, 0.4) And ST_Near%(volSpeech, 0.6), "5.01  CRLF and a last line with no newline"
ST_Reset
SETTINGS_Parse "music=0.2" + Chr$(13) + "sfx=0.4" + Chr$(13)
TC_Assert ST_Near%(volMusic, 0.2) And ST_Near%(volSfx, 0.4), "5.02  bare CR separates lines"
ST_Reset
SETTINGS_Parse stLf + stLf + "music=0.2" + stLf + stLf
TC_Assert ST_Near%(volMusic, 0.2), "5.03  blank lines are skipped"
Print ""

Print "--- 6. bindings lines (E3D_BindsLoadLine%) ---"
ST_Reset
stLine = E3D_BindsStr$(E3D_BIND_KEY)
TC_Assert E3D_BindsLoadLine%("keys", stLine) = -1, "6.01  keys is a binding line"
TC_Assert E3D_BindsLoadLine%("music", "0.5") = 0, "6.02  other keys are not"
ST_Reset
SETTINGS_Parse "padbind=Pad One|4,5,6" + stLf + "padbind=Pad Two|7,8" + stLf + "padbind=Pad One|9,9" + stLf
TC_Assert padSavedN = 2, "6.03  two pads saved; a repeat updates the first"
TC_Assert padSavedName$(1) = "Pad One" And padSavedBinds$(1) = "9,9" And padSavedName$(2) = "Pad Two", "6.04  names and binds kept per pad"
ST_Reset
SETTINGS_Parse "padbind=nobar" + stLf + "padbind=|1,2" + stLf
TC_Assert padSavedN = 0, "6.05  a padbind without a name or a bar is dropped"
ST_Reset
stKeys = E3D_BindsStr$(E3D_BIND_KEY)
SETTINGS_Parse "keys=" + stLf
TC_Assert E3D_BindsStr$(E3D_BIND_KEY) = stKeys, "6.06  an empty keys= line leaves the bindings alone"
ST_Reset
stText = ""
For stI = 1 To E3D_PAD_SAVED_MAX + 2
    stText = stText + "padbind=P" + LTrim$(Str$(stI)) + "|1" + stLf
Next stI
SETTINGS_Parse stText
TC_Assert padSavedN = E3D_PAD_SAVED_MAX, "6.07  pads past the table size are dropped"
Print ""

Print "=== " + LTrim$(Str$(tcPass + tcFail)) + " tests: " _
    + LTrim$(Str$(tcPass)) + " passed, " + LTrim$(Str$(tcFail)) + " failed ==="
If tcFail > 0 Then System 1 Else System 0
