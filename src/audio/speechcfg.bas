' speechcfg.bas -- assets/config/speech.ini: the IN prosody knobs of speech.bas (#236)
'
'   ok = SPK_ProsodyLoad%(src$)   read speech.ini text over the defaults SPK_Init set; 0 and
'                                 spkCfgErr on an unknown or out-of-range value (defaults kept)
' Needs config.bas (CFG_Parse$, CFG_Get$) and speech.bas.

Dim Shared spkCfgErr As String

Function SPK_ProsodyLoad% (splSrc As String)
    Dim splStore As String, splI As Integer, splTxt As String, splV As Single, splNew(0 To SPK_PK_N - 1) As Single
    SPK_ProsodyLoad% = 0
    spkCfgErr = ""
    splStore = CFG_Parse$(splSrc)
    For splI = 0 To SPK_PK_N - 1
        splNew(splI) = spkPkDef(splI)
        splTxt = CFG_Get$(splStore, spkPkKey(splI))
        If Len(splTxt) > 0 Then
            splV = Val(splTxt)
            If splV < spkPkMin(splI) Or splV > spkPkMax(splI) Then
                spkCfgErr = "speech.ini " + spkPkKey(splI) + ":" + Str$(spkPkMin(splI)) + " to" + Str$(spkPkMax(splI))
                Exit Function
            End If
            splNew(splI) = splV
        End If
    Next splI
    For splI = 0 To SPK_PK_N - 1 : spkPk(splI) = splNew(splI) : Next splI
    SPK_PlanPitch
    SPK_ProsodyLoad% = -1
End Function
