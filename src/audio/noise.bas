' noise.bas -- AUD_Noise!: 0..1 noise for every sound generated while the game runs
' (speech, blips, plosives), from a private xorshift instead of Rnd. How many samples
' get made depends on the audio device's timing, so drawing them from the shared Rnd
' stream would shift gameplay's random numbers and make --seed runs unrepeatable.
' Include before any audio file that uses it.

Dim Shared audNoiseState As _Unsigned Long  ' xorshift state (0 = unseeded)

Function AUD_Noise!
    If audNoiseState = 0 Then audNoiseState = 2463534242
    audNoiseState = audNoiseState Xor _SHL(audNoiseState, 13)
    audNoiseState = audNoiseState Xor _SHR(audNoiseState, 17)
    audNoiseState = audNoiseState Xor _SHL(audNoiseState, 5)
    AUD_Noise! = audNoiseState / 4294967295#
End Function
