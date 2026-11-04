' roster_test.bas -- per-level enemy introduction (#136)
'
' Drives src/gameplay/roster.bas with the real assets/sequence.txt and assets/config/enemies.ini:
'   1. the shipped combat levels: every roster parses, each level adds one type, the first level
'      has no debut and the later ones debut arrow, hline, pincer and vwedge in that order
'   2. ROS_Parse: names, case, an unknown name, an empty list
'   3. ROS_Enter: a missing or bad roster is every type with no debut; a debut needs both rosters
'   4. ROS_Pick: only roster types, never the previous one while another is left, debut weighting
'   5. SEQ_PrevRoster$ skips boss, asteroid and scripted PLAY lines
'   6. debut_weight: shipped value, bad values refused, dev nudges clamp
'
' Build: tools/dev test (builds and runs every test)
' Run:   builds/roster_test   (exit 0 = all pass)

$CONSOLE:ONLY
Option _Explicit

$EMBED:'assets/sequence.txt':'SEQTXT'
$EMBED:'assets/config/enemies.ini':'CFGENEMIES'

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'seq_stubs.bi'
'$INCLUDE:'../src/sys/sequence.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/gameplay/enemyatk.bas'
'$INCLUDE:'../src/gameplay/roster.bas'

Dim Shared roPassed As Integer, roFailed As Integer

Print "=== roster_test ==="

Sub RO_Assert (roOK As Integer, roName As String)
    If roOK Then
        Print "PASS  " + roName
        roPassed = roPassed + 1
    Else
        Print "FAIL  " + roName
        roFailed = roFailed + 1
    End If
End Sub

Function RO_Bits% (roM As Integer)
    Dim roT As Integer, roN As Integer
    For roT = 0 To EAT_TYPES - 1
        If (roM And (2 ^ roT)) <> 0 Then roN = roN + 1
    Next roT
    RO_Bits% = roN
End Function

' Share of 1000 evenly spaced rolls that land on type roT.
Function RO_Share! (roPrev As Integer, roW As Single, roT As Integer)
    Dim roK As Integer, roHit As Integer
    For roK = 0 To 999
        If ROS_Pick%(roPrev, roW, (roK + 0.5) / 1000) = roT Then roHit = roHit + 1
    Next roK
    RO_Share! = roHit / 1000
End Function

Dim roI As Integer, roN As Integer, roLast As Integer, roOK As Integer, roDebuts As String
Dim roPrevMask As Integer, roT As Integer, roSeen As Integer, roW As Single

' 1
SEQ_Load _EMBEDDED$("SEQTXT")
RO_Assert seqLoadErr = "", "shipped sequence.txt loads"
roOK = -1 : roPrevMask = 0 : roDebuts = ""
For roI = 0 To seqCount - 1
    If seqKind(roI) = SEQ_PLAY Then
        If LCase$(SEQ_GetKV$(seqSval$(roI), "type")) = "combat" And Len(SEQ_GetKV$(seqSval$(roI), "script")) = 0 Then
            roN = roN + 1
            If ROS_Parse%(SEQ_GetKV$(seqSval$(roI), "roster")) <= 0 Then roOK = 0
            ROS_Enter SEQ_GetKV$(seqSval$(roI), "roster"), SEQ_PrevRoster$(roI)
            If roPrevMask = 0 Then
                If rosDebut <> 0 Then roOK = 0
            Else
                If (rosMask And roPrevMask) <> roPrevMask Or RO_Bits%(rosDebut) <> 1 Then roOK = 0
            End If
            If rosDebut <> 0 Then roDebuts = roDebuts + EAT_TypeName$(ROS_FirstDebut%) + " "
            roPrevMask = rosMask
        End If
    End If
Next roI
RO_Assert roN = 5, "five combat levels carry a roster"
RO_Assert roOK, "every roster parses, keeps the earlier types, and adds exactly one (none on the first level)"
RO_Assert roDebuts = "arrow hline pincer vwedge ", "debuts in threat order: " + roDebuts
RO_Assert rosMask = ROS_ALL, "the last combat level sends every type"
SEQ_Load _EMBEDDED$("SEQTXT")
For roI = 0 To seqCount - 1
    If seqKind(roI) = SEQ_PLAY Then
        If LCase$(SEQ_GetKV$(seqSval$(roI), "type")) = "combat" And Len(SEQ_GetKV$(seqSval$(roI), "script")) = 0 Then
            If roSeen = 0 Then ROS_Enter SEQ_GetKV$(seqSval$(roI), "roster"), "" : roSeen = 1
        End If
    End If
Next roI
RO_Assert RO_Bits%(rosMask) = 2 And (rosMask And 1) <> 0 And (rosMask And 8) <> 0, "level 1 starts with two types, solo and vcol"

