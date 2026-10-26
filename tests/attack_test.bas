' attack_test.bas — boss attack overhaul (#26): depth cues, one attack per volley, the cut
'
' Drives the real modules:
'   - impact.bas : frames until a shot reaches the player's depth, where it crosses,
'                  which crossings count as threats, the closing-ring fraction
'   - attacks.bas: pick is always from the pool, unbuilt attacks (devour) never picked,
'                  a cooling special falls back to laser, cooldown expiry, empty pool
'   - cuts.bas   : warning does no damage, live beam hurts once inside the band only,
'                  at the right depth, chains alternate orientation and re-aim, idle after
'
' Build: ./tools/buildqb tests/attack_test.bas
' Run:   ./tests/attack_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

'$INCLUDE:'../src/gameplay/impact.bas'
'$INCLUDE:'../src/gameplay/attacks.bas'
'$INCLUDE:'../src/gameplay/cuts.bas'

Dim Shared atPassed As Integer, atFailed As Integer

Sub AT_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        atPassed = atPassed + 1
    Else
        Print "FAIL  " + testName
        atFailed = atFailed + 1
    End If
End Sub

Function AT_Near%(anA As Single, anB As Single)
    AT_Near% = (Abs(anA - anB) < 0.001)
End Function

' Runs rcN frames of the cut with the player at (rcX, rcY, rcZ); returns total damage.
Function AT_RunCut%(rcN As Integer, rcX As Single, rcY As Single, rcZ As Single)
    Dim atrI As Integer, atrD As Integer
    For atrI = 1 To rcN
        atrD = atrD + CUT_Update%(rcX, rcY, rcZ)
    Next atrI
    AT_RunCut% = atrD
End Function

Print "=== attack_test ==="
Print ""

Print "--- impact.bas: when and where a shot reaches the player's depth ---"
Dim atFr As Single, atCY As Single, atCZ As Single
IMP_Predict 10, 1, 2, -0.25, 0.05, -0.025, 0, 0, 0, 0, atFr, atCY, atCZ
AT_Assert AT_Near%(atFr, 40), "shot 10 units out at 0.25/frame arrives in 40 frames"
AT_Assert Abs(atCY - 3) < 0.01 And Abs(atCZ - 1) < 0.01, "crossing point follows its sideways drift"
IMP_Predict 10, 0, 0, 0.25, 0, 0, 0, 0, 0, 0, atFr, atCY, atCZ
AT_Assert atFr = -1, "shot moving away never arrives"
IMP_Predict -1, 0, 0, -0.25, 0, 0, 0, 0, 0, 0, atFr, atCY, atCZ
AT_Assert atFr = -1, "shot already past the player never arrives"

' homing: the prediction must match the real flight (same IMP_SeekStep), so with the
' player holding still the predicted crossing stays put frame after frame
Dim atSX As Single, atSY As Single, atSZ As Single, atVY As Single, atVZ As Single
Dim atFr0 As Single, atCY0 As Single, atCZ0 As Single, atDrift As Single, atK As Integer
atSX = 20 : atSY = 3 : atSZ = -2 : atVY = 0.06 : atVZ = 0.04
IMP_Predict atSX, atSY, atSZ, -0.26, atVY, atVZ, 0, 0.5, 1, 0.035, atFr0, atCY0, atCZ0
For atK = 1 To 40
    IMP_SeekStep atSY, atSZ, atVY, atVZ, 0.5, 1, 0.035
    atSX = atSX - 0.26 : atSY = atSY + atVY : atSZ = atSZ + atVZ
    IMP_Predict atSX, atSY, atSZ, -0.26, atVY, atVZ, 0, 0.5, 1, 0.035, atFr, atCY, atCZ
    If Abs(atCY - atCY0) > atDrift Then atDrift = Abs(atCY - atCY0)
    If Abs(atCZ - atCZ0) > atDrift Then atDrift = Abs(atCZ - atCZ0)
