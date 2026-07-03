Const AUDIO_BUFFER_TARGET = 0.10
Const BGM_BPM             = 140
Const TITLE_BPM           = 112
Const SND_SHOOT_LEN       = 2205
Const SND_BOOM_LEN        = 11025
Const SND_HIT_LEN         = 8820
Const SND_PUP_LEN         = 4410
Const SND_WHOOSH_LEN      = 6615
Const SND_KICK_LEN        = 11025  ' 250ms kick drum
Const SND_SNARE_LEN       = 4410   ' 100ms snare
Const SND_HIHAT_LEN       = 2205   ' 50ms hi-hat
Const BGM_PAD_TARGET      = 0.025  ' chord pad amplitude per voice (E minor triad)

Dim Shared sndEnginePhase As Single
Dim Shared sndEngineFreq  As Single
Dim Shared sndEngineAmp   As Single
Dim Shared musicSample    As Single
Dim Shared bgmNoteDur     As Integer
Dim Shared bgmBassNote    As Integer
Dim Shared bgmBassCount   As Integer
Dim Shared bgmBassPhase   As Single
Dim Shared bgmBassFreq    As Single
Dim Shared bgmLeadNote    As Integer
Dim Shared bgmLeadCount   As Integer
Dim Shared bgmLeadPhase   As Single
Dim Shared bgmLeadFreq    As Single
Dim Shared bgmBossMode    As Integer
Dim Shared bgmNormalBass(0 To 7)  As Single
Dim Shared bgmNormalLead(0 To 15) As Single
Dim Shared bgmBossBass(0 To 7)    As Single
Dim Shared bgmBossLead(0 To 15)   As Single
Dim Shared titleBgmNoteDur  As Integer
Dim Shared titleBgmBassNote As Integer
Dim Shared titleBgmBassCount As Integer
Dim Shared titleBgmBassPhase As Single
Dim Shared titleBgmBassFreq  As Single
Dim Shared titleBgmLeadNote  As Integer
Dim Shared titleBgmLeadCount As Integer
Dim Shared titleBgmLeadPhase As Single
Dim Shared titleBgmLeadFreq  As Single
Dim Shared titleBgmBassGate  As Integer
Dim Shared titleBgmLeadGate  As Integer
Dim Shared titleBgmBass(0 To 19) As Single
Dim Shared titleBgmLead(0 To 19) As Single
Dim Shared sndShoot(0 To SND_SHOOT_LEN - 1) As Single
Dim Shared sndBoom(0 To SND_BOOM_LEN - 1)   As Single
Dim Shared sndHit(0 To SND_HIT_LEN - 1)     As Single
Dim Shared sndPup(0 To SND_PUP_LEN - 1)     As Single
Dim Shared sndWhoosh(0 To SND_WHOOSH_LEN - 1) As Single
' Playhead positions for each effect (-1 = not playing).
' Set to 0 to (re)start; advanced sample-by-sample in SND_GameFill.
Dim Shared sndShootPos  As Integer : sndShootPos  = -1
Dim Shared sndBoomPos   As Integer : sndBoomPos   = -1
Dim Shared sndHitPos    As Integer : sndHitPos    = -1
Dim Shared sndPupPos    As Integer : sndPupPos    = -1
Dim Shared sndWhooshPos As Integer : sndWhooshPos = -1

' percussion wavetables and playheads
Dim Shared sndKick(0 To SND_KICK_LEN - 1)   As Single
Dim Shared sndSnare(0 To SND_SNARE_LEN - 1) As Single
Dim Shared sndHihat(0 To SND_HIHAT_LEN - 1) As Single
Dim Shared sndKickPos  As Integer : sndKickPos  = -1
Dim Shared sndSnarePos As Integer : sndSnarePos = -1
Dim Shared sndHihatPos As Integer : sndHihatPos = -1

' drum sequencer state (16-step, one 16th note per step)
Dim Shared bgmDrumStep  As Integer
Dim Shared bgmDrumCount As Integer

' chord pad oscillator state (E minor triad: E4/G4/B4)
Dim Shared bgmPadPhase1 As Single
Dim Shared bgmPadPhase2 As Single
Dim Shared bgmPadPhase3 As Single
Dim Shared bgmPadAmp    As Single

