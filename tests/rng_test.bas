' rng_test.bas — seeded random streams (src/sys/rng.bas)
'
' Drives the real module: a seed replays the same sequence, different seeds and
' different streams give different sequences, drawing from one stream never moves
' another, an unseeded stream starts from a fixed default, values stay in [0, 1) (never
' 1, so Int(RNG!(s) * n) is always 0..n-1), and RNG_UNIQUE ignores the master seed.
'
' Build: ./tools/buildqb tests/rng_test.bas
' Run:   ./tests/rng_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

'$INCLUDE:'../src/sys/rng.bas'

Dim Shared rtPassed As Integer, rtFailed As Integer

Sub RT_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        rtPassed = rtPassed + 1
    Else
        Print "FAIL  " + testName
        rtFailed = rtFailed + 1
    End If
End Sub

Dim rtA(1 To 20) As Single, rtB(1 To 20) As Single, rtI As Long, rtSame As Integer, rtV As Single
Dim rtLo As Integer, rtHi As Integer, rtSum As Double, rtBin(0 To 2) As Long, rtOk As Integer, rtK As Integer

Print "=== rng_test ==="
Print ""

Print "--- replay ---"
RNG_Seed 12345
For rtI = 1 To 20 : rtA(rtI) = RNG!(RNG_GAME) : Next rtI
RNG_Seed 12345
rtSame = -1
For rtI = 1 To 20
    rtV = RNG!(RNG_GAME)
    If rtV <> rtA(rtI) Then rtSame = 0
Next rtI
RT_Assert rtSame, "same seed: same sequence"

RNG_Seed 12346
rtSame = -1
For rtI = 1 To 20
    rtB(rtI) = RNG!(RNG_GAME)
    If rtB(rtI) <> rtA(rtI) Then rtSame = 0
Next rtI
RT_Assert rtSame = 0, "a neighbouring seed: different sequence"
RT_Assert Abs(rtA(1) - rtB(1)) > 0.01, "neighbouring seeds differ from the first draw"

RNG_Seed 12345
rtSame = -1
For rtI = 1 To 20
    rtV = RNG!(RNG_FX)
    If rtV <> rtA(rtI) Then rtSame = 0
Next rtI
RT_Assert rtSame = 0, "same seed, another stream: different sequence"

Print "--- independence ---"
RNG_Seed 12345
For rtI = 1 To 10 : rtV = RNG!(RNG_GAME) : Next rtI
For rtI = 1 To 500 : rtV = RNG!(RNG_FX) : rtV = RNG!(RNG_AUDIO) : Next rtI
rtSame = -1
For rtI = 11 To 20
    rtV = RNG!(RNG_GAME)
    If rtV <> rtA(rtI) Then rtSame = 0
Next rtI
RT_Assert rtSame, "drawing FX and AUDIO doesn't move GAME"

Print "--- unseeded default ---"
rngState(RNG_GAME) = 0
rtA(1) = RNG!(RNG_GAME) : rtA(2) = RNG!(RNG_GAME)
rngState(RNG_GAME) = 0
rtB(1) = RNG!(RNG_GAME) : rtB(2) = RNG!(RNG_GAME)
RT_Assert rtA(1) = rtB(1) And rtA(2) = rtB(2), "unseeded stream: fixed, repeatable start"
RT_Assert rngState(RNG_GAME) <> 0, "state never sticks at 0"

Print "--- range ---"
RNG_Seed 7
rtOk = -1 : rtLo = 0 : rtHi = 0
For rtI = 1 To 100000
    rtV = RNG!(RNG_GAME)
    If rtV < 0 Or rtV >= 1 Then rtOk = 0
    If rtV < 0.001 Then rtLo = -1
    If rtV > 0.999 Then rtHi = -1
    rtSum = rtSum + rtV
    rtK = Int(RNG!(RNG_FX) * 3)
    If rtK < 0 Or rtK > 2 Then rtOk = 0 Else rtBin(rtK) = rtBin(rtK) + 1
Next rtI
RT_Assert rtOk, "100k draws all in [0, 1)"
RT_Assert rtLo And rtHi, "reaches both ends of the range"
RT_Assert Abs(rtSum / 100000 - 0.5) < 0.01, "mean is about 0.5"
RT_Assert rtBin(0) > 30000 And rtBin(1) > 30000 And rtBin(2) > 30000, "Int(x * 3) hits 0, 1 and 2 evenly, never 3"

Print "--- RNG_UNIQUE ignores the seed ---"
RNG_Seed 12345
RT_Assert rngState(RNG_UNIQUE) <> RNG_StreamState~&(12345, RNG_UNIQUE), "UNIQUE isn't derived from the master seed"
RT_Assert rngState(RNG_GAME) = RNG_StreamState~&(12345, RNG_GAME), "GAME is"

Print ""
Print "=== " + LTrim$(Str$(rtPassed + rtFailed)) + " tests: " + LTrim$(Str$(rtPassed)) + " passed, " + LTrim$(Str$(rtFailed)) + " failed ==="
If rtFailed > 0 Then System 1 Else System 0
