' outline.bas -- silhouette outlines for meshes (#195)
'
' An outline is the mesh's silhouette edges drawn as lines after the faces. An edge is a silhouette
' when one of its two faces faces the camera and the other faces away, or when it has one face
' (a boundary edge) and that face faces the camera. Creases between two front faces are not drawn.
'
'   E3D_BuildMeshEdges mesh      once per mesh after loading: finds each edge's two faces and stores
'                                them in the shared edge pool (mesh.eStart, mesh.eCount index it)
'   E3D_OutlineConfig% on$, color$, width$
'                                parses the tunables (assets/config/render.ini); 0 + E3D_outlineErr on a bad value
'   E3D_OutlineCollect mesh      each frame, right after E3D_GetMeshFacesLit (which fills E3D_faceFront and
'                                E3D_meshWorldVerts): appends the mesh's silhouette edges to the scene
'   E3D_OutlineDraw vpMat, w, h  after the faces are drawn: projects, clips and draws them, hidden where
'                                E3D_zBuf holds something nearer
'
' Edge identity ignores vertex indices: vertices at the same position are one vertex (a mesh converted
' from an OBJ can split a vertex per face, which would otherwise make every seam look like a boundary).
' An edge shared by more than two faces keeps its first two; the rest are ignored.

Const E3D_EDGE_POOL = 16384
Const E3D_SCNEDGE_MAX = 8192
Const E3D_OUTLINE_BIAS = 0.0006
Const E3D_WELD_EPS = 0.00001

Dim Shared E3D_edgeA(1 To E3D_EDGE_POOL) As Integer
Dim Shared E3D_edgeB(1 To E3D_EDGE_POOL) As Integer
Dim Shared E3D_edgeF1(1 To E3D_EDGE_POOL) As Integer
Dim Shared E3D_edgeF2(1 To E3D_EDGE_POOL) As Integer
Dim Shared E3D_edgeNext(1 To E3D_EDGE_POOL) As Integer
Dim Shared E3D_edgeUsed As Integer
Dim Shared E3D_edgeNonManifold As Integer
Dim Shared E3D_edgeCanon(1 To E3D_MESH_VMAX) As Integer
Dim Shared E3D_edgeHead(1 To E3D_MESH_VMAX) As Integer


Dim Shared E3D_scnEdgeCount As Integer
Dim Shared E3D_scnEdge(1 To E3D_SCNEDGE_MAX, 1 To 6) As Single

Dim Shared E3D_outlineOn As Integer
Dim Shared E3D_outlineClr As Long
Dim Shared E3D_outlineWidth As Integer
Dim Shared E3D_outlineErr As String

Sub E3D_BuildMeshEdges (mesh As E3D_Mesh)
    Dim i As Integer, j As Integer, fi As Integer, k As Integer, n As Integer
    Dim va As Integer, vb As Integer, ca As Integer, cb As Integer, lo As Integer, hi As Integer
    Dim e As Integer, found As Integer

    For i = 1 To mesh.vCount
        E3D_edgeCanon(i) = i
        E3D_edgeHead(i) = 0
        For j = 1 To i - 1
            If Abs(mesh.verts(i).x - mesh.verts(j).x) < E3D_WELD_EPS Then
                If Abs(mesh.verts(i).y - mesh.verts(j).y) < E3D_WELD_EPS Then
                    If Abs(mesh.verts(i).z - mesh.verts(j).z) < E3D_WELD_EPS Then
                        E3D_edgeCanon(i) = j
                        Exit For
                    End If
                End If
            End If
        Next j
    Next i

    mesh.eStart = E3D_edgeUsed + 1
    For fi = 1 To mesh.fCount
        n = mesh.faces(fi).vCount
        For k = 1 To n
            va = mesh.faces(fi).vIdx(k)
            vb = mesh.faces(fi).vIdx((k Mod n) + 1)
            ca = E3D_edgeCanon(va)
            cb = E3D_edgeCanon(vb)
            If ca <> cb Then
                If ca < cb Then lo = ca : hi = cb Else lo = cb : hi = ca
                found = 0
                e = E3D_edgeHead(lo)
                Do While e > 0
                    If E3D_edgeCanon(E3D_edgeA(e)) + E3D_edgeCanon(E3D_edgeB(e)) = lo + hi Then
                        If E3D_edgeCanon(E3D_edgeA(e)) = lo Or E3D_edgeCanon(E3D_edgeB(e)) = lo Then found = e : Exit Do
                    End If
                    e = E3D_edgeNext(e)
                Loop
                If found > 0 Then
                    If E3D_edgeF2(found) = 0 And E3D_edgeF1(found) <> fi Then
                        E3D_edgeF2(found) = fi
                    Else
                        E3D_edgeNonManifold = E3D_edgeNonManifold + 1
                    End If
                Else
                    If E3D_edgeUsed >= E3D_EDGE_POOL Then
                        _Dest _Console
                        Print "E3D_BuildMeshEdges: meshes exceed" + Str$(E3D_EDGE_POOL) + " edges in all"
                        System 1
                    End If
                    E3D_edgeUsed = E3D_edgeUsed + 1
                    E3D_edgeA(E3D_edgeUsed) = va
                    E3D_edgeB(E3D_edgeUsed) = vb
                    E3D_edgeF1(E3D_edgeUsed) = fi
                    E3D_edgeF2(E3D_edgeUsed) = 0
                    E3D_edgeNext(E3D_edgeUsed) = E3D_edgeHead(lo)
                    E3D_edgeHead(lo) = E3D_edgeUsed
                End If
            End If
        Next k
    Next fi
    mesh.eCount = E3D_edgeUsed - mesh.eStart + 1
