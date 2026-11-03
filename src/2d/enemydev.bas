' enemydev.bas -- --enemy-dev: tune enemy attacks live in play (#136)
'
'   EDV_Frame   once per frame of play: T picks the enemy type, F picks the value, - and =
'               lower and raise it, L re-reads assets/config/enemies.ini from disk
'   EDV_Draw    the readout: type, value, number, and any parse problem
' Edits change the running game only; copy the numbers into enemies.ini to keep them.
' Local variable prefix: edv*

Const EDV_FILE = "assets/config/enemies.ini"

Dim Shared edvType As Integer   ' 0..EAT_TYPES-1 an enemy type; EAT_TYPES the mix (debut_weight)
Dim Shared edvParam As Integer
Dim Shared edvMsg As String
Dim Shared edvWasT As Integer, edvWasF As Integer, edvWasDn As Integer, edvWasUp As Integer, edvWasL As Integer

Function EDV_Path$ ()
    Dim edvA As String
    edvA = _StartDir$ + "/" + EDV_FILE
    If _FileExists(edvA) Then EDV_Path$ = edvA : Exit Function
    edvA = _Cwd$ + "/../" + EDV_FILE
    If _FileExists(edvA) Then EDV_Path$ = edvA : Exit Function
    EDV_Path$ = ""
End Function

Sub EDV_Reload ()
    Dim edvRP As String
    edvRP = EDV_Path$
    If edvRP = "" Then edvMsg = "L: enemies.ini not found (run from repo)" : Exit Sub
    If EAT_Load%(_ReadFile$(edvRP)) Then edvMsg = "reloaded" Else edvMsg = eatLoadErr
End Sub

Sub EDV_Nudge (edvDir As Integer)
    If edvType = EAT_TYPES Then
        EAT_SetDebutW eatDebutW + edvDir * EAT_DEBUT_STEP
    Else
        EAT_Set edvType, edvParam, EAT_Get!(edvType, edvParam) + edvDir * EAT_Step!(edvParam)
    End If
End Sub

Sub EDV_Frame ()
    Dim edvKT As Integer, edvKF As Integer, edvKD As Integer, edvKU As Integer, edvKL As Integer
    If cliEnemyDev = 0 Then Exit Sub
    edvKT = KEY_Down%(84) Or KEY_Down%(116)
    edvKF = KEY_Down%(70) Or KEY_Down%(102)
    edvKD = KEY_Down%(45)
    edvKU = KEY_Down%(61) Or KEY_Down%(43)
    edvKL = KEY_Down%(76) Or KEY_Down%(108)
    If edvKT And edvWasT = 0 Then edvType = (edvType + 1) Mod (EAT_TYPES + 1)
    If edvKF And edvWasF = 0 And edvType < EAT_TYPES Then edvParam = (edvParam + 1) Mod EAT_PARAMS
    If edvKD And edvWasDn = 0 Then EDV_Nudge -1
    If edvKU And edvWasUp = 0 Then EDV_Nudge 1
    If edvKL And edvWasL = 0 Then EDV_Reload
    edvWasT = edvKT : edvWasF = edvKF : edvWasDn = edvKD : edvWasUp = edvKU : edvWasL = edvKL
End Sub

Sub EDV_Draw ()
    Dim edvS As String
    If cliEnemyDev = 0 Then Exit Sub
    _Dest backBuffer
    If edvType = EAT_TYPES Then
        edvS = "ENEMY mix debut_weight =" + Str$(eatDebutW) + "  T F - = L"
    Else
        edvS = "ENEMY " + EAT_TypeName$(edvType) + " " + EAT_ParamName$(edvParam) + " =" + Str$(EAT_Get!(edvType, edvParam)) + "  T F - = L"
    End If
    Line (0, scrH - 2 * FONT_CHAR_H - 3)-(Len(edvS) * FONT_CHAR_W + 3, scrH - FONT_CHAR_H - 2), _RGBA(0, 0, 0, 200), BF
    FONT_PrintAlpha fontPalette(14), backBuffer, edvS, 2, scrH - 2 * FONT_CHAR_H - 2, 255
    If Len(edvMsg) > 0 Then FONT_PrintAlpha fontPalette(11), backBuffer, edvMsg, 2, scrH - 3 * FONT_CHAR_H - 2, 255
End Sub
