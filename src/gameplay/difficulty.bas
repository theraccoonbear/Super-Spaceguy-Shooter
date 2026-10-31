' difficulty.bas -- difficulty levels: Easy / Normal / Hard, or however many difficulty.ini lists (#102)
'
' Not the in-run ramp (diffScale / diffTime / DIFF_* in dims.bas and wave.bas), which tightens
' every run as it goes at every level. A level is a set of multipliers from
' assets/config/difficulty.ini (see the comments there) on top of the other config files:
'   - ini-loaded tuning is scaled inside each loader (UPG_Load%, SUP_Load%, PUP_Load%, WVT_Load%,
'     BHP_Load%) with DLV_M!(knob), so GAME_ResetState re-runs them (game.bas GAME_LoadTuning)
'     after DLV_Begin
'   - hard-coded constants are scaled where they're used, by the dlvF* factors below
' A knob a level doesn't set is 1, and so is every knob before DLV_Use / DLV_Begin runs (tests).
' Nothing else to include, and no game state, so tests drive it directly:
'   ok = DLV_Load%               read the levels (after CFG_Parse$ of difficulty.ini into
'                                cfgDifficulty); 0 + dlvLoadErr
'   n = DLV_Count%               how many levels
'   l$ = DLV_LevelAt$(i)         level i (1..n), in the ini's order
'   i = DLV_Index%(l$)           its position, 0 for an unknown level
'   l$ = DLV_Default$            the default level
'   s$ = DLV_List$               "easy, normal or hard" (CLI messages)
'   l$ = DLV_Valid$(l$)          l$ when it's a level, else the default (settings, CLI)
'   l$ = DLV_Step$(l$, dir)      the next (dir 1) or previous (dir -1) level, wrapping (Settings)
'   n$ = DLV_Name$(l$)           display name;  t$ = DLV_Tag$(l$)  leaderboard tag ("" = none)
'   l$ = DLV_Chosen$             the level the next run plays: --difficulty, else the setting
'   DLV_Use l$                   play level l$ (an unknown one plays the default): runDifficulty
'                                and the dlvF* factors. The loaders must be re-run after it.
'   DLV_Begin                    DLV_Use DLV_Chosen$ (GAME_ResetState)
'   m = DLV_M!(knob$)            the multiplier on a knob for the level in use
'   n = DLV_Round&(n, m)         n x m to the nearest whole number; exactly n when m is 1
'   d = DLV_Dmg%(d)              damage d at the level's dmg_taken, at least 1 when d > 0
' Shared: runDifficulty (the run's level, locked at GAME_ResetState), settingDifficulty
' (Settings, sss_settings.ini), cliDifficulty (dev --difficulty, wins over the setting).
' Local variable prefix: dlv*

Const DLV_MAX   = 16
Const DLV_KNOBS = 19
Const DLV_HALF  = 0.501   ' rounds x.5 up even when single precision stores x.4999 (250 x 1.15, 45 x 0.9)

Dim Shared cfgDifficulty As String
Dim Shared runDifficulty As String, settingDifficulty As String, cliDifficulty As String
Dim Shared dlvLevel(1 To DLV_MAX) As String, dlvName(1 To DLV_MAX) As String, dlvTag(1 To DLV_MAX) As String
Dim Shared dlvMult(1 To DLV_MAX, 1 To DLV_KNOBS) As Single
Dim Shared dlvKnob(1 To DLV_KNOBS) As String
Dim Shared dlvCount As Integer, dlvDefault As Integer, dlvCur As Integer
Dim Shared dlvLoadErr As String
Dim Shared dlvFEnemyFire As Single : dlvFEnemyFire = 1
Dim Shared dlvFEnemyLead As Single : dlvFEnemyLead = 1
Dim Shared dlvFEnemyHoming As Single : dlvFEnemyHoming = 1
Dim Shared dlvFEnemySpeed As Single : dlvFEnemySpeed = 1
Dim Shared dlvFDmg As Single : dlvFDmg = 1
Dim Shared dlvFBossFire As Single : dlvFBossFire = 1
Dim Shared dlvFFuelBurn As Single : dlvFFuelBurn = 1
Dim Shared dlvFAstInterval As Single : dlvFAstInterval = 1

