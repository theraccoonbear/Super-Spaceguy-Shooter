' impact.bas -- depth cues for incoming attacks (#26): when and where a shot reaches the
' player's depth, so the overlay can mark it and players can triage what to dodge.
' No rendering or game state here, so tests can drive it:
'
'   IMP_Predict sx,sy,sz, vx,vy,vz, playerX, frames, crossY, crossZ
'       frames = frames until the shot reaches playerX (-1 if it never will)
'   IMP_Threat%(crossY, crossZ, playerY, playerZ)   crosses close enough to need a ring
'   IMP_RingFrac!(frames, window)                   1 = ring wide open, 0 = impact now
'
' Straight-line prediction: homing shots re-predict every frame, so their ring drifts.
' Local variable prefix: imp*

Const IMP_RING_FRAMES = 90    ' a shot gets its ring this many frames before impact (1.5 s)
Const IMP_THREAT_R    = 2.5   ' world units: crossings farther from the player get no ring
Const IMP_RING_R_MIN  = 0.35  ' ring radius (world units) at impact
Const IMP_RING_R_MAX  = 1.8   ' ring radius when it first appears

Sub IMP_Predict(impSX As Single, impSY As Single, impSZ As Single, impVX As Single, impVY As Single, impVZ As Single, impPX As Single, impFrames As Single, impCY As Single, impCZ As Single)
    impFrames = -1 : impCY = impSY : impCZ = impSZ
    If impVX >= 0 Or impSX < impPX Then Exit Sub
    impFrames = (impPX - impSX) / impVX
    impCY = impSY + impVY * impFrames
    impCZ = impSZ + impVZ * impFrames
End Sub

Function IMP_Threat%(impTY As Single, impTZ As Single, impTPY As Single, impTPZ As Single)
    Dim impDY As Single, impDZ As Single
    impDY = impTY - impTPY : impDZ = impTZ - impTPZ
    IMP_Threat% = (impDY * impDY + impDZ * impDZ <= IMP_THREAT_R * IMP_THREAT_R)
End Function

Function IMP_RingFrac!(impRF As Single, impRW As Single)
    If impRF <= 0 Then
        IMP_RingFrac! = 0
    ElseIf impRF >= impRW Then
        IMP_RingFrac! = 1
    Else
        IMP_RingFrac! = impRF / impRW
    End If
End Function
