Const E3D_SCENE_MAX  = 8192
Const E3D_SCENE_VMAX = 8

Dim Shared E3D_scnVCount(1 To E3D_SCENE_MAX)                       As Integer
Dim Shared E3D_scnVX(1 To E3D_SCENE_MAX, 1 To E3D_SCENE_VMAX)     As Single
Dim Shared E3D_scnVY(1 To E3D_SCENE_MAX, 1 To E3D_SCENE_VMAX)     As Single
Dim Shared E3D_scnVZ(1 To E3D_SCENE_MAX, 1 To E3D_SCENE_VMAX)     As Single
Dim Shared E3D_scnClrs(1 To E3D_SCENE_MAX)                         As Long
Dim Shared E3D_scnDepths(1 To E3D_SCENE_MAX)                       As Single
Dim Shared E3D_scnOrder(1 To E3D_SCENE_MAX)                        As Integer
Dim Shared E3D_scnCount As Integer

' Per-mesh face workspace — Shared to avoid stack allocation for large meshes.
Dim Shared E3D_tmpPolys(1 To E3D_SCENE_MAX)  As E3D_Polygon
Dim Shared E3D_tmpClrs(1 To E3D_SCENE_MAX)   As Long
Dim Shared E3D_tmpDepths(1 To E3D_SCENE_MAX) As Single

Sub E3D_SceneBegin ()
    E3D_scnCount = 0
End Sub

Sub E3D_SceneAddMeshLit (mesh As E3D_Mesh, modelMat As E3D_Matrix4, camPos As E3D_Coord, tt As Single, lightDir As E3D_Coord)
    Dim fc As Integer, i As Integer, v As Integer, n As Integer, vc As Integer
    E3D_GetMeshFacesLit mesh, modelMat, camPos, tt, lightDir, E3D_tmpPolys(), E3D_tmpClrs(), E3D_tmpDepths(), fc
    For i = 1 To fc
        If E3D_scnCount < E3D_SCENE_MAX Then
            E3D_scnCount = E3D_scnCount + 1
            n = E3D_scnCount
            vc = E3D_tmpPolys(i).count
            E3D_scnVCount(n) = vc
            For v = 1 To vc
                E3D_scnVX(n, v) = E3D_tmpPolys(i).coords(v).x
                E3D_scnVY(n, v) = E3D_tmpPolys(i).coords(v).y
                E3D_scnVZ(n, v) = E3D_tmpPolys(i).coords(v).z
            Next v
            E3D_scnClrs(n)   = E3D_tmpClrs(i)
            E3D_scnDepths(n) = E3D_tmpDepths(i)
            E3D_scnOrder(n)  = n
        End If
    Next i
End Sub

Sub E3D_SceneFlush (vpMat As E3D_Matrix4, scrW As Single, scrH As Single)
    E3D_ZBufClear CInt(scrW), CInt(scrH)
    Dim didSwap As Integer, scI As Integer
    Dim oi1 As Integer, oi2 As Integer, oiTmp As Integer
    Dim facePoly As E3D_Polygon, screenPoly As E3D_Polygon
    Dim di As Integer, v As Integer, vc As Integer
    Dim c As E3D_Coord

    ' Insertion sort — O(n) on nearly-sorted data (typical between frames).
    ' Guard and array access are split across two lines because QB64-PE And
    ' is bitwise (no short-circuit): the array subscript would be evaluated
    ' even when oi1=0, causing a subscript-out-of-range crash.
    For scI = 2 To E3D_scnCount
        oiTmp = E3D_scnOrder(scI)
        oi1 = scI - 1
        Do While oi1 >= 1
            If E3D_scnDepths(E3D_scnOrder(oi1)) >= E3D_scnDepths(oiTmp) Then Exit Do
            E3D_scnOrder(oi1 + 1) = E3D_scnOrder(oi1)
            oi1 = oi1 - 1
        Loop
        E3D_scnOrder(oi1 + 1) = oiTmp
    Next scI

    For scI = 1 To E3D_scnCount
        di = E3D_scnOrder(scI)
        vc = E3D_scnVCount(di)
        E3D_MakePolygon facePoly
        For v = 1 To vc
            c.x = E3D_scnVX(di, v)
            c.y = E3D_scnVY(di, v)
            c.z = E3D_scnVZ(di, v)
            E3D_AddCoord facePoly, c
        Next v
        E3D_ProjectPoly facePoly, vpMat, scrW, scrH, screenPoly
        E3D_DrawPoly screenPoly, E3D_scnClrs(di)
    Next scI
End Sub
