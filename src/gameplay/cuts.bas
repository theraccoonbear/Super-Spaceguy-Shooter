' cuts.bas -- boss attack B, "the cut" (#26): a chain of telegraphed beams. Each cut
' flashes a warning line through where the player is, then fires a band across the
' whole play plane at the player's depth; changing lanes out of the band dodges it.
' Cuts alternate horizontal / vertical. No rendering or game state here, so tests can
' drive it:
'
'   CUT_Start count, horizFirst, playerX, playerY, playerZ   begin a chain
'   dmg = CUT_Update%(playerX, playerY, playerZ)               once per frame
'   CUT_Busy%    a chain is running (the boss holds other attacks meanwhile)
'   CUT_Clear    stop everything
'
' The caller applies the damage (and honours invTimer), the same as other hazards.
' Local variable prefix: cut*

Const CUT_WARN  = 60    ' frames of warning line before a cut fires (1 s)
Const CUT_LIVE  = 24    ' frames the beam is live
Const CUT_GAP   = 12    ' frames between one cut ending and the next warning
Const CUT_HALF  = 0.9   ' world-unit half-width of the band (player moves 0.12/frame)
Const CUT_DEPTH = 1.5   ' hurts within this many units of its depth (X)
Const CUT_DMG   = 8     ' shield damage, once per cut
Const CUT_SPAN  = 14    ' world-unit half-length, for drawing

Const CUT_ST_IDLE = 0
Const CUT_ST_WARN = 1
Const CUT_ST_LIVE = 2
Const CUT_ST_GAP  = 3

Dim Shared cutStage As Integer, cutT As Integer, cutLeft As Integer
Dim Shared cutHoriz As Integer, cutHit As Integer
Dim Shared cutX As Single, cutY As Single, cutZ As Single

Sub CUT_Start(cutN As Integer, cutH As Integer, cutSX As Single, cutSY As Single, cutSZ As Single)
    If cutN < 1 Then Exit Sub
    cutLeft = cutN
    cutHoriz = cutH
    CUT_Aim cutSX, cutSY, cutSZ
End Sub

Sub CUT_Aim(cutAX As Single, cutAY As Single, cutAZ As Single)
    cutStage = CUT_ST_WARN : cutT = 0 : cutHit = 0
    cutX = cutAX : cutY = cutAY : cutZ = cutAZ
End Sub

Sub CUT_Clear
    cutStage = CUT_ST_IDLE : cutT = 0 : cutLeft = 0 : cutHit = 0
End Sub

Function CUT_Busy%
    CUT_Busy% = (cutStage <> CUT_ST_IDLE)
End Function

' 1 when a warning line has just appeared, 0 the frame the beam fires.
Function CUT_WarnFrac!
    CUT_WarnFrac! = 1 - cutT / CUT_WARN
End Function

Function CUT_Update%(cutPX As Single, cutPY As Single, cutPZ As Single)
    Dim cutIn As Integer
    CUT_Update% = 0
    If cutStage = CUT_ST_IDLE Then Exit Function
    cutT = cutT + 1
    Select Case cutStage
    Case CUT_ST_WARN
        If cutT >= CUT_WARN Then cutStage = CUT_ST_LIVE : cutT = 0
    Case CUT_ST_LIVE
        If cutHoriz Then cutIn = (Abs(cutPY - cutY) <= CUT_HALF) Else cutIn = (Abs(cutPZ - cutZ) <= CUT_HALF)
        If cutIn And cutHit = 0 And Abs(cutPX - cutX) <= CUT_DEPTH Then
            cutHit = -1
            CUT_Update% = CUT_DMG
        End If
        If cutT >= CUT_LIVE Then
            cutLeft = cutLeft - 1
            If cutLeft > 0 Then cutStage = CUT_ST_GAP : cutT = 0 Else CUT_Clear
        End If
    Case CUT_ST_GAP
        If cutT >= CUT_GAP Then
            cutHoriz = (cutHoriz = 0)
            CUT_Aim cutPX, cutPY, cutPZ
        End If
    End Select
End Function
