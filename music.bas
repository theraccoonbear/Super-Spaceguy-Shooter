' music.bas — data-driven BGM engine; data from embedded MUSICDATA

Const MUS_VOICE_MAX  = 10
Const MUS_CUE_MAX    = 10
Const MUS_CUE_VMAX   = 8
Const MUS_SEQ_MAX    = 14
Const MUS_NOTE_MAX   = 256
Const MUS_PAD_MAX    = 8
Const MUS_DRUM_MAX   = 4
Const MUS_DRUM_STEPS = 32
Const MUS_INST_MAX   = 10

Type MUS_Voice
    vol     As Single
    h2      As Single
    h3      As Single
    gate    As Single
    atk     As Single
    isDet   As Integer
    freq    As Single
    phase   As Single
    amp     As Single
    count   As Long
    noteDur As Long
    gateOff As Long
    noteIdx As Integer
    seqBase As Integer
    seqLen  As Integer
    isPad   As Integer
End Type

Dim Shared musInstN$(0 To MUS_INST_MAX - 1)
Dim Shared musInstVol(0 To MUS_INST_MAX - 1)  As Single
Dim Shared musInstH2(0 To MUS_INST_MAX - 1)   As Single
Dim Shared musInstH3(0 To MUS_INST_MAX - 1)   As Single
Dim Shared musInstGate(0 To MUS_INST_MAX - 1) As Single
Dim Shared musInstAtk(0 To MUS_INST_MAX - 1)  As Single
Dim Shared musInstDet(0 To MUS_INST_MAX - 1)  As Integer
Dim Shared musInstCnt As Integer

Dim Shared musNF(0 To MUS_NOTE_MAX - 1) As Single   ' note freq pool
Dim Shared musND(0 To MUS_NOTE_MAX - 1) As Integer  ' note dur in 16th units
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
Dim Shared musCueVCnt(0 To MUS_CUE_MAX - 1) As Integer
Dim Shared musCueDrum(0 To MUS_CUE_MAX - 1) As Integer
Dim Shared musCueTmpl(0 To MUS_CUE_MAX - 1, 0 To MUS_CUE_VMAX - 1) As MUS_Voice
Dim Shared musCueCnt As Integer

Dim Shared musVoice(0 To MUS_VOICE_MAX - 1) As MUS_Voice
Dim Shared musVoiceCnt As Integer
Dim Shared musStepDur As Long
Dim Shared musDrumIdx As Integer    : musDrumIdx  = -1
Dim Shared musDrumStep As Integer
Dim Shared musDrumTick As Long
Dim Shared musParseLine$

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
    musNFoct = Val(musNFrest$)
    Select Case musNFletter$
        Case "C" : musNFsemi = 0
        Case "D" : musNFsemi = 2
        Case "E" : musNFsemi = 4
        Case "F" : musNFsemi = 5
        Case "G" : musNFsemi = 7
        Case "A" : musNFsemi = 9
        Case "B" : musNFsemi = 11
    End Select
    musNFmidi = musNFsemi + musNFacc + (musNFoct + 1) * 12
    MUS_NoteFreq! = 440.0 * 2.0 ^ ((musNFmidi - 69) / 12.0)
End Function

Function MUS_DrumBits%(musDTok$)
    Dim musDB As Integer, musDBi As Integer
    For musDBi = 1 To Len(musDTok$)
        Select Case Mid$(musDTok$, musDBi, 1)
            Case "K", "k" : musDB = musDB Or 1
            Case "S", "s" : musDB = musDB Or 2
            Case "H", "h" : musDB = musDB Or 4
        End Select
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