dlvKnob(1) = "wave_gap" : dlvKnob(2) = "wave_open_gap" : dlvKnob(3) = "wave_first"
dlvKnob(4) = "enemy_fire" : dlvKnob(5) = "enemy_lead" : dlvKnob(6) = "enemy_homing" : dlvKnob(7) = "enemy_speed"
dlvKnob(8) = "dmg_taken" : dlvKnob(9) = "boss_hp" : dlvKnob(10) = "boss_fire"
dlvKnob(11) = "fuel_price" : dlvKnob(12) = "shield_price" : dlvKnob(13) = "fuel_burn"
dlvKnob(14) = "credits" : dlvKnob(15) = "upgrade_price"
dlvKnob(16) = "pup_chance" : dlvKnob(17) = "pup_fuel" : dlvKnob(18) = "pup_shield" : dlvKnob(19) = "ast_interval"

Function DLV_KnobIdx% (dlvkiName As String)
    Dim dlvkiI As Integer
    DLV_KnobIdx% = 0
    For dlvkiI = 1 To DLV_KNOBS
        If dlvKnob(dlvkiI) = dlvkiName Then DLV_KnobIdx% = dlvkiI : Exit Function
    Next dlvkiI
End Function

' A level name: lower-case letters and digits only, so <level>_<knob> splits one way.
Function DLV_NameOk% (dlvnoS As String)
    Dim dlvnoI As Integer, dlvnoC As String
    DLV_NameOk% = 0
    If Len(dlvnoS) = 0 Then Exit Function
    For dlvnoI = 1 To Len(dlvnoS)
        dlvnoC = Mid$(dlvnoS, dlvnoI, 1)
        If (dlvnoC < "a" Or dlvnoC > "z") And (dlvnoC < "0" Or dlvnoC > "9") Then Exit Function
    Next dlvnoI
    DLV_NameOk% = -1
End Function

Function DLV_Load%
    DLV_Load% = DLV_Parse%
    If dlvLoadErr <> "" Then dlvCount = 0 : dlvDefault = 0
End Function

