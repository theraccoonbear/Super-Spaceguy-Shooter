' music.bas — data-driven BGM engine; data from embedded MUSICDATA (format: header of assets/music.mus)

Const MUS_VOICE_MAX  = 12
Const MUS_CUE_MAX    = 16
Const MUS_CUE_VMAX   = 12
Const MUS_SEQ_MAX    = 64
Const MUS_NOTE_MAX   = 2048
Const MUS_PAD_MAX    = 24
Const MUS_DRUM_MAX   = 16
Const MUS_DRUM_STEPS = 64
Const MUS_INST_MAX   = 32
Const MUS_HARM_MAX   = 16

Const MUS_WAVE_ADD = 0
Const MUS_WAVE_DET = 1
Const MUS_WAVE_SAW = 2
Const MUS_WAVE_SQR = 3

' drum kinds, in DRUM-letter order K S H T C O; a lowercase letter is a soft hit
Const MUS_DK_N      = 6
Const MUS_DK_SOFT   = 0.45
Const MUS_DK_XFADE  = 64      ' a retriggered drum fades its old hit out over this many samples
Const MUS_TAIL_K    = 0.995   ' a cue switch lets the old cue's last sample decay (~5 ms), never step
Const MUS_TWO_PI    = 6.2831853
Const MUS_PI        = 3.14159265

Type MUS_Voice
    vol     As Single
    h2      As Single
    h3      As Single
    gate    As Single
    atk     As Single
    wave    As Integer
    nHarm   As Integer
    atkN    As Long
    relN    As Long
    curAtk  As Long
    curRel  As Long
    sus     As Single
    dk      As Single
    dEnv    As Single
    vel     As Single
    freq    As Single
    phase   As Single
    phase2  As Single
    amp     As Single
    count   As Long
    noteDur As Long
    gateOff As Long
    noteIdx As Integer
    seqBase As Integer
    seqLen  As Integer
    isPad   As Integer
    lastOut As Single
End Type

Dim Shared musInstN$(0 To MUS_INST_MAX - 1)
Dim Shared musInstVol(0 To MUS_INST_MAX - 1)  As Single
Dim Shared musInstH2(0 To MUS_INST_MAX - 1)   As Single
Dim Shared musInstH3(0 To MUS_INST_MAX - 1)   As Single
Dim Shared musInstGate(0 To MUS_INST_MAX - 1) As Single
Dim Shared musInstAtk(0 To MUS_INST_MAX - 1)  As Single
Dim Shared musInstWave(0 To MUS_INST_MAX - 1) As Integer
Dim Shared musInstAMs(0 To MUS_INST_MAX - 1)  As Single
Dim Shared musInstRMs(0 To MUS_INST_MAX - 1)  As Single
Dim Shared musInstSus(0 To MUS_INST_MAX - 1)  As Single
Dim Shared musInstDec(0 To MUS_INST_MAX - 1)  As Single
Dim Shared musInstCnt As Integer

Dim Shared musNF(0 To MUS_NOTE_MAX - 1) As Single   ' note freq pool
Dim Shared musND(0 To MUS_NOTE_MAX - 1) As Integer  ' note dur in steps (CUE div steps per beat)
Dim Shared musNV(0 To MUS_NOTE_MAX - 1) As Single   ' note velocity, 1 = as written
Dim Shared musNCount As Integer

Dim Shared musSeqN$(0 To MUS_SEQ_MAX - 1)
Dim Shared musSeqBase(0 To MUS_SEQ_MAX - 1) As Integer
Dim Shared musSeqLen(0 To MUS_SEQ_MAX - 1)  As Integer
Dim Shared musSeqCnt As Integer

Dim Shared musPadN$(0 To MUS_PAD_MAX - 1)
Dim Shared musPadVol(0 To MUS_PAD_MAX - 1)  As Single
Dim Shared musPadAtk(0 To MUS_PAD_MAX - 1)  As Single
Dim Shared musPadNC(0 To MUS_PAD_MAX - 1)   As Integer
Dim Shared musPadF(0 To MUS_PAD_MAX - 1, 0 To 3) As Single
Dim Shared musPadTotal As Integer

Dim Shared musDrumN$(0 To MUS_DRUM_MAX - 1)
Dim Shared musDrumPat(0 To MUS_DRUM_MAX - 1, 0 To MUS_DRUM_STEPS - 1) As Integer
Dim Shared musDrumLen(0 To MUS_DRUM_MAX - 1) As Integer
Dim Shared musDrumCnt As Integer

Dim Shared musCueN$(0 To MUS_CUE_MAX - 1)
Dim Shared musCueBPM(0 To MUS_CUE_MAX - 1)  As Integer
Dim Shared musCueDiv(0 To MUS_CUE_MAX - 1)  As Integer
Dim Shared musCueVCnt(0 To MUS_CUE_MAX - 1) As Integer
Dim Shared musCueDrum(0 To MUS_CUE_MAX - 1) As Integer
Dim Shared musCueDrumGain(0 To MUS_CUE_MAX - 1) As Single
Dim Shared musCueTmpl(0 To MUS_CUE_MAX - 1, 0 To MUS_CUE_VMAX - 1) As MUS_Voice
Dim Shared musCueCnt As Integer

