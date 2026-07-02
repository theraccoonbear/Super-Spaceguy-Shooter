' ============================================================
' speech.bas -- robotic phoneme speech synthesizer
' Lookup table baked from CMU Pronouncing Dictionary.
' Call SPK_Init once, then SPK_Say(text) to queue speech.
' SPK_Fill returns one sample per call; wire into audio fill loop.
' ============================================================

Const SPK_DICT_MAX  = 400    ' max dictionary word entries
Const SPK_PHONE_MAX = 2048   ' max queued phonemes per utterance
Const SPK_FADE      = 441    ' 10ms fade at phoneme edges (@ 44100)

' ---- ARPAbet phoneme IDs (order must match SPK_NAMES$ below) ----
Const SPK_AA=0:Const SPK_AE=1:Const SPK_AH=2:Const SPK_AO=3:Const SPK_AW=4
Const SPK_AY=5:Const SPK_EH=6:Const SPK_ER=7:Const SPK_EY=8:Const SPK_IH=9
Const SPK_IY=10:Const SPK_OW=11:Const SPK_OY=12:Const SPK_UH=13:Const SPK_UW=14
Const SPK_L=15:Const SPK_M=16:Const SPK_N=17:Const SPK_NG=18:Const SPK_R=19
Const SPK_W=20:Const SPK_YW=21:Const SPK_DH=22:Const SPK_V=23:Const SPK_Z=24
Const SPK_ZH=25:Const SPK_B=26:Const SPK_D=27:Const SPK_G=28:Const SPK_F=29
Const SPK_S=30:Const SPK_SH=31:Const SPK_TH=32:Const SPK_HH=33:Const SPK_P=34
Const SPK_T=35:Const SPK_K=36:Const SPK_CH=37:Const SPK_JH=38:Const SPK_SIL=39

' Phoneme name tokens in ID order (used for lookup at load time)
Const SPK_NAMES = "AA AE AH AO AW AY EH ER EY IH IY OW OY UH UW L M N NG R W Y DH V Z ZH B D G F S SH TH HH P T K CH JH SIL"

' Duration in samples per phoneme per stress level (0=unstressed 1=primary 2=secondary)
Dim Shared spkDur(0 To 39, 0 To 2) As Integer

' Dictionary
Dim Shared spkDictCount As Integer
Dim Shared spkDictWord(0 To SPK_DICT_MAX - 1) As String
Dim Shared spkDictPhoneLen(0 To SPK_DICT_MAX - 1) As Integer
Dim Shared spkDictPh(0 To SPK_DICT_MAX - 1, 0 To 15) As Integer
Dim Shared spkDictSt(0 To SPK_DICT_MAX - 1, 0 To 15) As Integer

' Letter-name fallback sequences (A-Z spelled as robot letter-names)
' Format: space-separated "PHONEMEstress" tokens
Dim Shared spkLetterSeq(0 To 25) As String

' Utterance playhead
Dim Shared spkPhones(0 To SPK_PHONE_MAX - 1) As Integer
Dim Shared spkStress(0 To SPK_PHONE_MAX - 1) As Integer
Dim Shared spkPhoneCount As Integer
Dim Shared spkPhoneIdx   As Integer
Dim Shared spkSamplePos  As Integer
Dim Shared spkSampleOut  As Single  ' current sample; written by SPK_Advance, read by snd.bas

' Formant synthesis
' F1/F2 per phoneme (Hz, Peterson & Barney 1952 for vowels; Klatt 1980 for consonants)
Dim Shared spkF1(0 To 39) As Single
Dim Shared spkF2(0 To 39) As Single
' Voiced-source wavetable (512 samples, rebuilt at each phoneme boundary)
Const SPK_WAVE_LEN = 512
Dim Shared spkWave(0 To SPK_WAVE_LEN - 1) As Single
Dim Shared spkWavePhase As Single  ' position in wavetable [0, SPK_WAVE_LEN)
Dim Shared spkWaveStep  As Single  ' samples advanced per audio sample