Sub MUS_Load()
    Dim musLdat$, musLrest$, musLn$, musLdir$, musLtmp$
    Dim musLnote$, musLdur$, musLpn$, musLdstep$
    Dim musLp As Integer
    Dim musLii As Integer, musLsi As Integer, musLpi As Integer
    Dim musLdi As Integer, musLvi As Integer
    Dim musLpni As Integer, musLsidx As Integer
    Dim musLcur As Integer : musLcur = -1

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
                If musInstCnt >= MUS_INST_MAX Then GoTo musNextLine
                musLii = musInstCnt
                musInstN$(musLii)   = MUS_Tok$
                musInstVol(musLii)  = Val(MUS_Tok$)
                musInstH2(musLii)   = Val(MUS_Tok$)
                musInstH3(musLii)   = Val(MUS_Tok$)
                musInstGate(musLii) = Val(MUS_Tok$)
                musLtmp$ = MUS_Tok$
                If Len(musLtmp$) > 0 And UCase$(musLtmp$) <> "DET" Then
                    musInstAtk(musLii) = Val(musLtmp$) : musLtmp$ = MUS_Tok$
                End If
                If UCase$(musLtmp$) = "DET" Then musInstDet(musLii) = -1
                musInstCnt = musInstCnt + 1

            Case "SEQ"
                If musSeqCnt >= MUS_SEQ_MAX Then GoTo musNextLine
                musLsi = musSeqCnt
                musSeqN$(musLsi)   = MUS_Tok$
                musSeqBase(musLsi) = musNCount
                musLnote$ = MUS_Tok$
                Do While Len(musLnote$) > 0
                    musLdur$ = MUS_Tok$
                    If musNCount < MUS_NOTE_MAX Then
                        musNF(musNCount) = MUS_NoteFreq(musLnote$)
                        musND(musNCount) = Val(musLdur$)
                        musNCount = musNCount + 1
                    End If
                    musLnote$ = MUS_Tok$
                Loop
                musSeqLen(musLsi) = musNCount - musSeqBase(musLsi)
                musSeqCnt = musSeqCnt + 1

            Case "PAD"
                If musPadTotal >= MUS_PAD_MAX Then GoTo musNextLine
                musLpi = musPadTotal
                musPadN$(musLpi)  = MUS_Tok$
                musPadVol(musLpi) = Val(MUS_Tok$)
                musPadAtk(musLpi) = Val(MUS_Tok$)
                musPadNC(musLpi)  = 0
                musLpn$ = MUS_Tok$
                Do While Len(musLpn$) > 0 And musPadNC(musLpi) < 4
                    musPadF(musLpi, musPadNC(musLpi)) = MUS_NoteFreq(musLpn$)
                    musPadNC(musLpi) = musPadNC(musLpi) + 1
                    musLpn$ = MUS_Tok$
                Loop
                musPadTotal = musPadTotal + 1

            Case "DRUM"
                If musDrumCnt >= MUS_DRUM_MAX Then GoTo musNextLine
                musLdi = musDrumCnt
                musDrumN$(musLdi)  = MUS_Tok$
                musDrumLen(musLdi) = 0
                musLdstep$ = MUS_Tok$
                Do While Len(musLdstep$) > 0 And musDrumLen(musLdi) < MUS_DRUM_STEPS
                    musDrumPat(musLdi, musDrumLen(musLdi)) = MUS_DrumBits%(musLdstep$)
                    musDrumLen(musLdi) = musDrumLen(musLdi) + 1
                    musLdstep$ = MUS_Tok$
                Loop
                musDrumCnt = musDrumCnt + 1

            Case "CUE"
                musLcur = musCueCnt
                musCueN$(musLcur)   = MUS_Tok$
                musCueBPM(musLcur)  = Val(MUS_Tok$)
                musCueVCnt(musLcur) = 0
                musCueDrum(musLcur) = -1
                musCueCnt = musCueCnt + 1

            Case "VOICE"
                If musLcur < 0 Or musCueVCnt(musLcur) >= MUS_CUE_VMAX Then GoTo musNextLine
                musLtmp$ = MUS_Tok$ : musLsi   = MUS_FindInst%(musLtmp$)
                musLtmp$ = MUS_Tok$ : musLsidx = MUS_FindSeq%(musLtmp$)
                If musLsi < 0 Or musLsidx < 0 Then GoTo musNextLine
                musLvi = musCueVCnt(musLcur)
                musCueTmpl(musLcur, musLvi).vol     = musInstVol(musLsi)
                musCueTmpl(musLcur, musLvi).h2      = musInstH2(musLsi)
                musCueTmpl(musLcur, musLvi).h3      = musInstH3(musLsi)
                musCueTmpl(musLcur, musLvi).gate    = musInstGate(musLsi)
                musCueTmpl(musLcur, musLvi).atk     = musInstAtk(musLsi)
                musCueTmpl(musLcur, musLvi).isDet   = musInstDet(musLsi)
                musCueTmpl(musLcur, musLvi).seqBase = musSeqBase(musLsidx)
                musCueTmpl(musLcur, musLvi).seqLen  = musSeqLen(musLsidx)
                musCueTmpl(musLcur, musLvi).isPad   = 0
                musCueVCnt(musLcur) = musLvi + 1

            Case "CHORD"
                If musLcur < 0 Then GoTo musNextLine
                musLtmp$ = MUS_Tok$ : musLpi = MUS_FindPad%(musLtmp$)
                If musLpi < 0 Then GoTo musNextLine
                For musLpni = 0 To musPadNC(musLpi) - 1
                    If musCueVCnt(musLcur) < MUS_CUE_VMAX Then
                        musLvi = musCueVCnt(musLcur)
                        musCueTmpl(musLcur, musLvi).vol   = musPadVol(musLpi)
                        musCueTmpl(musLcur, musLvi).atk   = musPadAtk(musLpi)
                        musCueTmpl(musLcur, musLvi).freq  = musPadF(musLpi, musLpni)
                        musCueTmpl(musLcur, musLvi).isPad = -1
                        musCueVCnt(musLcur) = musLvi + 1
                    End If
                Next musLpni

            Case "DRUMS"
                If musLcur < 0 Then GoTo musNextLine
                musLtmp$ = MUS_Tok$
                musCueDrum(musLcur) = MUS_FindDrum%(musLtmp$)
        End Select

        musNextLine:
    Loop
