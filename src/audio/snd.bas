Const AUDIO_BUFFER_TARGET = 0.10
' Sample counts below are the lengths at AUTHOR_RATE (48000 Hz, the rate everything was tuned at);
' SND_Init sets each to that count scaled to the device rate (AUD_N&, src/sys/audiorate.bas).
Dim Shared SND_SHOOT_LEN  As Long
Dim Shared SND_BOOM_LEN   As Long
Dim Shared SND_HIT_LEN    As Long
Dim Shared SND_PUP_LEN    As Long
Dim Shared SND_WHOOSH_LEN As Long
Dim Shared SND_KICK_LEN   As Long  ' 11025 samples: kick drum
Dim Shared SND_SNARE_LEN  As Long  ' 4410 samples: snare
Dim Shared SND_HIHAT_LEN  As Long  ' 2205 samples: hi-hat
Dim Shared SND_TOM_LEN    As Long  ' 19845 samples: floor tom / timpani hit (music)
Dim Shared SND_CRASH_LEN  As Long  ' 30870 samples: crash cymbal (music)
Dim Shared SND_OHAT_LEN   As Long  ' 11025 samples: open hi-hat (music)
Dim Shared SND_DEATH_LEN  As Long  ' 32760 samples: ship-death, three impacts then a deep BOOM
Dim Shared SND_UIMOVE_LEN As Long  ' 1764 samples: dock / menu cursor tick
Dim Shared SND_UIDENY_LEN As Long  ' 5292 samples: "can't do that" double buzz
Dim Shared SND_UITYPE_LEN As Long  ' 1102 samples: callsign typewriter click
Dim Shared SND_UIDEL_LEN  As Long  ' 3087 samples: falling blip, delete and leaving a menu
Dim Shared SND_UICOL_LEN  As Long  ' 4851 samples: callsign color shimmer
Dim Shared SND_UISPIN_LEN As Long  ' 1323 samples: callsign spinner tick
Dim Shared SND_UI_XFADE   As Long  ' 96 samples: a retriggered one-shot fades the old one out over this many

Dim Shared sndEnginePhase As Single
Dim Shared sndEngineFreq  As Single
Dim Shared sndEngineAmp   As Single

ReDim Shared sndShoot(0 To 0) As Single
ReDim Shared sndBoom(0 To 0) As Single
ReDim Shared sndHit(0 To 0) As Single
ReDim Shared sndPup(0 To 0) As Single
ReDim Shared sndWhoosh(0 To 0) As Single  ' small asteroid
ReDim Shared sndWhooshMd(0 To 0) As Single  ' medium asteroid
ReDim Shared sndWhooshLg(0 To 0) As Single  ' large asteroid
Dim Shared sndShootPos As Long : sndShootPos    = -1
Dim Shared sndBoomPos As Long : sndBoomPos     = -1
Dim Shared sndHitPos As Long : sndHitPos      = -1
Dim Shared sndWhooshPos As Long : sndWhooshPos   = -1
Dim Shared sndWhooshMdPos As Long : sndWhooshMdPos = -1
Dim Shared sndWhooshLgPos As Long : sndWhooshLgPos = -1

ReDim Shared sndKick(0 To 0) As Single
ReDim Shared sndSnare(0 To 0) As Single
ReDim Shared sndHihat(0 To 0) As Single
ReDim Shared sndTom(0 To 0) As Single
ReDim Shared sndCrash(0 To 0) As Single
ReDim Shared sndOHat(0 To 0) As Single
ReDim Shared sndDeath(0 To 0) As Single
Dim Shared sndDeathPos As Long : sndDeathPos = -1

' one-shot UI voice (#268): the playing sound, plus the one it replaced fading out, so a
' retrigger never cuts a waveform off mid-cycle (the click). See SND_UiPlay / SND_UiNext!.
ReDim Shared sndUiMove(0 To 0) As Single
ReDim Shared sndUiDeny(0 To 0) As Single
ReDim Shared sndUiType(0 To 0) As Single
ReDim Shared sndUiDel(0 To 0) As Single
ReDim Shared sndUiCol(0 To 0) As Single
ReDim Shared sndUiSpin(0 To 0, 0 To 0) As Single
Dim Shared sndUiCur As Integer, sndUiCurPos As Long : sndUiCurPos = -1
Dim Shared sndUiOld As Integer, sndUiOldPos As Long : sndUiOldPos = -1
Dim Shared sndUiOldGain As Single

