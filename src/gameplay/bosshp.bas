' bosshp.bas -- boss hit points, phases and the phase-change shield (#90)
'
' Tuning comes from assets/config/bosses.ini and each fight's hp= in assets/sequence.txt (see
' the comments in bosses.ini). No game state here, so tests drive it directly:
'   ok = BHP_Load%                     read the tuning (after CFG_Parse$ of bosses.ini); 0 + bhpLoadErr
'   m = BHP_MaxHP%(hp, nerf)           a fight's hit points from its hp= (0 = none given),
'                                      x the difficulty's boss_hp, then x0.1 under --nerf
'   t = BHP_PhaseStart%(maxHp, phase)  hit points at which phase 2 or 3 starts
'   p = BHP_Phase%(hp, maxHp)          the phase (1..3) at hp hit points left
'   h = BHP_Damage%(hp, maxHp, dmg, shield)  hit points left after a hit of dmg: none while
'                                      shielded, and never past the next phase's start
'   f = BHP_ShieldFrames&(samples)     shield frames for a phase callout of that many samples
' Local variable prefix: bhp*

Dim Shared bhpDefault As Integer, bhpNerfMin As Integer
Dim Shared bhpPct2 As Single, bhpPct3 As Single
Dim Shared bhpShieldPad As Long, bhpShieldMin As Long
Dim Shared bhpHpMult As Single : bhpHpMult = 1
Dim Shared bhpLoadErr As String

Function BHP_Load%
    Dim bhplV(1 To 4) As String, bhplN As Integer
    BHP_Load% = 0
    bhpLoadErr = ""
    bhpDefault = Val(CFG_Get$(cfgBosses, "boss_hp_default"))
    bhpNerfMin = Val(CFG_Get$(cfgBosses, "boss_nerf_min"))
    bhpShieldPad = Val(CFG_Get$(cfgBosses, "boss_shield_pad"))
    bhpShieldMin = Val(CFG_Get$(cfgBosses, "boss_shield_min"))
    bhpHpMult = DLV_M!("boss_hp")
    If bhpDefault < 3 Or bhpNerfMin < 3 Then bhpLoadErr = "config/bosses.ini needs boss_hp_default and boss_nerf_min of 3 or more (one per phase)" : Exit Function
    If bhpShieldPad < 0 Or bhpShieldMin < 0 Then bhpLoadErr = "config/bosses.ini boss_shield_pad and boss_shield_min can't be negative" : Exit Function
    UPG_Split CFG_Get$(cfgBosses, "boss_phase"), ",", bhplV(), bhplN
    If bhplN <> 2 Then bhpLoadErr = "config/bosses.ini boss_phase needs 2 values (phase 2, phase 3)" : Exit Function
    bhpPct2 = Val(bhplV(1)) : bhpPct3 = Val(bhplV(2))
    If bhpPct2 >= 100 Or bhpPct3 <= 0 Or bhpPct3 >= bhpPct2 Then bhpLoadErr = "config/bosses.ini boss_phase: phase 2 below 100, phase 3 above 0 and below phase 2" : Exit Function
    BHP_Load% = -1
End Function

Function BHP_MaxHP% (bhpmHp As Integer, bhpmNerf As Integer)
    Dim bhpmM As Integer
    bhpmM = bhpmHp
    If bhpmM <= 0 Then bhpmM = bhpDefault
    If bhpHpMult <> 1 Then
        bhpmM = DLV_Round&(CLng(bhpmM), bhpHpMult)
        If bhpmM < 3 Then bhpmM = 3
    End If
    If bhpmNerf Then
        bhpmM = Int(bhpmM * NERF_FACTOR + 0.5)
        If bhpmM < bhpNerfMin Then bhpmM = bhpNerfMin
    End If
    BHP_MaxHP% = bhpmM
End Function

' Phase 3 starts at 1 HP or more, phase 2 above that and below the full count.
Function BHP_PhaseStart% (bhpsMax As Integer, bhpsPhase As Integer)
    Dim bhpsT2 As Integer, bhpsT3 As Integer
    bhpsT2 = Int(bhpsMax * bhpPct2 / 100 + 0.5)
    bhpsT3 = Int(bhpsMax * bhpPct3 / 100 + 0.5)
    If bhpsT3 < 1 Then bhpsT3 = 1
    If bhpsT2 <= bhpsT3 Then bhpsT2 = bhpsT3 + 1
    If bhpsT2 >= bhpsMax Then bhpsT2 = bhpsMax - 1
    If bhpsPhase <= 2 Then BHP_PhaseStart% = bhpsT2 Else BHP_PhaseStart% = bhpsT3
End Function

Function BHP_Phase% (bhppHp As Integer, bhppMax As Integer)
    If bhppHp > BHP_PhaseStart%(bhppMax, 2) Then
        BHP_Phase% = 1
    ElseIf bhppHp > BHP_PhaseStart%(bhppMax, 3) Then
        BHP_Phase% = 2
    Else
        BHP_Phase% = 3
    End If
End Function

Function BHP_Damage% (bhpdHp As Integer, bhpdMax As Integer, bhpdDmg As Integer, bhpdShield As Long)
    Dim bhpdNew As Integer, bhpdPhase As Integer, bhpdFloor As Integer
    BHP_Damage% = bhpdHp
    If bhpdShield > 0 Or bhpdDmg <= 0 Then Exit Function
    bhpdNew = bhpdHp - bhpdDmg
    bhpdPhase = BHP_Phase%(bhpdHp, bhpdMax)
    If bhpdPhase < 3 Then
        bhpdFloor = BHP_PhaseStart%(bhpdMax, bhpdPhase + 1)
        If bhpdNew < bhpdFloor Then bhpdNew = bhpdFloor
    End If
    If bhpdNew < 0 Then bhpdNew = 0
    BHP_Damage% = bhpdNew
End Function

Function BHP_ShieldFrames& (bhpfSamples As Long)
    Dim bhpfF As Long, bhpfPerFrame As Long
    bhpfPerFrame = SAMPLE_RATE \ 60
    bhpfF = (bhpfSamples + bhpfPerFrame - 1) \ bhpfPerFrame + bhpShieldPad
    If bhpfSamples <= 0 Then bhpfF = 0
    If bhpfF < bhpShieldMin Then bhpfF = bhpShieldMin
    BHP_ShieldFrames& = bhpfF
End Function
