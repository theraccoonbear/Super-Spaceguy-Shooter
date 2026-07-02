' stress.bas — E3D engine stress test
' Spawns faceted spheres (32 faces each) to measure polygon throughput.
' Controls: = add sphere   - remove sphere   arrows orbit camera   Q quit

'$INCLUDE:'types.bi'
'$INCLUDE:'poly.bas'
'$INCLUDE:'matrix.bas'
'$INCLUDE:'camera.bas'
'$INCLUDE:'mesh.bas'
'$INCLUDE:'object.bas'
'$INCLUDE:'scene.bas'

Const SCR_W    = 320
Const SCR_H    = 240
Const BALL_MAX = 28   ' 28 × ~16 visible faces ≈ 448 polys — right at E3D_SCENE_MAX

Dim backBuffer As Long
Dim cam        As E3D_Camera
Dim viewMat    As E3D_Matrix4
Dim projMat    As E3D_Matrix4
Dim vpMat      As E3D_Matrix4
Dim objMat     As E3D_Matrix4
Dim sphere     As E3D_Mesh
Dim ballPos(1 To BALL_MAX)  As E3D_Coord
Dim ballRot(1 To BALL_MAX)  As E3D_Coord
Dim ballDRot(1 To BALL_MAX) As E3D_Coord
Dim ballCount  As Integer
Dim lightDir   As E3D_Coord
Dim camAngle   As Single
Dim camH       As Single
Dim tt         As Single
Dim t0         As Double
Dim frameMs    As Single
Dim i          As Integer
Dim addWas     As Integer
Dim remWas     As Integer
Dim fps        As Integer
Dim polyClr    As Long
Dim fpsClr     As Long

Screen _NewImage(SCR_W, SCR_H, 32)
_Title "SSS Stress Test"
backBuffer = _NewImage(SCR_W, SCR_H, 32)

lightDir.x = 0.577 : lightDir.y = 0.577 : lightDir.z = -0.577

' --- generate sphere mesh: 4 stacks × 8 slices = 32 faces, 26 verts ---
MakeSphere sphere, 1.8

' --- scatter ball positions and spin rates ---
Randomize Timer
For i = 1 To BALL_MAX
    ballPos(i).x  = (Rnd * 32) - 16
    ballPos(i).y  = (Rnd * 20) - 10
    ballPos(i).z  = (Rnd * 20) - 10
    ballDRot(i).x = (Rnd - 0.5) * 0.05
    ballDRot(i).y = (Rnd - 0.5) * 0.06
    ballDRot(i).z = (Rnd - 0.5) * 0.04
Next i

ballCount = 3
camAngle  = 0
camH      = 5

' ============================================================
' MAIN LOOP
' ============================================================
Do
    t0 = Timer
    tt = tt + 0.016

    ' --- camera orbit ---
    If _KeyDown(19712) Then camAngle = camAngle + 0.03   ' right
    If _KeyDown(19200) Then camAngle = camAngle - 0.03   ' left
    If _KeyDown(18432) Then camH = camH + 0.25           ' up
    If _KeyDown(20480) Then camH = camH - 0.25           ' down

    ' --- add / remove (edge-triggered) ---
    If _KeyDown(61) Then       ' = key
        If Not addWas Then
            If ballCount < BALL_MAX Then ballCount = ballCount + 1
        End If
        addWas = -1
    Else
        addWas = 0
    End If
    If _KeyDown(45) Then       ' - key
        If Not remWas Then
            If ballCount > 1 Then ballCount = ballCount - 1
        End If
        remWas = -1
    Else
        remWas = 0
    End If

    ' --- spin each ball ---
    For i = 1 To ballCount
        ballRot(i).x = ballRot(i).x + ballDRot(i).x
        ballRot(i).y = ballRot(i).y + ballDRot(i).y
        ballRot(i).z = ballRot(i).z + ballDRot(i).z
    Next i

    ' --- build VP matrix ---
    Dim camX As Single, camZ As Single
    camX = 28 * Cos(camAngle)
    camZ = 28 * Sin(camAngle)
    E3D_MakeCamera cam, camX, camH, camZ, 0, 0, 0, 72
    cam.nearZ = 0.5 : cam.farZ = 120
    E3D_MatLookAt cam, viewMat
    E3D_MatPerspective cam, SCR_W / SCR_H, projMat
    E3D_MatMul projMat, viewMat, vpMat

    ' --- render ---
    _Dest backBuffer
    Line (0, 0)-(SCR_W - 1, SCR_H - 1), _RGB(4, 4, 14), BF

    E3D_SceneBegin
    For i = 1 To ballCount
        E3D_BuildObjectMat ballPos(i), ballRot(i), 1.0, objMat
        E3D_SceneAddMeshLit sphere, objMat, cam.pos, tt, lightDir
    Next i
    E3D_SceneFlush vpMat, SCR_W, SCR_H

    ' --- stats overlay ---
    frameMs = (Timer - t0) * 1000
    If frameMs > 0.01 Then fps = CInt(1000 / frameMs) Else fps = 999

    If E3D_scnCount > 350 Then
        polyClr = _RGB(255, 80, 60)
    ElseIf E3D_scnCount > 200 Then
        polyClr = _RGB(255, 210, 50)
    Else
        polyClr = _RGB(80, 210, 80)
    End If
    If fps < 30 Then
        fpsClr = _RGB(255, 80, 60)
    ElseIf fps < 50 Then
        fpsClr = _RGB(255, 210, 50)
    Else
        fpsClr = _RGB(80, 210, 80)
    End If

    _Dest 0
    _PutImage , backBuffer, 0
    Line (0, 0)-(145, 45), _RGBA(0, 0, 0, 200), BF
    Color polyClr : _PrintString (2, 2),  "POLY  " + LTrim$(Str$(E3D_scnCount)) + " / 450"
    Color fpsClr  : _PrintString (2, 13), "FPS   " + LTrim$(Str$(fps))
    Color _RGB(140, 140, 160) : _PrintString (2, 24), "ms    " + Left$(Str$(frameMs + 1000), 6)
    Color _RGB(200, 200, 220) : _PrintString (2, 35), "BALLS " + LTrim$(Str$(ballCount)) + "  [=] add  [-] rem"

    _Limit 60
    _Display