Dim Shared sndBlipPhase   As Single
Dim Shared sndBlipFreq    As Single
Dim Shared sndBlipTimer   As Integer : sndBlipTimer = -1
Dim Shared sndBlipLen     As Integer
Dim Shared sndBlipPlosLen As Integer

Sub SND_Init()
    Dim sndK As Long, sndF As Single, sndFade As Single
    Dim sndGenPh As Single, sndGenT As Single
    Dim sndGenNz As Single, sndGenHP As Single, sndGenPX As Single
    Dim sndDLK As Single, sndSpI As Integer
    Dim sndNz As _Unsigned Long, sndGenMt As Single, sndPole As Double

    sndEngineFreq = 80.0 : sndEngineAmp = 0.07

    SND_SHOOT_LEN  = AUD_N&(2205)
    SND_BOOM_LEN   = AUD_N&(11025)
    SND_HIT_LEN    = AUD_N&(8820)
    SND_PUP_LEN    = AUD_N&(4410)
    SND_WHOOSH_LEN = AUD_N&(22050)
    SND_KICK_LEN   = AUD_N&(11025)
    SND_SNARE_LEN  = AUD_N&(4410)
    SND_HIHAT_LEN  = AUD_N&(2205)
    SND_TOM_LEN    = AUD_N&(19845)
    SND_CRASH_LEN  = AUD_N&(30870)
    SND_OHAT_LEN   = AUD_N&(11025)
    SND_DEATH_LEN  = AUD_N&(32760)
    SND_UIMOVE_LEN = AUD_N&(1764)
    SND_UIDENY_LEN = AUD_N&(5292)
    SND_UITYPE_LEN = AUD_N&(1102)
    SND_UIDEL_LEN  = AUD_N&(3087)
    SND_UICOL_LEN  = AUD_N&(4851)
    SND_UISPIN_LEN = AUD_N&(1323)
    SND_UI_XFADE   = AUD_N&(96)
    ReDim sndShoot(0 To SND_SHOOT_LEN - 1) As Single
    ReDim sndBoom(0 To SND_BOOM_LEN - 1) As Single
    ReDim sndHit(0 To SND_HIT_LEN - 1) As Single
    ReDim sndPup(0 To SND_PUP_LEN - 1) As Single
    ReDim sndWhoosh(0 To SND_WHOOSH_LEN - 1) As Single
    ReDim sndWhooshMd(0 To SND_WHOOSH_LEN - 1) As Single
    ReDim sndWhooshLg(0 To SND_WHOOSH_LEN - 1) As Single
    ReDim sndKick(0 To SND_KICK_LEN - 1) As Single
    ReDim sndSnare(0 To SND_SNARE_LEN - 1) As Single
    ReDim sndHihat(0 To SND_HIHAT_LEN - 1) As Single
    ReDim sndTom(0 To SND_TOM_LEN - 1) As Single
    ReDim sndCrash(0 To SND_CRASH_LEN - 1) As Single
    ReDim sndOHat(0 To SND_OHAT_LEN - 1) As Single
    ReDim sndDeath(0 To SND_DEATH_LEN - 1) As Single
    ReDim sndUiMove(0 To SND_UIMOVE_LEN - 1) As Single
    ReDim sndUiDeny(0 To SND_UIDENY_LEN - 1) As Single
    ReDim sndUiType(0 To SND_UITYPE_LEN - 1) As Single
    ReDim sndUiDel(0 To SND_UIDEL_LEN - 1) As Single
    ReDim sndUiCol(0 To SND_UICOL_LEN - 1) As Single
    ReDim sndUiSpin(0 To SND_UI_SPIN_N - 1, 0 To SND_UISPIN_LEN - 1) As Single

    For sndK = 0 To SND_SHOOT_LEN - 1
        sndF    = 880.0 - 440.0 * sndK / SND_SHOOT_LEN
        sndFade = 1.0 - sndK / SND_SHOOT_LEN
        sndShoot(sndK) = Sin(6.2832 * sndF * sndK / audTune) * sndFade * 0.25
    Next sndK
    For sndK = 0 To SND_BOOM_LEN - 1
        sndF    = 300.0 - 260.0 * sndK / SND_BOOM_LEN
        sndFade = (1.0 - sndK / SND_BOOM_LEN) ^ 2
        sndBoom(sndK) = (Sin(6.2832 * sndF * sndK / audTune) * 0.5 + (RNG!(RNG_AUDIO) * 2.0 - 1.0) * 0.3) * sndFade
    Next sndK
    For sndK = 0 To SND_HIT_LEN - 1
        sndFade = (1.0 - sndK / SND_HIT_LEN) ^ 3
        sndHit(sndK) = Sin(6.2832 * 80.0 * sndK / audTune) * sndFade * 0.5
    Next sndK
    For sndK = 0 To SND_PUP_LEN - 1
        sndF    = 440.0 + 440.0 * sndK / SND_PUP_LEN
        sndFade = 1.0 - (sndK / SND_PUP_LEN) ^ 2
        sndPup(sndK) = (Sin(6.2832 * sndF * sndK / audTune) + Sin(6.2832 * sndF * 2.0 * sndK / audTune) * 0.3) * sndFade * 0.25
    Next sndK
    ' UI one-shots (#268): every one starts and ends at exactly 0 (raised-cosine attack and release)
    For sndK = 0 To SND_UIMOVE_LEN - 1
        sndUiMove(sndK) = (Sin(6.2832 * 760.0 * sndK / audTune) + Sin(6.2832 * 1520.0 * sndK / audTune) * 0.25) * SND_UiEnv!(sndK, SND_UIMOVE_LEN, AUD_N&(88), AUD_N&(660)) * 0.22
    Next sndK
    For sndK = 0 To SND_UIDENY_LEN - 1
        If sndK < AUD_N&(2205) Then
            sndF = SND_UiEnv!(sndK, AUD_N&(2205), AUD_N&(88), AUD_N&(660))
        ElseIf sndK >= AUD_N&(3087) Then
            sndF = SND_UiEnv!(sndK - AUD_N&(3087), SND_UIDENY_LEN - AUD_N&(3087), AUD_N&(88), AUD_N&(660))
        Else
            sndF = 0
        End If
        sndUiDeny(sndK) = (Sin(6.2832 * 196.0 * sndK / audTune) + Sin(6.2832 * 392.0 * sndK / audTune) * 0.4) * sndF * 0.22
    Next sndK
    ' callsign typewriter click: inharmonic metal partials over a low thunk, no noise (no hiss)
    For sndK = 0 To SND_UITYPE_LEN - 1
        sndGenT = sndK / audTune
        sndUiType(sndK) = ((Sin(6.2832 * 2150.0 * sndGenT) * 0.5 + Sin(6.2832 * 3430.0 * sndGenT) * 0.35 + Sin(6.2832 * 5170.0 * sndGenT) * 0.25) * Exp(-sndK / (110.0 * audK)) + Sin(6.2832 * 180.0 * sndGenT) * 0.45 * Exp(-sndK / (300.0 * audK))) * SND_UiEnv!(sndK, SND_UITYPE_LEN, AUD_N&(22), AUD_N&(300)) * 0.22
    Next sndK
    ' delete / menu back: 520 -> 240 Hz falling blip
    sndGenPh = 0
    For sndK = 0 To SND_UIDEL_LEN - 1
        sndF = 520.0 * (240.0 / 520.0) ^ (sndK / SND_UIDEL_LEN)
        sndGenPh = sndGenPh + 6.2832 * sndF / audTune
        sndUiDel(sndK) = (Sin(sndGenPh) + Sin(2 * sndGenPh) * 0.25) * SND_UiEnv!(sndK, SND_UIDEL_LEN, AUD_N&(88), AUD_N&(900)) * 0.22
    Next sndK
    ' color shimmer: an E-major triad gliding up 8% under a 30 Hz tremolo
    sndGenPh = 0
    For sndK = 0 To SND_UICOL_LEN - 1
        sndGenPh = sndGenPh + 6.2832 * 1320.0 * (1 + 0.08 * sndK / SND_UICOL_LEN) / audTune
        sndUiCol(sndK) = (Sin(sndGenPh) + Sin(sndGenPh * 1.2583) * 0.6 + Sin(sndGenPh * 1.497) * 0.4) * (0.6 + 0.4 * Sin(6.2832 * 30.0 * sndK / audTune)) * SND_UiEnv!(sndK, SND_UICOL_LEN, AUD_N&(132), AUD_N&(1800)) * 0.12
    Next sndK
    ' spinner ticks: 600 Hz for "A" rising to ~1 kHz at the set's last character
    For sndSpI = 0 To SND_UI_SPIN_N - 1
        sndF = 600.0 * 2 ^ (0.75 * sndSpI / (SND_UI_SPIN_N - 1))
        For sndK = 0 To SND_UISPIN_LEN - 1
            sndUiSpin(sndSpI, sndK) = (Sin(6.2832 * sndF * sndK / audTune) + Sin(6.2832 * 2 * sndF * sndK / audTune) * 0.2) * Exp(-sndK / (350.0 * audK)) * SND_UiEnv!(sndK, SND_UISPIN_LEN, AUD_N&(44), AUD_N&(400)) * 0.24
        Next sndK
    Next sndSpI
    ' the power-up chime gets the same short attack, so it starts from silence even mid-mix
    For sndK = 0 To AUD_N&(88) - 1
        sndPup(sndK) = sndPup(sndK) * SND_UiEnv!(sndK, SND_PUP_LEN, AUD_N&(88), AUD_N&(88))
    Next sndK
    sndPup(SND_PUP_LEN - 1) = 0

    ' small asteroid: bright, sharp Doppler drop 400→160 Hz
    For sndK = 0 To SND_WHOOSH_LEN - 1
        sndGenT = sndK / SND_WHOOSH_LEN
        If sndGenT < 0.30 Then
            sndFade = sndGenT / 0.30
        Else
            sndGenPX = (sndGenT - 0.30) / 0.70
            If sndGenPX < 0.0 Then sndGenPX = 0.0
            sndFade = Exp(-sndGenPX * 3.5)
        End If
        sndF = 400.0 - 240.0 * sndGenT
        sndWhoosh(sndK) = (Sin(6.2832 * sndF * sndK / audTune) * 0.18 + (RNG!(RNG_AUDIO) * 2.0 - 1.0) * 0.82) * sndFade * 0.42
    Next sndK
    ' medium asteroid: fuller mid-range Doppler drop 220→80 Hz
    For sndK = 0 To SND_WHOOSH_LEN - 1
        sndGenT = sndK / SND_WHOOSH_LEN
        If sndGenT < 0.30 Then
            sndFade = sndGenT / 0.30
        Else
            sndGenPX = (sndGenT - 0.30) / 0.70
            If sndGenPX < 0.0 Then sndGenPX = 0.0
            sndFade = Exp(-sndGenPX * 3.5)
        End If
        sndF = 220.0 - 140.0 * sndGenT
        sndWhooshMd(sndK) = (Sin(6.2832 * sndF * sndK / audTune) * 0.18 + (RNG!(RNG_AUDIO) * 2.0 - 1.0) * 0.82) * sndFade * 0.44
    Next sndK
    ' large asteroid: deep bass Doppler drop 110→35 Hz, slower decay, more sustain
    For sndK = 0 To SND_WHOOSH_LEN - 1
        sndGenT = sndK / SND_WHOOSH_LEN
        If sndGenT < 0.35 Then
            sndFade = sndGenT / 0.35
        Else
            sndGenPX = (sndGenT - 0.35) / 0.65
            If sndGenPX < 0.0 Then sndGenPX = 0.0
            sndFade = Exp(-sndGenPX * 2.5)
        End If
        sndF = 110.0 - 75.0 * sndGenT
        sndWhooshLg(sndK) = (Sin(6.2832 * sndF * sndK / audTune) * 0.25 + (RNG!(RNG_AUDIO) * 2.0 - 1.0) * 0.75) * sndFade * 0.50
    Next sndK

    ' kick drum: exponential frequency sweep 160->45 Hz over 250ms
    sndGenPh = 0
    For sndK = 0 To SND_KICK_LEN - 1
        sndGenT = sndK / SND_KICK_LEN
        sndF    = 160.0 * Exp(-sndGenT * 14.0) + 45.0
        sndFade = Exp(-sndGenT * 6.0)
        sndGenPh = sndGenPh + 6.2832 * sndF / audTune
        If sndGenPh > 6.2832 Then sndGenPh = sndGenPh - 6.2832
        sndKick(sndK) = Sin(sndGenPh) * sndFade * 0.30
    Next sndK

    ' snare: filtered noise + 180 Hz body, 100ms
    sndGenHP = 0 : sndGenPX = 0 : sndGenPh = 0 : sndPole = AUD_Decay#(0.65#)
    For sndK = 0 To SND_SNARE_LEN - 1
        sndGenT  = sndK / SND_SNARE_LEN
        sndFade  = (1.0 - sndGenT) ^ 2
        sndGenNz = RNG!(RNG_AUDIO) * 2.0 - 1.0
        sndGenHP = sndGenNz - sndGenPX + sndPole * sndGenHP
        sndGenPX = sndGenNz
        sndGenPh = sndGenPh + 6.2832 * 180.0 / audTune
        If sndGenPh > 6.2832 Then sndGenPh = sndGenPh - 6.2832
        sndSnare(sndK) = (sndGenHP * 0.60 + Sin(sndGenPh) * 0.40) * sndFade * 0.18
    Next sndK

    ' hi-hat: bright high-passed noise, 50ms
    sndGenHP = 0 : sndGenPX = 0 : sndPole = AUD_Decay#(0.85#)
    For sndK = 0 To SND_HIHAT_LEN - 1
        sndGenT  = sndK / SND_HIHAT_LEN
        sndFade  = (1.0 - sndGenT) ^ 3
        sndGenNz = RNG!(RNG_AUDIO) * 2.0 - 1.0
        sndGenHP = sndGenNz - sndGenPX + sndPole * sndGenHP
        sndGenPX = sndGenNz
        sndHihat(sndK) = sndGenHP * sndFade * 0.055
    Next sndK

    ' music-only drums (#207). Their noise comes from a local xorshift, not RNG_AUDIO, so adding
    ' them doesn't move the speech and blip randomness. Each starts and ends at exactly 0.
    sndNz = 2463534242
    ' floor tom / timpani: 110 -> 75 Hz drop, a fading 1.6x overtone, a 4 ms mallet thump
    sndGenPh = 0 : sndGenMt = 0
    For sndK = 0 To SND_TOM_LEN - 1
        sndGenT = sndK / SND_TOM_LEN
        sndF = 75.0 + 35.0 * Exp(-sndGenT * 9.0)
        sndGenPh = sndGenPh + 6.2832 * sndF / audTune
        If sndGenPh > 6.2832 Then sndGenPh = sndGenPh - 6.2832
        sndGenMt = sndGenMt + 6.2832 * sndF * 1.6 / audTune
        If sndGenMt > 6.2832 Then sndGenMt = sndGenMt - 6.2832
        sndNz = RNG_Step~&(sndNz)
        sndGenNz = sndNz / 4294967296# * 2 - 1
        sndTom(sndK) = (Sin(sndGenPh) + Sin(sndGenMt) * 0.3 * Exp(-sndGenT * 12.0) + sndGenNz * 0.4 * Exp(-sndK / (180.0 * audK))) * Exp(-sndGenT * 5.0) * SND_UiEnv!(sndK, SND_TOM_LEN, AUD_N&(22), AUD_N&(2000)) * 0.32
    Next sndK
    ' crash: high-passed noise over inharmonic metal partials, long decay
    sndGenHP = 0 : sndGenPX = 0 : sndPole = AUD_Decay#(0.80#)
    For sndK = 0 To SND_CRASH_LEN - 1
        sndGenT = sndK / SND_CRASH_LEN
        sndDLK = sndK / audTune
        sndNz = RNG_Step~&(sndNz)
        sndGenNz = sndNz / 4294967296# * 2 - 1
        sndGenHP = sndGenNz - sndGenPX + sndPole * sndGenHP
        sndGenPX = sndGenNz
        sndF = Sin(6.2832 * 3150.0 * sndDLK) * 0.3 + Sin(6.2832 * 4370.0 * sndDLK) * 0.25 + Sin(6.2832 * 5990.0 * sndDLK) * 0.2
        sndCrash(sndK) = (sndGenHP * 0.8 + sndF * Exp(-sndGenT * 3.0)) * Exp(-sndGenT * 4.0) * SND_UiEnv!(sndK, SND_CRASH_LEN, AUD_N&(44), AUD_N&(4000)) * 0.075
    Next sndK
    ' open hi-hat: the closed hat's noise, ringing 250 ms
    sndGenHP = 0 : sndGenPX = 0 : sndPole = AUD_Decay#(0.85#)
    For sndK = 0 To SND_OHAT_LEN - 1
        sndGenT = sndK / SND_OHAT_LEN
        sndNz = RNG_Step~&(sndNz)
        sndGenNz = sndNz / 4294967296# * 2 - 1
        sndGenHP = sndGenNz - sndGenPX + sndPole * sndGenHP
        sndGenPX = sndGenNz
        sndOHat(sndK) = sndGenHP * Exp(-sndGenT * 4.0) * SND_UiEnv!(sndK, SND_OHAT_LEN, AUD_N&(22), AUD_N&(1500)) * 0.045
    Next sndK

    ' death: ka-ka-ka-BOOOM (742ms total = Integer ceiling)
    ' Ka hits pack into first 408ms; BOOM owns 250ms→742ms = 492ms of rumble.
    ' BOOM Exp(-0.7) holds 70% at midpoint, fades with tail to prevent end-click.
    For sndK = 0 To SND_DEATH_LEN - 1
        sndGenT = sndK / SND_DEATH_LEN
        sndDeath(sndK) = 0

        ' ka 1: t=0.000→0.160 (0-119ms), localT 0→5241 samples
        sndGenPX = sndGenT / 0.160
        If sndGenPX >= 0 And sndGenPX < 1 Then
            sndDLK  = sndGenPX * (5241.0 * audK)
            sndF    = 350.0 - 270.0 * sndGenPX
            sndFade = (1.0 - sndGenPX) ^ 0.5
            If sndGenPX < 0.04 Then sndFade = sndFade * (sndGenPX / 0.04)
            sndGenNz = sndGenPX / 0.10 : If sndGenNz > 1.0 Then sndGenNz = 1.0
            sndDeath(sndK) = (Sin(6.2832 * sndF * sndDLK / audTune) * (0.30 + 0.45 * sndGenNz) + (RNG!(RNG_AUDIO) * 2.0 - 1.0) * (0.70 - 0.45 * sndGenNz)) * sndFade * 0.70
        End If

        ' ka 2: t=0.195→0.355 (145-264ms), localT 0→5241 samples
        sndGenPX = (sndGenT - 0.195) / 0.160
        If sndGenPX >= 0 And sndGenPX < 1 Then
            sndDLK  = sndGenPX * (5241.0 * audK)
            sndF    = 350.0 - 270.0 * sndGenPX
            sndFade = (1.0 - sndGenPX) ^ 0.5
            If sndGenPX < 0.04 Then sndFade = sndFade * (sndGenPX / 0.04)
            sndGenNz = sndGenPX / 0.10 : If sndGenNz > 1.0 Then sndGenNz = 1.0
            sndDeath(sndK) = sndDeath(sndK) + (Sin(6.2832 * sndF * sndDLK / audTune) * (0.30 + 0.45 * sndGenNz) + (RNG!(RNG_AUDIO) * 2.0 - 1.0) * (0.70 - 0.45 * sndGenNz)) * sndFade * 0.85
        End If

        ' ka 3: t=0.390→0.550 (290-408ms), localT 0→5241 samples
        sndGenPX = (sndGenT - 0.390) / 0.160
        If sndGenPX >= 0 And sndGenPX < 1 Then
            sndDLK  = sndGenPX * (5241.0 * audK)
            sndF    = 350.0 - 270.0 * sndGenPX
            sndFade = (1.0 - sndGenPX) ^ 0.5
            If sndGenPX < 0.04 Then sndFade = sndFade * (sndGenPX / 0.04)
            sndGenNz = sndGenPX / 0.10 : If sndGenNz > 1.0 Then sndGenNz = 1.0
            sndDeath(sndK) = sndDeath(sndK) + (Sin(6.2832 * sndF * sndDLK / audTune) * (0.30 + 0.45 * sndGenNz) + (RNG!(RNG_AUDIO) * 2.0 - 1.0) * (0.70 - 0.45 * sndGenNz)) * sndFade * 1.00
        End If

        ' BOOM: t=0.337→1.0 (250-742ms = 492ms), localT 0→21634 samples; 180→40 Hz
        ' Starts before ka3 so the third hit punches into an already-rising boom.
        ' Exp(-0.7) holds 70% at midpoint; tail fadeout last 10% prevents end-click.
        sndGenPX = (sndGenT - 0.337) / 0.663
        If sndGenPX >= 0 Then
            sndDLK  = sndGenPX * (21634.0 * audK)
            sndF    = 180.0 - 140.0 * sndGenPX
            sndFade = Exp(-sndGenPX * 0.7)
            If sndGenPX < 0.02 Then sndFade = sndFade * (sndGenPX / 0.02)
            If sndGenPX > 0.90 Then sndFade = sndFade * (1.0 - sndGenPX) / 0.10
            sndDeath(sndK) = sndDeath(sndK) + ((RNG!(RNG_AUDIO) * 2.0 - 1.0) * 0.65 + Sin(6.2832 * sndF * sndDLK / audTune) * 0.35) * sndFade * 1.0
        End If

        If sndDeath(sndK) >  1.0 Then sndDeath(sndK) =  1.0
        If sndDeath(sndK) < -1.0 Then sndDeath(sndK) = -1.0
    Next sndK

    MUS_Load