End Sub

' 1 when edge e is a silhouette given E3D_faceFront
Function E3D_EdgeIsSilhouette% (e As Integer)
    Dim f2 As Integer
    f2 = E3D_edgeF2(e)
    If f2 = 0 Then
        E3D_EdgeIsSilhouette% = (E3D_faceFront(E3D_edgeF1(e)) <> 0)
    Else
        E3D_EdgeIsSilhouette% = ((E3D_faceFront(E3D_edgeF1(e)) <> 0) <> (E3D_faceFront(f2) <> 0))
    End If
End Function

Sub E3D_OutlineCollect (mesh As E3D_Mesh)
    Dim e As Integer, n As Integer
    If E3D_outlineOn = 0 Then Exit Sub
    For e = mesh.eStart To mesh.eStart + mesh.eCount - 1
        If E3D_EdgeIsSilhouette%(e) Then
            If E3D_scnEdgeCount < E3D_SCNEDGE_MAX Then
                E3D_scnEdgeCount = E3D_scnEdgeCount + 1
                n = E3D_scnEdgeCount
                E3D_scnEdge(n, 1) = E3D_meshWorldVerts(E3D_edgeA(e)).x
                E3D_scnEdge(n, 2) = E3D_meshWorldVerts(E3D_edgeA(e)).y
                E3D_scnEdge(n, 3) = E3D_meshWorldVerts(E3D_edgeA(e)).z
                E3D_scnEdge(n, 4) = E3D_meshWorldVerts(E3D_edgeB(e)).x
                E3D_scnEdge(n, 5) = E3D_meshWorldVerts(E3D_edgeB(e)).y
                E3D_scnEdge(n, 6) = E3D_meshWorldVerts(E3D_edgeB(e)).z
            End If
        End If
    Next e
End Sub

' Clip the segment (x1,y1,z1)-(x2,y2,z2) to 0..maxX, 0..maxY (Liang-Barsky), z following the parameter.
' Returns 0 when nothing is left.
Function E3D_ClipSeg% (x1 As Single, y1 As Single, z1 As Single, x2 As Single, y2 As Single, z2 As Single, maxX As Single, maxY As Single)
    Dim t0 As Single, t1 As Single, dx As Single, dy As Single, dz As Single
    Dim p As Single, q As Single, r As Single, side As Integer
    t0 = 0 : t1 = 1
    dx = x2 - x1 : dy = y2 - y1 : dz = z2 - z1
    E3D_ClipSeg% = 0
    For side = 1 To 4
        Select Case side
            Case 1: p = -dx: q = x1
            Case 2: p = dx: q = maxX - x1
            Case 3: p = -dy: q = y1
            Case 4: p = dy: q = maxY - y1
        End Select
        If p = 0 Then
            If q < 0 Then Exit Function
        Else
            r = q / p
            If p < 0 Then
                If r > t1 Then Exit Function
                If r > t0 Then t0 = r
            Else
                If r < t0 Then Exit Function
                If r < t1 Then t1 = r
            End If
        End If
    Next side
    x2 = x1 + t1 * dx : y2 = y1 + t1 * dy : z2 = z1 + t1 * dz
    x1 = x1 + t0 * dx : y1 = y1 + t0 * dy : z1 = z1 + t0 * dz
    E3D_ClipSeg% = -1
End Function

Sub E3D_OutlinePlot (px As Integer, py As Integer, pz As Single)
    If px < 0 Or py < 0 Or px >= E3D_zBufScrW Or py >= E3D_zBufScrH Then Exit Sub
    If pz < E3D_zBuf(px, py) Then PSet (px, py), E3D_outlineClr
End Sub

