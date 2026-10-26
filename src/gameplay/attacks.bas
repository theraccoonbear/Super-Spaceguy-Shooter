' attacks.bas -- which attack a boss uses each volley (#26). A boss's attack= list in
' sequence.txt is its pool (cumulative across bosses: laser,spore / +cut / +devour); every
' volley picks ONE at random, never two at once. A special that just fired cools down,
' and picking it again during that time fires lasers instead. No rendering or game state
' here, so tests can drive it:
'
'   code = ATK_Pick%(pool$(), poolCnt, r)   r in [0, 1), e.g. Rnd
'   ATK_Fired code                          start that special's cooldown
'   ATK_Tick                                once per frame
'   ATK_Clear                               no cooldowns (boss spawn / reset)
'
' Local variable prefix: atk*

Const ATK_LASER  = 1
Const ATK_SPORE  = 2
Const ATK_CUT    = 3
Const ATK_DEVOUR = 4   ' attack C: parsed, not built yet, so never picked
Const ATK_COUNT  = 4
Const ATK_COOL_FRAMES = 240   ' 4 s before the same special can fire again

Dim Shared atkCool(1 To ATK_COUNT) As Integer

' attack= name -> ATK_* code; 0 for anything unknown.
Function ATK_Code%(atkName As String)
    Select Case UCase$(LTrim$(RTrim$(atkName)))
    Case "LASER"  : ATK_Code% = ATK_LASER
    Case "SPORE"  : ATK_Code% = ATK_SPORE
    Case "CUT"    : ATK_Code% = ATK_CUT
    Case "DEVOUR" : ATK_Code% = ATK_DEVOUR
    Case Else     : ATK_Code% = 0
    End Select
End Function

Function ATK_Built%(atkB As Integer)
    ATK_Built% = (atkB = ATK_LASER Or atkB = ATK_SPORE Or atkB = ATK_CUT)
End Function

Function ATK_Pick%(atkPool() As String, atkPoolCnt As Integer, atkR As Single)
    Dim atkI As Integer, atkN As Integer, atkC As Integer, atkWant As Integer
    For atkI = 0 To atkPoolCnt - 1
        If ATK_Built%(ATK_Code%(atkPool(atkI))) Then atkN = atkN + 1
    Next atkI
    ATK_Pick% = ATK_LASER
    If atkN = 0 Then Exit Function
    atkWant = Int(atkR * atkN)
    If atkWant >= atkN Then atkWant = atkN - 1
    If atkWant < 0 Then atkWant = 0
    For atkI = 0 To atkPoolCnt - 1
        atkC = ATK_Code%(atkPool(atkI))
        If ATK_Built%(atkC) Then
            If atkWant = 0 Then
                If atkCool(atkC) = 0 Then ATK_Pick% = atkC
                Exit Function
            End If
            atkWant = atkWant - 1
        End If
    Next atkI
End Function

Sub ATK_Fired(atkF As Integer)
    If atkF > ATK_LASER And atkF <= ATK_COUNT Then atkCool(atkF) = ATK_COOL_FRAMES
End Sub

Sub ATK_Tick
    Dim atkT As Integer
    For atkT = 1 To ATK_COUNT
        If atkCool(atkT) > 0 Then atkCool(atkT) = atkCool(atkT) - 1
    Next atkT
End Sub

Sub ATK_Clear
    Dim atkK As Integer
    For atkK = 1 To ATK_COUNT : atkCool(atkK) = 0 : Next atkK
End Sub