End Sub

Sub SND_GameFill(isManeuver As Integer)
    If isManeuver Then
        sndEngineFreq = sndEngineFreq + (150.0 - sndEngineFreq) * 0.07
        sndEngineAmp  = sndEngineAmp  + (0.20  - sndEngineAmp)  * 0.07
    Else
        sndEngineFreq = sndEngineFreq + (75.0  - sndEngineFreq) * 0.04
        sndEngineAmp  = sndEngineAmp  + (0.07  - sndEngineAmp)  * 0.04
    End If
    MUS_Fill 1
End Sub

Sub SND_Shoot() : sndShootPos  = 0 : End Sub
Sub SND_Boom()  : sndBoomPos   = 0 : End Sub
Sub SND_Hit()   : sndHitPos    = 0 : End Sub
Sub SND_Pup()   : SND_UiPlay SND_UI_PUP : End Sub
Sub SND_UiMove() : SND_UiPlay SND_UI_MOVE : End Sub
Sub SND_UiDeny() : SND_UiPlay SND_UI_DENY : End Sub
Sub SND_Whoosh(wscl As Single)
    If wscl > 2.5 Then
        sndWhooshLgPos = 0
    ElseIf wscl > 1.5 Then
        sndWhooshMdPos = 0
    Else
        sndWhooshPos = 0
    End If
