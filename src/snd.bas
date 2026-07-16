Const AUDIO_BUFFER_TARGET = 0.10
Const SND_SHOOT_LEN  = 2205
Const SND_BOOM_LEN   = 11025
Const SND_HIT_LEN    = 8820
Const SND_PUP_LEN    = 4410
Const SND_WHOOSH_LEN = 22050
Const SND_KICK_LEN   = 11025  ' 250ms kick drum
Const SND_SNARE_LEN  = 4410   ' 100ms snare
Const SND_HIHAT_LEN  = 2205   ' 50ms hi-hat
Const SND_DEATH_LEN  = 26460  ' 600ms ship-death: three impacts then a deep BOOM

Dim Shared sndEnginePhase As Single
Dim Shared sndEngineFreq  As Single
Dim Shared sndEngineAmp   As Single

Dim Shared sndShoot(0 To SND_SHOOT_LEN - 1)  As Single
Dim Shared sndBoom(0 To SND_BOOM_LEN - 1)    As Single
Dim Shared sndHit(0 To SND_HIT_LEN - 1)      As Single
Dim Shared sndPup(0 To SND_PUP_LEN - 1)      As Single
Dim Shared sndWhoosh(0 To SND_WHOOSH_LEN - 1)   As Single  ' small asteroid
Dim Shared sndWhooshMd(0 To SND_WHOOSH_LEN - 1) As Single  ' medium asteroid
Dim Shared sndWhooshLg(0 To SND_WHOOSH_LEN - 1) As Single  ' large asteroid
Dim Shared sndShootPos    As Integer : sndShootPos    = -1
Dim Shared sndBoomPos     As Integer : sndBoomPos     = -1
Dim Shared sndHitPos      As Integer : sndHitPos      = -1
Dim Shared sndPupPos      As Integer : sndPupPos      = -1
Dim Shared sndWhooshPos   As Integer : sndWhooshPos   = -1
Dim Shared sndWhooshMdPos As Integer : sndWhooshMdPos = -1
Dim Shared sndWhooshLgPos As Integer : sndWhooshLgPos = -1

Dim Shared sndKick(0 To SND_KICK_LEN - 1)   As Single
Dim Shared sndSnare(0 To SND_SNARE_LEN - 1) As Single
Dim Shared sndHihat(0 To SND_HIHAT_LEN - 1) As Single
Dim Shared sndDeath(0 To SND_DEATH_LEN - 1) As Single
Dim Shared sndDeathPos As Integer : sndDeathPos = -1

Dim Shared sndKickPos  As Integer : sndKickPos  = -1
Dim Shared sndSnarePos As Integer : sndSnarePos = -1
Dim Shared sndHihatPos As Integer : sndHihatPos = -1

Dim Shared sndBlipPhase   As Single
Dim Shared sndBlipFreq    As Single
Dim Shared sndBlipTimer   As Integer : sndBlipTimer = -1
Dim Shared sndBlipLen     As Integer
Dim Shared sndBlipPlosLen As Integer

