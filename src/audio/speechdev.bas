' speechdev.bas -- --speech-dev (dev builds): live A/B of the voice's clarity features and tuning of
' its intonation (#236).
'
' Works on every screen. I G B H M O toggle IN GL BU FR NL HB (see SPK_FX_* in speech.bas), [ turns
' them all off, or all on when any is off. U says the test line (two boss callouts from gametext.txt)
' at the chosen narration preset, and J cycles that preset (SLOW, NORMAL, FAST). A toggle applies
' from the next phoneme on.
' The IN knobs (assets/config/speech.ini): ; and ' select one, , and . nudge it down / up (holding
' repeats), / re-reads the ini from disk. A knob re-plans the pitch of the line being spoken. Copy tuned
' values into speech.ini, or use tools/dev speechtune, which scrubs and replays a line and saves the ini.
' The readout is two short rows in the top-left corner: the selected knob's full name and value, then
' the speed preset and features on (or, for a few seconds after /, the reload result).

Const SPKD_FILE = "assets/config/speech.ini"
Const SPKD_HOLD = 18      ' frames a nudge key is held before it repeats
Const SPKD_REPEAT = 3     ' frames between repeats

Dim Shared spdWas(0 To 11) As Integer
Dim Shared spdSel As Integer   ' the knob the cursor is on (SPK_PK_*)
Const SPKD_ROW_H = 8      ' pixel height of a readout row (the 8x8 font)
Dim Shared spdPreset As Integer
Dim Shared spdHeld(0 To SPK_PK_N - 1, 0 To 1) As Integer
Dim Shared spdMsg As String, spdMsgT As Integer   ' the reload result, shown for spdMsgT frames

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
    spdMsgT = 240
    If sdrP = "" Then spdMsg = "speech.ini not found (run from repo)" : Exit Sub
    If SPK_ProsodyLoad%(_ReadFile$(sdrP)) Then spdMsg = "speech.ini reloaded" Else spdMsg = spkCfgErr
End Sub

' The readout: two 8-pixel rows at the top-left corner on an opaque backing, which is the band the
' crawl fades out (CRAWL_TOP_FADE): text up there is already faded away, so the readout never
' covers crawl text that can still be read, wherever the crawl is.
Sub SPKD_Print (sdpRow As Integer, sdpTxt As String)
    Dim sdpY As Integer
    sdpY = sdpRow * SPKD_ROW_H
    Line (0, sdpY)-(Len(sdpTxt) * 8 + 3, sdpY + SPKD_ROW_H - 1), _RGB(0, 0, 0), BF
    Color _RGB(255, 230, 120)
    _PrintString (2, sdpY), sdpTxt
End Sub

Sub SPKD_Frame
    Dim sdfI As Integer, sdfOn As Integer, sdfV As String, sdfOld As Long
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

    If spdSel = SPK_PK_GPITCH Then sdfV = SPKD_OnOff$(spkPk(spdSel) >= 0.5) Else sdfV = SPK_Num$(spkPk(spdSel))
    If spdMsgT > 0 Then
        spdMsgT = spdMsgT - 1
    Else
        spdMsg = ""
    End If
    sdfOld = _Font
    _Dest 0
    _Font 8
    SPKD_Print 0, SPK_PkName$(spdSel) + ": " + sdfV
    If Len(spdMsg) > 0 Then
        SPKD_Print 1, spdMsg
    Else
        SPKD_Print 1, "Speed " + SPKD_PresetName$(spdPreset) + "  features " + LTrim$(Str$(sdfOn)) + " of " + LTrim$(Str$(SPK_FX_N)) + " on"
    End If
    _Font sdfOld
End Sub

Function SPKD_PresetName$ (sdqP As Integer)
    If sdqP = 1 Then
        SPKD_PresetName$ = "Slow"
    ElseIf sdqP = 3 Then
        SPKD_PresetName$ = "Fast"
    Else
        SPKD_PresetName$ = "Normal"
    End If
End Function