End Sub
Sub SND_Death()
    sndBoomPos  = -1   ' suppress generic boom so death BOOM dominates
    sndHitPos   = -1
    sndDeathPos = 0
End Sub
Sub SND_Blip(blipFreq As Single)
    sndBlipFreq    = blipFreq
    sndBlipPhase   = 0
    sndBlipLen     = AUD_N&(1323) + INT(RNG!(RNG_AUDIO) * AUD_N&(2205))  ' 30-80ms
    sndBlipPlosLen = 0
    IF RNG!(RNG_AUDIO) > 0.45 THEN sndBlipPlosLen = AUD_N&(441) + INT(RNG!(RNG_AUDIO) * AUD_N&(441))  ' ~55% chance of 10–20ms noise burst
    sndBlipTimer   = sndBlipLen
End Sub

' Raised-cosine envelope at sample ueK of a ueLen-sample sound: 0 -> 1 over ueAtk samples,
' 1 -> exactly 0 at the last sample over ueRel samples.
Function SND_UiEnv! (ueK As Long, ueLen As Long, ueAtk As Long, ueRel As Long)
    Dim ueE As Single
    ueE = 1
    If ueK < ueAtk Then ueE = 0.5 - 0.5 * Cos(3.14159265 * ueK / ueAtk)
    If ueK > ueLen - 1 - ueRel Then ueE = ueE * (0.5 - 0.5 * Cos(3.14159265 * (ueLen - 1 - ueK) / ueRel))
    If ueK >= ueLen - 1 Or ueK <= 0 Then ueE = 0
    SND_UiEnv! = ueE