Function DLV_Parse%
    Dim dlvlSrc As String, dlvlP As Long, dlvlQ As Long, dlvlE As Long
    Dim dlvlKey As String, dlvlVal As String, dlvlRest As String, dlvlItem As String
    Dim dlvlI As Integer, dlvlJ As Integer, dlvlK As Integer, dlvlL As Integer
    DLV_Parse% = 0
    dlvLoadErr = "" : dlvCount = 0 : dlvDefault = 0 : dlvCur = 0
    DLV_Use ""

    ' levels=a,b,c
    dlvlSrc = DLV_Entry$("levels") + ","
    If dlvlSrc = "," Then dlvLoadErr = "config/difficulty.ini has no levels" : Exit Function
    dlvlP = 1
    Do While dlvlP <= Len(dlvlSrc)
        dlvlQ = InStr(dlvlP, dlvlSrc, ",")
        dlvlItem = LTrim$(RTrim$(Mid$(dlvlSrc, dlvlP, dlvlQ - dlvlP)))
        dlvlP = dlvlQ + 1
        If DLV_NameOk%(dlvlItem) = 0 Then dlvLoadErr = "config/difficulty.ini levels: '" + dlvlItem + "' isn't a level name (a-z and 0-9 only)" : Exit Function
        If DLV_Index%(dlvlItem) > 0 Then dlvLoadErr = "config/difficulty.ini levels: '" + dlvlItem + "' is listed twice" : Exit Function
        If dlvCount >= DLV_MAX Then dlvLoadErr = "config/difficulty.ini levels: at most" + Str$(DLV_MAX) : Exit Function
        dlvCount = dlvCount + 1
        dlvLevel(dlvCount) = dlvlItem
        dlvName(dlvCount) = UCase$(dlvlItem)
        dlvTag(dlvCount) = ""
        For dlvlK = 1 To DLV_KNOBS : dlvMult(dlvCount, dlvlK) = 1 : Next dlvlK
    Loop

    dlvDefault = DLV_Index%(DLV_Entry$("default"))
    If dlvDefault = 0 Then dlvLoadErr = "config/difficulty.ini default must be one of the levels" : Exit Function

    ' every other key is <level>_name, <level>_tag or <level>_<knob>
    dlvlP = 1
    Do While dlvlP <= Len(cfgDifficulty)
        dlvlQ = InStr(dlvlP, cfgDifficulty, Chr$(1))
        If dlvlQ = 0 Then Exit Do
        dlvlE = InStr(dlvlQ + 1, cfgDifficulty, Chr$(2))
        If dlvlE = 0 Then dlvlE = Len(cfgDifficulty) + 1
        dlvlKey = Mid$(cfgDifficulty, dlvlP, dlvlQ - dlvlP)
        dlvlVal = Mid$(cfgDifficulty, dlvlQ + 1, dlvlE - dlvlQ - 1)
        dlvlP = dlvlE + 1
        If dlvlKey = "levels" Or dlvlKey = "default" Then _Continue
        dlvlL = 0
        dlvlI = InStr(dlvlKey, "_")
        If dlvlI > 1 Then dlvlL = DLV_Index%(Left$(dlvlKey, dlvlI - 1))
        If dlvlL = 0 Then dlvLoadErr = "config/difficulty.ini " + dlvlKey + ": not a level in levels" : Exit Function
        dlvlRest = Mid$(dlvlKey, dlvlI + 1)
        If dlvlRest = "name" Then
            If Len(dlvlVal) = 0 Then dlvLoadErr = "config/difficulty.ini " + dlvlKey + " can't be empty" : Exit Function
            dlvName(dlvlL) = dlvlVal
        ElseIf dlvlRest = "tag" Then
            dlvTag(dlvlL) = dlvlVal
        Else
            dlvlJ = DLV_KnobIdx%(dlvlRest)
            If dlvlJ = 0 Then dlvLoadErr = "config/difficulty.ini " + dlvlKey + ": unknown knob '" + dlvlRest + "'" : Exit Function
            dlvMult(dlvlL, dlvlJ) = Val(dlvlVal)
            If dlvMult(dlvlL, dlvlJ) <= 0 Then dlvLoadErr = "config/difficulty.ini " + dlvlKey + " must be above 0" : Exit Function
        End If
    Loop
    DLV_Parse% = -1
End Function

Function DLV_Entry$ (dlveKey As String)
    Dim dlveP As Long, dlveQ As Long, dlveE As Long
    DLV_Entry$ = ""
    dlveP = 1
    Do While dlveP <= Len(cfgDifficulty)
        dlveQ = InStr(dlveP, cfgDifficulty, Chr$(1))
        If dlveQ = 0 Then Exit Do
        dlveE = InStr(dlveQ + 1, cfgDifficulty, Chr$(2))
        If dlveE = 0 Then dlveE = Len(cfgDifficulty) + 1
        If Mid$(cfgDifficulty, dlveP, dlveQ - dlveP) = dlveKey Then DLV_Entry$ = Mid$(cfgDifficulty, dlveQ + 1, dlveE - dlveQ - 1) : Exit Function
        dlveP = dlveE + 1
    Loop
End Function

Function DLV_Count%
    DLV_Count% = dlvCount
End Function

Function DLV_LevelAt$ (dlvaI As Integer)
    If dlvaI < 1 Or dlvaI > dlvCount Then DLV_LevelAt$ = "" Else DLV_LevelAt$ = dlvLevel(dlvaI)
End Function

Function DLV_Index% (dlviL As String)
    Dim dlviI As Integer
    DLV_Index% = 0
    For dlviI = 1 To dlvCount
        If dlvLevel(dlviI) = dlviL Then DLV_Index% = dlviI : Exit Function
    Next dlviI
