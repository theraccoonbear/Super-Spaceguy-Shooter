' aimdev.bas -- --aim-dev (dev builds only): tune the shot-direction values (#199) in play without a rebuild.
'   1 / 2   player_nose_blend down / up, 0.1 a step (0 to 1)
'   3 / 4   enemy_fire_arc_deg down / up, 15 degrees a step (15 to 360)
'   5       re-read assets/config/waves.ini from disk (launch folder, else the repository next to the
'           executable) and apply its two aim values
' Changes are live only, never written back; the readout shows the values to copy into waves.ini.
' A new run keeps them (aimDevLive). Local variable prefix: adv*

Const ADV_NOTE_FRAMES = 30
Const ADV_FILE = "assets/config/waves.ini"
Const ADV_ROWS = 6

Dim Shared advMsg As String
Dim Shared advErr As Integer
Dim Shared advAt As Long
Dim Shared advWas1 As Integer, advWas2 As Integer, advWas3 As Integer, advWas4 As Integer, advWas5 As Integer

Function ADV_Path$ ()
    Dim advpA As String
    advpA = _StartDir$ + "/" + ADV_FILE
    If _FileExists(advpA) Then ADV_Path$ = advpA : Exit Function
    advpA = _Cwd$ + "/../" + ADV_FILE
    If _FileExists(advpA) Then ADV_Path$ = advpA : Exit Function
    ADV_Path$ = ""
End Function

Sub ADV_Reload ()
    Dim advrPath As String, advrCfg As String, advrB As String, advrA As String
    advrPath = ADV_Path$
    If advrPath = "" Then advMsg = "5: " + ADV_FILE + " not found (launch from the repository folder)" : advErr = -1 : Exit Sub
    advrCfg = CFG_Parse$(_ReadFile$(advrPath))
    advrB = CFG_Get$(advrCfg, "player_nose_blend")
    advrA = CFG_Get$(advrCfg, "enemy_fire_arc_deg")
    If advrB = "" Then advMsg = ADV_FILE + ": player_nose_blend is missing" : advErr = -1 : Exit Sub
    If advrA = "" Then advMsg = ADV_FILE + ": enemy_fire_arc_deg is missing" : advErr = -1 : Exit Sub
    If AIM_Set%(Val(advrB), Val(advrA)) = 0 Then advMsg = aimLoadErr : advErr = -1 : Exit Sub
    aimDevLive = -1
    advErr = 0 : advMsg = "reloaded" : advAt = gameFrame
End Sub

Sub ADV_Frame ()
    Dim advK1 As Integer, advK2 As Integer, advK3 As Integer, advK4 As Integer, advK5 As Integer
    Dim advOk As Integer
    If cliAimDev = 0 Then Exit Sub
    advK1 = KEY_Down%(49) : advK2 = KEY_Down%(50) : advK3 = KEY_Down%(51) : advK4 = KEY_Down%(52) : advK5 = KEY_Down%(53)
    If advK1 And advWas1 = 0 Then advOk = AIM_Set%(AIM_NudgeBlend!(aimNoseBlend, -1), aimArcCfg) : aimDevLive = -1
    If advK2 And advWas2 = 0 Then advOk = AIM_Set%(AIM_NudgeBlend!(aimNoseBlend, 1), aimArcCfg) : aimDevLive = -1
    If advK3 And advWas3 = 0 Then advOk = AIM_Set%(aimNoseBlend, AIM_NudgeArc!(aimArcCfg, -1)) : aimDevLive = -1
    If advK4 And advWas4 = 0 Then advOk = AIM_Set%(aimNoseBlend, AIM_NudgeArc!(aimArcCfg, 1)) : aimDevLive = -1
    If advK5 And advWas5 = 0 Then ADV_Reload
    advWas1 = advK1 : advWas2 = advK2 : advWas3 = advK3 : advWas4 = advK4 : advWas5 = advK5
End Sub

Sub ADV_Draw ()
    Dim advN As Integer, advL As Integer, advS As String, advRows(0 To ADV_ROWS - 1) As String
    If cliAimDev = 0 Then Exit Sub
    _Dest backBuffer
    advS = "AIM blend " + LTrim$(Str$(Int(aimNoseBlend * 10 + 0.5) / 10)) + "  arc " + LTrim$(Str$(aimArcCfg)) + "  1-2 3-4 5"
    Line (0, 0)-(Len(advS) * FONT_CHAR_W + 3, FONT_CHAR_H + 1), _RGBA(0, 0, 0, 200), BF
    FONT_PrintAlpha fontPalette(14), backBuffer, advS, 2, 1, 255
    If Len(advMsg) = 0 Then Exit Sub
    If advErr = 0 Then
        If gameFrame - advAt < ADV_NOTE_FRAMES Then UI_Text 10, advMsg, 2, FONT_CHAR_H + 3, 255
    Else
        advN = BD_WrapText%(advMsg, 40, advRows(), ADV_ROWS)
        If advN > ADV_ROWS Then advRows(ADV_ROWS - 1) = "(and more)" : advN = ADV_ROWS
        For advL = 0 To advN - 1
            UI_Text 12, advRows(advL), 2, FONT_CHAR_H * (advL + 1) + 3, 255
        Next advL
    End If
End Sub
