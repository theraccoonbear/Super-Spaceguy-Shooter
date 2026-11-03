' roster.bas -- which enemy formation types a combat level sends, and which it debuts (#136)
'
' A combat PLAY line in assets/sequence.txt names its types with roster=a,b,... (the type
' names of assets/config/enemies.ini). A type in the roster that the previous combat level's
' roster lacks is a debut: the level's first wave is that type, and it is picked
' debut_weight times as often (assets/config/enemies.ini) for the rest of the level.
' A type is a bit of a mask: bit t is the type number of EAT_TypeName$ (solo 0 ... vwedge 5).
' No game state beyond rosMask and rosDebut, so tests/roster_test.bas drives it.
'
'   m = ROS_Parse%(csv$)           mask of the names; -1 if a name is unknown (rosBadName)
'   ROS_Enter roster$, prev$       set rosMask and rosDebut for a level; an empty or bad roster is
'                                  every type, and no debut unless both rosters are given
'   t = ROS_FirstDebut%          the debut type (lowest number), -1 if the level has none
'   t = ROS_Pick%(prev, w, r)      a type of the mix for r in 0..1: never prev while another
'                                  type is left, a debut type w times as likely
' Local variable prefix: ros*

Const ROS_ALL = 63

Dim Shared rosMask As Integer, rosDebut As Integer
Dim Shared rosBadName As String

Function ROS_Parse% (rosCsv As String)
    Dim rosT As Integer, rosM As Integer, rosOK As Integer
    Dim rosS As Integer, rosC As Integer, rosName As String
    rosBadName = ""
    rosM = 0
    rosS = 1
    Do While rosS <= Len(rosCsv)
        rosC = InStr(rosS, rosCsv, ",")
        If rosC = 0 Then rosC = Len(rosCsv) + 1
        rosName = LCase$(Mid$(rosCsv, rosS, rosC - rosS))
        rosOK = 0
        For rosT = 0 To EAT_TYPES - 1
            If EAT_TypeName$(rosT) = rosName Then rosM = rosM Or (2 ^ rosT) : rosOK = -1
        Next rosT
        If rosOK = 0 Then rosBadName = rosName : ROS_Parse% = -1 : Exit Function
        rosS = rosC + 1
    Loop
    ROS_Parse% = rosM
End Function

Sub ROS_Enter (rosRoster As String, rosPrev As String)
    Dim rosM As Integer, rosPM As Integer
    rosM = ROS_Parse%(rosRoster)
    If rosM <= 0 Then rosM = ROS_ALL : rosPM = 0 Else rosPM = ROS_Parse%(rosPrev)
    If rosPM <= 0 Then rosPM = 0 : rosDebut = 0 Else rosDebut = rosM And (ROS_ALL - rosPM)
    rosMask = rosM
End Sub

Function ROS_FirstDebut%
    Dim rosT As Integer
    ROS_FirstDebut% = -1
    For rosT = 0 To EAT_TYPES - 1
        If (rosDebut And (2 ^ rosT)) <> 0 Then ROS_FirstDebut% = rosT : Exit Function
    Next rosT
End Function

Function ROS_Pick% (rosPrev As Integer, rosW As Single, rosR As Single)
    Dim rosT As Integer, rosTotal As Single, rosAcc As Single, rosWt As Single, rosLast As Integer
    Dim rosSkip As Integer, rosX As Single
    rosSkip = rosPrev
    If rosMask = 0 Or rosMask = (2 ^ rosPrev) Then rosSkip = -1
    rosLast = -1
    For rosT = 0 To EAT_TYPES - 1
        If (rosMask And (2 ^ rosT)) <> 0 And rosT <> rosSkip Then
            If (rosDebut And (2 ^ rosT)) <> 0 Then rosTotal = rosTotal + rosW Else rosTotal = rosTotal + 1
            rosLast = rosT
        End If
    Next rosT
    rosX = rosR * rosTotal
    For rosT = 0 To EAT_TYPES - 1
        If (rosMask And (2 ^ rosT)) <> 0 And rosT <> rosSkip Then
            If (rosDebut And (2 ^ rosT)) <> 0 Then rosWt = rosW Else rosWt = 1
            rosAcc = rosAcc + rosWt
            If rosX < rosAcc Then ROS_Pick% = rosT : Exit Function
        End If
    Next rosT
    ROS_Pick% = rosLast
End Function
