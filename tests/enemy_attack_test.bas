' enemy_attack_test.bas -- per-enemy-type attacks (#136)
'
' Drives src/gameplay/enemyatk.bas with the real assets/config/enemies.ini:
'   1. the shipped file loads, every mesh slot maps to its type, 
'   2. a bad value is refused with its key named; a missing key is the solo baseline
'   3. volley angles: centred, spread apart; a single shot is straight
'   4. EAT_Spread turns a unit direction sideways by the angle and keeps it unit length
'   5. EAT_HomeStep turns at most the cap per call, keeps speed, reaches the target direction
'   6. a homing bullet cannot turn onto a ship that dodges inside home_stop
'   7. balance: per-type shot rate stays near the baseline, solo and vcol are the baseline
'   8. dev nudges clamp to each value's range
'
' Build: tools/dev test (builds and runs every test)
' Run:   builds/enemy_attack_test   (exit 0 = all pass)

$CONSOLE:ONLY
Option _Explicit
'$INCLUDE:'../src/sys/failfast.bi'

$EMBED:'assets/config/enemies.ini':'CFGENEMIES'


Sub DBG_Print (eaDbg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/enemyatk.bas'

Dim Shared eaPassed As Integer, eaFailed As Integer

Print "=== enemy_attack_test ==="

Sub EA_Assert (eaOK As Integer, eaName As String)
    If eaOK Then
        Print "PASS  " + eaName
        eaPassed = eaPassed + 1
    Else
        Print "FAIL  " + eaName
        eaFailed = eaFailed + 1
    End If
End Sub

Function EA_Near% (eaA As Single, eaB As Single)
    EA_Near% = (Abs(eaA - eaB) < 0.001)
End Function


Dim eaT As Integer, eaK As Integer
Dim eaDX As Single, eaDY As Single, eaDZ As Single
Dim eaVX As Single, eaVY As Single, eaVZ As Single, eaTX As Single, eaTY As Single, eaTZ As Single
Dim eaI As Integer, eaSp As Single, eaAng As Single, eaOK As Integer

' 1
EA_Assert EAT_Load%(_EMBEDDED$("CFGENEMIES")), "shipped enemies.ini loads" + eatLoadErr
EA_Assert EAT_Type%(MESH_ENEMY) = 0 And EAT_Type%(MESH_ENEMY_ARROW) = 1 And EAT_Type%(MESH_ENEMY_HLINE) = 2 And EAT_Type%(MESH_ENEMY_VCOL) = 3 And EAT_Type%(MESH_ENEMY_PINCER) = 4 And EAT_Type%(MESH_ENEMY_VWEDGE) = 5, "each mesh slot maps to its type"
EA_Assert EAT_Type%(99) = 0, "an unknown mesh is solo"

' shipped values
EA_Assert EAT_Get!(4, EAT_P_SHOTS) = 3 And EAT_Get!(4, EAT_P_SPREAD) > 0, "pincer fires a 3-shot spread"
EA_Assert EAT_Get!(5, EAT_P_HOMING) > 0 And EAT_Get!(5, EAT_P_STOP) > 0 And EAT_Get!(5, EAT_P_SPEED) < 1, "vwedge homes, stops homing near the ship, and is slower"
EA_Assert EAT_Get!(1, EAT_P_SPEED) > 1 And EAT_Get!(1, EAT_P_COOL) < 1, "arrow is faster with a shorter cooldown"
EA_Assert EAT_Get!(2, EAT_P_COOL) < EAT_Get!(1, EAT_P_COOL) And EAT_Get!(2, EAT_P_LEAD) < 1, "hline fires most often with less lead"
EA_Assert EAT_Get!(0, EAT_P_SHOTS) = 1 And EAT_Get!(0, EAT_P_COOL) = 1 And EAT_Get!(0, EAT_P_SPEED) = 1 And EAT_Get!(0, EAT_P_LEAD) = 1 And EAT_Get!(0, EAT_P_HOMING) = 0, "solo is the baseline"
EA_Assert EAT_Get!(3, EAT_P_SHOTS) = 1 And EAT_Get!(3, EAT_P_COOL) = 1 And EAT_Get!(3, EAT_P_SPEED) = 1 And EAT_Get!(3, EAT_P_LEAD) = 1 And EAT_Get!(3, EAT_P_HOMING) = 0, "vcol is the baseline"

' 2
EA_Assert EAT_Load%("pincer_shots=9") = 0 And Instr(eatLoadErr, "pincer_shots") > 0, "shots out of range is refused, naming the key"
EA_Assert EAT_Load%("hline_cool=0") = 0 And Instr(eatLoadErr, "hline_cool") > 0, "a zero cooldown is refused"
EA_Assert EAT_Load%("arrow_speed=1.4") And EAT_Get!(1, EAT_P_SPEED) = 1.4 And EAT_Get!(4, EAT_P_SHOTS) = 1 And EAT_Get!(4, EAT_P_COOL) = 1, "a missing key is the baseline"

' 3
EA_Assert EAT_Load%("pincer_shots=3" + Chr$(10) + "pincer_spread=10"), "load 3-shot test file"
EA_Assert EA_Near%(EAT_ShotAngle!(4, 0), -10) And EA_Near%(EAT_ShotAngle!(4, 1), 0) And EA_Near%(EAT_ShotAngle!(4, 2), 10), "3 shots: -spread, 0, +spread"
EA_Assert EAT_Load%("pincer_shots=2" + Chr$(10) + "pincer_spread=10") And EA_Near%(EAT_ShotAngle!(4, 0), -5) And EA_Near%(EAT_ShotAngle!(4, 1), 5), "2 shots: straddle the aim"
EA_Assert EA_Near%(EAT_ShotAngle!(0, 0), 0), "one shot is straight"

' 4
For eaK = 0 To 3
    Select Case eaK
    Case 0 : eaDX = -1 : eaDY = 0 : eaDZ = 0
    Case 1 : eaDX = -0.8 : eaDY = 0.6 : eaDZ = 0
    Case 2 : eaDX = -0.6 : eaDY = -0.48 : eaDZ = 0.64
    Case Else : eaDX = -0.5 : eaDY = 0.5 : eaDZ = -0.7071
    End Select
    eaSp = Sqr(eaDX * eaDX + eaDY * eaDY + eaDZ * eaDZ)
    eaDX = eaDX / eaSp : eaDY = eaDY / eaSp : eaDZ = eaDZ / eaSp
    eaVX = eaDX : eaVY = eaDY : eaVZ = eaDZ
    EAT_Spread eaVX, eaVY, eaVZ, 12
    eaAng = EA_ACos(eaDX * eaVX + eaDY * eaVY + eaDZ * eaVZ)
    EA_Assert EA_Near%(Sqr(eaVX * eaVX + eaVY * eaVY + eaVZ * eaVZ), 1) And EA_Near%(eaAng, 12), "spread of 12 degrees stays unit and 12 degrees off aim " + Str$(eaK)
Next eaK
eaVX = -1 : eaVY = 0 : eaVZ = 0
EAT_Spread eaVX, eaVY, eaVZ, 10
EA_Assert eaVZ > 0 And EA_Near%(eaVY, 0), "a positive angle turns toward +z"
eaVX = -1 : eaVY = 0 : eaVZ = 0
EAT_Spread eaVX, eaVY, eaVZ, -10
EA_Assert eaVZ < 0, "a negative angle turns toward -z"

' 5
eaVX = -0.1 : eaVY = 0 : eaVZ = 0
eaTX = -1 : eaTY = 0 : eaTZ = 1
EAT_HomeStep eaVX, eaVY, eaVZ, eaTX, eaTY, eaTZ, 1
eaSp = Sqr(eaVX * eaVX + eaVY * eaVY + eaVZ * eaVZ)
eaAng = EA_ACos(-eaVX / eaSp)
EA_Assert EA_Near%(eaSp, 0.1) And EA_Near%(eaAng, 1), "one homing step turns exactly the cap and keeps speed"
eaOK = -1
For eaI = 1 To 200
    eaTX = -1 : eaTY = 0 : eaTZ = 1
    EAT_HomeStep eaVX, eaVY, eaVZ, eaTX, eaTY, eaTZ, 1
Next eaI
eaSp = Sqr(eaVX * eaVX + eaVY * eaVY + eaVZ * eaVZ)
EA_Assert EA_Near%(eaSp, 0.1) And EA_Near%(EA_ACos((-eaVX + eaVZ) / eaSp / Sqr(2)), 0), "repeated steps settle on the target direction"
eaVX = -0.1 : eaVY = 0 : eaVZ = 0
eaTX = -1 : eaTY = 0.001 : eaTZ = 0
EAT_HomeStep eaVX, eaVY, eaVZ, eaTX, eaTY, eaTZ, 5
EA_Assert EA_Near%(eaVX / 0.1, -1), "within the cap takes the target outright"
eaVX = -0.1 : eaVY = 0 : eaVZ = 0
EAT_HomeStep eaVX, eaVY, eaVZ, eaTX, eaTY, eaTZ, 0
EA_Assert EA_Near%(eaVX, -0.1) And eaVY = 0, "a zero cap leaves the velocity alone"

' 6: ship sits at z 0, bullet tracks it from 40 units out with the shipped values; ship
' jumps 3 units sideways at home_stop and the bullet must miss by more than the lateral
' room one frame of turning gives it
EA_Assert EAT_Load%(_EMBEDDED$("CFGENEMIES")), "reload shipped file"
Dim eaBX As Single, eaBY As Single, eaBZ As Single, eaShipZ As Single, eaStop As Single, eaSpd As Single
eaBX = 40 : eaBY = 0 : eaBZ = 6 : eaShipZ = 0
eaStop = EAT_Get!(EAT_VWEDGE, EAT_P_STOP)
eaSpd = 0.16 * EAT_Get!(EAT_VWEDGE, EAT_P_SPEED)
eaVX = -eaSpd : eaVY = 0 : eaVZ = 0
eaI = 0
Do While eaBX > 0 And eaI < 4000
    If eaBX > eaStop Then
        eaTX = 0 - eaBX : eaTY = 0 - eaBY : eaTZ = eaShipZ - eaBZ
        EAT_HomeStep eaVX, eaVY, eaVZ, eaTX, eaTY, eaTZ, EAT_Get!(EAT_VWEDGE, EAT_P_HOMING)
    ElseIf eaShipZ = 0 Then
        eaShipZ = 3
    End If
    eaBX = eaBX + eaVX : eaBY = eaBY + eaVY : eaBZ = eaBZ + eaVZ
    eaI = eaI + 1
Loop
EA_Assert Abs(eaBZ - eaShipZ) > 1.5, "a homing bullet misses a ship that sidesteps once it stops homing"

' 7
EA_Assert EAT_Load%(_EMBEDDED$("CFGENEMIES")), "reload shipped file"
eaOK = -1
For eaT = 0 To EAT_TYPES - 1
    If 1 / EAT_Get!(eaT, EAT_P_COOL) < 0.7 Or 1 / EAT_Get!(eaT, EAT_P_COOL) > 1.7 Then eaOK = 0
Next eaT
EA_Assert eaOK, "every type fires volleys within 0.7x to 1.7x of the baseline rate (flank shots of a spread mostly miss)"
EA_Assert EAT_Rate!(0) = 1 And EAT_Rate!(3) = 1, "solo and vcol shoot at the baseline rate"
' a type that shoots more often must also aim worse or fly slower, so extra rate is not extra damage
EA_Assert EAT_Rate!(2) > 1 And EAT_Get!(2, EAT_P_LEAD) < 0.5, "hline: more shots, much less lead"
EA_Assert EAT_Rate!(1) > 1 And EAT_Get!(1, EAT_P_LEAD) < 1, "arrow: more shots, less lead"
EA_Assert EAT_Get!(4, EAT_P_COOL) > 1, "pincer: three shots a volley, volleys further apart"

' 8
EAT_Set 4, EAT_P_SHOTS, 99 : EA_Assert EAT_Get!(4, EAT_P_SHOTS) = 5, "shots clamp at 5"
EAT_Set 4, EAT_P_SHOTS, -3 : EA_Assert EAT_Get!(4, EAT_P_SHOTS) = 1, "shots clamp at 1"
EAT_Set 1, EAT_P_COOL, 0 : EA_Assert EAT_Get!(1, EAT_P_COOL) = 0.2, "cooldown clamps at 0.2"
EAT_Set 5, EAT_P_HOMING, 50 : EA_Assert EAT_Get!(5, EAT_P_HOMING) = 5, "homing clamps at 5 degrees"

Print
Print "enemy_attack_test: passed"; eaPassed; " failed"; eaFailed
If eaFailed > 0 Then System 1
System 0

Function EA_ACos! (eaC As Single)
    Dim eaCC As Single
    eaCC = eaC
    If eaCC > 1 Then eaCC = 1
    If eaCC < -1 Then eaCC = -1
    If eaCC = 1 Then EA_ACos! = 0 : Exit Function
    EA_ACos! = (1.5707963 - _Atan2(eaCC, Sqr(1 - eaCC * eaCC))) * 180 / 3.14159265
End Function