End Function

Function DLV_List$
    Dim dlvliI As Integer, dlvliS As String
    For dlvliI = 1 To dlvCount
        If dlvliI > 1 Then
            If dlvliI = dlvCount Then dlvliS = dlvliS + " or " Else dlvliS = dlvliS + ", "
        End If
        dlvliS = dlvliS + dlvLevel(dlvliI)
    Next dlvliI
    DLV_List$ = dlvliS
End Function

Function DLV_Default$
    DLV_Default$ = DLV_LevelAt$(dlvDefault)
End Function

Function DLV_Valid$ (dlvvL As String)
    If DLV_Index%(dlvvL) > 0 Then DLV_Valid$ = dlvvL Else DLV_Valid$ = DLV_Default$
End Function

Function DLV_Step$ (dlvsL As String, dlvsDir As Integer)
    Dim dlvsI As Integer
    If dlvCount < 1 Then DLV_Step$ = "" : Exit Function
    dlvsI = DLV_Index%(DLV_Valid$(dlvsL)) - 1
    If dlvsDir < 0 Then dlvsI = dlvsI + dlvCount - 1 Else dlvsI = dlvsI + 1
    DLV_Step$ = dlvLevel((dlvsI Mod dlvCount) + 1)
End Function

Function DLV_Name$ (dlvnL As String)
    Dim dlvnI As Integer
    dlvnI = DLV_Index%(dlvnL)
    If dlvnI = 0 Then DLV_Name$ = UCase$(dlvnL) Else DLV_Name$ = dlvName(dlvnI)
End Function

Function DLV_Tag$ (dlvtL As String)
    Dim dlvtI As Integer
    dlvtI = DLV_Index%(dlvtL)
    If dlvtI = 0 Then DLV_Tag$ = "" Else DLV_Tag$ = dlvTag(dlvtI)
End Function

Function DLV_Chosen$
    If Len(cliDifficulty) > 0 Then DLV_Chosen$ = DLV_Valid$(cliDifficulty) Else DLV_Chosen$ = DLV_Valid$(settingDifficulty)
End Function

Sub DLV_Use (dlvuL As String)
    dlvCur = DLV_Index%(DLV_Valid$(dlvuL))
    runDifficulty = DLV_LevelAt$(dlvCur)
    dlvFEnemyFire = DLV_M!("enemy_fire")
    dlvFEnemyHoming = DLV_M!("enemy_homing")
    dlvFEnemySpeed = DLV_M!("enemy_speed")
    dlvFDmg = DLV_M!("dmg_taken")
    dlvFBossFire = DLV_M!("boss_fire")
    dlvFFuelBurn = DLV_M!("fuel_burn")
    dlvFAstInterval = DLV_M!("ast_interval")
    dlvFEnemyLead = DLV_M!("enemy_lead")
End Sub

Sub DLV_Begin
    DLV_Use DLV_Chosen$
End Sub

Function DLV_M! (dlvmKnob As String)
    Dim dlvmK As Integer
    DLV_M! = 1
    If dlvCur < 1 Then Exit Function
    dlvmK = DLV_KnobIdx%(dlvmKnob)
    If dlvmK > 0 Then DLV_M! = dlvMult(dlvCur, dlvmK)
End Function

Function DLV_Round& (dlvrN As Long, dlvrM As Single)
    If dlvrM = 1 Then DLV_Round& = dlvrN Else DLV_Round& = Int(dlvrN * dlvrM + DLV_HALF)
End Function

Function DLV_Dmg% (dlvdD As Integer)
    Dim dlvdR As Integer
    If dlvdD <= 0 Or dlvFDmg = 1 Then DLV_Dmg% = dlvdD : Exit Function
    dlvdR = Int(dlvdD * dlvFDmg + DLV_HALF)
    If dlvdR < 1 Then dlvdR = 1
    DLV_Dmg% = dlvdR
End Function