Sub SND_Init()
    Dim sndK As Integer, sndF As Single, sndFade As Single
    Dim sndGenPh As Single, sndGenT As Single
    Dim sndGenNz As Single, sndGenHP As Single, sndGenPX As Single

    sndEngineFreq = 80.0 : sndEngineAmp = 0.07

    ' game BGM — E minor chase theme, 16th-note sequencer @ 140 BPM
    bgmNoteDur = SAMPLE_RATE * 60 / BGM_BPM / 4

    bgmNormalBass(0) = 82.4  : bgmNormalBass(1) = 61.7
    bgmNormalBass(2) = 98.0  : bgmNormalBass(3) = 73.4
    bgmNormalBass(4) = 82.4  : bgmNormalBass(5) = 110.0
    bgmNormalBass(6) = 73.4  : bgmNormalBass(7) = 61.7

    bgmNormalLead(0)  = 329.6 : bgmNormalLead(1)  = 392.0
    bgmNormalLead(2)  = 493.9 : bgmNormalLead(3)  = 659.3
    bgmNormalLead(4)  = 293.7 : bgmNormalLead(5)  = 392.0
    bgmNormalLead(6)  = 440.0 : bgmNormalLead(7)  = 587.3
    bgmNormalLead(8)  = 392.0 : bgmNormalLead(9)  = 493.9
    bgmNormalLead(10) = 587.3 : bgmNormalLead(11) = 784.0
    bgmNormalLead(12) = 329.6 : bgmNormalLead(13) = 493.9
    bgmNormalLead(14) = 659.3 : bgmNormalLead(15) = 493.9

    bgmBossBass(0) = 82.4  : bgmBossBass(1) =  0.0
    bgmBossBass(2) = 82.4  : bgmBossBass(3) = 77.8
    bgmBossBass(4) = 98.0  : bgmBossBass(5) =  0.0
    bgmBossBass(6) = 87.3  : bgmBossBass(7) = 82.4

    bgmBossLead(0)  = 659.3 : bgmBossLead(1)  =   0.0
    bgmBossLead(2)  = 698.5 : bgmBossLead(3)  =   0.0
    bgmBossLead(4)  = 659.3 : bgmBossLead(5)  = 587.3
    bgmBossLead(6)  = 554.4 : bgmBossLead(7)  = 493.9
    bgmBossLead(8)  = 659.3 : bgmBossLead(9)  =   0.0
    bgmBossLead(10) = 784.0 : bgmBossLead(11) =   0.0
    bgmBossLead(12) = 698.5 : bgmBossLead(13) = 659.3
    bgmBossLead(14) = 622.3 : bgmBossLead(15) =   0.0

    bgmBassFreq = bgmNormalBass(0) : bgmBassCount = bgmNoteDur * 4
    bgmLeadFreq = bgmNormalLead(0) : bgmLeadCount = bgmNoteDur * 2
    bgmDrumStep = 15 : bgmDrumCount = 1  ' fires step 0 (kick) on first audio sample

    ' title BGM — Mars (Holst, PD), 5/4 time @ 112 BPM
    titleBgmNoteDur  = SAMPLE_RATE * 60 / TITLE_BPM / 4
    titleBgmBassGate = titleBgmNoteDur * 3
    titleBgmLeadGate = titleBgmNoteDur * 1

    titleBgmBass(0)  = 98.00  : titleBgmBass(1)  = 98.00  : titleBgmBass(2)  = 98.00
    titleBgmBass(3)  = 146.83 : titleBgmBass(4)  = 98.00
    titleBgmBass(5)  = 130.81 : titleBgmBass(6)  = 130.81 : titleBgmBass(7)  = 130.81
    titleBgmBass(8)  = 98.00  : titleBgmBass(9)  = 103.83
    titleBgmBass(10) = 87.31  : titleBgmBass(11) = 87.31  : titleBgmBass(12) = 87.31
    titleBgmBass(13) = 130.81 : titleBgmBass(14) = 146.83
    titleBgmBass(15) = 116.54 : titleBgmBass(16) = 116.54 : titleBgmBass(17) = 130.81
    titleBgmBass(18) = 146.83 : titleBgmBass(19) = 155.56

    titleBgmLead(0)  = 392.00 : titleBgmLead(1)  = 392.00 : titleBgmLead(2)  = 392.00
    titleBgmLead(3)  = 587.33 : titleBgmLead(4)  = 622.25
    titleBgmLead(5)  = 523.25 : titleBgmLead(6)  = 523.25 : titleBgmLead(7)  = 523.25
    titleBgmLead(8)  = 392.00 : titleBgmLead(9)  = 415.30
    titleBgmLead(10) = 349.23 : titleBgmLead(11) = 349.23 : titleBgmLead(12) = 349.23
    titleBgmLead(13) = 523.25 : titleBgmLead(14) = 587.33
    titleBgmLead(15) = 466.16 : titleBgmLead(16) = 466.16 : titleBgmLead(17) = 523.25
    titleBgmLead(18) = 587.33 : titleBgmLead(19) = 622.25

    titleBgmBassFreq = titleBgmBass(0) : titleBgmBassCount = titleBgmNoteDur * 4
    titleBgmLeadFreq = titleBgmLead(0) : titleBgmLeadCount = titleBgmNoteDur * 4

    ' pre-compute sound effects
    For sndK = 0 To SND_SHOOT_LEN - 1
        sndF    = 880.0 - 440.0 * sndK / SND_SHOOT_LEN
        sndFade = 1.0 - sndK / SND_SHOOT_LEN
        sndShoot(sndK) = Sin(6.2832 * sndF * sndK / SAMPLE_RATE) * sndFade * 0.25
    Next sndK
    For sndK = 0 To SND_BOOM_LEN - 1
        sndF    = 300.0 - 260.0 * sndK / SND_BOOM_LEN
        sndFade = (1.0 - sndK / SND_BOOM_LEN) ^ 2
        sndBoom(sndK) = (Sin(6.2832 * sndF * sndK / SAMPLE_RATE) * 0.5 + (Rnd * 2.0 - 1.0) * 0.3) * sndFade
    Next sndK
    For sndK = 0 To SND_HIT_LEN - 1
        sndFade = (1.0 - sndK / SND_HIT_LEN) ^ 3
        sndHit(sndK) = Sin(6.2832 * 80.0 * sndK / SAMPLE_RATE) * sndFade * 0.5
    Next sndK
    For sndK = 0 To SND_PUP_LEN - 1
        sndF    = 440.0 + 440.0 * sndK / SND_PUP_LEN
        sndFade = 1.0 - (sndK / SND_PUP_LEN) ^ 2
        sndPup(sndK) = (Sin(6.2832 * sndF * sndK / SAMPLE_RATE) + Sin(6.2832 * sndF * 2.0 * sndK / SAMPLE_RATE) * 0.3) * sndFade * 0.25
    Next sndK
    For sndK = 0 To SND_WHOOSH_LEN - 1
        sndF    = 580.0 - 500.0 * sndK / SND_WHOOSH_LEN
        sndFade = (1.0 - sndK / SND_WHOOSH_LEN) ^ 0.5
        sndWhoosh(sndK) = (Sin(6.2832 * sndF * sndK / SAMPLE_RATE) * 0.35 + (Rnd * 2.0 - 1.0) * 0.25) * sndFade * 0.32
    Next sndK

    ' kick drum: exponential frequency sweep 160->45 Hz over 250ms
    sndGenPh = 0
    For sndK = 0 To SND_KICK_LEN - 1
        sndGenT = sndK / SND_KICK_LEN
        sndF    = 160.0 * Exp(-sndGenT * 14.0) + 45.0
        sndFade = Exp(-sndGenT * 6.0)
        sndGenPh = sndGenPh + 6.2832 * sndF / SAMPLE_RATE
        If sndGenPh > 6.2832 Then sndGenPh = sndGenPh - 6.2832
        sndKick(sndK) = Sin(sndGenPh) * sndFade * 0.30
    Next sndK

    ' snare: filtered noise + 180 Hz body, 100ms
    sndGenHP = 0 : sndGenPX = 0 : sndGenPh = 0
    For sndK = 0 To SND_SNARE_LEN - 1
        sndGenT   = sndK / SND_SNARE_LEN
        sndFade   = (1.0 - sndGenT) ^ 2
        sndGenNz  = Rnd * 2.0 - 1.0
        sndGenHP  = sndGenNz - sndGenPX + 0.65 * sndGenHP  ' first-order HP, midrange noise
        sndGenPX  = sndGenNz
        sndGenPh  = sndGenPh + 6.2832 * 180.0 / SAMPLE_RATE
        If sndGenPh > 6.2832 Then sndGenPh = sndGenPh - 6.2832
        sndSnare(sndK) = (sndGenHP * 0.60 + Sin(sndGenPh) * 0.40) * sndFade * 0.18
    Next sndK

    ' hi-hat: bright high-passed noise, 50ms
    sndGenHP = 0 : sndGenPX = 0
    For sndK = 0 To SND_HIHAT_LEN - 1
        sndGenT  = sndK / SND_HIHAT_LEN
        sndFade  = (1.0 - sndGenT) ^ 3
        sndGenNz = Rnd * 2.0 - 1.0
        sndGenHP = sndGenNz - sndGenPX + 0.85 * sndGenHP  ' first-order HP, bright
        sndGenPX = sndGenNz
        sndHihat(sndK) = sndGenHP * sndFade * 0.055
    Next sndK