Dim Shared musVoice(0 To MUS_VOICE_MAX - 1) As MUS_Voice
Dim Shared musVoiceCnt As Integer
Dim Shared musStepDur As Long
Dim Shared musDrumIdx As Integer    : musDrumIdx  = -1
Dim Shared musDrumStep As Integer
Dim Shared musDrumTick As Long
Dim Shared musDrumGain As Single
Dim Shared musParseLine$
Dim Shared musInvK(1 To MUS_HARM_MAX) As Single
Dim Shared musTail As Single, musLastVox As Single

Dim Shared musDkPos(0 To MUS_DK_N - 1) As Long
Dim Shared musDkGain(0 To MUS_DK_N - 1) As Single
Dim Shared musDkOldPos(0 To MUS_DK_N - 1) As Long
Dim Shared musDkOldGain(0 To MUS_DK_N - 1) As Single
Dim Shared musDkOldT(0 To MUS_DK_N - 1) As Integer

' Data problems MUS_Load skipped (bad note, unknown name, a table full); tests require 0.
Dim Shared musLoadErrs As Integer
Dim Shared musLoadErrMsg$

' Consume and return next whitespace-delimited token from musParseLine$.
Function MUS_Tok$
    musParseLine$ = LTrim$(musParseLine$)
    Dim musTokP As Integer : musTokP = InStr(musParseLine$, " ")
    Dim musTokV$
    If musTokP > 0 Then
        musTokV$ = Left$(musParseLine$, musTokP - 1)
        musParseLine$ = Mid$(musParseLine$, musTokP + 1)
    Else
        musTokV$ = musParseLine$ : musParseLine$ = ""
    End If
    MUS_Tok$ = musTokV$
End Function

Sub MUS_LoadErr (musLEmsg$)
    musLoadErrs = musLoadErrs + 1
    If musLoadErrs = 1 Then musLoadErrMsg$ = musLEmsg$
End Sub

' Hz for a note name like A4, C#3, Bb2 (R = rest = 0); -1 if it isn't one.
Function MUS_NoteFreq!(musNFn$)
    If UCase$(musNFn$) = "R" Then MUS_NoteFreq! = 0 : Exit Function
    Dim musNFletter$, musNFrest$
    Dim musNFacc As Integer, musNFoct As Integer
    Dim musNFsemi As Integer, musNFmidi As Integer
    musNFletter$ = UCase$(Left$(musNFn$, 1))
    musNFrest$   = Mid$(musNFn$, 2)
    musNFacc = 0
    If Left$(musNFrest$, 1) = "#" Then musNFacc =  1 : musNFrest$ = Mid$(musNFrest$, 2)
    If Left$(musNFrest$, 1) = "b" Then musNFacc = -1 : musNFrest$ = Mid$(musNFrest$, 2)
    If Len(musNFrest$) <> 1 Or InStr("012345678", musNFrest$) = 0 Then MUS_NoteFreq! = -1 : Exit Function
    musNFoct = Val(musNFrest$)
    Select Case musNFletter$
        Case "C" : musNFsemi = 0
        Case "D" : musNFsemi = 2
        Case "E" : musNFsemi = 4
        Case "F" : musNFsemi = 5
        Case "G" : musNFsemi = 7
        Case "A" : musNFsemi = 9
        Case "B" : musNFsemi = 11
        Case Else : MUS_NoteFreq! = -1 : Exit Function
    End Select
    musNFmidi = musNFsemi + musNFacc + (musNFoct + 1) * 12
    MUS_NoteFreq! = 440.0 * 2.0 ^ ((musNFmidi - 69) / 12.0)
End Function

' Hit bits for one DRUM step: bit k = drum kind k (K S H T C O), bit k+8 = that hit is soft.
' -1 if the step has a character that isn't a drum.
Function MUS_DrumBits%(musDTok$)
    Dim musDB As Integer, musDBi As Integer, musDBc$, musDBk As Integer
    For musDBi = 1 To Len(musDTok$)
        musDBc$ = Mid$(musDTok$, musDBi, 1)
        musDBk = InStr("KSHTCO", UCase$(musDBc$)) - 1
        If musDBk >= 0 Then
            musDB = musDB Or (2 ^ musDBk)
            If musDBc$ <> UCase$(musDBc$) Then musDB = musDB Or (2 ^ (musDBk + 8))
        ElseIf musDBc$ <> "." Then
            MUS_DrumBits% = -1 : Exit Function
        End If
    Next musDBi
    MUS_DrumBits% = musDB
End Function

Function MUS_FindInst%(musFIn$)
    Dim musFIi As Integer
    For musFIi = 0 To musInstCnt - 1
        If musInstN$(musFIi) = musFIn$ Then MUS_FindInst% = musFIi : Exit Function
    Next musFIi
    MUS_FindInst% = -1
End Function

Function MUS_FindSeq%(musFSn$)
    Dim musFSi As Integer
    For musFSi = 0 To musSeqCnt - 1
        If musSeqN$(musFSi) = musFSn$ Then MUS_FindSeq% = musFSi : Exit Function
    Next musFSi
    MUS_FindSeq% = -1
End Function

Function MUS_FindPad%(musFPn$)
    Dim musFPi As Integer
    For musFPi = 0 To musPadTotal - 1
        If musPadN$(musFPi) = musFPn$ Then MUS_FindPad% = musFPi : Exit Function
    Next musFPi
    MUS_FindPad% = -1
End Function

Function MUS_FindDrum%(musFDn$)
    Dim musFDi As Integer
    For musFDi = 0 To musDrumCnt - 1
        If musDrumN$(musFDi) = musFDn$ Then MUS_FindDrum% = musFDi : Exit Function
    Next musFDi
    MUS_FindDrum% = -1
