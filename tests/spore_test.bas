' spore_test.bas — boss attack A "spore bloom" (src/gameplay/spores.bas, #26)
'
' Drives the real spore module frame by frame:
'   - spawning, pool limit, clear
'   - drift from the boss to the target, then lingering, then expiry
'   - damage only after arrival, only inside the radius and at the cloud's depth,
'     once per SPORE_TICK per cloud, none during the fade-out
'   - volley size per boss phase from the attack= list (A,A,A / A,B,B / A,B,C)
'
' Build: ./tools/buildqb tests/spore_test.bas
' Run:   ./tests/spore_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

'$INCLUDE:'../src/gameplay/spores.bas'

Dim Shared stPassed As Integer, stFailed As Integer

Sub ST_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        stPassed = stPassed + 1
    Else
        Print "FAIL  " + testName
        stFailed = stFailed + 1
    End If
End Sub

Function ST_Near%(snA As Single, snB As Single)
    ST_Near% = (Abs(snA - snB) < 0.001)
End Function

' Runs stN frames with the player at (stX, stY, stZ); returns total damage taken.
Function ST_Run%(stN As Integer, stX As Single, stY As Single, stZ As Single)
    Dim strI As Integer, strD As Integer
    For strI = 1 To stN
        strD = strD + SPORE_Update%(stX, stY, stZ)
    Next strI
    ST_Run% = strD
End Function

Print "=== spore_test ==="
Print ""

Print "--- spawn, pool, clear ---"
SPORE_Clear
SPORE_Spawn 20, 1, 2, 0, 3, 4
ST_Assert SPORE_Count% = 1, "one cloud after a spawn"
Dim stI As Integer
For stI = 1 To SPORE_MAX + 3 : SPORE_Spawn 20, 0, 0, 0, 0, 0 : Next stI
ST_Assert SPORE_Count% = SPORE_MAX, "pool caps at SPORE_MAX"
SPORE_Clear
ST_Assert SPORE_Count% = 0, "SPORE_Clear removes every cloud"

Print "--- drift, linger, expiry ---"
SPORE_Clear
SPORE_Spawn 20, 1, 2, 0, 3, 4
ST_Assert ST_Near%(sporeX(1), 20) And ST_Near%(sporeR(1), SPORE_R_START), "starts at the boss, small"
stI = ST_Run%(SPORE_DRIFT_FRAMES \ 2, 0, 50, 50)
ST_Assert sporeX(1) < 20 And sporeX(1) > 0 And sporeR(1) > SPORE_R_START And sporeR(1) < SPORE_R_MAX, "halfway: between boss and target, growing"
stI = ST_Run%(SPORE_DRIFT_FRAMES - SPORE_DRIFT_FRAMES \ 2, 0, 50, 50)
ST_Assert ST_Near%(sporeX(1), 0) And ST_Near%(sporeY(1), 3) And ST_Near%(sporeZ(1), 4), "arrives exactly at its target"
ST_Assert ST_Near%(sporeR(1), SPORE_R_MAX), "full size on arrival"
stI = ST_Run%(SPORE_LINGER - 1, 0, 50, 50)
ST_Assert SPORE_Count% = 1, "still lingering one frame before expiry"
stI = ST_Run%(1, 0, 50, 50)
ST_Assert SPORE_Count% = 0, "gone after SPORE_DRIFT_FRAMES + SPORE_LINGER"

Print "--- damage ---"
' the player waits at the target the whole time
SPORE_Clear
SPORE_Spawn 20, 0, 0, 0, 0, 0
ST_Assert ST_Run%(SPORE_DRIFT_FRAMES, 0, 0, 0) = 0, "no damage while drifting in"
ST_Assert SPORE_Update%(0, 0, 0) = SPORE_DMG, "first tick on the frame after arrival"
ST_Assert ST_Run%(SPORE_TICK - 1, 0, 0, 0) = 0, "no second tick inside SPORE_TICK"
ST_Assert SPORE_Update%(0, 0, 0) = SPORE_DMG, "next tick SPORE_TICK frames later"
SPORE_Clear
SPORE_Spawn 20, 0, 0, 0, 0, 0
Dim stHurt As Integer, stWant As Integer
stHurt = ST_Run%(SPORE_DRIFT_FRAMES + SPORE_LINGER, 0, 0, 0)
' hurting ages run SPORE_DRIFT_FRAMES+1 .. SPORE_DRIFT_FRAMES+SPORE_LINGER-SPORE_FADE-1
stWant = ((SPORE_LINGER - SPORE_FADE - 1 + SPORE_TICK - 1) \ SPORE_TICK) * SPORE_DMG
ST_Assert stHurt = stWant, "standing in it for its whole life costs" + Str$(stWant) + " (got" + Str$(stHurt) + ")"

