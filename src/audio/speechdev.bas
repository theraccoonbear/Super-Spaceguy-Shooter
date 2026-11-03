' speechdev.bas -- --speech-dev (dev builds): live A/B of the voice's clarity features (#236).
'
' Works on every screen. I G B H M O toggle IN GL BU FR NL HB (see SPK_FX_* in speech.bas), [ turns
' them all off, or all on when any is off. U says the test line (two boss callouts from gametext.txt)
' at the chosen narration preset, and J cycles that preset (SLOW, NORMAL, FAST). A change applies
' from the next phoneme on. The readout is one column at the left edge: name, key, value.

Dim Shared spdWas(0 To 8) As Integer
Dim Shared spdPreset As Integer

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

Sub SPKD_Line (sdlRow As Integer, sdlTxt As String)
    Dim sdlY As Integer
    sdlY = 82 + sdlRow * 10
    Line (0, sdlY - 1)-(Len(sdlTxt) * 8 + 3, sdlY + 8), _RGBA(0, 0, 0, 200), BF
    Color _RGB(255, 230, 120)
    _PrintString (2, sdlY), sdlTxt
End Sub

Sub SPKD_Frame
    Dim sdfI As Integer, sdfOn As Integer, sdfAll As String
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
End Sub
