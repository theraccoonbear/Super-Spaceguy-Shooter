' modelsheet.bas -- render enemy models with the game's own engine for the review sheets (#395)
'
'   modelsheet <outdir>
'
' For each enemy type it writes <outdir>/<old|new>_<type>_<near|far>_<view>.png at 320x240:
' views chase (the in-game camera), q3 (three-quarter), side, front (level, nose-on).
' "old" comes from assets/models.e3d, "new" from assets/models_enemies_v2.e3d.
' Needs a display for the software renderer; run it on Xvfb (tools/dev shell).
'
' Build: ./tools/buildqb tools/modelsheet.bas

Option _Explicit
$Resize:Stretch
$EMBED:'assets/models.e3d':'MODELS'
$EMBED:'assets/models_enemies_v2.e3d':'NEWMODELS'

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'

Const MS_W = 320
Const MS_H = 240
Const MS_TYPES = 6
Const MS_FOV = 72
Const MS_CAM_X = 6.72      ' CAM_CHASE_X in src/sys/dims.bas
Const MS_CAM_Y = 1.04      ' CAM_CHASE_Y
Const MS_LEAD = 8
Const MS_SCL = 1.1         ' mid of the 0.9..1.3 spawn range
Const MS_DIM_FAR = 55
Const MS_DIM_NEAR = 28
Const MS_DIM_AMB = 0.22

Dim msOld(1 To MS_TYPES) As String, msNew(1 To MS_TYPES) As String, msKey(1 To MS_TYPES) As String
msKey(1) = "solo"   : msOld(1) = "ENEMY"        : msNew(1) = "E2_SOLO"
msKey(2) = "arrow"  : msOld(2) = "ENEMY_ARROW"  : msNew(2) = "E2_ARROW"
msKey(3) = "hline"  : msOld(3) = "ENEMY_HLINE"  : msNew(3) = "E2_HLINE"
msKey(4) = "vcol"   : msOld(4) = "ENEMY_VCOL"   : msNew(4) = "E2_VCOL"
msKey(5) = "pincer" : msOld(5) = "ENEMY_PINCER" : msNew(5) = "E2_PINCER"
msKey(6) = "vwedge" : msOld(6) = "ENEMY_VWEDGE" : msNew(6) = "E2_VWEDGE"

Dim msOutDir As String
msOutDir = LTrim$(RTrim$(Command$))
If Len(msOutDir) = 0 Then Print "usage: modelsheet <outdir>" : System 2

Dim msBuf As Long, msI As Integer, msSet As Integer, msDist As Integer, msView As Integer
Screen _NewImage(MS_W, MS_H, 32)
msBuf = _NewImage(MS_W, MS_H, 32)

Dim msMesh As E3D_Mesh, msBox As E3D_AABB
Dim msData As String, msCam As E3D_Camera
Dim msView4 As E3D_Matrix4, msProj As E3D_Matrix4, msVP As E3D_Matrix4
Dim msPos As E3D_Coord, msRot As E3D_Coord, msObj As E3D_Matrix4
Dim msLit As E3D_Coord, msLightBase As E3D_Coord
Dim msD As Single, msDimF As Single, msR As Single
Dim msTag As String
Dim msEl As Single, msName As String, msViewName As String, msDistName As String
msLightBase.x = -0.4 : msLightBase.y = 0.7 : msLightBase.z = -0.5

For msSet = 1 To 2
    For msI = 1 To MS_TYPES
        If msSet = 1 Then
            msData = _Embedded$("MODELS") : msName = msOld(msI) : msTag = "old"
        Else
            msData = _Embedded$("NEWMODELS") : msName = msNew(msI) : msTag = "new"
        End If
        E3D_LoadMesh msData, msName, msMesh, msBox
        E3D_BakeMeshNormals msMesh
        If msMesh.fCount = 0 Then
            Print "missing mesh " + msName : System 2
        End If
        Print msTag + " " + msKey(msI) + " verts=" + LTrim$(Str$(msMesh.vCount)) + " faces=" + LTrim$(Str$(msMesh.fCount))
        For msDist = 1 To 2
            If msDist = 1 Then msD = 3 : msDistName = "near" Else msD = 25 : msDistName = "far"
            msDimF = 1.0
            If msD > MS_DIM_FAR Then
                msDimF = MS_DIM_AMB
            ElseIf msD > MS_DIM_NEAR Then
                msDimF = MS_DIM_AMB + (msD - MS_DIM_NEAR) * ((1.0 - MS_DIM_AMB) / (MS_DIM_FAR - MS_DIM_NEAR))
            End If
            msLit.x = msLightBase.x * msDimF : msLit.y = msLightBase.y * msDimF : msLit.z = msLightBase.z * msDimF
            msR = msD + MS_CAM_X
            For msView = 1 To 4
                Select Case msView
                    Case 1 : msViewName = "chase"
                    Case 2 : msViewName = "q3"    : msEl = 0.35
                    Case 3 : msViewName = "side"  : msEl = 0.12
                    Case 4 : msViewName = "front" : msEl = 0.0
                End Select
                msPos.x = msD : msPos.y = 0 : msPos.z = 0
                If msView = 1 Then
                    E3D_MakeCamera msCam, -MS_CAM_X, MS_CAM_Y, 0, MS_LEAD, 0, 0, MS_FOV
                Else
                    ' the enemies fly nose-first toward -X: front = level, nose-on; q3 = nose side, from the left;
                    ' side = from the left. All orbit the enemy at the chase distance.
                    If msView = 4 Then
                        E3D_MakeCamera msCam, msD - msR * Cos(msEl), msR * Sin(msEl), 0, msD, 0, 0, MS_FOV
                    ElseIf msView = 2 Then
                        E3D_MakeCamera msCam, msD - msR * Cos(msEl) * 0.7071, msR * Sin(msEl), msR * Cos(msEl) * 0.7071, msD, 0, 0, MS_FOV
                    Else
                        E3D_MakeCamera msCam, msD, msR * Sin(msEl), msR * Cos(msEl), msD, 0, 0, MS_FOV
                    End If
                End If
                msCam.nearZ = 0.1 : msCam.farZ = 120
                E3D_MatLookAt msCam, msView4
                E3D_MatPerspective msCam, MS_W / MS_H, msProj
                E3D_MatMul msProj, msView4, msVP
                _Dest msBuf
                Line (0, 0)-(MS_W - 1, MS_H - 1), _RGB(4, 5, 22), BF
                msRot.x = 0 : msRot.y = 0 : msRot.z = 0
                E3D_BuildObjectMat msPos, msRot, MS_SCL, msObj
                E3D_SceneBegin
                E3D_SceneAddMeshLit msMesh, msObj, msCam.pos, 0, msLit
                E3D_SceneFlush msVP, MS_W, MS_H
                _Dest 0
                _SaveImage msOutDir + "/" + msTag + "_" + msKey(msI) + "_" + msDistName + "_" + msViewName + ".png", msBuf
            Next msView
        Next msDist
    Next msI
Next msSet
System 0


' src/3d/input.bas logs via the game's DBG_Print (src/sys/debug.bas), which this tool doesn't include
Sub DBG_Print (msDbgMsg As String)
End Sub
