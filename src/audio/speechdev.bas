' speechdev.bas -- --speech-dev (dev builds): live A/B of the voice's clarity features and tuning of
' its intonation (#236).
'
' Works on every screen. I G B H M O toggle IN GL BU FR NL HB (see SPK_FX_* in speech.bas), [ turns
' them all off, or all on when any is off. U says the test line (two boss callouts from gametext.txt)
' at the chosen narration preset, and J cycles that preset (SLOW, NORMAL, FAST). A toggle applies
' from the next phoneme on.
' The IN knobs (assets/config/speech.ini): ; and ' move the cursor through them (the selected line is
' highlighted and marked <), , and . nudge it down / up (holding repeats), / re-reads the ini from disk. A knob re-plans the pitch of the line being spoken. Copy tuned values into speech.ini.
' The readout is one column at the left edge: name, keys, value.

Const SPKD_FILE = "assets/config/speech.ini"
Const SPKD_HOLD = 18      ' frames a nudge key is held before it repeats
Const SPKD_REPEAT = 3     ' frames between repeats

Dim Shared spdWas(0 To 11) As Integer
Dim Shared spdSel As Integer   ' the knob the cursor is on (SPK_PK_*)
Const SPKD_NAMES = "STDCACANFFRSSSGPLGLD"   ' readout names in SPK_PK_* order
Dim Shared spdPreset As Integer
Dim Shared spdHeld(0 To SPK_PK_N - 1, 0 To 1) As Integer
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

Sub SPKD_Line (sdlRow As Integer, sdlTxt As String, sdlSel As Integer)
    Dim sdlY As Integer
    sdlY = 4 + sdlRow * 10
    Line (0, sdlY - 1)-(Len(sdlTxt) * 8 + 3, sdlY + 8), _RGBA(0, 0, 0, 200), BF
    If sdlSel Then Color _RGB(120, 230, 255) Else Color _RGB(255, 230, 120)
    _PrintString (2, sdlY), sdlTxt
End Sub

Function SPKD_Num$ (sdnV As Single)
    Dim sdnS As String
    sdnS = LTrim$(Str$(Int(sdnV * 100 + 0.5) / 100))
    If Left$(sdnS, 1) = "." Then sdnS = "0" + sdnS
    SPKD_Num$ = sdnS
End Function

Sub SPKD_Frame
    Dim sdfI As Integer, sdfOn As Integer, sdfAll As String, sdfK As Integer, sdfV As String
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

    ' knobs: ; ' move the cursor, , . nudge the selected knob (holding repeats), / re-reads the ini
    If SPKD_Edge%(9, 59) Then spdSel = (spdSel + SPK_PK_N - 1) Mod SPK_PK_N
    If SPKD_Edge%(10, 39) Then spdSel = (spdSel + 1) Mod SPK_PK_N
    SPKD_NudgeKey spdSel, 0, 44
    SPKD_NudgeKey spdSel, 1, 46
    If SPKD_Edge%(11, 47) Then SPKD_Reload

    If sdfOn = SPK_FX_N Then
        sdfAll = "on"
    ElseIf sdfOn = 0 Then
        sdfAll = "off"
    Else
        sdfAll = "mix"
    End If
    _Dest 0
    SPKD_Line 0, "GL G " + SPKD_OnOff$(spkFx(SPK_FX_GL)), 0
    SPKD_Line 1, "BU B " + SPKD_OnOff$(spkFx(SPK_FX_BU)), 0
    SPKD_Line 2, "FR H " + SPKD_OnOff$(spkFx(SPK_FX_FR)), 0
    SPKD_Line 3, "NL M " + SPKD_OnOff$(spkFx(SPK_FX_NL)), 0
    SPKD_Line 4, "HB O " + SPKD_OnOff$(spkFx(SPK_FX_HB)), 0
    SPKD_Line 5, "IN I " + SPKD_OnOff$(spkFx(SPK_FX_IN)), 0
    SPKD_Line 6, "AL [ " + sdfAll, 0
    SPKD_Line 7, "PR J " + Mid$("SLONRMFST", spdPreset * 3 - 2, 3), 0
    SPKD_Line 8, "SA U " + SPKD_OnOff$(SPK_IsPlaying%), 0
    SPKD_Line 9, "KN ;' " + Mid$(SPKD_NAMES, spdSel * 2 + 1, 2), 0
    For sdfK = 0 To SPK_PK_N - 1
        If sdfK = SPK_PK_GPITCH Then sdfV = SPKD_OnOff$(spkPk(sdfK) >= 0.5) Else sdfV = SPKD_Num$(spkPk(sdfK))
        If sdfK = spdSel Then sdfV = sdfV + " <"
        SPKD_Line 10 + sdfK, Mid$(SPKD_NAMES, sdfK * 2 + 1, 2) + " ,. " + sdfV, (sdfK = spdSel)
    Next sdfK
    If Len(spdMsg) > 0 Then SPKD_Line 20, "RL / " + spdMsg, 0 Else SPKD_Line 20, "RL / -", 0
End Sub
