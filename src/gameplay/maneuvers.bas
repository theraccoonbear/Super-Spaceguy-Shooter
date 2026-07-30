' maneuvers.bas -- boss flight-path data loader
'
' MNV_Init  : call once at startup with the embedded maneuvers.txt content
' MNV_Load  : parse a named [block] into the bsmWp* arrays (behavior.bas)
'             sets bsmFlySpd; Z values are unsigned, caller applies bsmTurnDir sign

Dim Shared mnvRawData As String

Sub MNV_Init(mnviData As String)
    mnvRawData = mnviData
End Sub

Sub MNV_Load(mnvlName As String)
    Dim mnvldI As Integer, mnvldNL As Integer
    Dim mnvldRaw As String, mnvldLine As String
    Dim mnvldHdr As String, mnvldRest As String
    Dim mnvldSp As Integer
    Dim mnvldCapture As Integer

    bsmWpCount   = 0
    bsmFlySpd    = 0.025     ' fallback if speed= line is missing
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

        If LCase$(Left$(mnvldLine, 6)) = "speed=" Then
            bsmFlySpd = Val(Mid$(mnvldLine, 7))
            GoTo mnvldNext
        End If

        If bsmWpCount <= 15 Then
            mnvldSp = InStr(mnvldLine, " ")
            If mnvldSp > 0 Then
                bsmWpX(bsmWpCount) = Val(Left$(mnvldLine, mnvldSp))
                mnvldRest = LTrim$(Mid$(mnvldLine, mnvldSp))
                mnvldSp   = InStr(mnvldRest, " ")
                If mnvldSp > 0 Then
                    bsmWpY(bsmWpCount) = Val(Left$(mnvldRest, mnvldSp))
                    bsmWpZ(bsmWpCount) = Val(Mid$(mnvldRest, mnvldSp))
                    bsmWpCount = bsmWpCount + 1
                End If
            End If
        End If

        mnvldNext:
    Loop
End Sub