' ============================================================
Sub SPK_Init()
    Dim i As Integer

    ' Vowels 0-14: duration driven by stress
    ' Typical English stressed vowel ~150-200ms, unstressed ~70-90ms
    For i = 0 To 14
        spkDur(i, 0) = 3969   ' ~90ms  unstressed
        spkDur(i, 1) = 8820   ' ~200ms primary
        spkDur(i, 2) = 6174   ' ~140ms secondary
    Next i
    ' Sonorants 15-21 (L M N NG R W Y): ~120ms
    For i = 15 To 21
        spkDur(i, 0) = 5292 : spkDur(i, 1) = 5292 : spkDur(i, 2) = 5292
    Next i
    ' Voiced fricatives 22-25 (DH V Z ZH): ~110ms
    For i = 22 To 25
        spkDur(i, 0) = 4851 : spkDur(i, 1) = 4851 : spkDur(i, 2) = 4851
    Next i
    ' Voiced stops 26-28 (B D G): ~80ms -- shorter, burst is perceptual cue
    For i = 26 To 28
        spkDur(i, 0) = 3528 : spkDur(i, 1) = 3528 : spkDur(i, 2) = 3528
    Next i
    ' Unvoiced fricatives 29-33 (F S SH TH HH): ~140ms -- need length to register
    For i = 29 To 33
        spkDur(i, 0) = 6174 : spkDur(i, 1) = 6174 : spkDur(i, 2) = 6174
    Next i
    ' Unvoiced stops 34-36 (P T K): ~75ms
    For i = 34 To 36
        spkDur(i, 0) = 3307 : spkDur(i, 1) = 3307 : spkDur(i, 2) = 3307
    Next i
    ' Affricates 37-38 (CH JH): ~130ms
    For i = 37 To 38
        spkDur(i, 0) = 5733 : spkDur(i, 1) = 5733 : spkDur(i, 2) = 5733
    Next i
    ' Silence 39: ~50ms inter-word gap
    spkDur(39, 0) = 2205 : spkDur(39, 1) = 2205 : spkDur(39, 2) = 2205

    ' Letter-name phoneme sequences (for unknown-word fallback)
    spkLetterSeq(0)  = "EY1"                   ' A
    spkLetterSeq(1)  = "B IY1"                 ' B
    spkLetterSeq(2)  = "S IY1"                 ' C
    spkLetterSeq(3)  = "D IY1"                 ' D
    spkLetterSeq(4)  = "IY1"                   ' E
    spkLetterSeq(5)  = "EH1 F"                 ' F
    spkLetterSeq(6)  = "JH IY1"               ' G
    spkLetterSeq(7)  = "EY1 CH"               ' H
    spkLetterSeq(8)  = "AY1"                   ' I
    spkLetterSeq(9)  = "JH EY1"               ' J
    spkLetterSeq(10) = "K EY1"                ' K
    spkLetterSeq(11) = "EH1 L"                ' L
    spkLetterSeq(12) = "EH1 M"                ' M
    spkLetterSeq(13) = "EH1 N"                ' N
    spkLetterSeq(14) = "OW1"                   ' O
    spkLetterSeq(15) = "P IY1"                ' P
    spkLetterSeq(16) = "K Y UW1"              ' Q
    spkLetterSeq(17) = "AA1 R"                ' R
    spkLetterSeq(18) = "EH1 S"                ' S
    spkLetterSeq(19) = "T IY1"                ' T
    spkLetterSeq(20) = "Y UW1"                ' U
    spkLetterSeq(21) = "V IY1"                ' V
    spkLetterSeq(22) = "D AH0 B AH0 L Y UW1" ' W
    spkLetterSeq(23) = "EH1 K S"              ' X
    spkLetterSeq(24) = "W AY1"                ' Y
    spkLetterSeq(25) = "Z IY1"                ' Z

    ' ---- Formant frequency table (F1, F2 in Hz) ----
    ' Vowels 0-14: Peterson & Barney (1952) male mean values
    spkF1(SPK_AA)=730 : spkF2(SPK_AA)=1090   ' father
    spkF1(SPK_AE)=660 : spkF2(SPK_AE)=1720   ' cat
    spkF1(SPK_AH)=520 : spkF2(SPK_AH)=1190   ' cut
    spkF1(SPK_AO)=570 : spkF2(SPK_AO)= 840   ' caught
    spkF1(SPK_AW)=760 : spkF2(SPK_AW)=1290   ' cow (onset)
    spkF1(SPK_AY)=740 : spkF2(SPK_AY)=1640   ' bite (onset)
    spkF1(SPK_EH)=530 : spkF2(SPK_EH)=1840   ' bed
    spkF1(SPK_ER)=490 : spkF2(SPK_ER)=1350   ' bird
    spkF1(SPK_EY)=440 : spkF2(SPK_EY)=2060   ' bait (onset)
    spkF1(SPK_IH)=390 : spkF2(SPK_IH)=1990   ' bit
    spkF1(SPK_IY)=270 : spkF2(SPK_IY)=2290   ' beat
    spkF1(SPK_OW)=470 : spkF2(SPK_OW)= 830   ' boat (onset)
    spkF1(SPK_OY)=570 : spkF2(SPK_OY)= 840   ' boy (onset)
    spkF1(SPK_UH)=440 : spkF2(SPK_UH)=1020   ' book
    spkF1(SPK_UW)=310 : spkF2(SPK_UW)= 870   ' boot
    ' Sonorants 15-21: Klatt (1980) approximations
    spkF1(SPK_L) =360 : spkF2(SPK_L) =1000   ' lateral
    spkF1(SPK_M) =280 : spkF2(SPK_M) = 900   ' bilabial nasal
    spkF1(SPK_N) =280 : spkF2(SPK_N) =1700   ' alveolar nasal
    spkF1(SPK_NG)=280 : spkF2(SPK_NG)=2300   ' velar nasal
    spkF1(SPK_R) =490 : spkF2(SPK_R) =1350   ' rhotic (like ER)
    spkF1(SPK_W) =290 : spkF2(SPK_W) = 610   ' glide
    spkF1(SPK_YW)=270 : spkF2(SPK_YW)=2200   ' palatal glide
    ' Voiced fricatives / stops 22-28: light buzz formants
    spkF1(SPK_DH)=300 : spkF2(SPK_DH)=1800
    spkF1(SPK_V) =300 : spkF2(SPK_V) =1200
    spkF1(SPK_Z) =300 : spkF2(SPK_Z) =1800
    spkF1(SPK_ZH)=300 : spkF2(SPK_ZH)=2000
    spkF1(SPK_B) =300 : spkF2(SPK_B) = 800
    spkF1(SPK_D) =300 : spkF2(SPK_D) =1700
    spkF1(SPK_G) =300 : spkF2(SPK_G) =2200
    ' Unvoiced + affricates + silence: zeros (wavetable unused for these)
    ' (array default-initialises to 0; no explicit assignment needed)

    spkPhoneCount = 0 : spkPhoneIdx = 0 : spkSamplePos = 0
    spkWavePhase = 0.0 : spkWaveStep = 0.0

    SPK_LoadDict