End Sub

Sub SND_GameFill(isManeuver As Integer)
    Dim sndK As Integer, sndFillCount As Integer
    Dim bgmPadTarget As Single
    If bgmBossMode Then bgmPadTarget = 0.0 Else bgmPadTarget = BGM_PAD_TARGET
    If isManeuver Then
        sndEngineFreq = sndEngineFreq + (150.0 - sndEngineFreq) * 0.07
        sndEngineAmp  = sndEngineAmp  + (0.20  - sndEngineAmp)  * 0.07
    Else
        sndEngineFreq = sndEngineFreq + (75.0  - sndEngineFreq) * 0.04
        sndEngineAmp  = sndEngineAmp  + (0.07  - sndEngineAmp)  * 0.04
    End If
    sndFillCount = Int((AUDIO_BUFFER_TARGET - _SNDRAWLEN) * SAMPLE_RATE)
    If sndFillCount > 0 Then
        Dim sndEfx As Single
        For sndK = 0 To sndFillCount - 1
            sndEnginePhase = sndEnginePhase + 6.2832 * sndEngineFreq / SAMPLE_RATE
            If sndEnginePhase > 6.2832 Then sndEnginePhase = sndEnginePhase - 6.2832

            bgmBassCount = bgmBassCount - 1
            If bgmBassCount <= 0 Then
                bgmBassNote  = (bgmBassNote + 1) Mod 8
                bgmBassCount = bgmNoteDur * 4
                bgmBassPhase = 0
                If bgmBossMode Then bgmBassFreq = bgmBossBass(bgmBassNote) _
                               Else bgmBassFreq = bgmNormalBass(bgmBassNote)
            End If
            bgmLeadCount = bgmLeadCount - 1
            If bgmLeadCount <= 0 Then
                bgmLeadNote  = (bgmLeadNote + 1) Mod 16
                bgmLeadCount = bgmNoteDur * 2
                bgmLeadPhase = 0
                If bgmBossMode Then bgmLeadFreq = bgmBossLead(bgmLeadNote) _
                               Else bgmLeadFreq = bgmNormalLead(bgmLeadNote)
            End If
            If bgmBassFreq > 0 Then
                bgmBassPhase = bgmBassPhase + 6.2832 * bgmBassFreq / SAMPLE_RATE
                If bgmBassPhase > 6.2832 Then bgmBassPhase = bgmBassPhase - 6.2832
                musicSample = (Sin(bgmBassPhase) + Sin(bgmBassPhase * 2) * 0.5 + Sin(bgmBassPhase * 3) * 0.25) * 0.055
            Else
                musicSample = 0
            End If
            If bgmLeadFreq > 0 Then
                bgmLeadPhase = bgmLeadPhase + 6.2832 * bgmLeadFreq / SAMPLE_RATE
                If bgmLeadPhase > 6.2832 Then bgmLeadPhase = bgmLeadPhase - 6.2832
                musicSample = musicSample + (Sin(bgmLeadPhase) + Sin(bgmLeadPhase * 1.004) * 0.65) * 0.038
            End If

            ' chord pad: E minor triad (E4=329.6 G4=392.0 B4=493.9), slow attack
            bgmPadAmp = bgmPadAmp + (bgmPadTarget - bgmPadAmp) * 0.00005
            bgmPadPhase1 = bgmPadPhase1 + 6.2832 * 329.6 / SAMPLE_RATE
            bgmPadPhase2 = bgmPadPhase2 + 6.2832 * 392.0 / SAMPLE_RATE
            bgmPadPhase3 = bgmPadPhase3 + 6.2832 * 493.9 / SAMPLE_RATE
            If bgmPadPhase1 > 6.2832 Then bgmPadPhase1 = bgmPadPhase1 - 6.2832
            If bgmPadPhase2 > 6.2832 Then bgmPadPhase2 = bgmPadPhase2 - 6.2832
            If bgmPadPhase3 > 6.2832 Then bgmPadPhase3 = bgmPadPhase3 - 6.2832
            musicSample = musicSample + (Sin(bgmPadPhase1) + Sin(bgmPadPhase2) + Sin(bgmPadPhase3)) * bgmPadAmp

            ' 16-step drum sequencer; one step = one 16th note = bgmNoteDur samples
            bgmDrumCount = bgmDrumCount - 1
            If bgmDrumCount <= 0 Then
                bgmDrumStep  = (bgmDrumStep + 1) Mod 16
                bgmDrumCount = bgmNoteDur
                If bgmBossMode Then
                    ' syncopated kick + 16th-note hi-hat for boss intensity
                    If bgmDrumStep = 0 Or bgmDrumStep = 3 Or bgmDrumStep = 8 Or bgmDrumStep = 11 Then sndKickPos  = 0
                    If bgmDrumStep = 4 Or bgmDrumStep = 12 Then sndSnarePos = 0
                    sndHihatPos = 0
                Else
                    ' standard 4/4: kick on 1+3, snare on 2+4, 8th-note hi-hat
                    If bgmDrumStep = 0 Or bgmDrumStep = 8 Then sndKickPos  = 0
                    If bgmDrumStep = 4 Or bgmDrumStep = 12 Then sndSnarePos = 0
                    If (bgmDrumStep And 1) = 0 Then sndHihatPos = 0
                End If
            End If
            ' advance drum playheads into music bus
            If sndKickPos >= 0 Then
                musicSample = musicSample + sndKick(sndKickPos)
                sndKickPos = sndKickPos + 1
                If sndKickPos >= SND_KICK_LEN Then sndKickPos = -1
            End If
            If sndSnarePos >= 0 Then
                musicSample = musicSample + sndSnare(sndSnarePos)
                sndSnarePos = sndSnarePos + 1
                If sndSnarePos >= SND_SNARE_LEN Then sndSnarePos = -1
            End If
            If sndHihatPos >= 0 Then
                musicSample = musicSample + sndHihat(sndHihatPos)
                sndHihatPos = sndHihatPos + 1
                If sndHihatPos >= SND_HIHAT_LEN Then sndHihatPos = -1
            End If

            ' Mix all active SFX into a single sample alongside BGM+engine.
            ' Each effect has a playhead (xxxPos); triggering sets it to 0,
            ' re-triggering restarts the sound rather than queuing another copy.
            sndEfx = 0
            If sndShootPos >= 0 Then
                sndEfx = sndEfx + sndShoot(sndShootPos)
                sndShootPos = sndShootPos + 1
                If sndShootPos >= SND_SHOOT_LEN Then sndShootPos = -1
            End If
            If sndBoomPos >= 0 Then
                sndEfx = sndEfx + sndBoom(sndBoomPos)
                sndBoomPos = sndBoomPos + 1
                If sndBoomPos >= SND_BOOM_LEN Then sndBoomPos = -1
            End If
            If sndHitPos >= 0 Then
                sndEfx = sndEfx + sndHit(sndHitPos)
                sndHitPos = sndHitPos + 1
                If sndHitPos >= SND_HIT_LEN Then sndHitPos = -1
            End If
            If sndPupPos >= 0 Then
                sndEfx = sndEfx + sndPup(sndPupPos)
                sndPupPos = sndPupPos + 1
                If sndPupPos >= SND_PUP_LEN Then sndPupPos = -1
            End If
            If sndWhooshPos >= 0 Then
                sndEfx = sndEfx + sndWhoosh(sndWhooshPos)
                sndWhooshPos = sndWhooshPos + 1
                If sndWhooshPos >= SND_WHOOSH_LEN Then sndWhooshPos = -1
            End If

            SPK_Advance
            _SNDRAW ((Sin(sndEnginePhase) + Sin(sndEnginePhase * 2) * 0.4 + Sin(sndEnginePhase * 3) * 0.15) * sndEngineAmp * 0.35 + sndEfx) * volSfx _
                  + musicSample * volMusic + spkSampleOut * volSpeech
        Next sndK
    End If