Next atK
AT_Assert atDrift < 0.01, "homing shot, player still: predicted crossing doesn't drift"
AT_Assert AT_Near%(atFr, atFr0 - 40), "homing shot: frames-to-impact counts down one per frame"
atVY = 0 : atVZ = 0
IMP_SeekStep 0, 0, atVY, atVZ, 0, 5, 0
AT_Assert atVY = 0 And atVZ = 0, "seek 0: no steering (regular enemy shots fly straight)"
IMP_SeekStep 0, 0, atVY, atVZ, 0, 5, 1
AT_Assert AT_Near%(atVZ, IMP_SEEK_V) And AT_Near%(atVY, 0), "full seek: steers straight at the target at IMP_SEEK_V"
AT_Assert IMP_Threat%(0.5, 0.5, 0, 0), "crossing near the player is a threat"
AT_Assert IMP_Threat%(IMP_THREAT_R + 0.1, 0, 0, 0) = 0, "crossing outside IMP_THREAT_R is not"
AT_Assert AT_Near%(IMP_RingFrac!(IMP_RING_FRAMES * 2, IMP_RING_FRAMES), 1), "ring wide open while far off"
AT_Assert AT_Near%(IMP_RingFrac!(IMP_RING_FRAMES / 2, IMP_RING_FRAMES), 0.5), "ring half closed halfway in"
AT_Assert AT_Near%(IMP_RingFrac!(0, IMP_RING_FRAMES), 0), "ring closed at impact"

Print "--- attacks.bas: one attack per volley from the pool ---"
Dim atPool(0 To 7) As String, atI As Integer, atC As Integer, atOk As Integer
Dim atSawLaser As Integer, atSawSpore As Integer, atSawCut As Integer
atPool(0) = "LASER" : atPool(1) = "SPORE" : atPool(2) = "CUT" : atPool(3) = "DEVOUR"
ATK_Clear
atOk = -1
For atI = 0 To 99
    atC = ATK_Pick%(atPool(), 4, atI / 100)
    If atC = ATK_LASER Then atSawLaser = -1
    If atC = ATK_SPORE Then atSawSpore = -1
    If atC = ATK_CUT Then atSawCut = -1
    If atC = ATK_DEVOUR Or atC = 0 Then atOk = 0
Next atI
AT_Assert atOk, "devour (not built) is never picked"
AT_Assert atSawLaser And atSawSpore And atSawCut, "laser, spore and cut all come up"
AT_Assert ATK_Pick%(atPool(), 4, 0) = ATK_LASER And ATK_Pick%(atPool(), 4, 0.5) = ATK_SPORE And ATK_Pick%(atPool(), 4, 0.99) = ATK_CUT, "r splits evenly across the built entries"
AT_Assert ATK_Pick%(atPool(), 4, 1) = ATK_CUT, "r = 1 clamps to the last entry"
AT_Assert ATK_Pick%(atPool(), 2, 0.99) = ATK_SPORE, "boss 1 pool (laser,spore): spore at the top of r"
AT_Assert ATK_Pick%(atPool(), 0, 0.5) = ATK_LASER, "empty pool: lasers"
atPool(4) = "lAsEr " : atPool(5) = "bogus"
AT_Assert ATK_Code%(atPool(4)) = ATK_LASER And ATK_Code%(atPool(5)) = 0, "names are case/space tolerant; unknown names ignored"

ATK_Clear
ATK_Fired ATK_SPORE
AT_Assert ATK_Pick%(atPool(), 2, 0.99) = ATK_LASER, "spore cooling down: lasers instead"
For atI = 1 To ATK_COOL_FRAMES - 1 : ATK_Tick : Next atI
AT_Assert ATK_Pick%(atPool(), 2, 0.99) = ATK_LASER, "still cooling one frame early"
ATK_Tick
AT_Assert ATK_Pick%(atPool(), 2, 0.99) = ATK_SPORE, "spore available again after ATK_COOL_FRAMES"
ATK_Fired ATK_LASER
AT_Assert ATK_Pick%(atPool(), 1, 0) = ATK_LASER, "laser never cools down"
ATK_Fired ATK_CUT : ATK_Clear
AT_Assert ATK_Pick%(atPool(), 3, 0.99) = ATK_CUT, "ATK_Clear ends every cooldown"

