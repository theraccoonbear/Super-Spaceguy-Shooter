' speechcfg.bas -- assets/config/speech.ini: the IN prosody knobs and the six clarity-feature switches
' of speech.bas (#236), their labels, and writing them back
'
'   ok = SPK_ProsodyLoad%(src$)   read speech.ini text over the defaults SPK_Init set; 0 and
'                                 spkCfgErr on an unknown or out-of-range value (defaults kept)
'   out$ = SPK_ProsodySave$(src$) src$ with every knob and feature switch rewritten to its current
'                                 value in place (comments and layout stay; a missing key is appended)
'   SPK_PkName$(k), SPK_PkDesc$(k), SPK_FxName$(f), SPK_FxDesc$(f)   full names and one-line help
'   SPK_Num$(v)                   a value as short text (at most two decimals)
' Needs config.bas (CFG_Parse$, CFG_Get$) and speech.bas.

Dim Shared spkCfgErr As String

Function SPK_PkName$ (spnK As Integer)
    Select Case spnK
        Case SPK_PK_STEP: SPK_PkName$ = "Pitch step (semitones)"
        Case SPK_PK_DECL: SPK_PkName$ = "Declination per word (semitones)"
        Case SPK_PK_ACC: SPK_PkName$ = "Accent size (semitones)"
        Case SPK_PK_NACC: SPK_PkName$ = "Accents per phrase"
        Case SPK_PK_FALL: SPK_PkName$ = "Final fall (semitones)"
        Case SPK_PK_RISE: SPK_PkName$ = "Rise (semitones)"
        Case SPK_PK_SPREAD: SPK_PkName$ = "Stress pitch spread"
        Case SPK_PK_GPITCH: SPK_PkName$ = "Glide pitch"
        Case SPK_PK_LIQ: SPK_PkName$ = "Liquid glide length"
        Case SPK_PK_LOUD: SPK_PkName$ = "Unstressed loudness drop (dB)"
        Case Else: SPK_PkName$ = ""
    End Select
End Function

Function SPK_PkDesc$ (spdK As Integer)
    Select Case spdK
        Case SPK_PK_STEP: SPK_PkDesc$ = "Every pitch is a multiple of this; larger is blockier"
        Case SPK_PK_DECL: SPK_PkDesc$ = "Each word is this much lower than the one before"
        Case SPK_PK_ACC: SPK_PkDesc$ = "How far the accented words are raised"
        Case SPK_PK_NACC: SPK_PkDesc$ = "How many words of each clause are accented"
        Case SPK_PK_FALL: SPK_PkDesc$ = "Drop on the last word before a full stop or the end"
        Case SPK_PK_RISE: SPK_PkDesc$ = "Lift on the last word before , ; : (? lifts 1.5 times)"
        Case SPK_PK_SPREAD: SPK_PkDesc$ = "Pitch of stressed vowels in a word: 0 flat, 1 wide"
        Case SPK_PK_GPITCH: SPK_PkDesc$ = "On slides pitch over a formant glide, off steps it"
        Case SPK_PK_LIQ: SPK_PkDesc$ = "Glide into a vowel after L R W Y, times the normal"
        Case SPK_PK_LOUD: SPK_PkDesc$ = "Unstressed vowels are this much quieter"
        Case Else: SPK_PkDesc$ = ""
    End Select
End Function

' The speech.ini key of clarity feature spkFx(spfF)
Function SPK_FxKey$ (spfF As Integer)
    Select Case spfF
        Case SPK_FX_GL: SPK_FxKey$ = "feature_glides"
        Case SPK_FX_BU: SPK_FxKey$ = "feature_bursts"
        Case SPK_FX_FR: SPK_FxKey$ = "feature_fricatives"
        Case SPK_FX_NL: SPK_FxKey$ = "feature_nasals_liquids"
        Case SPK_FX_HB: SPK_FxKey$ = "feature_bright_tables"
        Case SPK_FX_IN: SPK_FxKey$ = "feature_intonation"
        Case Else: SPK_FxKey$ = ""
    End Select
End Function

Function SPK_FxName$ (spxF As Integer)
    Select Case spxF
        Case SPK_FX_GL: SPK_FxName$ = "Glides"
        Case SPK_FX_BU: SPK_FxName$ = "Stop bursts"
        Case SPK_FX_FR: SPK_FxName$ = "Fricatives"
        Case SPK_FX_NL: SPK_FxName$ = "Nasals and liquids"
        Case SPK_FX_HB: SPK_FxName$ = "Bright tables"
        Case SPK_FX_IN: SPK_FxName$ = "Intonation"
        Case Else: SPK_FxName$ = ""
    End Select
