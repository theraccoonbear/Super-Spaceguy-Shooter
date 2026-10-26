' rng.bas -- seeded random-number streams. Every random number the game draws comes from
' one of these, never Rnd, so a --seed run (and a scripted replay) repeats exactly. The
' streams are separate so that a cosmetic change (another particle, a starfield tweak)
' or the audio device's timing can't shift what gameplay draws:
'
'   RNG_GAME    waves, enemies, boss behaviour and attack picks
'   RNG_FX      particles, screen shake, VCR effect, starfield
'   RNG_AUDIO   sound tables, speech, blips
'   RNG_UNIQUE  telemetry session ids, auto pilot names: always clock-seeded, even with
'               --seed, so two seeded runs never share an id
'
'   RNG_Seed master     seed GAME/FX/AUDIO from master (UNIQUE from the clock)
'   x = RNG!(stream)    next value in [0, 1), like Rnd
'
' A stream that was never seeded starts from a fixed default, so a test that includes a
' module without calling RNG_Seed is repeatable too. Include before anything that uses it.
' Types: ~& is QB64's _UNSIGNED LONG (32-bit) suffix, ~&& its _UNSIGNED _INTEGER64.
' Local variable prefix: rng*

Const RNG_GAME   = 1
Const RNG_FX     = 2
Const RNG_AUDIO  = 3
Const RNG_UNIQUE = 4
Const RNG_COUNT  = 4

Dim Shared rngState(1 To RNG_COUNT) As _Unsigned Long

' One xorshift32 step (Marsaglia 13/17/5).
Function RNG_Step~&(rngV As _Unsigned Long)
    Dim rngW As _Unsigned Long
    rngW = rngV
    rngW = rngW Xor _SHL(rngW, 13)
    rngW = rngW Xor _SHR(rngW, 17)
    rngW = rngW Xor _SHL(rngW, 5)
    RNG_Step~& = rngW
End Function

' Starting state for stream rngS from seed rngM: offset by the golden-ratio constant so
' streams start apart, never 0 (xorshift's dead state), then stirred so that nearby
' seeds diverge at once.
Function RNG_StreamState~&(rngM As _Unsigned Long, rngS As Integer)
    Dim rngX As _Unsigned _Integer64, rngV As _Unsigned Long, rngI As Integer
    rngX = (rngM + rngS * 2654435769~&&) And 4294967295~&&
    rngV = rngX
    If rngV = 0 Then rngV = 2463534242~&
    For rngI = 1 To 8
        rngV = RNG_Step~&(rngV)
    Next rngI
    RNG_StreamState~& = rngV
End Function

' A seed from the clock and date, for unseeded runs and RNG_UNIQUE.
Function RNG_ClockSeed~&
    Dim rngD As _Unsigned _Integer64
    rngD = Val(Right$(Date$, 4)) * 372 + Val(Left$(Date$, 2)) * 31 + Val(Mid$(Date$, 4, 2))
    RNG_ClockSeed~& = (rngD * 86400000 + CLng(Timer * 1000)) And 4294967295~&&
End Function

Sub RNG_Seed(rngSeed As _Unsigned Long)
    Dim rngK As Integer
    For rngK = RNG_GAME To RNG_AUDIO
        rngState(rngK) = RNG_StreamState~&(rngSeed, rngK)
    Next rngK
    rngState(RNG_UNIQUE) = RNG_StreamState~&(RNG_ClockSeed~&, RNG_UNIQUE)
End Sub

' Next value of stream rngStream in [0, 1). The top 24 bits only, so the Single result
' is exact and never rounds up to 1 (Int(RNG!(s) * n) is always 0..n-1).
Function RNG!(rngStream As Integer)
    Dim rngV As _Unsigned Long
    rngV = rngState(rngStream)
    If rngV = 0 Then rngV = RNG_StreamState~&(0, rngStream)
    rngV = RNG_Step~&(rngV)
    rngState(rngStream) = rngV
    RNG! = _SHR(rngV, 8) / 16777216
End Function
