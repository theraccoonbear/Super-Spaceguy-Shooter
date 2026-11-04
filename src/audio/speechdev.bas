' speechdev.bas -- --speech-dev (dev builds): live A/B of the voice's clarity features and tuning of
' its intonation (#236).
'
' Works on every screen. I G B H M O toggle IN GL BU FR NL HB (see SPK_FX_* in speech.bas), [ turns
' them all off, or all on when any is off. U says the test line (two boss callouts from gametext.txt)
' at the chosen narration preset, and J cycles that preset (SLOW, NORMAL, FAST). A toggle applies
' from the next phoneme on.
' The IN knobs (assets/config/speech.ini) nudge down / up, holding repeats: F1/F2 step, F3/F4
' declination, F5/F6 accent, F7/F8 accents per phrase, F9/F10 final fall, , . rise, ; ' stress pitch
' spread, / ] liquid glide, PgDn/PgUp stress loudness; F12 toggles glide pitch; \ re-reads the ini
' from disk. A knob re-plans the pitch of the line being spoken. Copy tuned values into speech.ini.
' The readout is one column at the left edge: name, keys, value.

Const SPKD_FILE = "assets/config/speech.ini"
Const SPKD_HOLD = 18      ' frames a nudge key is held before it repeats
Const SPKD_REPEAT = 3     ' frames between repeats

Dim Shared spdWas(0 To 8) As Integer
Dim Shared spdPreset As Integer
Dim Shared spdHeld(0 To SPK_PK_N - 1, 0 To 1) As Integer
Dim Shared spdWasF12 As Integer, spdWasRl As Integer
Dim Shared spdMsg As String

Function SPKD_Edge% (sdeI As Integer, sdeUp As Long)
    Dim sdeNow As Integer
    sdeNow = KEY_Down%(sdeUp)
    If sdeUp >= 65 And sdeUp <= 90 Then sdeNow = sdeNow Or KEY_Down%(sdeUp + 32)
    SPKD_Edge% = (sdeNow <> 0 And spdWas(sdeI) = 0)
    spdWas(sdeI) = (sdeNow <> 0)
End Function

Function SPKD_OnOff$ (sdoV As Integer)
    If sdoV Then SPKD_OnOff$ = "on" Else SPKD_OnOff$ = "off"
End Function

' A knob's down (sdnDir 0) or up (1) key: a press nudges once, holding repeats.
Sub SPKD_NudgeKey (sdnK As Integer, sdnDir As Integer, sdnCode As Long)
    If KEY_Down%(sdnCode) Then
        spdHeld(sdnK, sdnDir) = spdHeld(sdnK, sdnDir) + 1
        If spdHeld(sdnK, sdnDir) = 1 Or (spdHeld(sdnK, sdnDir) > SPKD_HOLD And (spdHeld(sdnK, sdnDir) - SPKD_HOLD) Mod SPKD_REPEAT = 0) Then
            SPK_PkSet sdnK, spkPk(sdnK) + (2 * sdnDir - 1) * spkPkInc(sdnK)
        End If
    Else
        spdHeld(sdnK, sdnDir) = 0
    End If
End Sub

Function SPKD_Path$ ()
    Dim sdpA As String
    sdpA = _StartDir$ + "/" + SPKD_FILE
    If _FileExists(sdpA) Then SPKD_Path$ = sdpA : Exit Function
    sdpA = _Cwd$ + "/../" + SPKD_FILE
    If _FileExists(sdpA) Then SPKD_Path$ = sdpA : Exit Function
    SPKD_Path$ = ""
End Function

Sub SPKD_Reload ()
    Dim sdrP As String
    sdrP = SPKD_Path$
    If sdrP = "" Then spdMsg = "speech.ini not found (run from repo)" : Exit Sub
    If SPK_ProsodyLoad%(_ReadFile$(sdrP)) Then spdMsg = "reloaded" Else spdMsg = spkCfgErr
End Sub

Sub SPKD_Line (sdlRow As Integer, sdlTxt As String)
    Dim sdlY As Integer
    sdlY = 4 + sdlRow * 10
    Line (0, sdlY - 1)-(Len(sdlTxt) * 8 + 3, sdlY + 8), _RGBA(0, 0, 0, 200), BF
    Color _RGB(255, 230, 120)
    _PrintString (2, sdlY), sdlTxt
End Sub

Function SPKD_Num$ (sdnV As Single)
    Dim sdnS As String
    sdnS = LTrim$(Str$(Int(sdnV * 100 + 0.5) / 100))
    If Left$(sdnS, 1) = "." Then sdnS = "0" + sdnS
    SPKD_Num$ = sdnS
End Function