Loop Until _KeyDown(113) Or _KeyDown(81)   ' q / Q

End

' ============================================================
' MakeSphere — 4 stacks × 8 slices: 26 verts, 32 faces
' ============================================================
Sub MakeSphere (mesh As E3D_Mesh, radius As Single)
    Const ST = 4   ' stacks
    Const SL = 8   ' slices

    Dim lat As Integer, lon As Integer
    Dim theta As Single, phi As Single
    Dim r As Integer, g As Integer, b As Integer
    Dim v1 As Integer, v2 As Integer, v3 As Integer, v4 As Integer
    Dim r0 As Integer, r1 As Integer, rb As Integer, pole As Integer

    E3D_MakeMesh mesh

    ' top pole
    E3D_AddMeshVert mesh, 0, radius, 0

    ' latitude rings 1 .. ST-1
    For lat = 1 To ST - 1
        theta = _PI * lat / ST
        For lon = 0 To SL - 1
            phi = 2 * _PI * lon / SL
            E3D_AddMeshVert mesh, _
                radius * Sin(theta) * Cos(phi), _
                radius * Cos(theta), _
                radius * Sin(theta) * Sin(phi)
        Next lon
    Next lat

    ' bottom pole
    E3D_AddMeshVert mesh, 0, -radius, 0

    ' top cap — triangles from pole (v1) into ring 1 (v2..v9)
    For lon = 0 To SL - 1
        v1 = 1
        v2 = 2 + lon
        v3 = 2 + (lon + 1) Mod SL
        r = 180 + 60 * Sin(lon * _PI / 4)
        g = 100 + 60 * Sin(lon * _PI / 4 + 2.094)
        b = 140 + 80 * Sin(lon * _PI / 4 + 4.189)
        E3D_AddTriFace mesh, v1, v2, v3, _RGB(r, g, b)
    Next lon

    ' mid bands — quads between adjacent rings
    For lat = 0 To ST - 3
        r0 = 2 + lat * SL
        r1 = 2 + (lat + 1) * SL
        For lon = 0 To SL - 1
            v1 = r0 + lon
            v2 = r0 + (lon + 1) Mod SL
            v3 = r1 + (lon + 1) Mod SL
            v4 = r1 + lon
            r = 140 + 80 * Abs(Sin(lat * 1.6 + lon * 0.8))
            g = 120 + 80 * Abs(Sin(lat * 1.6 + lon * 0.8 + 2.094))
            b = 160 + 70 * Abs(Sin(lat * 1.6 + lon * 0.8 + 4.189))
            E3D_AddQuadFace mesh, v1, v2, v3, v4, _RGB(r, g, b)
        Next lon
    Next lat

    ' bottom cap — triangles from last ring into bottom pole
    pole = mesh.vCount
    rb   = 2 + (ST - 2) * SL
    For lon = 0 To SL - 1
        v1 = pole
        v2 = rb + (lon + 1) Mod SL
        v3 = rb + lon
        r = 120 + 80 * Abs(Sin(lon * 0.9))
        g = 150 + 70 * Abs(Sin(lon * 0.9 + 2.094))
        b = 180 + 60 * Abs(Sin(lon * 0.9 + 4.189))
        E3D_AddTriFace mesh, v1, v2, v3, _RGB(r, g, b)
    Next lon

    E3D_BakeMeshNormals mesh
End Sub
