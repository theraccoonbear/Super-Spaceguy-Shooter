' spores.bas -- boss attack A, "spore bloom" (#26): slow clouds that drift from the boss
' to the player's depth, linger there and hurt while the player stays inside, so the
' player has to keep moving. No rendering or game state here, so tests can drive it:
'
'   SPORE_Spawn fromX, fromY, fromZ, toX, toY, toZ   launch one cloud at a point
'   dmg = SPORE_Update%(playerX, playerY, playerZ)    once per frame; damage to apply
'   SPORE_Clear                                       remove every cloud
'
' The caller applies the damage (and honours invTimer), the same as other hazards.
' Parallel arrays, not a UDT array: writes to UDT arrays from included-file Subs don't
' reliably reach the global (see player.bas).
' Local variable prefix: spr*

Const SPORE_MAX          = 8
Const SPORE_DRIFT_FRAMES = 150   ' boss -> player depth (2.5 s)
Const SPORE_LINGER       = 240   ' frames hanging at the player's depth (4 s)
Const SPORE_FADE         = 40    ' last frames of the linger: shrinking, harmless
Const SPORE_R_START      = 0.6   ' world-unit radius at launch
Const SPORE_R_MAX        = 2.2   ' radius once it arrives (player moves 0.12/frame)
Const SPORE_DEPTH        = 1.5   ' hurts within this many units of its depth (X)
Const SPORE_TICK         = 30    ' frames between damage ticks per cloud (0.5 s)
Const SPORE_DMG          = 4     ' shield damage per tick

Dim Shared sporeActive(1 To SPORE_MAX) As Integer
Dim Shared sporeAge(1 To SPORE_MAX) As Integer
Dim Shared sporeTick(1 To SPORE_MAX) As Integer
Dim Shared sporeX0(1 To SPORE_MAX) As Single, sporeY0(1 To SPORE_MAX) As Single, sporeZ0(1 To SPORE_MAX) As Single
Dim Shared sporeX1(1 To SPORE_MAX) As Single, sporeY1(1 To SPORE_MAX) As Single, sporeZ1(1 To SPORE_MAX) As Single
Dim Shared sporeX(1 To SPORE_MAX) As Single, sporeY(1 To SPORE_MAX) As Single, sporeZ(1 To SPORE_MAX) As Single
Dim Shared sporeR(1 To SPORE_MAX) As Single

' Launches one cloud; does nothing if all SPORE_MAX are in the air.
Sub SPORE_Spawn(sprFX As Single, sprFY As Single, sprFZ As Single, sprTX As Single, sprTY As Single, sprTZ As Single)
    Dim sprI As Integer
    For sprI = 1 To SPORE_MAX
        If sporeActive(sprI) = 0 Then
            sporeActive(sprI) = -1 : sporeAge(sprI) = 0 : sporeTick(sprI) = 0
            sporeX0(sprI) = sprFX : sporeY0(sprI) = sprFY : sporeZ0(sprI) = sprFZ
            sporeX1(sprI) = sprTX : sporeY1(sprI) = sprTY : sporeZ1(sprI) = sprTZ
            sporeX(sprI) = sprFX : sporeY(sprI) = sprFY : sporeZ(sprI) = sprFZ
            sporeR(sprI) = SPORE_R_START
            Exit Sub
        End If
    Next sprI
End Sub

Sub SPORE_Clear
    Dim sprCI As Integer
    For sprCI = 1 To SPORE_MAX : sporeActive(sprCI) = 0 : Next sprCI
End Sub

Function SPORE_Count%
    Dim sprNI As Integer, sprN As Integer
    For sprNI = 1 To SPORE_MAX
        If sporeActive(sprNI) Then sprN = sprN + 1
    Next sprNI
    SPORE_Count% = sprN
End Function

' Advances every cloud one frame and returns the shield damage the player takes this
' frame from clouds they're inside (each cloud ticks at most once per SPORE_TICK).
Function SPORE_Update%(sprPX As Single, sprPY As Single, sprPZ As Single)
    Dim sprU As Integer, sprT As Single, sprDmg As Integer, sprDY As Single, sprDZ As Single, sprLeft As Integer
    For sprU = 1 To SPORE_MAX
        If sporeActive(sprU) Then
            sporeAge(sprU) = sporeAge(sprU) + 1
            If sporeAge(sprU) <= SPORE_DRIFT_FRAMES Then
                ' ease out: fast off the boss, settling as it arrives
                sprT = sporeAge(sprU) / SPORE_DRIFT_FRAMES
                sprT = 1 - (1 - sprT) * (1 - sprT)
                sporeX(sprU) = sporeX0(sprU) + (sporeX1(sprU) - sporeX0(sprU)) * sprT
                sporeY(sprU) = sporeY0(sprU) + (sporeY1(sprU) - sporeY0(sprU)) * sprT
                sporeZ(sprU) = sporeZ0(sprU) + (sporeZ1(sprU) - sporeZ0(sprU)) * sprT
                sporeR(sprU) = SPORE_R_START + (SPORE_R_MAX - SPORE_R_START) * sprT
            Else
                sporeX(sprU) = sporeX1(sprU) : sporeY(sprU) = sporeY1(sprU) : sporeZ(sprU) = sporeZ1(sprU)
                sprLeft = SPORE_DRIFT_FRAMES + SPORE_LINGER - sporeAge(sprU)
                If sprLeft <= 0 Then
                    sporeActive(sprU) = 0
                ElseIf sprLeft < SPORE_FADE Then
                    sporeR(sprU) = SPORE_R_MAX * sprLeft / SPORE_FADE
                Else
                    sporeR(sprU) = SPORE_R_MAX
                End If
            End If
            If sporeTick(sprU) > 0 Then sporeTick(sprU) = sporeTick(sprU) - 1
            If sporeActive(sprU) And SPORE_Hurts%(sprU) Then
                If Abs(sporeX(sprU) - sprPX) <= SPORE_DEPTH Then
                    sprDY = sporeY(sprU) - sprPY : sprDZ = sporeZ(sprU) - sprPZ
                    If sprDY * sprDY + sprDZ * sprDZ <= sporeR(sprU) * sporeR(sprU) And sporeTick(sprU) = 0 Then
                        sprDmg = sprDmg + SPORE_DMG
                        sporeTick(sprU) = SPORE_TICK
                    End If
                End If
            End If
        End If
    Next sprU
    SPORE_Update% = sprDmg
End Function

' True while cloud sprH can hurt: from arrival until its fade-out starts.
Function SPORE_Hurts%(sprH As Integer)
    SPORE_Hurts% = (sporeAge(sprH) > SPORE_DRIFT_FRAMES And sporeAge(sprH) < SPORE_DRIFT_FRAMES + SPORE_LINGER - SPORE_FADE)
End Function