End Sub

Sub MUS_SetCue(musSCn$)
    Dim musSCi As Integer, musSCv As Integer
    For musSCi = 0 To musCueCnt - 1
        If musCueN$(musSCi) = musSCn$ Then Exit For
    Next musSCi
    If musSCi >= musCueCnt Then Exit Sub

    musStepDur   = CLng(SAMPLE_RATE) * 60 \ musCueBPM(musSCi) \ 4
    musVoiceCnt  = musCueVCnt(musSCi)

    For musSCv = 0 To musVoiceCnt - 1
        musVoice(musSCv)       = musCueTmpl(musSCi, musSCv)
        musVoice(musSCv).phase = 0
        musVoice(musSCv).amp   = 0
        If Not musVoice(musSCv).isPad Then
            musVoice(musSCv).noteIdx = 0
            musVoice(musSCv).noteDur = CLng(musND(musVoice(musSCv).seqBase)) * musStepDur
            musVoice(musSCv).count   = musVoice(musSCv).noteDur
            musVoice(musSCv).gateOff = CLng(musVoice(musSCv).noteDur * (1.0 - musVoice(musSCv).gate))
            musVoice(musSCv).freq    = musNF(musVoice(musSCv).seqBase)
        End If
    Next musSCv

    musDrumIdx = musCueDrum(musSCi)
    If musDrumIdx >= 0 Then
        musDrumStep = musDrumLen(musDrumIdx) - 1
        musDrumTick = 1
    End If
End Sub

