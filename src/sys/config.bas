' config.bas -- the one key=value config parser, for every embedded .ini
'
' Each file is "key=value" lines; blank lines and lines starting with ; are skipped,
' no spaces around =, no quotes. Which file holds what:
'   assets/gamevalues.ini         text substitution tokens for gametext.txt only (gametext.bas)
'   assets/config/economy.ini     credits earned (cfgEconomy)
'   assets/config/upgrades.ini    the dock's upgrade table and descriptions (cfgUpgrades)
'   assets/config/abilities.ini   nova / roll behaviour and their launch hints (cfgAbilities)
'   assets/config/powerups.ini    power-up odds, amounts, spawn lane and grab size (cfgPowerups)
'   assets/config/waves.ini       combat waves: timing, size, spawn distance, enemy fire, the clear-out (cfgWaves)
'   assets/config/bosses.ini      boss hit points, phases and the phase-change shield (cfgBosses)
' sss.bas parses each embedded file once at startup:
'   store$ = CFG_Parse$(text$)     parsed lookup: key + Chr$(1) + value + Chr$(2) + ...
'   v$ = CFG_Get$(store$, key$)    the value, or "" when the key is missing
'   n = CFG_Count%(store$)         how many keys
' No rendering or game state here.
' Local variable prefix: cfg*

Dim Shared cfgEconomy As String
Dim Shared cfgUpgrades As String
Dim Shared cfgAbilities As String
Dim Shared cfgPowerups As String
Dim Shared cfgWaves As String
Dim Shared cfgBosses As String

Function CFG_Parse$ (cfgpSrc As String)
    Dim cfgpP As Long, cfgpQ As Long, cfgpE As Long, cfgpL As String, cfgpOut As String
    cfgpP = 1
    Do While cfgpP <= Len(cfgpSrc)
        cfgpQ = InStr(cfgpP, cfgpSrc, Chr$(10))
        If cfgpQ = 0 Then cfgpQ = Len(cfgpSrc) + 1
        cfgpL = Mid$(cfgpSrc, cfgpP, cfgpQ - cfgpP)
        If Right$(cfgpL, 1) = Chr$(13) Then cfgpL = Left$(cfgpL, Len(cfgpL) - 1)
        cfgpP = cfgpQ + 1
        cfgpL = LTrim$(RTrim$(cfgpL))
        If Len(cfgpL) > 0 Then
            If Left$(cfgpL, 1) <> ";" Then
                cfgpE = InStr(cfgpL, "=")
                If cfgpE > 1 Then cfgpOut = cfgpOut + Left$(cfgpL, cfgpE - 1) + Chr$(1) + Mid$(cfgpL, cfgpE + 1) + Chr$(2)
            End If
        End If
    Loop
    CFG_Parse$ = cfgpOut
End Function

Function CFG_Get$ (cfggStore As String, cfggKey As String)
    Dim cfggP As Long, cfggQ As Long, cfggE As Long
    cfggP = 1
    Do While cfggP <= Len(cfggStore)
        cfggQ = InStr(cfggP, cfggStore, Chr$(1))
        If cfggQ = 0 Then Exit Do
        cfggE = InStr(cfggQ + 1, cfggStore, Chr$(2))
        If cfggE = 0 Then cfggE = Len(cfggStore) + 1
        If Mid$(cfggStore, cfggP, cfggQ - cfggP) = cfggKey Then
            CFG_Get$ = Mid$(cfggStore, cfggQ + 1, cfggE - cfggQ - 1)
            Exit Function
        End If
        cfggP = cfggE + 1
    Loop
    CFG_Get$ = ""
End Function

Function CFG_Count% (cfgcStore As String)
    Dim cfgcP As Long, cfgcN As Integer
    For cfgcP = 1 To Len(cfgcStore)
        If Mid$(cfgcStore, cfgcP, 1) = Chr$(2) Then cfgcN = cfgcN + 1
    Next cfgcP
    CFG_Count% = cfgcN
End Function