End Sub

' ============================================================
' Build a 512-sample voiced-source wavetable shaped by the F1/F2
' formants of the given phoneme.  Called once per phoneme boundary.
'
' Each harmonic k of the fundamental f0 gets amplitude:
'   gain = (bandpass(k*f0, F1, Q1) + bandpass(k*f0, F2, Q2)) / k
' where bandpass is the standard 2-pole magnitude response (peaks at 1.0).
' The /k gives sawtooth spectral tilt.  Output is normalized to peak 1.0.
' ============================================================
Sub SPK_BuildWave(phoneID As Integer, stress As Integer)
    Dim f0 As Single, f1v As Single, f2v As Single
    Dim k As Integer, i As Integer
    Dim hf As Single, r1 As Single, r2 As Single
    Dim g1 As Single, g2 As Single, g As Single
    Dim ph As Single, s As Single, pk As Single
    Const Q1 = 9.0    ' F1 Q factor  (BW = F/Q; ~80Hz at 730Hz)
    Const Q2 = 12.0   ' F2 Q factor  (BW = F/Q; ~90Hz at 1090Hz)
    Const NHARM = 24  ' harmonics to sum (covers up to ~2640Hz at f0=110Hz)

    Select Case stress
        Case 1    : f0 = 155.0
        Case 2    : f0 = 130.0
        Case Else : f0 = 110.0
    End Select
    spkWaveStep = SPK_WAVE_LEN * f0 / SAMPLE_RATE

    f1v = spkF1(phoneID) : f2v = spkF2(phoneID)

    For i = 0 To SPK_WAVE_LEN - 1
        ph = 6.2832 * i / SPK_WAVE_LEN
        s = 0.0
        For k = 1 To NHARM
            hf = k * f0
            ' Bandpass magnitude: 1 / sqrt(1 + Q^2*(ratio - 1/ratio)^2)
            If f1v > 0 Then
                r1 = hf / f1v
                g1 = 1.0 / Sqr(1.0 + Q1*Q1 * (r1 - 1.0/r1) * (r1 - 1.0/r1))
            Else
                g1 = 0.5  ' flat spectrum fallback if no formant defined
            End If
            If f2v > 0 Then
                r2 = hf / f2v
                g2 = 1.0 / Sqr(1.0 + Q2*Q2 * (r2 - 1.0/r2) * (r2 - 1.0/r2))
            Else
                g2 = 0.5
            End If
            g = (g1 + g2) / k   ' spectral tilt: /k for sawtooth-like rolloff
            s = s + Sin(k * ph) * g
        Next k
        spkWave(i) = s
    Next i

    ' Normalize peak to 1.0
    pk = 0.001  ' small floor avoids div/0 for all-zero wavetables (unvoiced)
    For i = 0 To SPK_WAVE_LEN - 1
        If Abs(spkWave(i)) > pk Then pk = Abs(spkWave(i))
    Next i
    For i = 0 To SPK_WAVE_LEN - 1
        spkWave(i) = spkWave(i) / pk
    Next i
