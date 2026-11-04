' enemyatk.bas -- per-enemy-type attack personality (#136)
'
' The numbers live in assets/config/enemies.ini; this module loads them and holds the pure
' maths enemy.bas fires with, so tests/enemy_attack_test.bas drives it with plain numbers.
' No game state, no RNG: enemy.bas keeps its one RNG_GAME draw per volley.
'
'   t = EAT_Type%(mesh)              attack type 0..5 of an enemy's mesh slot (the fTypeToMesh
'                                    order: solo, arrow, hline, vcol, pincer, vwedge)
'   ok = EAT_Load%(src$)             read the tuning from ini text; 0 + eatLoadErr on a bad value
'   v = EAT_Get!(t, p)               value p (EAT_P_*) of type t
'   EAT_Set t, p, v                  dev tuning: set one value, clamped to its range
'   a = EAT_ShotAngle!(t, k)         sideways angle in degrees of shot k (0-based) of a volley
'   EAT_Spread dx, dy, dz, deg       turn a unit direction sideways (z) by deg degrees
'   EAT_HomeStep vx, vy, vz, tx, ty, tz, deg   turn a velocity toward target direction t,
'                                    at most deg degrees, speed unchanged
'   EAT_SetDebutW v                  dev tuning: the debut weight (eatDebutW, debut_weight in enemies.ini), clamped
'   s = EAT_Rate!(t)                 shots per unit time relative to the baseline
' Local variable prefix: eat*

Const EAT_TYPES = 6
Const EAT_PARAMS = 7
Const EAT_VWEDGE = 5
Const EAT_P_SHOTS = 0
Const EAT_P_SPREAD = 1
Const EAT_P_SPEED = 2
Const EAT_P_COOL = 3
Const EAT_P_LEAD = 4
Const EAT_P_HOMING = 5
Const EAT_P_STOP = 6

Dim Shared eatV(0 To EAT_TYPES - 1, 0 To EAT_PARAMS - 1) As Single
Dim Shared eatLoadErr As String
Dim Shared eatDebutW As Single
Const EAT_DEBUT_DEFAULT = 3
Const EAT_DEBUT_MIN = 1
Const EAT_DEBUT_MAX = 10
Const EAT_DEBUT_STEP = 0.25

Function EAT_Type% (eatMesh As Integer)
    Select Case eatMesh
    Case MESH_ENEMY_ARROW  : EAT_Type% = 1
    Case MESH_ENEMY_HLINE  : EAT_Type% = 2
    Case MESH_ENEMY_VCOL   : EAT_Type% = 3
    Case MESH_ENEMY_PINCER : EAT_Type% = 4
    Case MESH_ENEMY_VWEDGE : EAT_Type% = 5
    Case Else              : EAT_Type% = 0
    End Select
End Function

Function EAT_TypeName$ (eatT As Integer)
    Select Case eatT
    Case 0 : EAT_TypeName$ = "solo"
    Case 1 : EAT_TypeName$ = "arrow"
    Case 2 : EAT_TypeName$ = "hline"
    Case 3 : EAT_TypeName$ = "vcol"
    Case 4 : EAT_TypeName$ = "pincer"
    Case Else : EAT_TypeName$ = "vwedge"
    End Select
End Function

Function EAT_ParamName$ (eatP As Integer)
    Select Case eatP
    Case EAT_P_SHOTS  : EAT_ParamName$ = "shots"
    Case EAT_P_SPREAD : EAT_ParamName$ = "spread"
    Case EAT_P_SPEED  : EAT_ParamName$ = "speed"
    Case EAT_P_COOL   : EAT_ParamName$ = "cool"
    Case EAT_P_LEAD   : EAT_ParamName$ = "lead"
    Case EAT_P_HOMING : EAT_ParamName$ = "homing"
    Case Else         : EAT_ParamName$ = "home_stop"
    End Select
End Function

Function EAT_Min! (eatP As Integer)
    Select Case eatP
    Case EAT_P_SHOTS : EAT_Min! = 1
    Case EAT_P_SPEED, EAT_P_COOL : EAT_Min! = 0.2
    Case Else : EAT_Min! = 0
    End Select
End Function

Function EAT_Max! (eatP As Integer)
    Select Case eatP
    Case EAT_P_SHOTS  : EAT_Max! = 5
    Case EAT_P_SPREAD : EAT_Max! = 45
    Case EAT_P_SPEED  : EAT_Max! = 3
    Case EAT_P_COOL   : EAT_Max! = 5
    Case EAT_P_LEAD   : EAT_Max! = 2
    Case EAT_P_HOMING : EAT_Max! = 5
    Case Else         : EAT_Max! = 20
    End Select
End Function

' One dev nudge step for a value.
Function EAT_Step! (eatP As Integer)
    Select Case eatP
    Case EAT_P_SHOTS, EAT_P_SPREAD, EAT_P_STOP : EAT_Step! = 1
    Case Else : EAT_Step! = 0.05
    End Select
End Function

Sub EAT_Defaults
    Dim eatDT As Integer
    eatDebutW = EAT_DEBUT_DEFAULT
    For eatDT = 0 To EAT_TYPES - 1
        eatV(eatDT, EAT_P_SHOTS) = 1 : eatV(eatDT, EAT_P_SPREAD) = 0 : eatV(eatDT, EAT_P_SPEED) = 1
        eatV(eatDT, EAT_P_COOL) = 1 : eatV(eatDT, EAT_P_LEAD) = 1 : eatV(eatDT, EAT_P_HOMING) = 0
        eatV(eatDT, EAT_P_STOP) = 0
    Next eatDT
End Sub

Function EAT_Load% (eatSrc As String)
    Dim eatStore As String, eatLT As Integer, eatLP As Integer, eatKey As String, eatTxt As String, eatNum As Single
    EAT_Load% = 0
    eatLoadErr = ""
    EAT_Defaults
    eatStore = CFG_Parse$(eatSrc)
    eatTxt = CFG_Get$(eatStore, "debut_weight")
    If Len(eatTxt) > 0 Then
        eatNum = Val(eatTxt)
        If eatNum < EAT_DEBUT_MIN Or eatNum > EAT_DEBUT_MAX Then
            eatLoadErr = "enemies.ini debut_weight:" + Str$(EAT_DEBUT_MIN) + " to" + Str$(EAT_DEBUT_MAX)
            EAT_Defaults
            Exit Function
        End If
        eatDebutW = eatNum
    End If
    For eatLT = 0 To EAT_TYPES - 1
        For eatLP = 0 To EAT_PARAMS - 1
            eatKey = EAT_TypeName$(eatLT) + "_" + EAT_ParamName$(eatLP)
            eatTxt = CFG_Get$(eatStore, eatKey)
            If Len(eatTxt) > 0 Then
                eatNum = Val(eatTxt)
                If eatNum < EAT_Min!(eatLP) Or eatNum > EAT_Max!(eatLP) Then
                    eatLoadErr = "config/enemies.ini " + eatKey + ": " + Str$(EAT_Min!(eatLP)) + " to" + Str$(EAT_Max!(eatLP))
                    EAT_Defaults
                    Exit Function
                End If
                If eatLP = EAT_P_SHOTS Then eatNum = Int(eatNum)
                eatV(eatLT, eatLP) = eatNum
            End If
        Next eatLP
    Next eatLT
    EAT_Load% = -1
End Function

Sub EAT_SetDebutW (eatVal As Single)
    If eatVal < EAT_DEBUT_MIN Then eatVal = EAT_DEBUT_MIN
    If eatVal > EAT_DEBUT_MAX Then eatVal = EAT_DEBUT_MAX
    eatDebutW = Int(eatVal * 1000 + 0.5) / 1000
End Sub

Function EAT_Get! (eatT As Integer, eatP As Integer)
    EAT_Get! = eatV(eatT, eatP)
End Function

Sub EAT_Set (eatT As Integer, eatP As Integer, eatVal As Single)
    If eatVal < EAT_Min!(eatP) Then eatVal = EAT_Min!(eatP)
    If eatVal > EAT_Max!(eatP) Then eatVal = EAT_Max!(eatP)
    If eatP = EAT_P_SHOTS Then eatVal = Int(eatVal + 0.5) Else eatVal = Int(eatVal * 1000 + 0.5) / 1000
    eatV(eatT, eatP) = eatVal
End Sub

' Sideways angle (degrees) of shot k, 0-based, in a volley: centred, eatSpread apart.
Function EAT_ShotAngle! (eatT As Integer, eatK As Integer)
    EAT_ShotAngle! = (eatK - (eatV(eatT, EAT_P_SHOTS) - 1) / 2) * eatV(eatT, EAT_P_SPREAD)
End Function

' Shots per unit time against the baseline (more shots, or a shorter cooldown, raise it).
Function EAT_Rate! (eatT As Integer)
    EAT_Rate! = eatV(eatT, EAT_P_SHOTS) / eatV(eatT, EAT_P_COOL)
End Function

Sub EAT_Spread (eatDX As Single, eatDY As Single, eatDZ As Single, eatDeg As Single)
    Dim eatTan As Single, eatLX As Single, eatLY As Single, eatLZ As Single, eatM As Single
    If eatDeg = 0 Then Exit Sub
    eatLX = -eatDZ * eatDX : eatLY = -eatDZ * eatDY : eatLZ = 1 - eatDZ * eatDZ
    eatM = Sqr(eatLX * eatLX + eatLY * eatLY + eatLZ * eatLZ)
    If eatM < 0.000001 Then Exit Sub
    eatTan = Tan(eatDeg * 3.14159265 / 180) / eatM
    eatDX = eatDX + eatLX * eatTan : eatDY = eatDY + eatLY * eatTan : eatDZ = eatDZ + eatLZ * eatTan
    eatM = Sqr(eatDX * eatDX + eatDY * eatDY + eatDZ * eatDZ)
    eatDX = eatDX / eatM : eatDY = eatDY / eatM : eatDZ = eatDZ / eatM
End Sub

Sub EAT_HomeStep (eatVX As Single, eatVY As Single, eatVZ As Single, eatTX As Single, eatTY As Single, eatTZ As Single, eatDeg As Single)
    Dim eatSp As Single, eatCX As Single, eatCY As Single, eatCZ As Single
    Dim eatM As Single, eatDot As Single, eatPX As Single, eatPY As Single, eatPZ As Single
    Dim eatPL As Single, eatTn As Single
    eatSp = Sqr(eatVX * eatVX + eatVY * eatVY + eatVZ * eatVZ)
    eatM = Sqr(eatTX * eatTX + eatTY * eatTY + eatTZ * eatTZ)
    If eatSp < 0.000001 Or eatM < 0.000001 Or eatDeg <= 0 Then Exit Sub
    eatCX = eatVX / eatSp : eatCY = eatVY / eatSp : eatCZ = eatVZ / eatSp
    eatTX = eatTX / eatM : eatTY = eatTY / eatM : eatTZ = eatTZ / eatM
    eatDot = eatCX * eatTX + eatCY * eatTY + eatCZ * eatTZ
    eatPX = eatTX - eatCX * eatDot : eatPY = eatTY - eatCY * eatDot : eatPZ = eatTZ - eatCZ * eatDot
    eatPL = Sqr(eatPX * eatPX + eatPY * eatPY + eatPZ * eatPZ)
    If eatPL < 0.000001 Then Exit Sub
    ' the angle still to turn: if it is within the cap, take the target direction outright
    If eatDot > Cos(eatDeg * 3.14159265 / 180) Then
        eatCX = eatTX : eatCY = eatTY : eatCZ = eatTZ
    Else
        eatTn = Tan(eatDeg * 3.14159265 / 180)
        eatCX = eatCX + eatPX / eatPL * eatTn
        eatCY = eatCY + eatPY / eatPL * eatTn
        eatCZ = eatCZ + eatPZ / eatPL * eatTn
        eatM = Sqr(eatCX * eatCX + eatCY * eatCY + eatCZ * eatCZ)
        eatCX = eatCX / eatM : eatCY = eatCY / eatM : eatCZ = eatCZ / eatM
    End If
    eatVX = eatCX * eatSp : eatVY = eatCY * eatSp : eatVZ = eatCZ * eatSp
End Sub