End Function

Function SND_UiLen& (ulId As Integer)
    Select Case ulId
        Case SND_UI_MOVE : SND_UiLen& = SND_UIMOVE_LEN
        Case SND_UI_DENY : SND_UiLen& = SND_UIDENY_LEN
        Case SND_UI_PUP  : SND_UiLen& = SND_PUP_LEN
        Case SND_UI_TYPE  : SND_UiLen& = SND_UITYPE_LEN
        Case SND_UI_DEL   : SND_UiLen& = SND_UIDEL_LEN
        Case SND_UI_COLOR : SND_UiLen& = SND_UICOL_LEN
        Case SND_UI_SPIN To SND_UI_SPIN + SND_UI_SPIN_N - 1 : SND_UiLen& = SND_UISPIN_LEN
        Case Else        : SND_UiLen& = 0
    End Select
End Function

Function SND_UiSample! (usId As Integer, usPos As Long)
    Select Case usId
        Case SND_UI_MOVE : SND_UiSample! = sndUiMove(usPos)
        Case SND_UI_DENY : SND_UiSample! = sndUiDeny(usPos)
        Case SND_UI_PUP  : SND_UiSample! = sndPup(usPos)
        Case SND_UI_TYPE  : SND_UiSample! = sndUiType(usPos)
        Case SND_UI_DEL   : SND_UiSample! = sndUiDel(usPos)
        Case SND_UI_COLOR : SND_UiSample! = sndUiCol(usPos)
        Case SND_UI_SPIN To SND_UI_SPIN + SND_UI_SPIN_N - 1 : SND_UiSample! = sndUiSpin(usId - SND_UI_SPIN, usPos)
        Case Else        : SND_UiSample! = 0
    End Select