End Sub

' ============================================================
' Parse a phoneme token like "EH1" or "SH" into ID and stress.
' ============================================================
Sub SPK_ParsePhone(tok As String, phID As Integer, stress As Integer)
    Dim bare As String, lastC As String, p As Integer, scan As String
    Dim rest As String

    bare = tok
    stress = 0
    If LEN(bare) > 0 Then
        lastC = RIGHT$(bare, 1)
        If lastC >= "0" And lastC <= "9" Then
            stress = VAL(lastC)
            bare = LEFT$(bare, LEN(bare) - 1)
        End If
    End If

    ' Linear scan of SPK_NAMES
    rest = SPK_NAMES
    Dim cur As Integer : cur = 0
    Do While LEN(rest) > 0
        p = INSTR(rest, " ")
        If p > 0 Then
            scan = LEFT$(rest, p - 1)
            rest = MID$(rest, p + 1)
        Else
            scan = rest : rest = ""
        End If
        If scan = bare Then
            phID = cur
            Exit Sub
        End If
        cur = cur + 1
    Loop
    phID = SPK_SIL   ' unknown -> silence
End Sub

' ============================================================
' Append phoneme tokens from a space-separated string into the
' utterance queue.  phStr is like "EH1 L OW0".
' ============================================================
Sub SPK_AppendPhoneStr(phStr As String)
    Dim rest As String : rest = phStr
    Dim tok As String, p As Integer
    Dim phID As Integer, stress As Integer

    Do While LEN(rest) > 0
        rest = LTRIM$(rest)
        p = INSTR(rest, " ")
        If p > 0 Then
            tok = LEFT$(rest, p - 1)
            rest = MID$(rest, p + 1)
        Else
            tok = rest : rest = ""
        End If
        If LEN(tok) > 0 Then
            SPK_ParsePhone tok, phID, stress
            If spkPhoneCount < SPK_PHONE_MAX Then
                spkPhones(spkPhoneCount) = phID
                spkStress(spkPhoneCount) = stress
                spkPhoneCount = spkPhoneCount + 1
            End If
        End If
    Loop
End Sub

' ============================================================
' Spell an unknown word letter-by-letter using letter-name phonemes.
' ============================================================
Sub SPK_SpellWord(wrd As String)
    Dim i As Integer, c As Integer
    For i = 1 To LEN(wrd)
        c = ASC(MID$(wrd, i, 1)) - ASC("A")
        If c >= 0 And c <= 25 Then
            SPK_AppendPhoneStr spkLetterSeq(c)
            ' short pause between letters
            If spkPhoneCount < SPK_PHONE_MAX Then
                spkPhones(spkPhoneCount) = SPK_SIL
                spkStress(spkPhoneCount) = 0
                spkPhoneCount = spkPhoneCount + 1
            End If
        End If
    Next i