End Sub


Sub SND_TitleFill()
    Dim sndK As Integer, sndFillCount As Integer, sndTitleEfx As Single
    sndFillCount = Int((AUDIO_BUFFER_TARGET - _SNDRAWLEN) * SAMPLE_RATE)
    If sndFillCount > 0 Then
        For sndK = 0 To sndFillCount - 1
            titleBgmBassCount = titleBgmBassCount - 1
            If titleBgmBassCount <= 0 Then
                titleBgmBassNote  = (titleBgmBassNote + 1) Mod 20
                titleBgmBassCount = titleBgmNoteDur * 4
                titleBgmBassPhase = 0
                titleBgmBassFreq  = titleBgmBass(titleBgmBassNote)
            End If
            titleBgmLeadCount = titleBgmLeadCount - 1
            If titleBgmLeadCount <= 0 Then
                titleBgmLeadNote  = (titleBgmLeadNote + 1) Mod 20
                titleBgmLeadCount = titleBgmNoteDur * 4
                titleBgmLeadPhase = 0
                titleBgmLeadFreq  = titleBgmLead(titleBgmLeadNote)
            End If
            If titleBgmBassCount > titleBgmBassGate Then
                titleBgmBassPhase = titleBgmBassPhase + 6.2832 * titleBgmBassFreq / SAMPLE_RATE
                If titleBgmBassPhase > 6.2832 Then titleBgmBassPhase = titleBgmBassPhase - 6.2832
                musicSample = (Sin(titleBgmBassPhase) + Sin(titleBgmBassPhase * 2) * 0.5 + Sin(titleBgmBassPhase * 3) * 0.25) * 0.07
            Else
                musicSample = 0
            End If
            If titleBgmLeadCount > titleBgmLeadGate Then
                titleBgmLeadPhase = titleBgmLeadPhase + 6.2832 * titleBgmLeadFreq / SAMPLE_RATE
                If titleBgmLeadPhase > 6.2832 Then titleBgmLeadPhase = titleBgmLeadPhase - 6.2832
                musicSample = musicSample + (Sin(titleBgmLeadPhase) + Sin(titleBgmLeadPhase * 2) * 0.3 + Sin(titleBgmLeadPhase * 3) * 0.15) * 0.055
            End If
            ' SFX preview for settings screen (pup sound triggered by OPTS_Update)
            sndTitleEfx = 0.0
            If sndPupPos >= 0 Then
                sndTitleEfx = sndPup(sndPupPos)
                sndPupPos = sndPupPos + 1
                If sndPupPos >= SND_PUP_LEN Then sndPupPos = -1
            End If
            SPK_Advance
            _SNDRAW musicSample * volMusic + sndTitleEfx * volSfx + spkSampleOut * volSpeech
        Next sndK
    End If