End Function

' Start a UI one-shot. One still playing isn't cut: it fades out over SND_UI_XFADE samples.
Sub SND_UiPlay (upId As Integer)
    If sndUiCurPos >= 0 Then
        sndUiOld = sndUiCur : sndUiOldPos = sndUiCurPos : sndUiOldGain = 1
    End If
    sndUiCur = upId : sndUiCurPos = 0
End Sub

' The UI voice's next output sample (the mixer calls it once per sample; tests step it).
Function SND_UiNext!
    Dim unS As Single
    If sndUiCurPos >= 0 Then
        unS = SND_UiSample!(sndUiCur, sndUiCurPos)
        sndUiCurPos = sndUiCurPos + 1
        If sndUiCurPos >= SND_UiLen&(sndUiCur) Then sndUiCurPos = -1
    End If
    If sndUiOldPos >= 0 Then
        sndUiOldGain = sndUiOldGain - 1 / SND_UI_XFADE
        If sndUiOldGain > 0 Then unS = unS + SND_UiSample!(sndUiOld, sndUiOldPos) * sndUiOldGain
        sndUiOldPos = sndUiOldPos + 1
        If sndUiOldGain <= 0 Or sndUiOldPos >= SND_UiLen&(sndUiOld) Then sndUiOldPos = -1
    End If
    SND_UiNext! = unS
End Function

' Engine hum: one output sample's phase step (the mixer calls it once per sample while SFX are on).
Sub SND_EngineStep
    sndEnginePhase = sndEnginePhase + 6.2832 * sndEngineFreq / audTune
    If sndEnginePhase > 6.2832 Then sndEnginePhase = sndEnginePhase - 6.2832
End Sub

' The narration blip's next output sample (0 once it has finished); the mixer calls it once per sample.
Function SND_BlipNext!
    Dim blpPos As Long, blpEnv As Single, blpOut As Single
    blpOut = 0
    If sndBlipTimer > 0 Then
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
            blpOut = (RNG!(RNG_AUDIO) * 2.0 - 1.0) * blpEnv * 0.22
        Else
            sndBlipPhase = sndBlipPhase + 6.2832 * sndBlipFreq / audTune
            If sndBlipPhase > 6.2832 Then sndBlipPhase = sndBlipPhase - 6.2832
            blpOut = (Sin(sndBlipPhase) + Sin(sndBlipPhase * 2.0) * 0.35) * blpEnv * 0.26
        End If
        sndBlipTimer = sndBlipTimer - 1
    End If
    SND_BlipNext! = blpOut
End Function