Print "--- cuts.bas: warning, live beam, chains ---"
CUT_Clear
AT_Assert CUT_Busy% = 0, "idle after clear"
CUT_Start 1, -1, 0, 2, 3
AT_Assert CUT_Busy% And cutStage = CUT_ST_WARN And AT_Near%(cutY, 2), "start: warning aimed through the player"
AT_Assert AT_Near%(CUT_WarnFrac!, 1), "warning fraction starts at 1"
AT_Assert AT_RunCut%(CUT_WARN - 1, 0, 2, 3) = 0, "no damage during the warning"
atC = AT_RunCut%(1, 0, 2, 3)
AT_Assert atC = 0 And cutStage = CUT_ST_LIVE, "beam goes live after CUT_WARN frames"
AT_Assert AT_RunCut%(CUT_LIVE, 0, 2, 3) = CUT_DMG, "inside the band: hurt exactly once per cut"
AT_Assert CUT_Busy% = 0, "single cut: idle afterwards"

CUT_Start 1, -1, 0, 2, 3
atC = AT_RunCut%(CUT_WARN, 0, 2 + CUT_HALF + 0.2, 3)
AT_Assert AT_RunCut%(CUT_LIVE, 0, 2 + CUT_HALF + 0.2, 3) = 0, "horizontal cut: moving up out of the band dodges it"
CUT_Start 1, -1, 0, 2, 3
atC = AT_RunCut%(CUT_WARN, 0, 2, 50)
AT_Assert AT_RunCut%(CUT_LIVE, 0, 2, 50) = CUT_DMG, "horizontal cut spans the plane: sideways doesn't dodge"
CUT_Start 1, 0, 0, 2, 3
atC = AT_RunCut%(CUT_WARN, 0, 50, 3)
AT_Assert AT_RunCut%(CUT_LIVE, 0, 50, 3) = CUT_DMG, "vertical cut spans the plane: up/down doesn't dodge"
CUT_Start 1, 0, 0, 2, 3
atC = AT_RunCut%(CUT_WARN, 0, 2, 3 + CUT_HALF + 0.2)
AT_Assert AT_RunCut%(CUT_LIVE, 0, 2, 3 + CUT_HALF + 0.2) = 0, "vertical cut: moving sideways dodges it"
CUT_Start 1, -1, 0, 2, 3
atC = AT_RunCut%(CUT_WARN, CUT_DEPTH + 1, 2, 3)
AT_Assert AT_RunCut%(CUT_LIVE, CUT_DEPTH + 1, 2, 3) = 0, "no damage away from the cut's depth"

CUT_Start 3, -1, 0, 2, 3
atC = AT_RunCut%(CUT_WARN + CUT_LIVE + CUT_GAP, 0, 5, 7)
AT_Assert atC = 0 And cutStage = CUT_ST_WARN And cutHoriz = 0, "chain: second cut is vertical"
AT_Assert AT_Near%(cutY, 5) And AT_Near%(cutZ, 7), "chain: second cut re-aims at the player"
atC = AT_RunCut%(CUT_WARN + CUT_LIVE, 0, 5, 7)
AT_Assert atC = CUT_DMG, "chain: second cut hurts on its own"
atC = AT_RunCut%(CUT_GAP + CUT_WARN + CUT_LIVE, 0, 5, 7)
AT_Assert atC = CUT_DMG And CUT_Busy% = 0, "chain of 3: third cut, then idle"
CUT_Start 0, -1, 0, 2, 3
AT_Assert CUT_Busy% = 0, "a chain of 0 cuts does nothing"
CUT_Start 2, -1, 0, 2, 3 : CUT_Clear
AT_Assert CUT_Busy% = 0 And AT_RunCut%(CUT_WARN + CUT_LIVE, 0, 2, 3) = 0, "CUT_Clear stops a running chain"

Print ""
Print "=== " + LTrim$(Str$(atPassed + atFailed)) + " tests: " + LTrim$(Str$(atPassed)) + " passed, " + LTrim$(Str$(atFailed)) + " failed ==="
If atFailed > 0 Then System 1 Else System 0