End Function

' "+name" or "+name^semitones" inside a SEQ: append an earlier SEQ's notes, transposed.
Sub MUS_SeqCopy (scRef$, scInto$)
    Dim scP As Integer, scName$, scSemi As Integer, scS As Integer, scI As Integer, scMul As Single
    scP = InStr(scRef$, "^")
    scName$ = scRef$
    If scP > 0 Then scName$ = Left$(scRef$, scP - 1) : scSemi = Val(Mid$(scRef$, scP + 1))
    scS = MUS_FindSeq%(scName$)
    If scS < 0 Then MUS_LoadErr "SEQ " + scInto$ + ": +" + scRef$ + " names no earlier SEQ" : Exit Sub
    scMul = 2 ^ (scSemi / 12)
    For scI = musSeqBase(scS) To musSeqBase(scS) + musSeqLen(scS) - 1
        If musNCount >= MUS_NOTE_MAX Then MUS_LoadErr "note pool full in SEQ " + scInto$ : Exit Sub
        musNF(musNCount) = musNF(scI) * scMul
        musND(musNCount) = musND(scI)
        musNV(musNCount) = musNV(scI)
        musNCount = musNCount + 1
    Next scI
End Sub

Sub MUS_Load()
    Dim musLdat$, musLrest$, musLn$, musLdir$, musLtmp$, musLkey$
    Dim musLnote$, musLdur$, musLpn$, musLdstep$, musLvel$
    Dim musLp As Integer, musLat As Integer, musLbits As Integer, musLposAtk As Integer
    Dim musLii As Integer, musLsi As Integer, musLpi As Integer
    Dim musLdi As Integer, musLvi As Integer
    Dim musLpni As Integer, musLsidx As Integer
    Dim musLfreq As Single
    Dim musLcur As Integer : musLcur = -1

    For musLii = 1 To MUS_HARM_MAX : musInvK(musLii) = 1 / musLii : Next musLii
    For musLii = 0 To MUS_DK_N - 1 : musDkPos(musLii) = -1 : musDkOldPos(musLii) = -1 : Next musLii

    musLdat$  = _EMBEDDED$("MUSICDATA")
    musLrest$ = musLdat$

    Do While Len(musLrest$) > 0
        musLp = InStr(musLrest$, Chr$(10))
        If musLp > 0 Then
            musLn$    = Left$(musLrest$, musLp - 1)
            musLrest$ = Mid$(musLrest$, musLp + 1)
        Else
            musLn$ = musLrest$ : musLrest$ = ""
        End If
        If Len(musLn$) > 0 And Right$(musLn$, 1) = Chr$(13) Then musLn$ = Left$(musLn$, Len(musLn$) - 1)
        musLn$ = LTrim$(RTrim$(musLn$))
        If Len(musLn$) = 0 Or Left$(musLn$, 1) = "#" Then GoTo musNextLine

        musParseLine$ = musLn$
        musLdir$ = MUS_Tok$

        Select Case UCase$(musLdir$)
            Case "INST"
                If musInstCnt >= MUS_INST_MAX Then MUS_LoadErr "INST table full: " + musLn$ : GoTo musNextLine
                musLii = musInstCnt
                musInstN$(musLii)   = MUS_Tok$
                musInstVol(musLii)  = Val(MUS_Tok$)
                musInstH2(musLii)   = Val(MUS_Tok$)
                musInstH3(musLii)   = Val(MUS_Tok$)
                musInstGate(musLii) = Val(MUS_Tok$)
                musInstAMs(musLii) = 3 : musInstRMs(musLii) = 5 : musInstSus(musLii) = 1
                musLposAtk = 0
                musLtmp$ = MUS_Tok$
                Do While Len(musLtmp$) > 0
                    musLkey$ = UCase$(Left$(musLtmp$, 2))
                    Select Case UCase$(musLtmp$)
                        Case "DET" : musInstWave(musLii) = MUS_WAVE_DET
                        Case "SAW" : musInstWave(musLii) = MUS_WAVE_SAW
                        Case "SQR" : musInstWave(musLii) = MUS_WAVE_SQR
                        Case Else
                            If musLkey$ = "A=" Then
                                musInstAMs(musLii) = Val(Mid$(musLtmp$, 3))
                            ElseIf musLkey$ = "R=" Then
                                musInstRMs(musLii) = Val(Mid$(musLtmp$, 3))
                            ElseIf musLkey$ = "S=" Then
                                musInstSus(musLii) = Val(Mid$(musLtmp$, 3))
                            ElseIf musLkey$ = "D=" Then
                                musInstDec(musLii) = Val(Mid$(musLtmp$, 3))
                            ElseIf musLposAtk = 0 And InStr("0123456789.", Left$(musLtmp$, 1)) > 0 Then
                                musInstAtk(musLii) = Val(musLtmp$) : musLposAtk = -1
                            Else
                                MUS_LoadErr "INST " + musInstN$(musLii) + ": unknown option " + musLtmp$
                            End If
                    End Select
                    musLtmp$ = MUS_Tok$
                Loop
                If musInstGate(musLii) <= 0 Or musInstGate(musLii) > 1 Or musInstVol(musLii) <= 0 Then MUS_LoadErr "INST " + musInstN$(musLii) + ": vol or gate out of range"
                If musInstAMs(musLii) < 1 Or musInstRMs(musLii) < 1 Then MUS_LoadErr "INST " + musInstN$(musLii) + ": A= and R= must be >= 1 ms (click-free)"
                If musInstSus(musLii) < 0 Or musInstSus(musLii) > 1 Or musInstDec(musLii) < 0 Then MUS_LoadErr "INST " + musInstN$(musLii) + ": S= must be 0..1, D= >= 0"
                musInstCnt = musInstCnt + 1

            Case "SEQ"
                If musSeqCnt >= MUS_SEQ_MAX Then MUS_LoadErr "SEQ table full: " + musLn$ : GoTo musNextLine
                musLsi = musSeqCnt
                musSeqN$(musLsi)   = MUS_Tok$
                musSeqBase(musLsi) = musNCount
                musLnote$ = MUS_Tok$
                Do While Len(musLnote$) > 0
                    If Left$(musLnote$, 1) = "+" Then
                        MUS_SeqCopy Mid$(musLnote$, 2), musSeqN$(musLsi)
                        musLnote$ = MUS_Tok$
                        _Continue
                    End If
                    musLdur$ = MUS_Tok$
                    musLvel$ = "100"
                    musLat = InStr(musLnote$, "@")
                    If musLat > 0 Then musLvel$ = Mid$(musLnote$, musLat + 1) : musLnote$ = Left$(musLnote$, musLat - 1)
                    musLfreq = MUS_NoteFreq(musLnote$)
                    If musLfreq < 0 Or Val(musLdur$) < 1 Or Val(musLvel$) < 1 Or Val(musLvel$) > 150 Then
                        MUS_LoadErr "SEQ " + musSeqN$(musLsi) + ": bad note '" + musLnote$ + "' dur '" + musLdur$ + "' vel '" + musLvel$ + "'"
                    ElseIf musNCount >= MUS_NOTE_MAX Then
                        MUS_LoadErr "note pool full in SEQ " + musSeqN$(musLsi)
                    Else
                        musNF(musNCount) = musLfreq
                        musND(musNCount) = Val(musLdur$)
                        musNV(musNCount) = Val(musLvel$) / 100
                        musNCount = musNCount + 1
                    End If
                    musLnote$ = MUS_Tok$
                Loop
                musSeqLen(musLsi) = musNCount - musSeqBase(musLsi)
                If musSeqLen(musLsi) = 0 Then MUS_LoadErr "SEQ " + musSeqN$(musLsi) + " has no notes" Else musSeqCnt = musSeqCnt + 1

            Case "PAD"
                If musPadTotal >= MUS_PAD_MAX Then MUS_LoadErr "PAD table full: " + musLn$ : GoTo musNextLine
                musLpi = musPadTotal
                musPadN$(musLpi)  = MUS_Tok$
                musPadVol(musLpi) = Val(MUS_Tok$)
                musPadAtk(musLpi) = Val(MUS_Tok$)
                musPadNC(musLpi)  = 0
                musLpn$ = MUS_Tok$
                Do While Len(musLpn$) > 0
                    musLfreq = MUS_NoteFreq(musLpn$)
                    If musLfreq <= 0 Or musPadNC(musLpi) >= 4 Then
                        MUS_LoadErr "PAD " + musPadN$(musLpi) + ": bad or 5th note " + musLpn$
                    Else
                        musPadF(musLpi, musPadNC(musLpi)) = musLfreq
                        musPadNC(musLpi) = musPadNC(musLpi) + 1
                    End If
                    musLpn$ = MUS_Tok$
                Loop
                If musPadAtk(musLpi) <= 0 Or musPadAtk(musLpi) > 0.01 Then MUS_LoadErr "PAD " + musPadN$(musLpi) + ": attack must be in (0, 0.01] (click-free fade-in)"
                musPadTotal = musPadTotal + 1

            Case "DRUM"
                If musDrumCnt >= MUS_DRUM_MAX Then MUS_LoadErr "DRUM table full: " + musLn$ : GoTo musNextLine
                musLdi = musDrumCnt
                musDrumN$(musLdi)  = MUS_Tok$
                musDrumLen(musLdi) = 0
                musLdstep$ = MUS_Tok$
                Do While Len(musLdstep$) > 0
                    musLbits = MUS_DrumBits%(musLdstep$)
                    If musLbits < 0 Or musDrumLen(musLdi) >= MUS_DRUM_STEPS Then
                        MUS_LoadErr "DRUM " + musDrumN$(musLdi) + ": bad step '" + musLdstep$ + "' or more than" + Str$(MUS_DRUM_STEPS) + " steps"
                    Else
                        musDrumPat(musLdi, musDrumLen(musLdi)) = musLbits
                        musDrumLen(musLdi) = musDrumLen(musLdi) + 1
                    End If
                    musLdstep$ = MUS_Tok$
                Loop
                musDrumCnt = musDrumCnt + 1

            Case "CUE"
                If musCueCnt >= MUS_CUE_MAX Then musLcur = -1 : MUS_LoadErr "CUE table full: " + musLn$ : GoTo musNextLine
                musLcur = musCueCnt
                musCueN$(musLcur)   = MUS_Tok$
                musCueBPM(musLcur)  = Val(MUS_Tok$)
                musLtmp$ = MUS_Tok$
                musCueDiv(musLcur) = 4
                If Len(musLtmp$) > 0 Then musCueDiv(musLcur) = Val(musLtmp$)
                If musCueBPM(musLcur) < 20 Or musCueBPM(musLcur) > 300 Or musCueDiv(musLcur) < 1 Or musCueDiv(musLcur) > 12 Then
                    MUS_LoadErr "CUE " + musCueN$(musLcur) + ": bpm must be 20..300 and div 1..12"
                    If musCueBPM(musLcur) < 20 Then musCueBPM(musLcur) = 20
                    If musCueDiv(musLcur) < 1 Or musCueDiv(musLcur) > 12 Then musCueDiv(musLcur) = 4
                End If
                musCueVCnt(musLcur) = 0
                musCueDrum(musLcur) = -1
                musCueDrumGain(musLcur) = 1
                musCueCnt = musCueCnt + 1

            Case "VOICE"
                If musLcur < 0 Then MUS_LoadErr "VOICE outside a CUE: " + musLn$ : GoTo musNextLine
                If musCueVCnt(musLcur) >= MUS_CUE_VMAX Then MUS_LoadErr "CUE " + musCueN$(musLcur) + ": more than" + Str$(MUS_CUE_VMAX) + " voices" : GoTo musNextLine
                musLtmp$ = MUS_Tok$ : musLsi   = MUS_FindInst%(musLtmp$)
                musLtmp$ = MUS_Tok$ : musLsidx = MUS_FindSeq%(musLtmp$)
                If musLsi < 0 Or musLsidx < 0 Then MUS_LoadErr "VOICE with unknown INST or SEQ: " + musLn$ : GoTo musNextLine
                musLvi = musCueVCnt(musLcur)
                musCueTmpl(musLcur, musLvi).vol     = musInstVol(musLsi)
                musCueTmpl(musLcur, musLvi).h2      = musInstH2(musLsi)
                musCueTmpl(musLcur, musLvi).h3      = musInstH3(musLsi)
                musCueTmpl(musLcur, musLvi).gate    = musInstGate(musLsi)
                musCueTmpl(musLcur, musLvi).atk     = musInstAtk(musLsi)
                musCueTmpl(musLcur, musLvi).wave    = musInstWave(musLsi)
                musCueTmpl(musLcur, musLvi).atkN    = CLng(musInstAMs(musLsi) * SAMPLE_RATE / 1000)
                musCueTmpl(musLcur, musLvi).relN    = CLng(musInstRMs(musLsi) * SAMPLE_RATE / 1000)
                musCueTmpl(musLcur, musLvi).sus     = musInstSus(musLsi)
                musCueTmpl(musLcur, musLvi).dk      = 1
                If musInstDec(musLsi) > 0 Then musCueTmpl(musLcur, musLvi).dk = Exp(-1 / (musInstDec(musLsi) * SAMPLE_RATE))
                musCueTmpl(musLcur, musLvi).seqBase = musSeqBase(musLsidx)
                musCueTmpl(musLcur, musLvi).seqLen  = musSeqLen(musLsidx)
                musCueTmpl(musLcur, musLvi).isPad   = 0
                musCueVCnt(musLcur) = musLvi + 1

            Case "CHORD"
                If musLcur < 0 Then MUS_LoadErr "CHORD outside a CUE: " + musLn$ : GoTo musNextLine
                musLtmp$ = MUS_Tok$ : musLpi = MUS_FindPad%(musLtmp$)
                If musLpi < 0 Then MUS_LoadErr "CHORD with unknown PAD: " + musLn$ : GoTo musNextLine
                For musLpni = 0 To musPadNC(musLpi) - 1
                    If musCueVCnt(musLcur) < MUS_CUE_VMAX Then
                        musLvi = musCueVCnt(musLcur)
                        musCueTmpl(musLcur, musLvi).vol   = musPadVol(musLpi)
                        musCueTmpl(musLcur, musLvi).atk   = musPadAtk(musLpi)
                        musCueTmpl(musLcur, musLvi).freq  = musPadF(musLpi, musLpni)
                        musCueTmpl(musLcur, musLvi).isPad = -1
                        musCueVCnt(musLcur) = musLvi + 1
                    Else
                        MUS_LoadErr "CUE " + musCueN$(musLcur) + ": more than" + Str$(MUS_CUE_VMAX) + " voices"
                    End If
                Next musLpni

            Case "DRUMS"
                If musLcur < 0 Then MUS_LoadErr "DRUMS outside a CUE: " + musLn$ : GoTo musNextLine
                musLtmp$ = MUS_Tok$
                musCueDrum(musLcur) = MUS_FindDrum%(musLtmp$)
                If musCueDrum(musLcur) < 0 Then MUS_LoadErr "DRUMS with unknown DRUM: " + musLn$
                musLtmp$ = MUS_Tok$
                If Len(musLtmp$) > 0 Then musCueDrumGain(musLcur) = Val(musLtmp$)

            Case Else
                MUS_LoadErr "unknown directive: " + musLn$
        End Select

        musNextLine:
    Loop