End Sub

Sub SND_SetBossMode(onOff As Integer)
    bgmBossMode  = onOff
    bgmBassNote  = 0 : bgmLeadNote  = 0
    bgmBassCount = 0 : bgmLeadCount = 0
    bgmDrumStep = 15 : bgmDrumCount = 1
    If onOff Then
        bgmBassFreq = bgmBossBass(0) : bgmLeadFreq = bgmBossLead(0)
    Else
        bgmBassFreq = bgmNormalBass(0) : bgmLeadFreq = bgmNormalLead(0)
    End If
End Sub

Sub SND_ResetGameBGM()
    bgmBossMode  = 0
    bgmBassNote  = 0 : bgmLeadNote  = 0
    bgmBassCount = 0 : bgmLeadCount = 0
    bgmBassFreq  = bgmNormalBass(0) : bgmLeadFreq = bgmNormalLead(0)
    bgmDrumStep = 15 : bgmDrumCount = 1
    bgmPadAmp   = 0  ' restart pad fade-in
End Sub

Sub SND_Shoot() : sndShootPos  = 0 : End Sub
Sub SND_Boom()  : sndBoomPos   = 0 : End Sub
Sub SND_Hit()   : sndHitPos    = 0 : End Sub
Sub SND_Pup()   : sndPupPos    = 0 : End Sub
Sub SND_Whoosh(): sndWhooshPos = 0 : End Sub