' 2
RO_Assert ROS_Parse%("solo,vcol") = 9, "solo,vcol is bits 0 and 3"
RO_Assert ROS_Parse%("VWedge") = 32, "names are case-insensitive"
RO_Assert ROS_Parse%("") = 0, "an empty list is no types"
RO_Assert ROS_Parse%("solo,boss") = -1 And rosBadName = "boss", "an unknown name is refused and named"
RO_Assert ROS_Parse%("solo,,vcol") = -1, "an empty entry is refused"

' 3
ROS_Enter "", "solo"
RO_Assert rosMask = ROS_ALL And rosDebut = 0, "no roster: every type, no debut"
ROS_Enter "solo,nope", "solo"
RO_Assert rosMask = ROS_ALL And rosDebut = 0, "a bad roster: every type, no debut"
ROS_Enter "solo,arrow", ""
RO_Assert rosMask = 3 And rosDebut = 0, "no previous roster: no debut"
ROS_Enter "solo,arrow", "solo,vcol"
RO_Assert rosMask = 3 And rosDebut = 2 And ROS_FirstDebut% = 1, "arrow is the debut over solo,vcol"
ROS_Enter "solo,vcol,arrow", "solo,vcol,arrow"
RO_Assert rosDebut = 0 And ROS_FirstDebut% = -1, "the same roster twice has no debut"

' 4
ROS_Enter "solo,vcol,arrow", "solo,vcol"
roOK = -1
For roI = 0 To 99
    roT = ROS_Pick%(-1, 3, roI / 100)
    If (rosMask And (2 ^ roT)) = 0 Then roOK = 0
Next roI
RO_Assert roOK, "a pick is always a roster type"
roOK = -1
For roI = 0 To 99
    If ROS_Pick%(1, 3, roI / 100) = 1 Then roOK = 0
Next roI
RO_Assert roOK, "the previous type is never picked again"
RO_Assert Abs(RO_Share!(0, 3, 1) - 0.75) < 0.005, "debut weight 3 against one other: arrow 3 in 4"
RO_Assert Abs(RO_Share!(-1, 3, 1) - 0.6) < 0.005, "debut weight 3 against two others: arrow 3 in 5"
RO_Assert Abs(RO_Share!(-1, 1, 1) - 1 / 3) < 0.005, "weight 1 is an even mix"
RO_Assert Abs(RO_Share!(1, 3, 0) - 0.5) < 0.005 And Abs(RO_Share!(1, 3, 3) - 0.5) < 0.005, "without the debut type the others split evenly"
ROS_Enter "solo", ""
RO_Assert ROS_Pick%(0, 3, 0.5) = 0, "a one-type roster repeats rather than stall"
ROS_Enter "solo,vcol", "solo,vcol"
RO_Assert ROS_Pick%(0, 3, 0.1) = 3 And ROS_Pick%(3, 3, 0.9) = 0, "a two-type roster alternates"
ROS_Enter "solo,arrow,hline", "solo,arrow"
RO_Assert Abs(RO_Share!(1, 4, 2) - 0.8) < 0.005, "the debut hline carries the weight: 4 in 5 against one other"

' 5
SEQ_Load "a:" + Chr$(10) + "    PLAY type=combat roster=solo,vcol" + Chr$(10) + "    PLAY type=boss mus=b" + Chr$(10) + "    PLAY type=asteroid" + Chr$(10) + "    PLAY type=combat script=tutorial" + Chr$(10) + "    PLAY type=combat roster=solo,arrow" + Chr$(10) + "    NEXT end" + Chr$(10)
RO_Assert SEQ_PrevRoster$(4) = "solo,vcol", "the previous roster skips boss, asteroid and scripted PLAY lines"
RO_Assert SEQ_PrevRoster$(0) = "", "the first combat PLAY has no previous roster"

' 6
RO_Assert EAT_Load%(_EMBEDDED$("CFGENEMIES")), "shipped enemies.ini loads" + eatLoadErr
RO_Assert eatDebutW = 3, "shipped debut_weight is 3"
RO_Assert EAT_Load%("debut_weight=0.5") = 0 And InStr(eatLoadErr, "debut_weight") > 0, "debut_weight below 1 is refused with its key named"
RO_Assert EAT_Load%("debut_weight=11") = 0, "debut_weight above 10 is refused"
RO_Assert EAT_Load%("solo_shots=1") And eatDebutW = EAT_DEBUT_DEFAULT, "a missing debut_weight is the default"
EAT_SetDebutW 99 : RO_Assert eatDebutW = 10, "debut weight clamps at 10"
EAT_SetDebutW 0 : RO_Assert eatDebutW = 1, "debut weight clamps at 1"
EAT_SetDebutW 3 + EAT_DEBUT_STEP : RO_Assert eatDebutW = 3.25, "a nudge is a quarter"

Print
Print "roster_test: passed"; roPassed; " failed"; roFailed
If roFailed > 0 Then System 1
System 0