End Sub

' ============================================================
' Binary search in sorted spkDictWord array.
' Sets result to found index, or -1 if not found.
' ============================================================
Sub SPK_DictFind(wrd As String, result As Integer)
    Dim lo As Integer, hi As Integer, mdx As Integer
    lo = 0 : hi = spkDictCount - 1
    result = -1
    Do While lo <= hi
        mdx = (lo + hi) \ 2
        If spkDictWord(mdx) = wrd Then
            result = mdx
            Exit Sub
        ElseIf spkDictWord(mdx) < wrd Then
            lo = mdx + 1
        Else
            hi = mdx - 1
        End If
    Loop
End Sub

' ============================================================
' Queue text for speech.  Call at any time; SPK_Fill drains it.
' ============================================================
Sub SPK_Say(text As String)
    Dim wrd As String, rest As String, p As Integer, uc As String
    Dim idx As Integer, pi As Integer

    spkPhoneCount = 0 : spkPhoneIdx = 0 : spkSamplePos = 0
    spkWavePhase = 0.0

    uc = UCASE$(text)
    ' Strip non-alpha characters except spaces
    Dim cleaned As String : cleaned = ""
    Dim ci As Integer
    For ci = 1 To LEN(uc)
        Dim ch As String : ch = MID$(uc, ci, 1)
        If (ch >= "A" And ch <= "Z") Or ch = " " Then
            cleaned = cleaned + ch
        Else
            cleaned = cleaned + " "
        End If
    Next ci

    rest = LTRIM$(RTRIM$(cleaned))
    Do While LEN(rest) > 0
        rest = LTRIM$(rest)
        p = INSTR(rest, " ")
        If p > 0 Then
            wrd = LEFT$(rest, p - 1)
            rest = MID$(rest, p + 1)
        Else
            wrd = rest : rest = ""
        End If

        If LEN(wrd) = 0 Then GoTo nextWord

        SPK_DictFind wrd, idx
        If idx >= 0 Then
            For pi = 0 To spkDictPhoneLen(idx) - 1
                If spkPhoneCount < SPK_PHONE_MAX Then
                    spkPhones(spkPhoneCount) = spkDictPh(idx, pi)
                    spkStress(spkPhoneCount) = spkDictSt(idx, pi)
                    spkPhoneCount = spkPhoneCount + 1
                End If
            Next pi
        Else
            SPK_SpellWord wrd
        End If

        ' inter-word silence
        If spkPhoneCount < SPK_PHONE_MAX Then
            spkPhones(spkPhoneCount) = SPK_SIL
            spkStress(spkPhoneCount) = 0
            spkPhoneCount = spkPhoneCount + 1
        End If

        nextWord:
    Loop
End Sub