End Sub

' Load note nsIdx into sequenced voice nsV: its length, gate, pitch, velocity and the
' attack/release it gets (each at most half the sounding time, so short notes still close).
Sub MUS_NoteStart (nsV As Integer, nsIdx As Integer)
    Dim nsLen As Long, nsMax As Integer
    musVoice(nsV).noteDur = CLng(musND(nsIdx)) * musStepDur
    musVoice(nsV).count   = musVoice(nsV).noteDur
    musVoice(nsV).gateOff = CLng(musVoice(nsV).noteDur * (1.0 - musVoice(nsV).gate))
    musVoice(nsV).freq    = musNF(nsIdx)
    musVoice(nsV).vel     = musNV(nsIdx)
    musVoice(nsV).phase   = 0
    musVoice(nsV).phase2  = 0
    musVoice(nsV).dEnv    = 1
    nsLen = musVoice(nsV).noteDur - musVoice(nsV).gateOff
    musVoice(nsV).curAtk = musVoice(nsV).atkN
    If musVoice(nsV).curAtk > nsLen \ 2 Then musVoice(nsV).curAtk = nsLen \ 2
    musVoice(nsV).curRel = musVoice(nsV).relN
    If musVoice(nsV).curRel > nsLen \ 2 Then musVoice(nsV).curRel = nsLen \ 2
    If musVoice(nsV).wave = MUS_WAVE_SAW Or musVoice(nsV).wave = MUS_WAVE_SQR Then
        nsMax = 8 : If musVoice(nsV).wave = MUS_WAVE_SQR Then nsMax = 15
        If musVoice(nsV).h2 >= 1 Then nsMax = Int(musVoice(nsV).h2)
        If nsMax > MUS_HARM_MAX Then nsMax = MUS_HARM_MAX
        If musVoice(nsV).freq > 0 Then
            Do While nsMax > 1 And nsMax * musVoice(nsV).freq > 16000 : nsMax = nsMax - 1 : Loop
        End If
        musVoice(nsV).nHarm = nsMax
    End If