Sub E3D_OutlineDraw (vpMat As E3D_Matrix4, scrW As Single, scrH As Single)
    Dim e As Integer, steps As Integer, s As Integer
    Dim x1 As Single, y1 As Single, z1 As Single, x2 As Single, y2 As Single, z2 As Single
    Dim wx As Single, wy As Single, wz As Single, cx As Single, cy As Single, cz As Single, cw As Single
    Dim dx As Single, dy As Single, dz As Single, ax As Single, ay As Single
    Dim fx As Single, fy As Single, fz As Single, ix As Integer, iy As Integer
    Dim endp As Integer, okEdge As Integer

    If E3D_outlineOn = 0 Then Exit Sub
    For e = 1 To E3D_scnEdgeCount
        okEdge = -1
        For endp = 0 To 1
            wx = E3D_scnEdge(e, endp * 3 + 1)
            wy = E3D_scnEdge(e, endp * 3 + 2)
            wz = E3D_scnEdge(e, endp * 3 + 3)
            cx = wx * vpMat.m(0,0) + wy * vpMat.m(0,1) + wz * vpMat.m(0,2) + vpMat.m(0,3)
            cy = wx * vpMat.m(1,0) + wy * vpMat.m(1,1) + wz * vpMat.m(1,2) + vpMat.m(1,3)
            cz = wx * vpMat.m(2,0) + wy * vpMat.m(2,1) + wz * vpMat.m(2,2) + vpMat.m(2,3)
            cw = wx * vpMat.m(3,0) + wy * vpMat.m(3,1) + wz * vpMat.m(3,2) + vpMat.m(3,3)
            If cw > 0.00001 Then
                If endp = 0 Then
                    x1 = (cx / cw + 1.0) * scrW * 0.5 : y1 = (1.0 - cy / cw) * scrH * 0.5 : z1 = cz / cw
                Else
                    x2 = (cx / cw + 1.0) * scrW * 0.5 : y2 = (1.0 - cy / cw) * scrH * 0.5 : z2 = cz / cw
                End If
            Else
                okEdge = 0
            End If
        Next endp
        If okEdge Then
            If E3D_ClipSeg%(x1, y1, z1, x2, y2, z2, scrW - 1, scrH - 1) Then
                dx = x2 - x1 : dy = y2 - y1 : dz = z2 - z1
                ax = Abs(dx) : ay = Abs(dy)
                If ax > ay Then steps = Int(ax) Else steps = Int(ay)
                If steps < 1 Then steps = 1
                fx = dx / steps : fy = dy / steps : fz = dz / steps
                For s = 0 To steps
                    ix = Int(x1 + 0.5) : iy = Int(y1 + 0.5)
                    cz = z1 - E3D_OUTLINE_BIAS
                    E3D_OutlinePlot ix, iy, cz
                    If E3D_outlineWidth > 1 Then
                        If ax > ay Then E3D_OutlinePlot ix, iy + 1, cz Else E3D_OutlinePlot ix + 1, iy, cz
                    End If
                    x1 = x1 + fx : y1 = y1 + fy : z1 = z1 + fz
                Next s
            End If
        End If
    Next e
End Sub

' on$ "0"/"1", color$ "r,g,b" (0-255), width$ "1"/"2". Nothing changes unless all three are valid.
Function E3D_OutlineConfig% (onS As String, clrS As String, widthS As String)
    Dim p1 As Integer, p2 As Integer, r As Long, g As Long, b As Long, w As Long
    E3D_OutlineConfig% = 0
    E3D_outlineErr = ""
    If onS <> "0" And onS <> "1" Then E3D_outlineErr = "config/render.ini outline must be 0 or 1, got '" + onS + "'" : Exit Function
    If widthS <> "1" And widthS <> "2" Then E3D_outlineErr = "config/render.ini outline_width must be 1 or 2, got '" + widthS + "'" : Exit Function
    p1 = InStr(clrS, ",")
    If p1 = 0 Then E3D_outlineErr = "config/render.ini outline_color needs r,g,b" : Exit Function
    p2 = InStr(p1 + 1, clrS, ",")
    If p2 = 0 Then E3D_outlineErr = "config/render.ini outline_color needs r,g,b" : Exit Function
    If InStr(p2 + 1, clrS, ",") > 0 Then E3D_outlineErr = "config/render.ini outline_color needs r,g,b" : Exit Function
    r = Val(Left$(clrS, p1 - 1))
    g = Val(Mid$(clrS, p1 + 1, p2 - p1 - 1))
    b = Val(Mid$(clrS, p2 + 1))
    If r < 0 Or r > 255 Or g < 0 Or g > 255 Or b < 0 Or b > 255 Then E3D_outlineErr = "config/render.ini outline_color values must be 0-255" : Exit Function
    w = Val(widthS)
    If onS = "1" Then E3D_outlineOn = -1 Else E3D_outlineOn = 0
    E3D_outlineWidth = w
    E3D_outlineClr = _RGB32(r, g, b)
    E3D_OutlineConfig% = -1
End Function