Sub MUS_Fill(musFdoSfx As Integer)
    Dim musFillCnt As Integer, musFk As Integer
    Dim musFsample As Single, musFefx As Single
    Dim musFvi As Integer, musFph As Single
    Dim musFnIdx As Integer, musFdbits As Integer

    musFillCnt = Int((AUDIO_BUFFER_TARGET - _SNDRAWLEN) * SAMPLE_RATE)
    If musFillCnt <= 0 Then Exit Sub

    For musFk = 0 To musFillCnt - 1
        musFsample = 0

        If musFdoSfx Then
            sndEnginePhase = sndEnginePhase + 6.2832 * sndEngineFreq / SAMPLE_RATE
            If sndEnginePhase > 6.2832 Then sndEnginePhase = sndEnginePhase - 6.2832
        End If

        For musFvi = 0 To musVoiceCnt - 1
            If musVoice(musFvi).isPad Then
                musVoice(musFvi).amp   = musVoice(musFvi).amp + (musVoice(musFvi).vol - musVoice(musFvi).amp) * musVoice(musFvi).atk
                musVoice(musFvi).phase = musVoice(musFvi).phase + 6.2832 * musVoice(musFvi).freq / SAMPLE_RATE
                If musVoice(musFvi).phase > 6.2832 Then musVoice(musFvi).phase = musVoice(musFvi).phase - 6.2832
                musFsample = musFsample + Sin(musVoice(musFvi).phase) * musVoice(musFvi).amp
            Else
                musVoice(musFvi).count = musVoice(musFvi).count - 1
                If musVoice(musFvi).count <= 0 Then
                    musVoice(musFvi).noteIdx = (musVoice(musFvi).noteIdx + 1) Mod musVoice(musFvi).seqLen
                    musFnIdx = musVoice(musFvi).seqBase + musVoice(musFvi).noteIdx
                    musVoice(musFvi).noteDur = CLng(musND(musFnIdx)) * musStepDur
                    musVoice(musFvi).count   = musVoice(musFvi).noteDur
                    musVoice(musFvi).gateOff = CLng(musVoice(musFvi).noteDur * (1.0 - musVoice(musFvi).gate))
                    musVoice(musFvi).freq    = musNF(musFnIdx)
                    musVoice(musFvi).phase   = 0
                End If
                If musVoice(musFvi).count > musVoice(musFvi).gateOff And musVoice(musFvi).freq > 0 Then
                    musVoice(musFvi).phase = musVoice(musFvi).phase + 6.2832 * musVoice(musFvi).freq / SAMPLE_RATE
                    If musVoice(musFvi).phase > 6.2832 Then musVoice(musFvi).phase = musVoice(musFvi).phase - 6.2832
                    musFph = musVoice(musFvi).phase
                    If musVoice(musFvi).isDet Then
                        musFsample = musFsample + (Sin(musFph) + Sin(musFph * (1.0 + musVoice(musFvi).h3)) * musVoice(musFvi).h2) * musVoice(musFvi).vol
                    Else
                        musFsample = musFsample + (Sin(musFph) + Sin(musFph * 2) * musVoice(musFvi).h2 + Sin(musFph * 3) * musVoice(musFvi).h3) * musVoice(musFvi).vol
                    End If
                End If
            End If
        Next musFvi

        If musDrumIdx >= 0 Then
            musDrumTick = musDrumTick - 1
            If musDrumTick <= 0 Then
                musDrumStep = (musDrumStep + 1) Mod musDrumLen(musDrumIdx)
                musDrumTick = musStepDur
                musFdbits = musDrumPat(musDrumIdx, musDrumStep)
                If musFdbits And 1 Then sndKickPos  = 0
                If musFdbits And 2 Then sndSnarePos = 0
                If musFdbits And 4 Then sndHihatPos = 0
            End If
        End If

        If sndKickPos >= 0 Then
            musFsample = musFsample + sndKick(sndKickPos)
            sndKickPos = sndKickPos + 1
            If sndKickPos >= SND_KICK_LEN Then sndKickPos = -1
        End If
        If sndSnarePos >= 0 Then
            musFsample = musFsample + sndSnare(sndSnarePos)
            sndSnarePos = sndSnarePos + 1
            If sndSnarePos >= SND_SNARE_LEN Then sndSnarePos = -1
        End If
        If sndHihatPos >= 0 Then
            musFsample = musFsample + sndHihat(sndHihatPos)
            sndHihatPos = sndHihatPos + 1
            If sndHihatPos >= SND_HIHAT_LEN Then sndHihatPos = -1
        End If

        musFefx = 0
        If sndPupPos >= 0 Then
            musFefx = musFefx + sndPup(sndPupPos)
            sndPupPos = sndPupPos + 1
            If sndPupPos >= SND_PUP_LEN Then sndPupPos = -1
        End If
        If sndBlipTimer > 0 Then
            sndBlipPhase = sndBlipPhase + 6.2832 * sndBlipFreq / SAMPLE_RATE
            If sndBlipPhase > 6.2832 Then sndBlipPhase = sndBlipPhase - 6.2832
            musFefx = musFefx + Sin(sndBlipPhase) * 0.3
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
            SPK_Advance
            _SNDRAW ((Sin(sndEnginePhase) + Sin(sndEnginePhase * 2) * 0.4 + Sin(sndEnginePhase * 3) * 0.15) * sndEngineAmp * 0.35 + musFefx) * volSfx _
                  + musFsample * volMusic + spkSampleOut * volSpeech
        Else
            SPK_Advance
            _SNDRAW musFsample * volMusic + musFefx * volSfx + spkSampleOut * volSpeech
        End If
    Next musFk
End Sub
