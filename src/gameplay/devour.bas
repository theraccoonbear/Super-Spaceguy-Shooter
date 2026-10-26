' devour.bas -- boss attack C, "devour" (#26): after a short suction warning the boss
' drags the player toward its line of fire for a few seconds while it keeps shooting,
' so the player fights the drag and dodges at the same time. The pull is under the
' player's top speed (0.12/frame), so flying away still gains ground. No rendering or
' game state here, so tests can drive it:
'
'   DEV_Start phase                        begin (pull strength grows with boss phase)
'   DEV_Update                             once per frame: advance the timers
'   DEV_Pull playerY, playerZ, bossY, bossZ   this frame's pull -> devPullY / devPullZ
'   DEV_Busy%     warning or pulling (the boss starts no other special meanwhile)
'   DEV_Clear     stop everything
'
' The caller adds devPullY/devPullZ to the player's position. They're shared so boss
' aim can lead a player who is being dragged.
' Local variable prefix: dev*

Const DEV_WARN       = 45     ' frames of suction warning before the pull (0.75 s)
Const DEV_PULL_FRAMES = 180   ' frames of pull (3 s)
Const DEV_STRENGTH   = 0.06   ' pull per frame in boss phase 1 (player max is 0.12)
Const DEV_PHASE_STEP = 0.01   ' extra pull per boss phase after the first

Const DEV_ST_IDLE = 0
Const DEV_ST_WARN = 1
Const DEV_ST_PULL = 2

Dim Shared devStage As Integer, devT As Integer, devStr As Single
Dim Shared devPullY As Single, devPullZ As Single

Sub DEV_Start(devPhase As Integer)
    devStage = DEV_ST_WARN : devT = 0
    devStr = DEV_STRENGTH + DEV_PHASE_STEP * (devPhase - 1)
    devPullY = 0 : devPullZ = 0
End Sub

Sub DEV_Clear
    devStage = DEV_ST_IDLE : devT = 0 : devPullY = 0 : devPullZ = 0
End Sub

Function DEV_Busy%
    DEV_Busy% = (devStage <> DEV_ST_IDLE)
End Function

' 1 when the warning has just started, 0 the frame the pull begins.
Function DEV_WarnFrac!
    DEV_WarnFrac! = 1 - devT / DEV_WARN
End Function

Sub DEV_Update
    If devStage = DEV_ST_IDLE Then Exit Sub
    devT = devT + 1
    If devStage = DEV_ST_WARN Then
        If devT >= DEV_WARN Then devStage = DEV_ST_PULL : devT = 0
    ElseIf devT >= DEV_PULL_FRAMES Then
        DEV_Clear
    End If
End Sub

' Straight toward the boss's Y/Z at devStr, never past it (no jitter on the line).
Sub DEV_Pull(devPY As Single, devPZ As Single, devBY As Single, devBZ As Single)
    Dim devDY As Single, devDZ As Single, devM As Single, devS As Single
    devPullY = 0 : devPullZ = 0
    If devStage <> DEV_ST_PULL Then Exit Sub
    devDY = devBY - devPY : devDZ = devBZ - devPZ
    devM = Sqr(devDY * devDY + devDZ * devDZ)
    If devM < 0.0001 Then Exit Sub
    devS = devStr
    If devS > devM Then devS = devM
    devPullY = devDY / devM * devS
    devPullZ = devDZ / devM * devS
End Sub
