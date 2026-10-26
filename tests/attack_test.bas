' attack_test.bas — boss attack overhaul (#26): depth cues, one attack per volley, cut, devour
'
' Drives the real modules:
'   - impact.bas : frames until a shot reaches the player's depth, where it crosses,
'                  which crossings count as threats, the closing-ring fraction
'   - attacks.bas: pick is always from the pool, unknown names never picked,
'                  a cooling special falls back to laser, cooldown expiry, empty pool
'   - cuts.bas   : warning does no damage, live beam hurts once inside the band only,
'                  at the right depth, chains alternate orientation and re-aim, idle after
'   - devour.bas : no pull while warning, pull toward the boss's line capped at its
'                  strength and never past the line, escape still gains, ends on time
'
' Build: ./tools/buildqb tests/attack_test.bas
' Run:   ./tests/attack_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

'$INCLUDE:'../src/gameplay/impact.bas'
'$INCLUDE:'../src/gameplay/attacks.bas'
'$INCLUDE:'../src/gameplay/cuts.bas'
'$INCLUDE:'../src/gameplay/devour.bas'

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

' Flies one boss laser with the real IMP_AimLead / IMP_LeadPoint / IMP_SeekStep from 20
' units out at a player strafing at full speed (0.12) in Z; when lmRev > 0 the player
' reverses after lmRev frames. True if it hits: the player+EBULLET AABB half-sums from
' models.e3d (Y .2879+.08, Z .7616+.08), as EBULLET_Update's E3D_AABBOverlap tests.
Function AT_LeadHit%(lmSpd As Single, lmSeek As Single, lmRev As Integer)
    Dim lmX As Single, lmY As Single, lmZ As Single, lmVX As Single, lmVY As Single, lmVZ As Single
    Dim lmPY As Single, lmPZ As Single, lmPVZ As Single, lmTY As Single, lmTZ As Single
    Dim lmDX As Single, lmDY As Single, lmDZ As Single, lmN As Integer
    lmX = 20 : lmPVZ = -0.12
    IMP_AimLead lmX, lmY, lmZ, 0, lmPY, lmPZ, 0, lmPVZ, lmSpd, lmDX, lmDY, lmDZ
    lmVX = lmDX * lmSpd : lmVY = lmDY * lmSpd : lmVZ = lmDZ * lmSpd
    Do While lmX > 0 And lmN < 600
        lmN = lmN + 1
        If lmRev > 0 And lmN = lmRev Then lmPVZ = -lmPVZ
        lmPZ = lmPZ + lmPVZ
        IMP_LeadPoint lmPY, lmPZ, 0, lmPVZ, IMP_FramesLeft!(lmX, lmVX, 0), lmTY, lmTZ
        IMP_SeekStep lmY, lmZ, lmVY, lmVZ, lmTY, lmTZ, lmSeek
        lmX = lmX + lmVX : lmY = lmY + lmVY : lmZ = lmZ + lmVZ
    Loop
    AT_LeadHit% = (Abs(lmY - lmPY) <= 0.2879 + 0.08 And Abs(lmZ - lmPZ) <= 0.7616 + 0.08)
End Function

' Runs rcN frames of the cut with the player at (rcX, rcY, rcZ); returns total damage.
Function AT_RunCut%(rcN As Integer, rcX As Single, rcY As Single, rcZ As Single)
    Dim atrI As Integer, atrD As Integer
    For atrI = 1 To rcN
        atrD = atrD + CUT_Update%(rcX, rcY, rcZ, 0, 0)
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

Print "--- impact.bas: boss lead aim vs a player holding one direction ---"
Dim atSpd(1 To 3) As Single, atSeek(1 To 3) As Single
atSpd(1) = 0.26 : atSpd(2) = 0.30 : atSpd(3) = 0.35
atSeek(1) = 0.015 : atSeek(2) = 0.035 : atSeek(3) = 0.055
For atK = 1 To 3
    AT_Assert AT_LeadHit%(atSpd(atK), atSeek(atK), 0), "phase" + Str$(atK) + ": holding one direction at full speed gets hit"
    AT_Assert AT_LeadHit%(atSpd(atK), atSeek(atK), 15) = 0, "phase" + Str$(atK) + ": reversing 15 frames after the shot dodges it"
Next atK
AT_Assert IMP_Threat%(0.5, 0.5, 0, 0), "crossing near the player is a threat"
AT_Assert IMP_Threat%(IMP_THREAT_R + 0.1, 0, 0, 0) = 0, "crossing outside IMP_THREAT_R is not"
AT_Assert AT_Near%(IMP_RingFrac!(IMP_RING_FRAMES * 2, IMP_RING_FRAMES), 1), "ring wide open while far off"
AT_Assert AT_Near%(IMP_RingFrac!(IMP_RING_FRAMES / 2, IMP_RING_FRAMES), 0.5), "ring half closed halfway in"
AT_Assert AT_Near%(IMP_RingFrac!(0, IMP_RING_FRAMES), 0), "ring closed at impact"

