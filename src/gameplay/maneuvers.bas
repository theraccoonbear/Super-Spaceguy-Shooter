' maneuvers.bas -- boss flight-path data loader
'
' MNV_Init  : call once at startup with the embedded maneuvers.txt content
' MNV_Load  : parse a named [block] into the bsmWp* arrays (behavior.bas)
'             sets bsmFlySpd; Z values are unsigned, caller applies bsmTurnDir sign

Dim Shared mnvRawData As String

Sub MNV_Init(mnviData As String)
    mnvRawData = mnviData
End Sub

Sub MNV_ListBlocks(mnvlbNames() As String, mnvlbCount As Integer)
    mnvlbCount = 0
    Dim mnvlbI As Integer, mnvlbNL As Integer
    Dim mnvlbRaw As String, mnvlbLine As String, mnvlbClose As Integer
    mnvlbI = 1
    Do While mnvlbI <= Len(mnvRawData)
        mnvlbNL = InStr(mnvlbI, mnvRawData, Chr$(10))
        If mnvlbNL = 0 Then mnvlbNL = Len(mnvRawData) + 1
        mnvlbRaw  = Mid$(mnvRawData, mnvlbI, mnvlbNL - mnvlbI)
        mnvlbI    = mnvlbNL + 1
        If Right$(mnvlbRaw, 1) = Chr$(13) Then mnvlbRaw = Left$(mnvlbRaw, Len(mnvlbRaw) - 1)
        mnvlbLine = LTrim$(RTrim$(mnvlbRaw))
        If Left$(mnvlbLine, 1) = "[" Then
            mnvlbClose = InStr(mnvlbLine, "]")
            If mnvlbClose > 2 And mnvlbCount <= 15 Then
                mnvlbNames(mnvlbCount) = Mid$(mnvlbLine, 2, mnvlbClose - 2)
                mnvlbCount = mnvlbCount + 1
            End If
        End If
    Loop
End Sub

