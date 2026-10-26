' impact.bas -- depth cues for incoming attacks (#26): when and where a shot reaches the
' player's depth, so the overlay can mark it and players can triage what to dodge.
' No rendering or game state here, so tests can drive it:
'
'   IMP_SeekStep sy,sz, vy,vz, targetY,targetZ, seek   one frame of homing (EBULLET_Update)
'   IMP_Predict sx,sy,sz, vx,vy,vz, playerX,playerY,playerZ, seek, frames, crossY, crossZ
'       frames = frames until the shot reaches playerX (-1 if it never will)
'   IMP_Threat%(crossY, crossZ, playerY, playerZ)   crosses close enough to need a ring
'   IMP_RingFrac!(frames, window)                   1 = ring wide open, 0 = impact now
'
' IMP_Predict flies the shot forward with the same IMP_SeekStep the game uses, against a
' player who stays put, so a ring only moves when the player does.
' Local variable prefix: imp*

Const IMP_RING_FRAMES = 60    ' a shot gets its ring this many frames before impact (1 s)
Const IMP_RING_MAX_N  = 3     ' at most this many rings at once: the soonest impacts
Const IMP_THREAT_R    = 2.5   ' world units: crossings farther from the player get no ring
Const IMP_RING_R_MIN  = 0.3   ' ring radius (world units) at impact
Const IMP_RING_R_MAX  = 0.9   ' ring radius when it first appears
Const IMP_SEEK_V      = 0.12  ' lateral speed homing steers toward
Const IMP_MAX_FRAMES  = 600   ' prediction horizon

Sub IMP_SeekStep(impKY As Single, impKZ As Single, impKVY As Single, impKVZ As Single, impKTY As Single, impKTZ As Single, impKS As Single)
    Dim impKDY As Single, impKDZ As Single, impKM As Single
    If impKS <= 0 Then Exit Sub
    impKDY = impKTY - impKY : impKDZ = impKTZ - impKZ
    impKM = Sqr(impKDY * impKDY + impKDZ * impKDZ)
    If impKM > 0.1 Then
        impKVY = impKVY + ((impKDY / impKM) * IMP_SEEK_V - impKVY) * impKS
        impKVZ = impKVZ + ((impKDZ / impKM) * IMP_SEEK_V - impKVZ) * impKS
    End If
End Sub

Sub IMP_Predict(impSX As Single, impSY As Single, impSZ As Single, impVX As Single, impVY As Single, impVZ As Single, impPX As Single, impPY As Single, impPZ As Single, impSeek As Single, impFrames As Single, impCY As Single, impCZ As Single)
    Dim impX As Single, impY As Single, impZ As Single, impVY2 As Single, impVZ2 As Single, impN As Integer
    impFrames = -1 : impCY = impSY : impCZ = impSZ
    If impVX >= 0 Or impSX < impPX Then Exit Sub
    impX = impSX : impY = impSY : impZ = impSZ : impVY2 = impVY : impVZ2 = impVZ
    Do While impX > impPX And impN < IMP_MAX_FRAMES
        IMP_SeekStep impY, impZ, impVY2, impVZ2, impPY, impPZ, impSeek
        impX = impX + impVX : impY = impY + impVY2 : impZ = impZ + impVZ2
        impN = impN + 1
    Loop
    If impX > impPX Then Exit Sub
    impFrames = impN : impCY = impY : impCZ = impZ
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