Print "--- attacks.bas: one attack per volley from the pool ---"
Dim atPool(0 To 7) As String, atI As Integer, atC As Integer, atOk As Integer
Dim atSawLaser As Integer, atSawSpore As Integer, atSawCut As Integer, atSawDev As Integer
atPool(0) = "LASER" : atPool(1) = "SPORE" : atPool(2) = "CUT" : atPool(3) = "DEVOUR"
ATK_Clear
atOk = -1
For atI = 0 To 99
    atC = ATK_Pick%(atPool(), 4, atI / 100)
    If atC = ATK_LASER Then atSawLaser = -1
    If atC = ATK_SPORE Then atSawSpore = -1
    If atC = ATK_CUT Then atSawCut = -1
    If atC = ATK_DEVOUR Then atSawDev = -1
    If atC < ATK_LASER Or atC > ATK_COUNT Then atOk = 0
Next atI
AT_Assert atOk, "every pick is a real attack"
AT_Assert atSawLaser And atSawSpore And atSawCut And atSawDev, "laser, spore, cut and devour all come up"
AT_Assert ATK_Pick%(atPool(), 4, 0) = ATK_LASER And ATK_Pick%(atPool(), 4, 0.3) = ATK_SPORE And ATK_Pick%(atPool(), 4, 0.6) = ATK_CUT And ATK_Pick%(atPool(), 4, 0.99) = ATK_DEVOUR, "r splits evenly across the pool"
AT_Assert ATK_Pick%(atPool(), 4, 1) = ATK_DEVOUR, "r = 1 clamps to the last entry"
AT_Assert ATK_Pick%(atPool(), 2, 0.99) = ATK_SPORE, "boss 1 pool (laser,spore): spore at the top of r"
AT_Assert ATK_Pick%(atPool(), 0, 0.5) = ATK_LASER, "empty pool: lasers"
atPool(4) = "lAsEr " : atPool(5) = "bogus"
AT_Assert ATK_Code%(atPool(4)) = ATK_LASER And ATK_Code%(atPool(5)) = 0, "names are case/space tolerant; unknown names ignored"
Dim atPool2(0 To 1) As String
atPool2(0) = "LASER" : atPool2(1) = "bogus"
AT_Assert ATK_Pick%(atPool2(), 2, 0.99) = ATK_LASER, "unknown pool names are skipped, not picked"

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
CUT_Start 1, -1, 0, 2, 3, 0, 0
AT_Assert CUT_Busy% And cutStage = CUT_ST_WARN And AT_Near%(cutY, 2), "start: warning aimed through the player"
CUT_Start 1, 0, 0, 2, 3, 0.06, -0.12
AT_Assert AT_Near%(cutY, 2 + 0.06 * CUT_LEAD_FRAMES) And AT_Near%(cutZ, 3 - 0.12 * CUT_LEAD_FRAMES), "moving player: cut aims CUT_LEAD_FRAMES ahead"
CUT_Clear
CUT_Start 1, -1, 0, 2, 3, 0, 0
AT_Assert AT_Near%(CUT_WarnFrac!, 1), "warning fraction starts at 1"
AT_Assert AT_RunCut%(CUT_WARN - 1, 0, 2, 3) = 0, "no damage during the warning"
atC = AT_RunCut%(1, 0, 2, 3)
AT_Assert atC = 0 And cutStage = CUT_ST_LIVE, "beam goes live after CUT_WARN frames"
AT_Assert AT_RunCut%(CUT_LIVE, 0, 2, 3) = CUT_DMG, "inside the band: hurt exactly once per cut"
AT_Assert CUT_Busy% = 0, "single cut: idle afterwards"

CUT_Start 1, -1, 0, 2, 3, 0, 0
atC = AT_RunCut%(CUT_WARN, 0, 2 + CUT_HALF + 0.2, 3)
AT_Assert AT_RunCut%(CUT_LIVE, 0, 2 + CUT_HALF + 0.2, 3) = 0, "horizontal cut: moving up out of the band dodges it"
CUT_Start 1, -1, 0, 2, 3, 0, 0
atC = AT_RunCut%(CUT_WARN, 0, 2, 50)
AT_Assert AT_RunCut%(CUT_LIVE, 0, 2, 50) = CUT_DMG, "horizontal cut spans the plane: sideways doesn't dodge"
CUT_Start 1, 0, 0, 2, 3, 0, 0
atC = AT_RunCut%(CUT_WARN, 0, 50, 3)
AT_Assert AT_RunCut%(CUT_LIVE, 0, 50, 3) = CUT_DMG, "vertical cut spans the plane: up/down doesn't dodge"
CUT_Start 1, 0, 0, 2, 3, 0, 0
atC = AT_RunCut%(CUT_WARN, 0, 2, 3 + CUT_HALF + 0.2)
AT_Assert AT_RunCut%(CUT_LIVE, 0, 2, 3 + CUT_HALF + 0.2) = 0, "vertical cut: moving sideways dodges it"
CUT_Start 1, -1, 0, 2, 3, 0, 0
atC = AT_RunCut%(CUT_WARN, CUT_DEPTH + 1, 2, 3)
AT_Assert AT_RunCut%(CUT_LIVE, CUT_DEPTH + 1, 2, 3) = 0, "no damage away from the cut's depth"