' outside the radius, wrong depth, leaving the cloud
SPORE_Clear
SPORE_Spawn 20, 0, 0, 0, 0, 0
stI = ST_Run%(SPORE_DRIFT_FRAMES, 0, 50, 50)
ST_Assert ST_Run%(SPORE_LINGER - SPORE_FADE - 1, 0, SPORE_R_MAX + 0.1, 0) = 0, "just outside the radius: no damage"
SPORE_Clear
SPORE_Spawn 20, 0, 0, 0, 0, 0
stI = ST_Run%(SPORE_DRIFT_FRAMES, 0, 50, 50)
ST_Assert ST_Run%(SPORE_LINGER - SPORE_FADE - 1, SPORE_DEPTH + 0.5, 0, 0) = 0, "in front of or behind its depth: no damage"
SPORE_Clear
SPORE_Spawn 20, 0, 0, 0, 0, 0
stI = ST_Run%(SPORE_DRIFT_FRAMES, 0, 50, 50)
ST_Assert ST_Run%(5, 0, 0, 0) = SPORE_DMG, "step in: one tick"
ST_Assert ST_Run%(SPORE_TICK * 3, 0, 10, 0) = 0, "step out: no more damage"

' fade-out is harmless
SPORE_Clear
SPORE_Spawn 20, 0, 0, 0, 0, 0
stI = ST_Run%(SPORE_DRIFT_FRAMES + SPORE_LINGER - SPORE_FADE, 0, 50, 50)
ST_Assert ST_Run%(SPORE_FADE, 0, 0, 0) = 0, "fading cloud does no damage"
ST_Assert sporeActive(1) = 0, "and is gone at the end of its fade"

' two clouds on the player tick independently
SPORE_Clear
SPORE_Spawn 20, 0, 0, 0, 0, 0
SPORE_Spawn 20, 0, 0, 0, 0.5, 0
stI = ST_Run%(SPORE_DRIFT_FRAMES, 0, 50, 50)
ST_Assert SPORE_Update%(0, 0.25, 0) = SPORE_DMG * 2, "overlapping clouds each tick"

Print "--- volley size per boss phase (attack= list) ---"
Dim stL(0 To 7) As String, stP As Integer, stRow As String
stL(0) = "A" : stL(1) = "A" : stL(2) = "A"
ST_Assert SPORE_VolleySize%(stL(), 3, 1) = 1 And SPORE_VolleySize%(stL(), 3, 2) = 2 And SPORE_VolleySize%(stL(), 3, 3) = 3, "boss 1 (A,A,A): 1, 2, 3 clouds"
stL(0) = "A" : stL(1) = "B" : stL(2) = "B"
ST_Assert SPORE_VolleySize%(stL(), 3, 1) = 1 And SPORE_VolleySize%(stL(), 3, 2) = 0 And SPORE_VolleySize%(stL(), 3, 3) = 0, "boss 2 (A,B,B): 1, 0, 0 clouds"
stL(0) = "A" : stL(1) = "B" : stL(2) = "C"
ST_Assert SPORE_VolleySize%(stL(), 3, 1) = 1 And SPORE_VolleySize%(stL(), 3, 2) = 0 And SPORE_VolleySize%(stL(), 3, 3) = 0, "boss 3 (A,B,C): 1, 0, 0 clouds"
ST_Assert SPORE_VolleySize%(stL(), 0, 1) = 0, "no attack= list: no clouds"
ST_Assert SPORE_VolleySize%(stL(), 3, 0) = 0 And SPORE_VolleySize%(stL(), 3, 4) = 0, "out-of-range phase: no clouds"

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
