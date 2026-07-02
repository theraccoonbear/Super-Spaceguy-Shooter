' stress.bas — E3D engine stress test
' Spawns faceted spheres (32 faces each) to measure polygon throughput.
' Each sphere has a unique randomized color palette.
' Controls: = add sphere   - remove sphere   arrows orbit camera   ESC/Q quit

'$INCLUDE:'types.bi'
'$INCLUDE:'poly.bas'
'$INCLUDE:'matrix.bas'
'$INCLUDE:'camera.bas'
'$INCLUDE:'mesh.bas'
'$INCLUDE:'object.bas'
'$INCLUDE:'scene.bas'

Const SCR_W    = 320
Const SCR_H    = 240
Const BALL_MAX = 300  ' 300 × ~16 visible faces pushes well past 4000

Dim backBuffer As Long
Dim cam        As E3D_Camera
Dim viewMat    As E3D_Matrix4
Dim projMat    As E3D_Matrix4
Dim vpMat      As E3D_Matrix4
Dim objMat     As E3D_Matrix4
Dim spheres(1 To BALL_MAX) As E3D_Mesh
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

' --- generate one mesh per ball with a unique color seed ---
Randomize Timer
For i = 1 To BALL_MAX
    MakeSphere spheres(i), 1.8, Rnd * 6.283
Next i

' --- scatter positions and spin rates ---
For i = 1 To BALL_MAX
    ballPos(i).x  = (Rnd * 60) - 30
    ballPos(i).y  = (Rnd * 40) - 20
    ballPos(i).z  = (Rnd * 40) - 20
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
    If _KeyDown(19712) Then camAngle = camAngle + 0.03
    If _KeyDown(19200) Then camAngle = camAngle - 0.03
    If _KeyDown(18432) Then camH = camH + 0.25
    If _KeyDown(20480) Then camH = camH - 0.25

    ' --- add / remove (edge-triggered; And split to avoid non-short-circuit crash) ---
    If _KeyDown(61) Then
        If Not addWas Then
            If ballCount < BALL_MAX Then ballCount = ballCount + 1
        End If
        addWas = -1
    Else
        addWas = 0
    End If
    If _KeyDown(45) Then
        If Not remWas Then
            If ballCount > 1 Then ballCount = ballCount - 1
        End If
        remWas = -1
    Else
        remWas = 0
    End If

    ' --- spin ---
    For i = 1 To ballCount
        ballRot(i).x = ballRot(i).x + ballDRot(i).x
        ballRot(i).y = ballRot(i).y + ballDRot(i).y
        ballRot(i).z = ballRot(i).z + ballDRot(i).z
    Next i

    ' --- camera ---
    Dim camX As Single, camZ As Single
    camX = 45 * Cos(camAngle)
    camZ = 45 * Sin(camAngle)
    E3D_MakeCamera cam, camX, camH, camZ, 0, 0, 0, 72
    cam.nearZ = 0.5 : cam.farZ = 180
    E3D_MatLookAt cam, viewMat
    E3D_MatPerspective cam, SCR_W / SCR_H, projMat
    E3D_MatMul projMat, viewMat, vpMat

    ' --- render ---
    _Dest backBuffer
    Line (0, 0)-(SCR_W - 1, SCR_H - 1), _RGB(4, 4, 14), BF

    E3D_SceneBegin
    For i = 1 To ballCount
        E3D_BuildObjectMat ballPos(i), ballRot(i), 1.0, objMat
        E3D_SceneAddMeshLit spheres(i), objMat, cam.pos, tt, lightDir
    Next i
    E3D_SceneFlush vpMat, SCR_W, SCR_H

    ' --- stats overlay ---
    frameMs = (Timer - t0) * 1000
    If frameMs > 0.01 Then fps = CInt(1000 / frameMs) Else fps = 999

    If E3D_scnCount > 3000 Then
        polyClr = _RGB(255, 80, 60)
    ElseIf E3D_scnCount > 1500 Then
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
    Line (0, 0)-(SCR_W - 1, 56), _RGBA(0, 0, 0, 200), BF
    Color polyClr : _PrintString (2, 2),  "POLY  " + LTrim$(Str$(E3D_scnCount)) + " / " + LTrim$(Str$(E3D_SCENE_MAX))
    Color fpsClr  : _PrintString (2, 13), "FPS   " + LTrim$(Str$(fps))
    Color _RGB(140, 140, 160) : _PrintString (2, 24), "ms    " + Left$(Str$(frameMs + 1000), 6)
    Color _RGB(200, 200, 220) : _PrintString (2, 35), "BALLS " + LTrim$(Str$(ballCount)) + " / " + LTrim$(Str$(BALL_MAX))
    Color _RGB(160, 160, 130) : _PrintString (2, 46), "[=] add  [-] rem  [ESC/Q] quit"

    _Limit 60
    _Display

Loop Until _KeyDown(27) Or _KeyDown(113) Or _KeyDown(81)   ' ESC, q, Q

End

' ============================================================
' MakeSphere — 4 stacks × 8 slices = 32 faces, 26 verts
' hueShift rotates the color palette so each instance looks distinct.
' ============================================================
Sub MakeSphere (mesh As E3D_Mesh, radius As Single, hueShift As Single)
    Const ST = 4
    Const SL = 8

    Dim lat As Integer, lon As Integer
    Dim theta As Single, phi As Single
    Dim r As Integer, g As Integer, b As Integer
    Dim v1 As Integer, v2 As Integer, v3 As Integer, v4 As Integer
    Dim r0 As Integer, r1 As Integer, rb As Integer, pole As Integer
    Dim h As Single

    E3D_MakeMesh mesh

    ' top pole
    E3D_AddMeshVert mesh, 0, radius, 0

    ' latitude rings
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

    ' top cap triangles
    For lon = 0 To SL - 1
        v1 = 1
        v2 = 2 + lon
        v3 = 2 + (lon + 1) Mod SL
        h = hueShift + lon * _PI / 4
        r = 128 + 100 * Sin(h)
        g = 128 + 100 * Sin(h + 2.094)
        b = 128 + 100 * Sin(h + 4.189)
        E3D_AddTriFace mesh, v1, v2, v3, _RGB(r, g, b)
    Next lon

    ' mid band quads
    For lat = 0 To ST - 3
        r0 = 2 + lat * SL
        r1 = 2 + (lat + 1) * SL
        For lon = 0 To SL - 1
            v1 = r0 + lon
            v2 = r0 + (lon + 1) Mod SL
            v3 = r1 + (lon + 1) Mod SL
            v4 = r1 + lon
            h = hueShift + lat * 1.1 + lon * 0.8
            r = 128 + 100 * Sin(h)
            g = 128 + 100 * Sin(h + 2.094)
            b = 128 + 100 * Sin(h + 4.189)
            E3D_AddQuadFace mesh, v1, v2, v3, v4, _RGB(r, g, b)
        Next lon
    Next lat

    ' bottom cap triangles
    pole = mesh.vCount
    rb   = 2 + (ST - 2) * SL
    For lon = 0 To SL - 1
        v1 = pole
        v2 = rb + (lon + 1) Mod SL
        v3 = rb + lon
        h = hueShift + lon * 0.9 + 1.5
        r = 128 + 100 * Sin(h)
        g = 128 + 100 * Sin(h + 2.094)
        b = 128 + 100 * Sin(h + 4.189)
        E3D_AddTriFace mesh, v1, v2, v3, _RGB(r, g, b)
    Next lon

    E3D_BakeMeshNormals mesh
End Sub
