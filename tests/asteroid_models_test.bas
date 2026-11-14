' asteroid_models_test.bas -- the v2 asteroid shapes (#436): assets/models_asteroids_v2.e3d and AST_ShapeFor%
'
' Reads the committed file the way the game embeds it and checks each A2_* mesh: the face count is
' inside the budget in tools/gen_asteroid_models.bas, the aabb line is the vertex extents, every face
' points away from the centre of its part, the RMS vertex radius is the old asteroid's (so on-screen size
' is unchanged), and the four silhouettes differ (the shard long, the rest near-equal on all axes).
' Also AST_ShapeFor%: always a valid shape, all shapes turn up, no RNG draw.
'
' Build: ./tools/buildqb tests/asteroid_models_test.bas
' Run:   builds/asteroid_models_test    (from the repo root; exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
'$INCLUDE:'../src/sys/failfast.bi'
$EMBED:'assets/models_asteroids_v2.e3d':'ASTMODELS'

Sub DBG_Print (amtDbg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/gameplay/asteroidshape.bas'

Const AMT_RMS = 0.62

Dim Shared amtPassed As Integer, amtFailed As Integer
Dim Shared amtVX(1 To 200) As Single, amtVY(1 To 200) As Single, amtVZ(1 To 200) As Single
Dim Shared amtFV(1 To 200, 1 To 3) As Integer
Dim Shared amtVN As Integer, amtFN As Integer
Dim Shared amtBX As Single, amtBY As Single, amtBZ As Single
Dim Shared amtMaxX(1 To 4) As Single, amtMaxY(1 To 4) As Single, amtMaxZ(1 To 4) As Single

Sub AMT_Assert (amtaCond As Integer, amtaName As String)
    If amtaCond Then
        Print "PASS  " + amtaName
        amtPassed = amtPassed + 1
    Else
        Print "FAIL  " + amtaName
        amtFailed = amtFailed + 1
    End If
End Sub

' Parses mesh amtlName from the embedded file into amtVX.., amtFV, and the aabb line into amtBX..
Sub AMT_Load (amtlName As String)
    Dim amtlData As String, amtlLn As String, amtlRest As String, amtlTok As String
    Dim amtlFound As Integer, amtlSp As Integer, amtlA As Integer, amtlB As Integer, amtlC As Integer
    Dim amtlX As Single, amtlY As Single, amtlZ As Single
    amtlData = _EMBEDDED$("ASTMODELS")
    amtVN = 0 : amtFN = 0 : amtBX = 0 : amtBY = 0 : amtBZ = 0
    Do While Len(amtlData) > 0
        E3D_NextLine amtlData, amtlLn
        amtlLn = LTrim$(RTrim$(amtlLn))
        If Len(amtlLn) > 0 And Left$(amtlLn, 1) <> "#" Then
            amtlSp = InStr(amtlLn, " ")
            If amtlSp = 0 Then
                amtlTok = amtlLn : amtlRest = ""
            Else
                amtlTok = Left$(amtlLn, amtlSp - 1) : amtlRest = LTrim$(Mid$(amtlLn, amtlSp + 1))
            End If
            If amtlFound = 0 Then
                If amtlTok = "o" And amtlRest = amtlName Then amtlFound = -1
            Else
                Select Case amtlTok
                    Case "end"
                        Exit Do
                    Case "aabb"
                        E3D_TokF amtlRest, amtBX : E3D_TokF amtlRest, amtBY : E3D_TokF amtlRest, amtBZ
                    Case "v"
                        E3D_TokF amtlRest, amtlX : E3D_TokF amtlRest, amtlY : E3D_TokF amtlRest, amtlZ
                        amtVN = amtVN + 1
                        amtVX(amtVN) = amtlX : amtVY(amtVN) = amtlY : amtVZ(amtVN) = amtlZ
                    Case "f"
                        E3D_TokI amtlRest, amtlA : E3D_TokI amtlRest, amtlB : E3D_TokI amtlRest, amtlC
                        amtFN = amtFN + 1
                        amtFV(amtFN, 1) = amtlA : amtFV(amtFN, 2) = amtlB : amtFV(amtFN, 3) = amtlC
                End Select
            End If
        End If
    Loop
End Sub

Function AMT_Near% (amtnA As Single, amtnB As Single, amtnTol As Single)
    AMT_Near% = (Abs(amtnA - amtnB) <= amtnTol)
End Function

' Faces whose normal points toward the centre of their part (parts share no vertices, so a part is a connected set of faces).
Function AMT_InwardFaces%
    Dim amtiLab(1 To 200) As Integer, amtiChg As Integer, amtiI As Integer, amtiK As Integer, amtiM As Integer
    Dim amtiCX(1 To 200) As Single, amtiCY(1 To 200) As Single, amtiCZ(1 To 200) As Single, amtiCnt(1 To 200) As Integer
    Dim amtiFx As Single, amtiFy As Single, amtiFz As Single, amtiNx As Single, amtiNy As Single, amtiNz As Single
    Dim amtiE1x As Single, amtiE1y As Single, amtiE1z As Single, amtiE2x As Single, amtiE2y As Single, amtiE2z As Single
    Dim amtiBad As Integer, amtiL As Integer
    For amtiI = 1 To amtVN : amtiLab(amtiI) = amtiI : Next amtiI
    Do
        amtiChg = 0
        For amtiI = 1 To amtFN
            amtiM = amtiLab(amtFV(amtiI, 1))
            For amtiK = 2 To 3
                If amtiLab(amtFV(amtiI, amtiK)) < amtiM Then amtiM = amtiLab(amtFV(amtiI, amtiK))
            Next amtiK
            For amtiK = 1 To 3
                If amtiLab(amtFV(amtiI, amtiK)) <> amtiM Then amtiLab(amtFV(amtiI, amtiK)) = amtiM : amtiChg = -1
            Next amtiK
        Next amtiI
    Loop While amtiChg
    For amtiI = 1 To amtVN
        amtiL = amtiLab(amtiI)
        amtiCX(amtiL) = amtiCX(amtiL) + amtVX(amtiI) : amtiCY(amtiL) = amtiCY(amtiL) + amtVY(amtiI) : amtiCZ(amtiL) = amtiCZ(amtiL) + amtVZ(amtiI)
        amtiCnt(amtiL) = amtiCnt(amtiL) + 1
    Next amtiI
    For amtiI = 1 To amtFN
        amtiL = amtiLab(amtFV(amtiI, 1))
        amtiFx = (amtVX(amtFV(amtiI, 1)) + amtVX(amtFV(amtiI, 2)) + amtVX(amtFV(amtiI, 3))) / 3 - amtiCX(amtiL) / amtiCnt(amtiL)
        amtiFy = (amtVY(amtFV(amtiI, 1)) + amtVY(amtFV(amtiI, 2)) + amtVY(amtFV(amtiI, 3))) / 3 - amtiCY(amtiL) / amtiCnt(amtiL)
        amtiFz = (amtVZ(amtFV(amtiI, 1)) + amtVZ(amtFV(amtiI, 2)) + amtVZ(amtFV(amtiI, 3))) / 3 - amtiCZ(amtiL) / amtiCnt(amtiL)
        amtiE1x = amtVX(amtFV(amtiI, 2)) - amtVX(amtFV(amtiI, 1)) : amtiE1y = amtVY(amtFV(amtiI, 2)) - amtVY(amtFV(amtiI, 1)) : amtiE1z = amtVZ(amtFV(amtiI, 2)) - amtVZ(amtFV(amtiI, 1))
        amtiE2x = amtVX(amtFV(amtiI, 3)) - amtVX(amtFV(amtiI, 1)) : amtiE2y = amtVY(amtFV(amtiI, 3)) - amtVY(amtFV(amtiI, 1)) : amtiE2z = amtVZ(amtFV(amtiI, 3)) - amtVZ(amtFV(amtiI, 1))
        amtiNx = amtiE1y * amtiE2z - amtiE1z * amtiE2y
        amtiNy = amtiE1z * amtiE2x - amtiE1x * amtiE2z
        amtiNz = amtiE1x * amtiE2y - amtiE1y * amtiE2x
        If amtiNx * amtiFx + amtiNy * amtiFy + amtiNz * amtiFz <= 0 Then amtiBad = amtiBad + 1
    Next amtiI
    AMT_InwardFaces% = amtiBad
End Function

Sub AMT_CheckMesh (amtcIdx As Integer, amtcName As String, amtcBudget As Integer)
    Dim amtcI As Integer, amtcHx As Single, amtcHy As Single, amtcHz As Single, amtcSq As Single, amtcRms As Single
    AMT_Load amtcName
    AMT_Assert amtFN > 0 And amtVN > 0, amtcName + ": has vertices and faces"
    AMT_Assert amtFN <= amtcBudget, amtcName + ": faces" + Str$(amtFN) + " within the budget of" + Str$(amtcBudget)
    For amtcI = 1 To amtVN
        If Abs(amtVX(amtcI)) > amtcHx Then amtcHx = Abs(amtVX(amtcI))
        If Abs(amtVY(amtcI)) > amtcHy Then amtcHy = Abs(amtVY(amtcI))
        If Abs(amtVZ(amtcI)) > amtcHz Then amtcHz = Abs(amtVZ(amtcI))
        amtcSq = amtcSq + amtVX(amtcI) ^ 2 + amtVY(amtcI) ^ 2 + amtVZ(amtcI) ^ 2
    Next amtcI
    AMT_Assert AMT_Near%(amtBX, amtcHx, .001) And AMT_Near%(amtBY, amtcHy, .001) And AMT_Near%(amtBZ, amtcHz, .001), amtcName + ": aabb line is the vertex extents"
    AMT_Assert AMT_InwardFaces% = 0, amtcName + ": every face points away from its part's centre"
    amtcRms = Sqr(amtcSq / amtVN)
    AMT_Assert Abs(amtcRms - AMT_RMS) <= AMT_RMS * .1, amtcName + ": RMS radius" + Str$(Int(amtcRms * 1000) / 1000) + " within 10% of" + Str$(AMT_RMS)
    amtMaxX(amtcIdx) = amtBX : amtMaxY(amtcIdx) = amtBY : amtMaxZ(amtcIdx) = amtBZ
End Sub

Function AMT_Ratio! (amtrIdx As Integer)
    Dim amtrHi As Single, amtrLo As Single
    amtrHi = amtMaxX(amtrIdx) : amtrLo = amtMaxX(amtrIdx)
    If amtMaxY(amtrIdx) > amtrHi Then amtrHi = amtMaxY(amtrIdx)
    If amtMaxZ(amtrIdx) > amtrHi Then amtrHi = amtMaxZ(amtrIdx)
    If amtMaxY(amtrIdx) < amtrLo Then amtrLo = amtMaxY(amtrIdx)
    If amtMaxZ(amtrIdx) < amtrLo Then amtrLo = amtMaxZ(amtrIdx)
    AMT_Ratio! = amtrHi / amtrLo
End Function

Sub AMT_CheckDistinct
    Dim amtdI As Integer, amtdJ As Integer, amtdSame As Integer
    AMT_Assert AMT_Ratio!(2) >= 1.5, "A2_SHARD is elongated: max/min extent" + Str$(Int(AMT_Ratio!(2) * 100) / 100) + " >= 1.5"
    AMT_Assert AMT_Ratio!(1) <= 1.3, "A2_CHUNK is near-equal on all axes: max/min extent" + Str$(Int(AMT_Ratio!(1) * 100) / 100) + " <= 1.3"
    AMT_Assert AMT_Ratio!(3) <= 1.3, "A2_CRATER is near-equal on all axes: max/min extent" + Str$(Int(AMT_Ratio!(3) * 100) / 100) + " <= 1.3"
    AMT_Assert AMT_Ratio!(4) <= 1.3, "A2_SPLIT is near-equal on all axes: max/min extent" + Str$(Int(AMT_Ratio!(4) * 100) / 100) + " <= 1.3"
    For amtdI = 1 To 3
        For amtdJ = amtdI + 1 To 4
            amtdSame = (Abs(amtMaxX(amtdI) - amtMaxX(amtdJ)) < .01 And Abs(amtMaxY(amtdI) - amtMaxY(amtdJ)) < .01 And Abs(amtMaxZ(amtdI) - amtMaxZ(amtdJ)) < .01)
            AMT_Assert amtdSame = 0, "shapes" + Str$(amtdI) + " and" + Str$(amtdJ) + " have different extents"
        Next amtdJ
    Next amtdI
End Sub

Sub AMT_CheckPick
    Dim amtpI As Integer, amtpS As Integer, amtpDry As Single, amtpBad As Integer
    Dim amtpHits(0 To AST_SHAPES - 1) As Integer, amtpAll As Integer, amtpState As _Unsigned Long
    RNG_Seed 1
    For amtpI = 1 To 1000
        amtpDry = (RNG!(RNG_GAME) - 0.5) * 2
        amtpS = AST_ShapeFor%(amtpDry)
        If amtpS < 0 Or amtpS > AST_SHAPES - 1 Then amtpBad = amtpBad + 1 Else amtpHits(amtpS) = amtpHits(amtpS) + 1
    Next amtpI
    AMT_Assert amtpBad = 0, "AST_ShapeFor% stays in 0.." + LTrim$(Str$(AST_SHAPES - 1)) + " over 1000 seeded draws"
    amtpAll = -1
    For amtpS = 0 To AST_SHAPES - 1
        If amtpHits(amtpS) = 0 Then amtpAll = 0
    Next amtpS
    AMT_Assert amtpAll <> 0, "every shape is picked over 1000 seeded draws:" + Str$(amtpHits(0)) + Str$(amtpHits(1)) + Str$(amtpHits(2)) + Str$(amtpHits(3))
    AMT_Assert AST_ShapeFor%(-1) >= 0 And AST_ShapeFor%(-1) < AST_SHAPES And AST_ShapeFor%(.999999) >= 0 And AST_ShapeFor%(.999999) < AST_SHAPES, "AST_ShapeFor% is valid at both ends of the spin range"
    amtpState = rngState(RNG_GAME)
    amtpS = AST_ShapeFor%(.3)
    AMT_Assert rngState(RNG_GAME) = amtpState, "AST_ShapeFor% draws no random number"
End Sub

Print "=== asteroid_models_test ==="
AMT_CheckMesh 1, "A2_CHUNK", 36
AMT_CheckMesh 2, "A2_SHARD", 50
AMT_CheckMesh 3, "A2_CRATER", 64
AMT_CheckMesh 4, "A2_SPLIT", 48
AMT_CheckDistinct
AMT_CheckPick

Print "passed:" + Str$(amtPassed) + "  failed:" + Str$(amtFailed)
If amtFailed > 0 Then System 1
System 0
