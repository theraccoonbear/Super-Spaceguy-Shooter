' ============================================================
' speech.bas -- robotic phoneme speech synthesizer
' Lookup table baked from CMU Pronouncing Dictionary.
' Call SPK_Init once, then SPK_Say(text) to queue speech.
' SPK_Fill returns one sample per call; wire into audio fill loop.
' ============================================================

CONST SPK_DICT_MAX  = 400    ' max dictionary word entries
CONST SPK_PHONE_MAX = 2048   ' max queued phonemes per utterance
CONST SPK_FADE      = 441    ' 10ms fade at phoneme edges (@ 44100)

' ---- ARPAbet phoneme IDs (order must match SPK_NAMES$ below) ----
CONST SPK_AA=0:CONST SPK_AE=1:CONST SPK_AH=2:CONST SPK_AO=3:CONST SPK_AW=4
CONST SPK_AY=5:CONST SPK_EH=6:CONST SPK_ER=7:CONST SPK_EY=8:CONST SPK_IH=9
CONST SPK_IY=10:CONST SPK_OW=11:CONST SPK_OY=12:CONST SPK_UH=13:CONST SPK_UW=14
CONST SPK_L=15:CONST SPK_M=16:CONST SPK_N=17:CONST SPK_NG=18:CONST SPK_R=19
CONST SPK_W=20:CONST SPK_YW=21:CONST SPK_DH=22:CONST SPK_V=23:CONST SPK_Z=24
CONST SPK_ZH=25:CONST SPK_B=26:CONST SPK_D=27:CONST SPK_G=28:CONST SPK_F=29
CONST SPK_S=30:CONST SPK_SH=31:CONST SPK_TH=32:CONST SPK_HH=33:CONST SPK_P=34
CONST SPK_T=35:CONST SPK_K=36:CONST SPK_CH=37:CONST SPK_JH=38:CONST SPK_SIL=39

' Phoneme name tokens in ID order (used for lookup at load time)
CONST SPK_NAMES = "AA AE AH AO AW AY EH ER EY IH IY OW OY UH UW L M N NG R W Y DH V Z ZH B D G F S SH TH HH P T K CH JH SIL"

' Duration in samples per phoneme per stress level (0=unstressed 1=primary 2=secondary)
DIM SHARED spkDur(0 TO 39, 0 TO 2) AS INTEGER

' Dictionary
DIM SHARED spkDictCount AS INTEGER
DIM SHARED spkDictWord(0 TO SPK_DICT_MAX - 1) AS STRING
DIM SHARED spkDictPhoneLen(0 TO SPK_DICT_MAX - 1) AS INTEGER
DIM SHARED spkDictPh(0 TO SPK_DICT_MAX - 1, 0 TO 15) AS INTEGER
DIM SHARED spkDictSt(0 TO SPK_DICT_MAX - 1, 0 TO 15) AS INTEGER

' Letter-name fallback sequences (A-Z spelled as robot letter-names)
' Format: space-separated "PHONEMEstress" tokens
DIM SHARED spkLetterSeq(0 TO 25) AS STRING

' Utterance playhead
DIM SHARED spkPhones(0 TO SPK_PHONE_MAX - 1) AS INTEGER
DIM SHARED spkStress(0 TO SPK_PHONE_MAX - 1) AS INTEGER
DIM SHARED spkPhoneCount AS INTEGER
DIM SHARED spkPhoneIdx   AS INTEGER
DIM SHARED spkSamplePos  AS INTEGER
DIM SHARED spkSampleOut  AS SINGLE  ' current sample; written by SPK_Advance, read by snd.bas

' Formant synthesis
' F1/F2 per phoneme (Hz, Peterson & Barney 1952 for vowels; Klatt 1980 for consonants)
DIM SHARED spkF1(0 TO 39) AS SINGLE
DIM SHARED spkF2(0 TO 39) AS SINGLE
' Voiced-source wavetable (512 samples per phoneme+stress; library pre-built at init)
' Building at runtime from trig would stall the audio fill loop and kill _SNDRAW.
CONST SPK_WAVE_LEN = 512
DIM SHARED spkWaveLib(0 TO 39, 0 TO 2, 0 TO SPK_WAVE_LEN - 1) AS SINGLE  ' [phone][stress][sample]
DIM SHARED spkWave(0 TO SPK_WAVE_LEN - 1) AS SINGLE      ' active phoneme wavetable
DIM SHARED spkWavePrev(0 TO SPK_WAVE_LEN - 1) AS SINGLE  ' previous phoneme (coarticulation blend)
DIM SHARED spkWavePhase AS SINGLE  ' position in wavetable [0, SPK_WAVE_LEN)
DIM SHARED spkWaveStep  AS SINGLE  ' samples advanced per audio sample
' F3 formant, previous-phoneme tracking, fricative HP filter
DIM SHARED spkF3(0 TO 39) AS SINGLE
DIM SHARED spkDiEnd(0 TO 39) AS INTEGER  ' diphthong glide target (-1 = monophthong)
DIM SHARED spkRateScale AS SINGLE        ' speech rate multiplier (1.0 = natural; set by SPK_SyncToScroll)
DIM SHARED spkPrevPhoneID AS INTEGER
DIM SHARED spkHpCoeff AS SINGLE
DIM SHARED spkHpX1    AS SINGLE
DIM SHARED spkHpY1    AS SINGLE