Sub MNV_Load(mnvlName As String)
    Dim mnvldI As Integer, mnvldNL As Integer
    Dim mnvldRaw As String, mnvldLine As String
    Dim mnvldHdr As String, mnvldRest As String
    Dim mnvldSp As Integer
    Dim mnvldCapture As Integer
    Dim mnvldOrV As String   ' value side of orient= key
    Dim mnvldJ As Integer    ' roll-array clear loop counter
    Dim mnvldScale As Single ' scale= multiplier applied to all waypoint coords

    bsmWpCount   = 0
    bsmFlySpd    = 0.025     ' fallback if speed= line is missing
    bsmClosed    = 0
    bsmStandoff  = 0
    mnvldScale   = 1.0
    bsmOrientMode = 0
    bsmTargetX   = 0 : bsmTargetY = 0 : bsmTargetZ = 0
    For mnvldJ = 0 To BSM_WP_MAX - 1
        bsmPathRoll(mnvldJ) = 0 : bsmCraftRoll(mnvldJ) = 0
    Next mnvldJ
    mnvldCapture = 0
    mnvldI       = 1

    Do While mnvldI <= Len(mnvRawData)
        mnvldNL  = InStr(mnvldI, mnvRawData, Chr$(10))
        If mnvldNL = 0 Then mnvldNL = Len(mnvRawData) + 1
        mnvldRaw  = Mid$(mnvRawData, mnvldI, mnvldNL - mnvldI)
        mnvldI    = mnvldNL + 1
        If Right$(mnvldRaw, 1) = Chr$(13) Then mnvldRaw = Left$(mnvldRaw, Len(mnvldRaw) - 1)
        mnvldLine = LTrim$(RTrim$(mnvldRaw))
        If Len(mnvldLine) = 0 Or Left$(mnvldLine, 1) = "#" Then GoTo mnvldNext

        If Left$(mnvldLine, 1) = "[" Then
            If mnvldCapture Then Exit Do       ' new section: done
            mnvldHdr     = Mid$(mnvldLine, 2, InStr(mnvldLine, "]") - 2)
            mnvldCapture = (LCase$(mnvldHdr) = LCase$(mnvlName))
            GoTo mnvldNext
        End If

        If mnvldCapture = 0 Then GoTo mnvldNext

        ' ── Key=value lines ──────────────────────────────────────────────
        If LCase$(Left$(mnvldLine, 6)) = "speed=" Then
            bsmFlySpd = Val(Mid$(mnvldLine, 7))
            GoTo mnvldNext
        End If

        If LCase$(Left$(mnvldLine, 9)) = "standoff=" Then
            bsmStandoff = Val(Mid$(mnvldLine, 10))
            GoTo mnvldNext
        End If

        If LCase$(Left$(mnvldLine, 6)) = "scale=" Then
            mnvldScale = Val(Mid$(mnvldLine, 7))
            If mnvldScale < 0.001 Then mnvldScale = 1.0
            GoTo mnvldNext
        End If

        If LCase$(Left$(mnvldLine, 7)) = "closed=" Then
            bsmClosed = Val(Mid$(mnvldLine, 8))
            GoTo mnvldNext
        End If

        If LCase$(Left$(mnvldLine, 7)) = "orient=" Then
            mnvldOrV = Mid$(mnvldLine, 8)
            If LCase$(Left$(mnvldOrV, 7)) = "target:" Then
                bsmOrientMode = 1
                mnvldRest = Mid$(mnvldOrV, 8)          ' "x,y,z"
                mnvldSp   = InStr(mnvldRest, ",")
                If mnvldSp > 0 Then
                    bsmTargetX = Val(Left$(mnvldRest, mnvldSp))
                    mnvldRest  = Mid$(mnvldRest, mnvldSp + 1)
                    mnvldSp    = InStr(mnvldRest, ",")
                    If mnvldSp > 0 Then
                        bsmTargetY = Val(Left$(mnvldRest, mnvldSp))
                        bsmTargetZ = Val(Mid$(mnvldRest, mnvldSp + 1))
                    End If
                End If
            Else
                bsmOrientMode = 0
            End If
            GoTo mnvldNext
        End If

        ' ── Waypoint line: X Y Z [pathRoll [craftRoll]] ─────────────────
        If bsmWpCount < BSM_WP_MAX Then
            mnvldSp = InStr(mnvldLine, " ")
            If mnvldSp > 0 Then
                bsmWp(bsmWpCount).x = Val(Left$(mnvldLine, mnvldSp)) * mnvldScale
                mnvldRest = LTrim$(Mid$(mnvldLine, mnvldSp))  ' "Y Z [pR [cR]]"
                mnvldSp   = InStr(mnvldRest, " ")
                If mnvldSp > 0 Then
                    bsmWp(bsmWpCount).y = Val(Left$(mnvldRest, mnvldSp)) * mnvldScale
                    mnvldRest = LTrim$(Mid$(mnvldRest, mnvldSp)) ' "Z [pR [cR]]"
                    mnvldSp   = InStr(mnvldRest, " ")
                    If mnvldSp > 0 Then
                        bsmWp(bsmWpCount).z = Val(Left$(mnvldRest, mnvldSp)) * mnvldScale
                        mnvldRest = LTrim$(Mid$(mnvldRest, mnvldSp)) ' "[pR [cR]]"
                        mnvldSp   = InStr(mnvldRest, " ")
                        If mnvldSp > 0 Then
                            bsmPathRoll(bsmWpCount)  = Val(Left$(mnvldRest, mnvldSp))
                            bsmCraftRoll(bsmWpCount) = Val(LTrim$(Mid$(mnvldRest, mnvldSp)))
                        ElseIf Len(mnvldRest) > 0 Then
                            bsmPathRoll(bsmWpCount) = Val(mnvldRest)
                        End If
                    Else
                        bsmWp(bsmWpCount).z = Val(mnvldRest) * mnvldScale  ' Z is last token
                    End If
                    bsmWpCount = bsmWpCount + 1
                End If
            End If
        End If

        mnvldNext:
    Loop
End Sub