End Sub

Sub MUS_SetCue(musSCn$)
    Dim musSCi As Integer, musSCv As Integer
    For musSCi = 0 To musCueCnt - 1
        If musCueN$(musSCi) = musSCn$ Then Exit For
    Next musSCi
    If musSCi >= musCueCnt Then Exit Sub

    musTail = musTail + musLastVox
    musLastVox = 0
    musStepDur   = CLng(SAMPLE_RATE) * 60 \ (CLng(musCueBPM(musSCi)) * musCueDiv(musSCi))
    musVoiceCnt  = musCueVCnt(musSCi)

    For musSCv = 0 To musVoiceCnt - 1
        musVoice(musSCv)         = musCueTmpl(musSCi, musSCv)
        musVoice(musSCv).phase   = 0
        musVoice(musSCv).amp     = 0
        musVoice(musSCv).lastOut = 0
        If musVoice(musSCv).isPad = 0 Then
            musVoice(musSCv).noteIdx = 0
            MUS_NoteStart musSCv, musVoice(musSCv).seqBase
        End If
    Next musSCv

    musDrumIdx  = musCueDrum(musSCi)
    musDrumGain = musCueDrumGain(musSCi)
    If musDrumIdx >= 0 Then
        musDrumStep = musDrumLen(musDrumIdx) - 1
        musDrumTick = 1
    End If