Sub SPKD_Frame
    Dim sdfI As Integer, sdfOn As Integer, sdfAll As String, sdfK As Integer
    If cliSpeechDev = 0 Then Exit Sub
    If spdPreset < 1 Or spdPreset > 3 Then spdPreset = settingNarrSpeed
    If spdPreset < 1 Or spdPreset > 3 Then spdPreset = 2

    If SPKD_Edge%(0, 71) Then spkFx(SPK_FX_GL) = Not spkFx(SPK_FX_GL)
    If SPKD_Edge%(1, 66) Then spkFx(SPK_FX_BU) = Not spkFx(SPK_FX_BU)
    If SPKD_Edge%(2, 72) Then spkFx(SPK_FX_FR) = Not spkFx(SPK_FX_FR)
    If SPKD_Edge%(3, 77) Then spkFx(SPK_FX_NL) = Not spkFx(SPK_FX_NL)
    If SPKD_Edge%(4, 79) Then spkFx(SPK_FX_HB) = Not spkFx(SPK_FX_HB)
    If SPKD_Edge%(5, 73) Then spkFx(SPK_FX_IN) = Not spkFx(SPK_FX_IN)
    sdfOn = 0
    For sdfI = 0 To SPK_FX_N - 1
        If spkFx(sdfI) Then sdfOn = sdfOn + 1
    Next sdfI
    If SPKD_Edge%(6, 91) Then
        For sdfI = 0 To SPK_FX_N - 1 : spkFx(sdfI) = (sdfOn < SPK_FX_N) : Next sdfI
        If sdfOn < SPK_FX_N Then sdfOn = SPK_FX_N Else sdfOn = 0
    End If
    If SPKD_Edge%(7, 74) Then spdPreset = spdPreset Mod 3 + 1
    If SPKD_Edge%(8, 85) Then
        SPK_Say GTEXT_Get$("speech_boss_phase2") + " " + GTEXT_Get$("speech_boss_phase3")
        SPK_SetPreset spdPreset
    End If

    ' knobs: F1..F10 are 15104 + 256 * (n - 1)
    For sdfK = 0 To 4
        SPKD_NudgeKey sdfK, 0, 15104 + 512 * sdfK
        SPKD_NudgeKey sdfK, 1, 15360 + 512 * sdfK
    Next sdfK
    SPKD_NudgeKey SPK_PK_RISE, 0, 44 : SPKD_NudgeKey SPK_PK_RISE, 1, 46
    SPKD_NudgeKey SPK_PK_SPREAD, 0, 59 : SPKD_NudgeKey SPK_PK_SPREAD, 1, 39
    SPKD_NudgeKey SPK_PK_LIQ, 0, 47 : SPKD_NudgeKey SPK_PK_LIQ, 1, 93
    SPKD_NudgeKey SPK_PK_LOUD, 0, 20736 : SPKD_NudgeKey SPK_PK_LOUD, 1, 18688
    If KEY_Down%(34304) And spdWasF12 = 0 Then SPK_PkSet SPK_PK_GPITCH, 1 - spkPk(SPK_PK_GPITCH)
    spdWasF12 = KEY_Down%(34304)
    If KEY_Down%(92) And spdWasRl = 0 Then SPKD_Reload
    spdWasRl = KEY_Down%(92)

    If sdfOn = SPK_FX_N Then
        sdfAll = "on"
    ElseIf sdfOn = 0 Then
        sdfAll = "off"
    Else
        sdfAll = "mix"
    End If
    _Dest 0
    SPKD_Line 0, "GL G " + SPKD_OnOff$(spkFx(SPK_FX_GL))
    SPKD_Line 1, "BU B " + SPKD_OnOff$(spkFx(SPK_FX_BU))
    SPKD_Line 2, "FR H " + SPKD_OnOff$(spkFx(SPK_FX_FR))
    SPKD_Line 3, "NL M " + SPKD_OnOff$(spkFx(SPK_FX_NL))
    SPKD_Line 4, "HB O " + SPKD_OnOff$(spkFx(SPK_FX_HB))
    SPKD_Line 5, "IN I " + SPKD_OnOff$(spkFx(SPK_FX_IN))
    SPKD_Line 6, "AL [ " + sdfAll
    SPKD_Line 7, "PR J " + Mid$("SLONRMFST", spdPreset * 3 - 2, 3)
    SPKD_Line 8, "SA U " + SPKD_OnOff$(SPK_IsPlaying%)
    SPKD_Line 9, "ST F1/F2 " + SPKD_Num$(spkPk(SPK_PK_STEP))
    SPKD_Line 10, "DC F3/F4 " + SPKD_Num$(spkPk(SPK_PK_DECL))
    SPKD_Line 11, "AC F5/F6 " + SPKD_Num$(spkPk(SPK_PK_ACC))
    SPKD_Line 12, "AN F7/F8 " + SPKD_Num$(spkPk(SPK_PK_NACC))
    SPKD_Line 13, "FF F9/F10 " + SPKD_Num$(spkPk(SPK_PK_FALL))
    SPKD_Line 14, "RS ,/. " + SPKD_Num$(spkPk(SPK_PK_RISE))
    SPKD_Line 15, "SS ;/' " + SPKD_Num$(spkPk(SPK_PK_SPREAD))
    SPKD_Line 16, "LG //] " + SPKD_Num$(spkPk(SPK_PK_LIQ))
    SPKD_Line 17, "LD PD/PU " + SPKD_Num$(spkPk(SPK_PK_LOUD))
    SPKD_Line 18, "GP F12 " + SPKD_OnOff$(spkPk(SPK_PK_GPITCH) >= 0.5)
    If Len(spdMsg) > 0 Then SPKD_Line 19, "RL \ " + spdMsg Else SPKD_Line 19, "RL \ -"
End Sub