CUT_Start 3, -1, 0, 2, 3, 0, 0
atC = AT_RunCut%(CUT_WARN + CUT_LIVE + CUT_GAP, 0, 5, 7)
AT_Assert atC = 0 And cutStage = CUT_ST_WARN And cutHoriz = 0, "chain: second cut is vertical"
AT_Assert AT_Near%(cutY, 5) And AT_Near%(cutZ, 7), "chain: second cut re-aims at the player"
atC = AT_RunCut%(CUT_WARN + CUT_LIVE, 0, 5, 7)
AT_Assert atC = CUT_DMG, "chain: second cut hurts on its own"
atC = AT_RunCut%(CUT_GAP + CUT_WARN + CUT_LIVE, 0, 5, 7)
AT_Assert atC = CUT_DMG And CUT_Busy% = 0, "chain of 3: third cut, then idle"
CUT_Start 0, -1, 0, 2, 3, 0, 0
AT_Assert CUT_Busy% = 0, "a chain of 0 cuts does nothing"
CUT_Start 2, -1, 0, 2, 3, 0, 0 : CUT_Clear
AT_Assert CUT_Busy% = 0 And AT_RunCut%(CUT_WARN + CUT_LIVE, 0, 2, 3) = 0, "CUT_Clear stops a running chain"

Print "--- devour.bas: suction warning, pull toward the boss's line ---"
Dim atPY As Single, atPZ As Single
DEV_Clear
DEV_Pull 0, 0, 5, 0
AT_Assert DEV_Busy% = 0 And devPullY = 0 And devPullZ = 0, "idle: no pull"
DEV_Start 1
For atK = 1 To DEV_WARN - 1
    DEV_Update
Next atK
DEV_Pull 0, 0, 5, 0
AT_Assert DEV_Busy% And devStage = DEV_ST_WARN And devPullY = 0 And devPullZ = 0, "warning: busy but no pull yet"
DEV_Update
DEV_Pull 0, 0, 3, 4
AT_Assert devStage = DEV_ST_PULL, "pull starts after DEV_WARN frames"
AT_Assert AT_Near%(devPullY, DEV_STRENGTH * 0.6) And AT_Near%(devPullZ, DEV_STRENGTH * 0.8), "pull points at the boss's line at DEV_STRENGTH"
DEV_Pull 0, 0, 0.01, 0
AT_Assert AT_Near%(devPullY, 0.01) And AT_Near%(devPullZ, 0), "never pulls past the line"

' a still player is dragged onto the boss's line
atPY = 0 : atPZ = 3
For atK = 1 To 60
    DEV_Update
    DEV_Pull atPY, atPZ, 0, 0
    atPY = atPY + devPullY : atPZ = atPZ + devPullZ
Next atK
AT_Assert Abs(atPZ) < 0.001 And Abs(atPY) < 0.001, "still player: dragged onto the line (3 units in 50 frames)"

' flying straight away at full speed (0.12) still gains ground, even in phase 3
DEV_Start 3
For atK = 1 To DEV_WARN : DEV_Update : Next atK
atPY = 0 : atPZ = 1
For atK = 1 To 60
    DEV_Update
    DEV_Pull atPY, atPZ, 0, 0
    atPZ = atPZ + 0.12 + devPullZ
Next atK
AT_Assert atPZ > 1 + 60 * 0.03, "phase 3: full-speed escape still gains ground"
AT_Assert DEV_STRENGTH + 2 * DEV_PHASE_STEP < 0.12, "strongest pull stays under the player's top speed"

For atK = 1 To DEV_PULL_FRAMES : DEV_Update : Next atK
DEV_Pull 0, 0, 5, 0
AT_Assert DEV_Busy% = 0 And devPullY = 0 And devPullZ = 0, "pull ends after DEV_PULL_FRAMES frames"
DEV_Start 2 : DEV_Clear
AT_Assert DEV_Busy% = 0, "DEV_Clear stops it"

Print ""
Print "=== " + LTrim$(Str$(atPassed + atFailed)) + " tests: " + LTrim$(Str$(atPassed)) + " passed, " + LTrim$(Str$(atFailed)) + " failed ==="
If atFailed > 0 Then System 1 Else System 0