End Sub

Function MUS_DkLen& (dlK As Integer)
    Select Case dlK
        Case 0 : MUS_DkLen& = SND_KICK_LEN
        Case 1 : MUS_DkLen& = SND_SNARE_LEN
        Case 2 : MUS_DkLen& = SND_HIHAT_LEN
        Case 3 : MUS_DkLen& = SND_TOM_LEN
        Case 4 : MUS_DkLen& = SND_CRASH_LEN
        Case 5 : MUS_DkLen& = SND_OHAT_LEN
    End Select
End Function

Function MUS_DkSample! (dsK As Integer, dsPos As Long)
    Select Case dsK
        Case 0 : MUS_DkSample! = sndKick(dsPos)
        Case 1 : MUS_DkSample! = sndSnare(dsPos)
        Case 2 : MUS_DkSample! = sndHihat(dsPos)
        Case 3 : MUS_DkSample! = sndTom(dsPos)
        Case 4 : MUS_DkSample! = sndCrash(dsPos)
        Case 5 : MUS_DkSample! = sndOHat(dsPos)
    End Select
End Function

' Start drum kind dhK at gain dhG. A hit still ringing isn't cut: it fades out over MUS_DK_XFADE.
Sub MUS_DrumHit (dhK As Integer, dhG As Single)
    If musDkPos(dhK) >= 0 Then
        musDkOldPos(dhK) = musDkPos(dhK) : musDkOldGain(dhK) = musDkGain(dhK) : musDkOldT(dhK) = 0
    End If
    musDkPos(dhK) = 0 : musDkGain(dhK) = dhG
End Sub