' ============================================================
' Returns 1 if speech is still playing, 0 if silent.
' ============================================================
' Compute next speech sample into spkSampleOut.  Call once per audio sample.
' snd.bas reads spkSampleOut directly after calling SPK_Advance.
' ============================================================
Sub SPK_Advance()
    Dim phoneID As Integer, stress As Integer, dur As Integer
    Dim env As Single, s As Single, t As Single
    Dim wIdx As Integer, buzz As Single

    If spkPhoneIdx >= spkPhoneCount Then
        spkSampleOut = 0.0
        Exit Sub
    End If

    phoneID = spkPhones(spkPhoneIdx)
    stress  = spkStress(spkPhoneIdx)
    dur     = spkDur(phoneID, stress)

    ' Rebuild wavetable at phoneme boundary (once per phoneme)
    If spkSamplePos = 0 Then SPK_BuildWave phoneID, stress

    ' Amplitude envelope: 10ms fade in/out
    If spkSamplePos < SPK_FADE Then
        env = spkSamplePos / SPK_FADE
    ElseIf spkSamplePos > dur - SPK_FADE Then
        env = (dur - spkSamplePos) / SPK_FADE
        If env < 0 Then env = 0
    Else
        env = 1.0
    End If

    ' Advance wavetable (formant-shaped voiced source)
    wIdx = Int(spkWavePhase)
    buzz = spkWave(wIdx) + (spkWavePhase - wIdx) * (spkWave((wIdx + 1) And (SPK_WAVE_LEN - 1)) - spkWave(wIdx))
    spkWavePhase = spkWavePhase + spkWaveStep
    If spkWavePhase >= SPK_WAVE_LEN Then spkWavePhase = spkWavePhase - SPK_WAVE_LEN

    Select Case phoneID
        Case SPK_AA To SPK_UW, SPK_L To SPK_YW
            s = buzz * 0.50
        Case SPK_DH, SPK_V, SPK_Z, SPK_ZH
            s = buzz * 0.22 + (Rnd * 2.0 - 1.0) * 0.10
        Case SPK_B, SPK_D, SPK_G
            t = spkSamplePos / dur
            If t < 0.60 Then
                s = buzz * 0.05  ' quiet voice bar during closure
            Else
                s = buzz * 0.35  ' voiced release
            End If
        Case SPK_F, SPK_S, SPK_SH, SPK_TH
            s = (Rnd * 2.0 - 1.0) * 0.18
        Case SPK_HH
            s = (Rnd * 2.0 - 1.0) * 0.09
        Case SPK_P, SPK_T, SPK_K
            t = spkSamplePos / dur
            If t < 0.65 Then s = 0.0 _
            Else s = (Rnd * 2.0 - 1.0) * 0.26
        Case SPK_CH, SPK_JH
            t = spkSamplePos / dur
            If t < 0.40 Then s = 0.0 _
            Else s = (Rnd * 2.0 - 1.0) * 0.20
        Case Else
            s = 0.0
    End Select

    spkSampleOut = s * env * 0.45

    spkSamplePos = spkSamplePos + 1
    If spkSamplePos >= dur Then
        spkSamplePos = 0
        spkPhoneIdx  = spkPhoneIdx + 1
    End If
End Sub

' ============================================================
' Load baked dictionary from embedded SPEECHDICT data.
' Expects lines: "WORD PH1 PH2 ..." (# comment / blank = skip).
' Words must be in alphabetical order for binary search.
' ============================================================
Sub SPK_LoadDict()
    Dim dat As String, ln As String, rest As String
    Dim p As Integer, tok As String
    Dim phID As Integer, stress As Integer
    Dim pi As Integer, lp As Integer
    Dim dw As String, phones As String, pr As String, pp As Integer
    Dim valid As Integer

    dat  = _EMBEDDED$("SPEECHDICT")
    rest = dat
    spkDictCount = 0

    Do While LEN(rest) > 0
        ' Extract one line
        p = INSTR(rest, CHR$(10))
        If p > 0 Then
            ln   = LEFT$(rest, p - 1)
            rest = MID$(rest, p + 1)
        Else
            ln = rest : rest = ""
        End If
        ln = RTRIM$(ln)
        If LEN(ln) > 0 Then
            If RIGHT$(ln, 1) = CHR$(13) Then ln = LEFT$(ln, LEN(ln) - 1)
        End If

        valid = -1
        If LEN(ln) = 0 Then valid = 0
        If valid And LEFT$(ln, 1) = "#" Then valid = 0
        If valid And spkDictCount >= SPK_DICT_MAX Then valid = 0

        If valid Then
            lp = INSTR(ln, " ")
            If lp = 0 Then valid = 0
        End If

        If valid Then
            dw     = LEFT$(ln, lp - 1)
            phones = MID$(ln, lp + 1)
            spkDictWord(spkDictCount) = dw
            pi = 0
            pr = phones
            Do While LEN(pr) > 0
                pr = LTRIM$(pr)
                pp = INSTR(pr, " ")
                If pp > 0 Then
                    tok = LEFT$(pr, pp - 1)
                    pr  = MID$(pr, pp + 1)
                Else
                    tok = pr : pr = ""
                End If
                If LEN(tok) > 0 And pi < 16 Then
                    SPK_ParsePhone tok, phID, stress
                    spkDictPh(spkDictCount, pi) = phID
                    spkDictSt(spkDictCount, pi) = stress
                    pi = pi + 1
                End If
            Loop
            spkDictPhoneLen(spkDictCount) = pi
            spkDictCount = spkDictCount + 1
        End If
    Loop
End Sub
