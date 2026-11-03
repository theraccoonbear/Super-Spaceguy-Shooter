' audiorate.bas -- the rate the game synthesizes audio at (#400).
'
' All audio is synthesized at runtime and handed to _SNDRAW, which plays at the sound device's rate
' (_SNDRATE). The values in snd.bas, music.bas and speech.bas were written against 44100 Hz but heard
' and tuned by ear on a 48000 Hz device, so 48000 Hz playback of that stream is the reference sound.
' AUTHOR_RATE anchors it: at SAMPLE_RATE = AUTHOR_RATE every expression below reduces to the value
' the code used before the device rate was followed, and the sample stream is bit-identical.
'
'   SAMPLE_RATE  the device rate; the synthesis rate. AUD_SetRate sets it, once, before SND_Init.
'   audK         SAMPLE_RATE / AUTHOR_RATE (exactly 1.0 at the reference rate).
'   audTune      44100 * audK: the divisor for phase steps, time constants and the like, written
'                against 44100 Hz. Per-sample counts at the reference rate are the literals of the
'                code; AUD_N& scales those.
'
' Includes before snd.bas, music.bas, speech.bas and bosshp.bas.

Const AUTHOR_RATE = 48000

Dim Shared SAMPLE_RATE As Long : SAMPLE_RATE = AUTHOR_RATE
Dim Shared audK As Single      : audK = 1
Dim Shared audTune As Single   : audTune = 44100

' Set the synthesis rate; a rate outside what a sound device reports (or 0, no device) keeps the reference.
Sub AUD_SetRate (srRate As Long)
    If srRate < 8000 Or srRate > 192000 Then srRate = AUTHOR_RATE
    SAMPLE_RATE = srRate
    audK = CSng(srRate / AUTHOR_RATE)
    audTune = CSng(44100# * srRate / AUTHOR_RATE)
End Sub

' A count of samples at AUTHOR_RATE, at the synthesis rate (identical at AUTHOR_RATE).
Function AUD_N& (anCount As Long)
    AUD_N& = CLng(anCount * audK)
End Function

' A per-sample decay factor (the old value is multiplied by it every sample) written at
' AUTHOR_RATE, at the synthesis rate: the same decay per second.
Function AUD_Decay# (adF As Double)
    If audK = 1 Then AUD_Decay# = adF Else AUD_Decay# = adF ^ (AUTHOR_RATE / CDbl(SAMPLE_RATE))
End Function

' A per-sample smoothing coefficient (value = value + (target - value) * c) written at
' AUTHOR_RATE, at the synthesis rate: the same approach per second.
Function AUD_Smooth! (smC As Single)
    If audK = 1 Then AUD_Smooth! = smC Else AUD_Smooth! = CSng(1# - (1# - smC) ^ (AUTHOR_RATE / CDbl(SAMPLE_RATE)))
End Function

' Output samples in one 60 fps game frame of game time. Sample-derived game timing (speech clock,
' crawl paragraph length, boss shield length) counts in units of 44100 / 60 = 735 samples a frame at
' the reference rate, as it did before the device rate was followed, so what is on screen does not move.
Function AUD_FrameSamples&
    AUD_FrameSamples& = CLng(audTune) \ 60
End Function