' One sample of the current cue: its voices, pads and drum pattern, before volume.
Function MUS_MusicSample!
    Dim musMSs As Single, musMSvi As Integer, musMSph As Single
    Dim musMSdbits As Integer, musMSk As Integer, musMSg As Single
    Dim musMSw As Single, musMSenv As Single, musMSel As Long, musMSleft As Long
    Dim musMSs1 As Single, musMSc2 As Single, musMSsp As Single, musMSsc As Single, musMSsn As Single
    Dim musMSout As Single
    musMSs = 0
    For musMSvi = 0 To musVoiceCnt - 1
        If musVoice(musMSvi).isPad Then
            musVoice(musMSvi).amp   = musVoice(musMSvi).amp + (musVoice(musMSvi).vol - musVoice(musMSvi).amp) * musVoice(musMSvi).atk
            musVoice(musMSvi).phase = musVoice(musMSvi).phase + MUS_TWO_PI * musVoice(musMSvi).freq / SAMPLE_RATE
            If musVoice(musMSvi).phase > MUS_TWO_PI Then musVoice(musMSvi).phase = musVoice(musMSvi).phase - MUS_TWO_PI
            musMSout = Sin(musVoice(musMSvi).phase) * musVoice(musMSvi).amp
        Else
            musMSout = 0
            musVoice(musMSvi).count = musVoice(musMSvi).count - 1
            If musVoice(musMSvi).count <= 0 Then
                musVoice(musMSvi).noteIdx = (musVoice(musMSvi).noteIdx + 1) Mod musVoice(musMSvi).seqLen
                MUS_NoteStart musMSvi, musVoice(musMSvi).seqBase + musVoice(musMSvi).noteIdx
            End If
            If musVoice(musMSvi).count > musVoice(musMSvi).gateOff And musVoice(musMSvi).freq > 0 Then
                musVoice(musMSvi).phase = musVoice(musMSvi).phase + MUS_TWO_PI * musVoice(musMSvi).freq / SAMPLE_RATE
                If musVoice(musMSvi).phase > MUS_TWO_PI Then musVoice(musMSvi).phase = musVoice(musMSvi).phase - MUS_TWO_PI
                musMSph = musVoice(musMSvi).phase
                Select Case musVoice(musMSvi).wave
                    Case MUS_WAVE_DET
                        musVoice(musMSvi).phase2 = musVoice(musMSvi).phase2 + MUS_TWO_PI * musVoice(musMSvi).freq * (1.0 + musVoice(musMSvi).h3) / SAMPLE_RATE
                        If musVoice(musMSvi).phase2 > MUS_TWO_PI Then musVoice(musMSvi).phase2 = musVoice(musMSvi).phase2 - MUS_TWO_PI
                        musMSw = Sin(musMSph) + Sin(musVoice(musMSvi).phase2) * musVoice(musMSvi).h2
                    Case MUS_WAVE_SAW, MUS_WAVE_SQR
                        ' band-limited: sin(k*ph) for k = 2..nHarm by the Chebyshev recurrence, 1/k each
                        musMSs1 = Sin(musMSph) : musMSc2 = 2 * Cos(musMSph)
                        musMSsp = 0 : musMSsc = musMSs1 : musMSw = musMSs1
                        For musMSk = 2 To musVoice(musMSvi).nHarm
                            musMSsn = musMSc2 * musMSsc - musMSsp : musMSsp = musMSsc : musMSsc = musMSsn
                            If musVoice(musMSvi).wave = MUS_WAVE_SAW Or (musMSk And 1) = 1 Then musMSw = musMSw + musMSsc * musInvK(musMSk)
                        Next musMSk
                        If musVoice(musMSvi).wave = MUS_WAVE_SAW Then musMSw = musMSw * 0.6 Else musMSw = musMSw * 1.1
                    Case Else
                        musMSw = Sin(musMSph) + Sin(musMSph * 2) * musVoice(musMSvi).h2 + Sin(musMSph * 3) * musVoice(musMSvi).h3
                End Select
                ' raised-cosine attack from 0 and release to exactly 0 at gate-off, so no note clicks
                musMSenv = 1
                musMSel = musVoice(musMSvi).noteDur - musVoice(musMSvi).count
                If musMSel < musVoice(musMSvi).curAtk Then musMSenv = 0.5 - 0.5 * Cos(MUS_PI * musMSel / musVoice(musMSvi).curAtk)
                musMSleft = musVoice(musMSvi).count - musVoice(musMSvi).gateOff
                If musMSleft <= musVoice(musMSvi).curRel Then musMSenv = musMSenv * (0.5 - 0.5 * Cos(MUS_PI * (musMSleft - 1) / musVoice(musMSvi).curRel))
                If musMSel = 0 Or musMSleft <= 1 Then musMSenv = 0
                If musVoice(musMSvi).dk < 1 Then
                    musVoice(musMSvi).dEnv = musVoice(musMSvi).dEnv * musVoice(musMSvi).dk
                    musMSenv = musMSenv * (musVoice(musMSvi).sus + (1 - musVoice(musMSvi).sus) * musVoice(musMSvi).dEnv)
                End If
                musMSout = musMSw * musVoice(musMSvi).vol * musVoice(musMSvi).vel * musMSenv
            End If
        End If
        musVoice(musMSvi).lastOut = musMSout
        musMSs = musMSs + musMSout
    Next musMSvi
    musLastVox = musMSs
    musTail = musTail * MUS_TAIL_K
    musMSs = musMSs + musTail

    If musDrumIdx >= 0 Then
        musDrumTick = musDrumTick - 1
        If musDrumTick <= 0 Then
            musDrumStep = (musDrumStep + 1) Mod musDrumLen(musDrumIdx)
            musDrumTick = musStepDur
            musMSdbits = musDrumPat(musDrumIdx, musDrumStep)
            For musMSk = 0 To MUS_DK_N - 1
                If musMSdbits And (2 ^ musMSk) Then
                    musMSg = musDrumGain
                    If musMSdbits And (2 ^ (musMSk + 8)) Then musMSg = musMSg * MUS_DK_SOFT
                    MUS_DrumHit musMSk, musMSg
                End If
            Next musMSk
        End If
    End If

    For musMSk = 0 To MUS_DK_N - 1
        If musDkPos(musMSk) >= 0 Then
            musMSs = musMSs + MUS_DkSample!(musMSk, musDkPos(musMSk)) * musDkGain(musMSk)
            musDkPos(musMSk) = musDkPos(musMSk) + 1
            If musDkPos(musMSk) >= MUS_DkLen&(musMSk) Then musDkPos(musMSk) = -1
        End If
        If musDkOldPos(musMSk) >= 0 Then
            musDkOldT(musMSk) = musDkOldT(musMSk) + 1
            musMSs = musMSs + MUS_DkSample!(musMSk, musDkOldPos(musMSk)) * musDkOldGain(musMSk) * (1 - musDkOldT(musMSk) / MUS_DK_XFADE)
            musDkOldPos(musMSk) = musDkOldPos(musMSk) + 1
            If musDkOldT(musMSk) >= MUS_DK_XFADE Or musDkOldPos(musMSk) >= MUS_DkLen&(musMSk) Then musDkOldPos(musMSk) = -1
        End If
    Next musMSk
    MUS_MusicSample! = musMSs