Sub SND_Init()
    Dim sndK As Long, sndF As Single, sndFade As Single
    Dim sndGenPh As Single, sndGenT As Single
    Dim sndGenNz As Single, sndGenHP As Single, sndGenPX As Single
    Dim sndDLK As Single

    sndEngineFreq = 80.0 : sndEngineAmp = 0.07

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
        sndWhoosh(sndK) = (Sin(6.2832 * sndF * sndK / SAMPLE_RATE) * 0.18 + (Rnd * 2.0 - 1.0) * 0.82) * sndFade * 0.42
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
        sndWhooshMd(sndK) = (Sin(6.2832 * sndF * sndK / SAMPLE_RATE) * 0.18 + (Rnd * 2.0 - 1.0) * 0.82) * sndFade * 0.44
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
        sndWhooshLg(sndK) = (Sin(6.2832 * sndF * sndK / SAMPLE_RATE) * 0.25 + (Rnd * 2.0 - 1.0) * 0.75) * sndFade * 0.50
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
        sndGenT  = sndK / SND_SNARE_LEN
        sndFade  = (1.0 - sndGenT) ^ 2
        sndGenNz = Rnd * 2.0 - 1.0
        sndGenHP = sndGenNz - sndGenPX + 0.65 * sndGenHP
        sndGenPX = sndGenNz
        sndGenPh = sndGenPh + 6.2832 * 180.0 / SAMPLE_RATE
        If sndGenPh > 6.2832 Then sndGenPh = sndGenPh - 6.2832
        sndSnare(sndK) = (sndGenHP * 0.60 + Sin(sndGenPh) * 0.40) * sndFade * 0.18
    Next sndK

    ' hi-hat: bright high-passed noise, 50ms
    sndGenHP = 0 : sndGenPX = 0
    For sndK = 0 To SND_HIHAT_LEN - 1
        sndGenT  = sndK / SND_HIHAT_LEN
        sndFade  = (1.0 - sndGenT) ^ 3
        sndGenNz = Rnd * 2.0 - 1.0
        sndGenHP = sndGenNz - sndGenPX + 0.85 * sndGenHP
        sndGenPX = sndGenNz
        sndHihat(sndK) = sndGenHP * sndFade * 0.055
    Next sndK

    ' death: ka-ka-ka-BOOOM
    ' Each component uses sin(freq * localT / SAMPLE_RATE) where localT resets to 0 at
    ' each onset — so sin(0)=0 at every attack, eliminating discontinuity clicks.
    ' Same technique as SND_Boom. Impacts: 350→80 Hz; BOOM: 180→40 Hz.
    For sndK = 0 To SND_DEATH_LEN - 1
        sndGenT = sndK / SND_DEATH_LEN
        sndDeath(sndK) = 0

        ' ka 1: t=0.000→0.133 (0-80ms), localT 0→3519 samples
        sndGenPX = sndGenT / 0.133
        If sndGenPX >= 0 And sndGenPX < 1 Then
            sndDLK  = sndGenPX * 3519.0
            sndF    = 350.0 - 270.0 * sndGenPX
            sndFade = (1.0 - sndGenPX) ^ 2
            If sndGenPX < 0.05 Then sndFade = sndFade * (sndGenPX / 0.05)
            sndDeath(sndK) = (Sin(6.2832 * sndF * sndDLK / SAMPLE_RATE) * 0.55 + (Rnd * 2.0 - 1.0) * 0.45) * sndFade * 0.70
        End If

        ' ka 2: t=0.250→0.383 (150-230ms), localT 0→3519 samples
        sndGenPX = (sndGenT - 0.250) / 0.133
        If sndGenPX >= 0 And sndGenPX < 1 Then
            sndDLK  = sndGenPX * 3519.0
            sndF    = 350.0 - 270.0 * sndGenPX
            sndFade = (1.0 - sndGenPX) ^ 2
            If sndGenPX < 0.05 Then sndFade = sndFade * (sndGenPX / 0.05)
            sndDeath(sndK) = sndDeath(sndK) + (Sin(6.2832 * sndF * sndDLK / SAMPLE_RATE) * 0.55 + (Rnd * 2.0 - 1.0) * 0.45) * sndFade * 0.85
        End If

        ' ka 3: t=0.500→0.633 (300-380ms), localT 0→3519 samples
        sndGenPX = (sndGenT - 0.500) / 0.133
        If sndGenPX >= 0 And sndGenPX < 1 Then
            sndDLK  = sndGenPX * 3519.0
            sndF    = 350.0 - 270.0 * sndGenPX
            sndFade = (1.0 - sndGenPX) ^ 2
            If sndGenPX < 0.05 Then sndFade = sndFade * (sndGenPX / 0.05)
            sndDeath(sndK) = sndDeath(sndK) + (Sin(6.2832 * sndF * sndDLK / SAMPLE_RATE) * 0.55 + (Rnd * 2.0 - 1.0) * 0.45) * sndFade * 1.00
        End If

        ' BOOM: t=0.583→1.0 (350-600ms = 250ms), localT 0→11025 samples; 180→40 Hz
        sndGenPX = (sndGenT - 0.583) / 0.417
        If sndGenPX >= 0 Then
            sndDLK  = sndGenPX * 11025.0
            sndF    = 180.0 - 140.0 * sndGenPX
            sndFade = (1.0 - sndGenPX) ^ 1.5
            If sndGenPX < 0.03 Then sndFade = sndFade * (sndGenPX / 0.03)
            sndDeath(sndK) = sndDeath(sndK) + ((Rnd * 2.0 - 1.0) * 0.65 + Sin(6.2832 * sndF * sndDLK / SAMPLE_RATE) * 0.35) * sndFade * 1.0
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
Sub SND_Pup()   : sndPupPos    = 0 : End Sub
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
    sndBlipLen     = 1323 + INT(RND * 2205)  ' 30–80ms
    sndBlipPlosLen = 0
    IF RND > 0.45 THEN sndBlipPlosLen = 441 + INT(RND * 441)  ' ~55% chance of 10–20ms noise burst
    sndBlipTimer   = sndBlipLen
End Sub