CONST SPK_MAX_WORDS = 128
DIM SHARED spkWordStart(0 TO SPK_MAX_WORDS - 1) AS INTEGER
DIM SHARED spkWordEnd(0 TO SPK_MAX_WORDS - 1) AS INTEGER
DIM SHARED spkWordText$(0 TO SPK_MAX_WORDS - 1)
DIM SHARED spkWordOcc(0 TO SPK_MAX_WORDS - 1) AS INTEGER  ' 0-based occurrence index of this word among same-text words
DIM SHARED spkWordCount AS INTEGER

' ============================================================
SUB SPK_Init()
    DIM i AS INTEGER

    ' Vowels 0-14: duration driven by stress
    ' Typical English stressed vowel ~150-200ms, unstressed ~70-90ms
    FOR i = 0 TO 14
        spkDur(i, 0) = 3969   ' ~90ms  unstressed
        spkDur(i, 1) = 8820   ' ~200ms primary
        spkDur(i, 2) = 6174   ' ~140ms secondary
    NEXT i
    ' Sonorants 15-21 (L M N NG R W Y): ~120ms
    FOR i = 15 TO 21
        spkDur(i, 0) = 5292 : spkDur(i, 1) = 5292 : spkDur(i, 2) = 5292
    NEXT i
    ' Voiced fricatives 22-25 (DH V Z ZH): ~110ms
    FOR i = 22 TO 25
        spkDur(i, 0) = 4851 : spkDur(i, 1) = 4851 : spkDur(i, 2) = 4851
    NEXT i
    ' Voiced stops 26-28 (B D G): ~80ms -- shorter, burst is perceptual cue
    FOR i = 26 TO 28
        spkDur(i, 0) = 3528 : spkDur(i, 1) = 3528 : spkDur(i, 2) = 3528
    NEXT i
    ' Unvoiced fricatives 29-33 (F S SH TH HH): ~140ms -- need length to register
    FOR i = 29 TO 33
        spkDur(i, 0) = 6174 : spkDur(i, 1) = 6174 : spkDur(i, 2) = 6174
    NEXT i
    ' Unvoiced stops 34-36 (P T K): ~75ms
    FOR i = 34 TO 36
        spkDur(i, 0) = 3307 : spkDur(i, 1) = 3307 : spkDur(i, 2) = 3307
    NEXT i
    ' Affricates 37-38 (CH JH): ~130ms
    FOR i = 37 TO 38
        spkDur(i, 0) = 5733 : spkDur(i, 1) = 5733 : spkDur(i, 2) = 5733
    NEXT i
    ' Silence 39: ~100ms inter-word gap
    spkDur(39, 0) = 5733 : spkDur(39, 1) = 5733 : spkDur(39, 2) = 5733

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
    spkF1(SPK_L) =360 : spkF2(SPK_L) =1200   ' lateral (raised F2 + anti-res in wavetable)
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

    ' F3 formant (Hz) — critical for R/ER rhotic quality (uniquely low F3=1830Hz)
    ' Vowels: Peterson & Barney (1952) male mean
    spkF3(SPK_AA)=2440 : spkF3(SPK_AE)=2600 : spkF3(SPK_AH)=2400
    spkF3(SPK_AO)=2410 : spkF3(SPK_AW)=2500 : spkF3(SPK_AY)=2600
    spkF3(SPK_EH)=2550 : spkF3(SPK_ER)=1830 : spkF3(SPK_EY)=2700
    spkF3(SPK_IH)=2550 : spkF3(SPK_IY)=3010 : spkF3(SPK_OW)=2500
    spkF3(SPK_OY)=2500 : spkF3(SPK_UH)=2240 : spkF3(SPK_UW)=2240
    ' Sonorants: Klatt (1980); R shares ER's low F3 (retroflexion)
    spkF3(SPK_L) =2700 : spkF3(SPK_M) =2200 : spkF3(SPK_N) =2300
    spkF3(SPK_NG)=2700 : spkF3(SPK_R) =1830 : spkF3(SPK_W) =2200
    spkF3(SPK_YW)=3000
    ' Voiced stops / fricatives
    spkF3(SPK_DH)=2700 : spkF3(SPK_V) =2200 : spkF3(SPK_Z) =2700
    spkF3(SPK_ZH)=2600 : spkF3(SPK_B) =2200 : spkF3(SPK_D) =2700
    spkF3(SPK_G) =2600

    ' Diphthong glide targets: blend from onset wavetable to target vowel over phoneme duration
    DIM spkDiI AS INTEGER
    FOR spkDiI = 0 TO 39 : spkDiEnd(spkDiI) = -1 : NEXT spkDiI
        spkDiEnd(SPK_AY) = SPK_IY   ' /aɪ/ bite, like, right → AA onset → IY
        spkDiEnd(SPK_EY) = SPK_IY   ' /eɪ/ say, face, space → EH onset → IY
        spkDiEnd(SPK_OW) = SPK_UW   ' /oʊ/ go, know, those  → AO onset → UW
        spkDiEnd(SPK_AW) = SPK_UH   ' /aʊ/ out, down, power → AA onset → UH
        spkDiEnd(SPK_OY) = SPK_IY   ' /ɔɪ/ boy, point, void → AO onset → IY

        spkRateScale = 1.0
        spkPhoneCount = 0 : spkPhoneIdx = 0 : spkSamplePos = 0
        spkWavePhase = 0.0 : spkWaveStep = 0.0
        spkPrevPhoneID = SPK_SIL

        SPK_BuildAllWaves   ' pre-build all 40x3 wavetables before entering audio loop
        SPK_LoadDict
    END SUB

    ' ============================================================
    ' Pre-build all phoneme wavetables at startup (120 builds, done once).
    ' Called from SPK_Init before any audio fill loop starts.
    ' Doing this upfront keeps SPK_BuildWave (called per phoneme in the
    ' real-time audio path) down to a fast array copy instead of trig.
    ' ============================================================
    SUB SPK_BuildAllWaves()
        DIM bwPhone AS INTEGER, bwSt AS INTEGER, bwK AS INTEGER, bwI AS INTEGER
        DIM bwF0 AS SINGLE, bwF1 AS SINGLE, bwF2 AS SINGLE, bwF3 AS SINGLE
        DIM bwHf AS SINGLE, bwR1 AS SINGLE, bwR2 AS SINGLE, bwR3 AS SINGLE
        DIM bwG1 AS SINGLE, bwG2 AS SINGLE, bwG3 AS SINGLE, bwG AS SINGLE
        DIM bwPh AS SINGLE, bwS AS SINGLE, bwPk AS SINGLE
        DIM bwRa AS SINGLE, bwGa AS SINGLE  ' anti-resonance (L lateral notch)
        CONST bwQ1 = 9.0 : CONST bwQ2 = 12.0 : CONST bwQ3 = 10.0 : CONST bwNH = 32

        FOR bwSt = 0 TO 2
            SELECT CASE bwSt
            CASE 1    : bwF0 = 155.0
            CASE 2    : bwF0 = 130.0
            CASE ELSE : bwF0 = 110.0
            END SELECT
            FOR bwPhone = 0 TO 39
                bwF1 = spkF1(bwPhone) : bwF2 = spkF2(bwPhone) : bwF3 = spkF3(bwPhone)
                FOR bwI = 0 TO SPK_WAVE_LEN - 1
                    bwPh = 6.2832 * bwI / SPK_WAVE_LEN
                    bwS = 0.0
                    FOR bwK = 1 TO bwNH
                        bwHf = bwK * bwF0
                        IF bwF1 > 0 THEN
                            bwR1 = bwHf / bwF1
                            bwG1 = 1.0 / SQR(1.0 + bwQ1*bwQ1*(bwR1 - 1.0/bwR1)*(bwR1 - 1.0/bwR1))
                        ELSE
                            bwG1 = 0.5
                        END IF
                        IF bwF2 > 0 THEN
                            bwR2 = bwHf / bwF2
                            bwG2 = 1.0 / SQR(1.0 + bwQ2*bwQ2*(bwR2 - 1.0/bwR2)*(bwR2 - 1.0/bwR2))
                        ELSE
                            bwG2 = 0.5
                        END IF
                        IF bwF3 > 0 THEN
                            bwR3 = bwHf / bwF3
                            bwG3 = 1.0 / SQR(1.0 + bwQ3*bwQ3*(bwR3 - 1.0/bwR3)*(bwR3 - 1.0/bwR3))
                        ELSE
                            bwG3 = 0.0
                        END IF
                        bwG = (bwG1 + bwG2 + bwG3 * 0.5) / bwK
                        ' L: subtract anti-resonance notch ~1800Hz for lateral quality
                        IF bwPhone = SPK_L THEN
                            bwRa = bwHf / 1800.0
                            bwGa = 1.0 / SQR(1.0 + 10.0*10.0*(bwRa - 1.0/bwRa)*(bwRa - 1.0/bwRa))
                            bwG = bwG - bwGa * 0.35 : IF bwG < 0.0 THEN bwG = 0.0
                        END IF
                        bwS = bwS + SIN(bwK * bwPh) * bwG
                    NEXT bwK
                    spkWaveLib(bwPhone, bwSt, bwI) = bwS
                NEXT bwI
                bwPk = 0.001
                FOR bwI = 0 TO SPK_WAVE_LEN - 1
                    IF ABS(spkWaveLib(bwPhone, bwSt, bwI)) > bwPk THEN bwPk = ABS(spkWaveLib(bwPhone, bwSt, bwI))
                NEXT bwI
                FOR bwI = 0 TO SPK_WAVE_LEN - 1
                    spkWaveLib(bwPhone, bwSt, bwI) = spkWaveLib(bwPhone, bwSt, bwI) / bwPk
                NEXT bwI
            NEXT bwPhone
        NEXT bwSt
    END SUB

    ' ============================================================
    ' Load next phoneme's wavetable from pre-built library (fast array copy).
    ' Saves outgoing wave to spkWavePrev for coarticulation blend.
    ' ============================================================
    SUB SPK_BuildWave(phoneID AS INTEGER, stress AS INTEGER)
        DIM bwJ AS INTEGER, bwSIdx AS INTEGER

        FOR bwJ = 0 TO SPK_WAVE_LEN - 1
            spkWavePrev(bwJ) = spkWave(bwJ)
        NEXT bwJ

        SELECT CASE stress
        CASE 1    : bwSIdx = 1 : spkWaveStep = SPK_WAVE_LEN * 155.0 / SAMPLE_RATE
        CASE 2    : bwSIdx = 2 : spkWaveStep = SPK_WAVE_LEN * 130.0 / SAMPLE_RATE
        CASE ELSE : bwSIdx = 0 : spkWaveStep = SPK_WAVE_LEN * 110.0 / SAMPLE_RATE
        END SELECT

        FOR bwJ = 0 TO SPK_WAVE_LEN - 1
            spkWave(bwJ) = spkWaveLib(phoneID, bwSIdx, bwJ)
        NEXT bwJ

        SELECT CASE phoneID
        CASE SPK_S, SPK_Z              : spkHpCoeff = 0.607
        CASE SPK_SH, SPK_ZH, SPK_CH, SPK_JH : spkHpCoeff = 0.774
        CASE SPK_F, SPK_V, SPK_TH, SPK_DH   : spkHpCoeff = 0.843
        CASE SPK_HH                    : spkHpCoeff = 0.958
        CASE SPK_P                     : spkHpCoeff = 0.870  ' bilabial burst fc~800Hz
        CASE SPK_T                     : spkHpCoeff = 0.607  ' alveolar burst fc~3500Hz (hissy)
        CASE SPK_K                     : spkHpCoeff = 0.720  ' velar burst fc~2000Hz
        CASE ELSE                      : spkHpCoeff = 0.900
        END SELECT
        spkHpX1 = 0.0 : spkHpY1 = 0.0
    END SUB

    ' ============================================================
    ' Parse a phoneme token like "EH1" or "SH" into ID and stress.
    ' ============================================================
    SUB SPK_ParsePhone(tok AS STRING, phID AS INTEGER, stress AS INTEGER)
        DIM bare AS STRING, lastC AS STRING, p AS INTEGER, scan AS STRING
        DIM rest AS STRING

        bare = tok
        stress = 0
        IF LEN(bare) > 0 THEN
            lastC = RIGHT$(bare, 1)
            IF lastC >= "0" AND lastC <= "9" THEN
                stress = VAL(lastC)
                bare = LEFT$(bare, LEN(bare) - 1)
            END IF
        END IF

        ' Linear scan of SPK_NAMES
        rest = SPK_NAMES
        DIM cur AS INTEGER : cur = 0
        DO WHILE LEN(rest) > 0
            p = INSTR(rest, " ")
            IF p > 0 THEN
                scan = LEFT$(rest, p - 1)
                rest = MID$(rest, p + 1)
            ELSE
                scan = rest : rest = ""
            END IF
            IF scan = bare THEN
                phID = cur
                EXIT SUB
            END IF
            cur = cur + 1
        LOOP
        phID = SPK_SIL   ' unknown -> silence
    END SUB

    ' ============================================================
    ' Append phoneme tokens from a space-separated string into the
    ' utterance queue.  phStr is like "EH1 L OW0".
    ' ============================================================
    SUB SPK_AppendPhoneStr(phStr AS STRING)
        DIM rest AS STRING : rest = phStr
        DIM tok AS STRING, p AS INTEGER
        DIM phID AS INTEGER, stress AS INTEGER

        DO WHILE LEN(rest) > 0
            rest = LTRIM$(rest)
            p = INSTR(rest, " ")
            IF p > 0 THEN
                tok = LEFT$(rest, p - 1)
                rest = MID$(rest, p + 1)
            ELSE
                tok = rest : rest = ""
            END IF
            IF LEN(tok) > 0 THEN
                SPK_ParsePhone tok, phID, stress
                IF spkPhoneCount < SPK_PHONE_MAX THEN
                    spkPhones(spkPhoneCount) = phID
                    spkStress(spkPhoneCount) = stress
                    spkPhoneCount = spkPhoneCount + 1
                END IF
            END IF
        LOOP
    END SUB

    ' ============================================================
    ' Spell an unknown word letter-by-letter using letter-name phonemes.
    ' ============================================================
    SUB SPK_SpellWord(wrd AS STRING)
        DIM i AS INTEGER, c AS INTEGER
        FOR i = 1 TO LEN(wrd)
            c = ASC(MID$(wrd, i, 1)) - ASC("A")
            IF c >= 0 AND c <= 25 THEN
                SPK_AppendPhoneStr spkLetterSeq(c)
                ' short pause between letters
                IF spkPhoneCount < SPK_PHONE_MAX THEN
                    spkPhones(spkPhoneCount) = SPK_SIL
                    spkStress(spkPhoneCount) = 0
                    spkPhoneCount = spkPhoneCount + 1
                END IF
            END IF
        NEXT i
    END SUB

    ' ============================================================
    ' Binary search in sorted spkDictWord array.
    ' Sets result to found index, or -1 if not found.
    ' ============================================================
    SUB SPK_DictFind(wrd AS STRING, result AS INTEGER)
        DIM lo AS INTEGER, hi AS INTEGER, mdx AS INTEGER
        lo = 0 : hi = spkDictCount - 1
        result = -1
        DO WHILE lo <= hi
            mdx = (lo + hi) \ 2
            IF spkDictWord(mdx) = wrd THEN
                result = mdx
                EXIT SUB
            ELSEIF spkDictWord(mdx) < wrd THEN
                lo = mdx + 1
            ELSE
                hi = mdx - 1
            END IF
        LOOP
    END SUB

    ' ============================================================
    ' Reconstruct CMU phoneme string for a loaded dict entry.
    ' e.g. SPK_PhoneStr$(idx) -> "S IH1 R IY0 AH0 S L IY0"
    ' Vowels (ID 0-14) get stress digit appended; consonants do not.
    ' ============================================================
    FUNCTION SPK_PhoneStr$(pfsIdx AS INTEGER)
        DIM pfsOut AS STRING, pfsI AS INTEGER, pfsN AS INTEGER, pfsPh AS INTEGER
        DIM pfsP AS INTEGER, pfsQ AS INTEGER, pfsToken AS STRING
        pfsOut = ""
        FOR pfsI = 0 TO spkDictPhoneLen(pfsIdx) - 1
            pfsPh = spkDictPh(pfsIdx, pfsI)
            pfsN = 0 : pfsP = 1 : pfsToken = "?"
            DO WHILE pfsP <= LEN(SPK_NAMES)
                pfsQ = INSTR(pfsP, SPK_NAMES, " ")
                IF pfsQ = 0 THEN pfsQ = LEN(SPK_NAMES) + 1
                IF pfsN = pfsPh THEN
                    pfsToken = MID$(SPK_NAMES, pfsP, pfsQ - pfsP) : EXIT DO
                END IF
                pfsN = pfsN + 1 : pfsP = pfsQ + 1
            LOOP
            IF pfsPh <= 14 THEN pfsToken = pfsToken + LTRIM$(STR$(spkDictSt(pfsIdx, pfsI)))
            IF pfsI > 0 THEN pfsOut = pfsOut + " "
            pfsOut = pfsOut + pfsToken
        NEXT pfsI
        SPK_PhoneStr$ = pfsOut
    END FUNCTION

    ' Returns -1 if speech is still playing, 0 if done.
    FUNCTION SPK_IsPlaying%()
        SPK_IsPlaying% = (spkPhoneIdx < spkPhoneCount)
    END FUNCTION

    ' Returns the word currently being spoken (for HUD indicator), or "" between words.
    FUNCTION SPK_CurWord$()
        DIM cwI AS INTEGER
        FOR cwI = 0 TO spkWordCount - 1
            IF spkPhoneIdx >= spkWordStart(cwI) AND spkPhoneIdx <= spkWordEnd(cwI) THEN
                SPK_CurWord$ = spkWordText$(cwI) : EXIT FUNCTION
            END IF
        NEXT cwI
        SPK_CurWord$ = ""
    END FUNCTION

    ' Returns the 0-based occurrence index of the current word within this utterance.
    ' Used to highlight exactly the right instance when the same word appears multiple times.
    FUNCTION SPK_CurWordOcc%()
        DIM cwI AS INTEGER
        FOR cwI = 0 TO spkWordCount - 1
            IF spkPhoneIdx >= spkWordStart(cwI) AND spkPhoneIdx <= spkWordEnd(cwI) THEN
                SPK_CurWordOcc% = spkWordOcc(cwI) : EXIT FUNCTION
            END IF
        NEXT cwI
        SPK_CurWordOcc% = 0
    END FUNCTION

    ' ============================================================
    ' Queue text for speech.  Call at any time; SPK_Fill drains it.
    ' ============================================================
    SUB SPK_Say(text AS STRING)
        DIM wrd AS STRING, rest AS STRING, p AS INTEGER, uc AS STRING
        DIM idx AS INTEGER, pi AS INTEGER
        DIM spkPpI AS INTEGER, spkPpOut AS STRING
        DIM spkPI2 AS INTEGER, spkPI3 AS INTEGER, spkPI4 AS INTEGER
        DIM spkLogStr AS STRING, spkLogFH AS INTEGER, spkLogMiss AS INTEGER
        DIM spkWStart AS INTEGER
        DIM spkWOccI AS INTEGER, spkWOccN AS INTEGER

        spkRateScale = 1.0  ' reset; SPK_SyncToScroll may override after this returns
        spkPhoneCount = 0 : spkPhoneIdx = 0 : spkSamplePos = 0
        spkWavePhase = 0.0 : spkPrevPhoneID = SPK_SIL
        spkWordCount = 0
        DIM spkTs AS LONG : spkTs = CLNG(TIMER * 1000) MOD 3600000  ' ms since last hour
        spkLogStr = "--- [" + LTRIM$(STR$(spkTs \ 60000)) + ":" + RIGHT$("0" + LTRIM$(STR$((spkTs \ 1000) MOD 60)), 2) + "." + RIGHT$("00" + LTRIM$(STR$(spkTs MOD 1000)), 3) + "] " + LEFT$(text, 60) + CHR$(10)
        spkLogMiss = 0

        ' Pre-pass: replace punctuation with pause tokens before alpha stripping.
        ' Also eat apostrophes: 'S (possessive) -> nothing; bare ' (contraction) -> nothing.
        ' Without this, "EMPIRE'S" splits into "EMPIRE" + "S" and S gets spelled.
        spkPpOut = "" : spkPpI = 1
        DO WHILE spkPpI <= LEN(text)
            IF MID$(text, spkPpI, 3) = "..." THEN
                spkPpOut = spkPpOut + " STOPPAUSE " : spkPpI = spkPpI + 3
            ELSEIF MID$(text, spkPpI, 1) = "." OR MID$(text, spkPpI, 1) = "!" OR MID$(text, spkPpI, 1) = "?" THEN
                spkPpOut = spkPpOut + " STOPPAUSE " : spkPpI = spkPpI + 1
            ELSEIF MID$(text, spkPpI, 1) = "," OR MID$(text, spkPpI, 1) = ";" OR MID$(text, spkPpI, 1) = ":" THEN
                spkPpOut = spkPpOut + " CMAPAUSE " : spkPpI = spkPpI + 1
            ELSEIF MID$(text, spkPpI, 2) = "'s" OR MID$(text, spkPpI, 2) = "'S" THEN
                spkPpI = spkPpI + 2  ' strip possessive 'S entirely
            ELSEIF MID$(text, spkPpI, 1) = "'" THEN
                spkPpI = spkPpI + 1  ' strip bare apostrophe (contractions: don't->dont)
            ELSE
                spkPpOut = spkPpOut + MID$(text, spkPpI, 1) : spkPpI = spkPpI + 1
            END IF
        LOOP

        uc = UCASE$(spkPpOut)
        ' Strip non-alpha characters except spaces (pause tokens survive as they're all alpha)
        DIM cleaned AS STRING : cleaned = ""
        DIM ci AS INTEGER
        FOR ci = 1 TO LEN(uc)
            DIM ch AS STRING : ch = MID$(uc, ci, 1)
            IF (ch >= "A" AND ch <= "Z") OR ch = " " THEN
                cleaned = cleaned + ch
            ELSE
                cleaned = cleaned + " "
            END IF
        NEXT ci

        rest = LTRIM$(RTRIM$(cleaned))
        DO WHILE LEN(rest) > 0
            rest = LTRIM$(rest)
            p = INSTR(rest, " ")
            IF p > 0 THEN
                wrd = LEFT$(rest, p - 1)
                rest = MID$(rest, p + 1)
            ELSE
                wrd = rest : rest = ""
            END IF

            IF LEN(wrd) = 0 THEN GOTO nextWord

            ' Punctuation pause tokens — inject silence instead of doing dict lookup
            IF wrd = "CMAPAUSE" THEN
                FOR spkPI2 = 1 TO 2  ' ~100ms extra pause at comma/semicolon/colon
                    IF spkPhoneCount < SPK_PHONE_MAX THEN
                        spkPhones(spkPhoneCount) = SPK_SIL : spkStress(spkPhoneCount) = 0 : spkPhoneCount = spkPhoneCount + 1
                    END IF
                NEXT spkPI2
                GOTO nextWord
            END IF
            IF wrd = "STOPPAUSE" THEN
                FOR spkPI3 = 1 TO 6  ' ~300ms extra pause at sentence end
                    IF spkPhoneCount < SPK_PHONE_MAX THEN
                        spkPhones(spkPhoneCount) = SPK_SIL : spkStress(spkPhoneCount) = 0 : spkPhoneCount = spkPhoneCount + 1
                    END IF
                NEXT spkPI3
                GOTO nextWord
            END IF
            IF wrd = "PARSPAUSE" THEN
                FOR spkPI4 = 1 TO 6  ' ~300ms extra pause at paragraph break
                    IF spkPhoneCount < SPK_PHONE_MAX THEN
                        spkPhones(spkPhoneCount) = SPK_SIL : spkStress(spkPhoneCount) = 0 : spkPhoneCount = spkPhoneCount + 1
                    END IF
                NEXT spkPI4
                GOTO nextWord
            END IF

            spkWStart = spkPhoneCount
            SPK_DictFind wrd, idx
            IF idx >= 0 THEN
                spkLogStr = spkLogStr + "  OK   " + wrd + " -> " + SPK_PhoneStr$(idx) + CHR$(10)
                FOR pi = 0 TO spkDictPhoneLen(idx) - 1
                    IF spkPhoneCount < SPK_PHONE_MAX THEN
                        spkPhones(spkPhoneCount) = spkDictPh(idx, pi)
                        spkStress(spkPhoneCount) = spkDictSt(idx, pi)
                        spkPhoneCount = spkPhoneCount + 1
                    END IF
                NEXT pi
            ELSE
                spkLogStr = spkLogStr + "  MISS " + wrd + CHR$(10)
                spkLogMiss = spkLogMiss + 1
                SPK_SpellWord wrd
            END IF

            ' inter-word silence
            IF spkPhoneCount < SPK_PHONE_MAX THEN
                spkPhones(spkPhoneCount) = SPK_SIL
                spkStress(spkPhoneCount) = 0
                spkPhoneCount = spkPhoneCount + 1
            END IF

            ' word boundary record (includes the trailing SIL so indicator stays up)
            IF spkWordCount < SPK_MAX_WORDS THEN
                spkWordStart(spkWordCount) = spkWStart
                spkWordEnd(spkWordCount) = spkPhoneCount - 1
                spkWordText$(spkWordCount) = wrd
                ' count how many times this exact word appeared earlier in this utterance
                spkWOccN = 0
                FOR spkWOccI = 0 TO spkWordCount - 1
                    IF spkWordText$(spkWOccI) = wrd THEN spkWOccN = spkWOccN + 1
                NEXT spkWOccI
                spkWordOcc(spkWordCount) = spkWOccN
                spkWordCount = spkWordCount + 1
            END IF

            nextWord:
        LOOP
    END SUB

    ' ============================================================
    ' Adjust speech rate so the queued utterance ends when the last crawl
    ' line exits the top of the screen.  Call immediately after SPK_Say.
    '   scrollPx   : pixels remaining until last line reaches y=0
    '   pxPerFrame : scroll speed (CRAWL_SPEED)
    ' Rate is clamped 0.6x-1.8x to avoid distorting phoneme quality.
    ' ============================================================
    SUB SPK_SyncToScroll(scrollPx AS SINGLE, pxPerFrame AS SINGLE)
        DIM syncI AS INTEGER
        DIM syncTotal AS LONG, syncScrollSamples AS LONG

        IF spkPhoneCount = 0 OR pxPerFrame <= 0 THEN EXIT SUB

        syncTotal = 0
        FOR syncI = 0 TO spkPhoneCount - 1
            syncTotal = syncTotal + spkDur(spkPhones(syncI), spkStress(syncI))
        NEXT syncI

        ' scrollPx / pxPerFrame = frames; × SAMPLE_RATE/60 = samples at 60fps
        syncScrollSamples = CLNG(scrollPx / pxPerFrame * SAMPLE_RATE / 60.0)

        IF syncTotal > 0 AND syncScrollSamples > 0 THEN
            spkRateScale = syncScrollSamples / syncTotal
            IF spkRateScale < 0.60 THEN spkRateScale = 0.60
            IF spkRateScale > 1.20 THEN spkRateScale = 1.20
        END IF
    END SUB

    ' ============================================================
    ' Returns 1 if speech is still playing, 0 if silent.
    ' ============================================================
    ' Compute next speech sample into spkSampleOut.  Call once per audio sample.
    ' snd.bas reads spkSampleOut directly after calling SPK_Advance.
    ' ============================================================
    SUB SPK_Advance()
        DIM phoneID AS INTEGER, stress AS INTEGER, dur AS INTEGER
        DIM env AS SINGLE, s AS SINGLE, t AS SINGLE
        DIM wIdx AS INTEGER, wNext AS INTEGER, wFrac AS SINGLE
        DIM newBuzz AS SINGLE, prevBuzz AS SINGLE, blendT AS SINGLE, buzz AS SINGLE
        DIM nx AS SINGLE, hy AS SINGLE
        DIM diphT AS SINGLE, diphA AS SINGLE, diphB AS SINGLE

        IF spkPhoneIdx >= spkPhoneCount THEN
            spkSampleOut = 0.0
            EXIT SUB
        END IF

        phoneID = spkPhones(spkPhoneIdx)
        stress  = spkStress(spkPhoneIdx)
        dur     = INT(spkDur(phoneID, stress) * spkRateScale)
        IF dur < 2 THEN dur = 2

        IF spkSamplePos = 0 THEN SPK_BuildWave phoneID, stress

        ' Amplitude envelope: 10ms fade in/out (overridden to 1.0 during voiced crossfade)
        IF spkSamplePos < SPK_FADE THEN
            env = spkSamplePos / SPK_FADE
        ELSEIF spkSamplePos > dur - SPK_FADE THEN
            env = (dur - spkSamplePos) / SPK_FADE
            IF env < 0 THEN env = 0
        ELSE
            env = 1.0
        END IF

        ' Wavetable read with linear interpolation
        wIdx  = INT(spkWavePhase)
        wFrac = spkWavePhase - wIdx
        wNext = (wIdx + 1) AND (SPK_WAVE_LEN - 1)
        IF spkDiEnd(phoneID) >= 0 THEN
            ' Diphthong: glide from onset wavetable to target vowel wavetable
            diphT = spkSamplePos / dur : IF diphT > 1.0 THEN diphT = 1.0
            diphA = spkWaveLib(phoneID, stress, wIdx) + wFrac * (spkWaveLib(phoneID, stress, wNext) - spkWaveLib(phoneID, stress, wIdx))
            diphB = spkWaveLib(spkDiEnd(phoneID), stress, wIdx) + wFrac * (spkWaveLib(spkDiEnd(phoneID), stress, wNext) - spkWaveLib(spkDiEnd(phoneID), stress, wIdx))
            newBuzz = diphA + diphT * (diphB - diphA)
        ELSE
            newBuzz = spkWave(wIdx) + wFrac * (spkWave(wNext) - spkWave(wIdx))
        END IF

        ' Coarticulation: crossfade from previous phoneme's wavetable during fade-in.
        ' Only voiced->voiced transitions; unvoiced onset keeps its own fade-in envelope.
        ' env is NOT overridden: the outgoing phoneme fades to ~0 at its end, so env=1.0
        ' here would cause a discontinuity (click) when the new phoneme jumps to full
        ' amplitude. The normal fade-in ramps from 0; the wavetable blend handles timbre.
        IF spkSamplePos < SPK_FADE AND spkF1(spkPrevPhoneID) > 0 AND spkF1(phoneID) > 0 THEN
            prevBuzz = spkWavePrev(wIdx) + wFrac * (spkWavePrev(wNext) - spkWavePrev(wIdx))
            blendT = spkSamplePos / SPK_FADE
            buzz = prevBuzz + blendT * (newBuzz - prevBuzz)
        ELSE
            buzz = newBuzz
        END IF

        spkWavePhase = spkWavePhase + spkWaveStep
        IF spkWavePhase >= SPK_WAVE_LEN THEN spkWavePhase = spkWavePhase - SPK_WAVE_LEN

        SELECT CASE phoneID
        CASE SPK_AA TO SPK_UW, SPK_L TO SPK_YW
            s = buzz * 0.50
        CASE SPK_DH, SPK_V, SPK_Z, SPK_ZH
            ' Voiced fricatives: formant buzz + HP-filtered noise component
            nx = RND * 2.0 - 1.0
            hy = (1.0 + spkHpCoeff) * 0.5 * (nx - spkHpX1) + spkHpCoeff * spkHpY1
            spkHpX1 = nx : spkHpY1 = hy
            s = buzz * 0.18 + hy * 0.10
        CASE SPK_B, SPK_D, SPK_G
            t = spkSamplePos / dur
            IF t < 0.60 THEN
                s = buzz * 0.05
            ELSE
                s = buzz * 0.35
            END IF
        CASE SPK_F, SPK_S, SPK_SH, SPK_TH, SPK_HH
            ' HP-filtered white noise; cutoff set per-phoneme in SPK_BuildWave
            nx = RND * 2.0 - 1.0
            hy = (1.0 + spkHpCoeff) * 0.5 * (nx - spkHpX1) + spkHpCoeff * spkHpY1
            spkHpX1 = nx : spkHpY1 = hy
            s = hy * 0.20
        CASE SPK_P, SPK_T, SPK_K
            ' Closure (0-55%) → silence; release (55-100%) → aspirated HP-filtered noise.
            ' Burst HP coeff set per place of articulation in SPK_BuildWave:
            '   P=bilabial(low cutoff), T=alveolar(high/hissy), K=velar(mid).
            ' Filter starts from cold state (reset in SPK_BuildWave) so the onset
            ' has a natural transient click at the moment of release.
            t = spkSamplePos / dur
            IF t < 0.55 THEN
                s = 0.0
            ELSE
                nx = RND * 2.0 - 1.0
                hy = (1.0 + spkHpCoeff) * 0.5 * (nx - spkHpX1) + spkHpCoeff * spkHpY1
                spkHpX1 = nx : spkHpY1 = hy
                s = hy * 0.30
            END IF
        CASE SPK_CH, SPK_JH
            t = spkSamplePos / dur
            IF t < 0.40 THEN s = 0.0 _
        ELSE s = (RND * 2.0 - 1.0) * 0.20
        CASE ELSE
            s = 0.0
        END SELECT

        spkSampleOut = s * env * 0.45

        spkSamplePos = spkSamplePos + 1
        IF spkSamplePos >= dur THEN
            spkSamplePos = 0
            spkPrevPhoneID = phoneID  ' track what's now in spkWavePrev for next blend
            spkPhoneIdx    = spkPhoneIdx + 1
        END IF
    END SUB

    ' ============================================================
    ' Load baked dictionary from embedded SPEECHDICT data.
    ' Expects lines: "WORD PH1 PH2 ..." (# comment / blank = skip).
    ' Words must be in alphabetical order for binary search.
    ' ============================================================
    SUB SPK_LoadDict()
        DIM dat AS STRING, ln AS STRING, rest AS STRING
        DIM p AS INTEGER, tok AS STRING
        DIM phID AS INTEGER, stress AS INTEGER
        DIM pi AS INTEGER, lp AS INTEGER
        DIM dw AS STRING, phones AS STRING, pr AS STRING, pp AS INTEGER
        DIM valid AS INTEGER

        dat  = _EMBEDDED$("SPEECHDICT")
        rest = dat
        spkDictCount = 0

        DO WHILE LEN(rest) > 0
            ' Extract one line
            p = INSTR(rest, CHR$(10))
            IF p > 0 THEN
                ln   = LEFT$(rest, p - 1)
                rest = MID$(rest, p + 1)
            ELSE
                ln = rest : rest = ""
            END IF
            ln = RTRIM$(ln)
            IF LEN(ln) > 0 THEN
                IF RIGHT$(ln, 1) = CHR$(13) THEN ln = LEFT$(ln, LEN(ln) - 1)
            END IF

            valid = -1
            IF LEN(ln) = 0 THEN valid = 0
            IF valid AND LEFT$(ln, 1) = "#" THEN valid = 0
            IF valid AND spkDictCount >= SPK_DICT_MAX THEN valid = 0

            IF valid THEN
                lp = INSTR(ln, " ")
                IF lp = 0 THEN valid = 0
            END IF

            IF valid THEN
                dw     = LEFT$(ln, lp - 1)
                phones = MID$(ln, lp + 1)
                spkDictWord(spkDictCount) = dw
                pi = 0
                pr = phones
                DO WHILE LEN(pr) > 0
                    pr = LTRIM$(pr)
                    pp = INSTR(pr, " ")
                    IF pp > 0 THEN
                        tok = LEFT$(pr, pp - 1)
                        pr  = MID$(pr, pp + 1)
                    ELSE
                        tok = pr : pr = ""
                    END IF
                    IF LEN(tok) > 0 AND pi < 16 THEN
                        SPK_ParsePhone tok, phID, stress
                        spkDictPh(spkDictCount, pi) = phID
                        spkDictSt(spkDictCount, pi) = stress
                        pi = pi + 1
                    END IF
                LOOP
                spkDictPhoneLen(spkDictCount) = pi
                spkDictCount = spkDictCount + 1
            END IF
        LOOP
    END SUB