End Function

Sub MUS_Fill(musFdoSfx As Integer)
    Dim musFillCnt As Integer, musFk As Integer
    Dim musFsample As Single, musFefx As Single, musFnarBlip As Single

    musFillCnt = Int((AUDIO_BUFFER_TARGET - _SNDRAWLEN) * SAMPLE_RATE)
    If musFillCnt <= 0 Then Exit Sub

    For musFk = 0 To musFillCnt - 1
        If musFdoSfx Then
            sndEnginePhase = sndEnginePhase + 6.2832 * sndEngineFreq / SAMPLE_RATE
            If sndEnginePhase > 6.2832 Then sndEnginePhase = sndEnginePhase - 6.2832
        End If

        musFsample = MUS_MusicSample!

        musFefx = 0 : musFnarBlip = 0
        musFefx = musFefx + SND_UiNext!   ' UI one-shots and the power-up chime (snd.bas)
        If sndDeathPos >= 0 Then
            musFefx = musFefx + sndDeath(sndDeathPos)
            sndDeathPos = sndDeathPos + 1
            If sndDeathPos >= SND_DEATH_LEN Then sndDeathPos = -1
        End If
        If sndBlipTimer > 0 Then
            Dim blpPos As Long, blpEnv As Single
            blpPos = sndBlipLen - sndBlipTimer
            If blpPos < sndBlipLen * 0.1 Then
                blpEnv = blpPos / (sndBlipLen * 0.1)
            ElseIf blpPos > sndBlipLen * 0.55 Then
                blpEnv = 1.0 - (blpPos - sndBlipLen * 0.55) / (sndBlipLen * 0.45)
            Else
                blpEnv = 1.0
            End If
            If blpEnv < 0 Then blpEnv = 0
            If blpPos < sndBlipPlosLen Then
                musFnarBlip = (RNG!(RNG_AUDIO) * 2.0 - 1.0) * blpEnv * 0.22
            Else
                sndBlipPhase = sndBlipPhase + 6.2832 * sndBlipFreq / SAMPLE_RATE
                If sndBlipPhase > 6.2832 Then sndBlipPhase = sndBlipPhase - 6.2832
                musFnarBlip = (Sin(sndBlipPhase) + Sin(sndBlipPhase * 2.0) * 0.35) * blpEnv * 0.26
            End If
            sndBlipTimer = sndBlipTimer - 1
        End If

        If musFdoSfx Then
            If sndShootPos >= 0 Then
                musFefx = musFefx + sndShoot(sndShootPos)
                sndShootPos = sndShootPos + 1
                If sndShootPos >= SND_SHOOT_LEN Then sndShootPos = -1
            End If
            If sndBoomPos >= 0 Then
                musFefx = musFefx + sndBoom(sndBoomPos)
                sndBoomPos = sndBoomPos + 1
                If sndBoomPos >= SND_BOOM_LEN Then sndBoomPos = -1
            End If
            If sndHitPos >= 0 Then
                musFefx = musFefx + sndHit(sndHitPos)
                sndHitPos = sndHitPos + 1
                If sndHitPos >= SND_HIT_LEN Then sndHitPos = -1
            End If
            If sndWhooshPos >= 0 Then
                musFefx = musFefx + sndWhoosh(sndWhooshPos)
                sndWhooshPos = sndWhooshPos + 1
                If sndWhooshPos >= SND_WHOOSH_LEN Then sndWhooshPos = -1
            End If
            If sndWhooshMdPos >= 0 Then
                musFefx = musFefx + sndWhooshMd(sndWhooshMdPos)
                sndWhooshMdPos = sndWhooshMdPos + 1
                If sndWhooshMdPos >= SND_WHOOSH_LEN Then sndWhooshMdPos = -1
            End If
            If sndWhooshLgPos >= 0 Then
                musFefx = musFefx + sndWhooshLg(sndWhooshLgPos)
                sndWhooshLgPos = sndWhooshLgPos + 1
                If sndWhooshLgPos >= SND_WHOOSH_LEN Then sndWhooshLgPos = -1
            End If
            SPK_Advance
            _SNDRAW ((Sin(sndEnginePhase) + Sin(sndEnginePhase * 2) * 0.4 + Sin(sndEnginePhase * 3) * 0.15) * sndEngineAmp * 0.35 + musFefx) * volSfx _
                  + musFsample * volMusic + (spkSampleOut + musFnarBlip) * volSpeech
        Else
            SPK_Advance
            _SNDRAW musFsample * volMusic + musFefx * volSfx + (spkSampleOut + musFnarBlip) * volSpeech
        End If
    Next musFk
End Sub