End Function

Function SPK_FxDesc$ (spyF As Integer)
    Select Case spyF
        Case SPK_FX_GL: SPK_FxDesc$ = "Formants glide between sounds, no level notch"
        Case SPK_FX_BU: SPK_FxDesc$ = "Stops get a burst shaped by place of articulation"
        Case SPK_FX_FR: SPK_FxDesc$ = "S, Z, SH, CH are shaped hiss, not plain noise"
        Case SPK_FX_NL: SPK_FxDesc$ = "Nasal murmur, liquids a little below the vowels"
        Case SPK_FX_HB: SPK_FxDesc$ = "Harmonics up to about 5 kHz instead of 3 kHz"
        Case SPK_FX_IN: SPK_FxDesc$ = "Phrase pitch: declination, accents, falls and rises"
        Case Else: SPK_FxDesc$ = ""
    End Select
End Function

Function SPK_Num$ (spmV As Single)
    Dim spmS As String
    spmS = LTrim$(Str$(Int(spmV * 100 + 0.5) / 100))
    If Left$(spmS, 1) = "." Then spmS = "0" + spmS
    If Left$(spmS, 2) = "-." Then spmS = "-0" + Mid$(spmS, 2)
    SPK_Num$ = spmS
End Function

Function SPK_ProsodyLoad% (splSrc As String)
    Dim splStore As String, splI As Integer, splTxt As String, splV As Single, splNew(0 To SPK_PK_N - 1) As Single
    Dim splFx(0 To SPK_FX_N - 1) As Integer
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
    For splI = 0 To SPK_FX_N - 1
        splFx(splI) = -1
        splTxt = CFG_Get$(splStore, SPK_FxKey$(splI))
        If Len(splTxt) > 0 Then
            If splTxt <> "0" And splTxt <> "1" Then
                spkCfgErr = "speech.ini " + SPK_FxKey$(splI) + ": 0 or 1"
                Exit Function
            End If
            splFx(splI) = (splTxt = "1")
        End If
    Next splI
    For splI = 0 To SPK_PK_N - 1 : spkPk(splI) = splNew(splI) : Next splI
    For splI = 0 To SPK_FX_N - 1 : spkFx(splI) = splFx(splI) : Next splI
    SPK_PlanPitch
    SPK_ProsodyLoad% = -1
End Function

' The line "key=value" for knob or feature slot spsI (knobs first, then the features)
Function SPK_IniLine$ (spiI As Integer)
    If spiI < SPK_PK_N Then
        SPK_IniLine$ = spkPkKey(spiI) + "=" + SPK_Num$(spkPk(spiI))
    Else
        SPK_IniLine$ = SPK_FxKey$(spiI - SPK_PK_N) + "=" + LTrim$(Str$(-(spkFx(spiI - SPK_PK_N) <> 0)))
    End If
End Function

Function SPK_ProsodySave$ (spsSrc As String)
    Dim spsP As Long, spsQ As Long, spsL As String, spsT As String, spsE As Integer, spsI As Integer
    Dim spsOut As String, spsKey As String, spsCr As String, spsDone(0 To SPK_PK_N + SPK_FX_N - 1) As Integer
    spsP = 1
    Do While spsP <= Len(spsSrc)
        spsQ = InStr(spsP, spsSrc, Chr$(10))
        If spsQ = 0 Then spsQ = Len(spsSrc) + 1
        spsL = Mid$(spsSrc, spsP, spsQ - spsP)
        spsP = spsQ + 1
        spsCr = ""
        If Right$(spsL, 1) = Chr$(13) Then spsCr = Chr$(13) : spsL = Left$(spsL, Len(spsL) - 1)
        spsT = LTrim$(spsL)
        spsE = InStr(spsT, "=")
        If Left$(spsT, 1) <> ";" And spsE > 1 Then
            spsKey = RTrim$(Left$(spsT, spsE - 1))
            For spsI = 0 To SPK_PK_N + SPK_FX_N - 1
                If Left$(SPK_IniLine$(spsI), Len(spsKey) + 1) = spsKey + "=" And spsDone(spsI) = 0 Then
                    spsL = SPK_IniLine$(spsI) : spsDone(spsI) = -1
                    Exit For
                End If
            Next spsI
        End If
        spsOut = spsOut + spsL + spsCr + Chr$(10)
    Loop
    For spsI = 0 To SPK_PK_N + SPK_FX_N - 1
        If spsDone(spsI) = 0 Then spsOut = spsOut + SPK_IniLine$(spsI) + Chr$(10)
    Next spsI
    SPK_ProsodySave$ = spsOut
End Function
