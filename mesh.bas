Sub E3D_MakeMesh (mesh As E3D_Mesh)
    mesh.vCount = 0
    mesh.fCount = 0
End Sub

Sub E3D_AddMeshVert (mesh As E3D_Mesh, x As Single, y As Single, z As Single)
    Dim idx As Integer
    idx = mesh.vCount + 1
    mesh.vCount = idx
    mesh.verts(idx).x = x
    mesh.verts(idx).y = y
    mesh.verts(idx).z = z
End Sub

Sub E3D_AddTriFace (mesh As E3D_Mesh, i1 As Integer, i2 As Integer, i3 As Integer, clr As Long)
    Dim fi As Integer
    fi = mesh.fCount + 1
    mesh.fCount = fi
    mesh.faces(fi).vCount = 3
    mesh.faces(fi).baseClr = clr
    mesh.faces(fi).vIdx(1) = i1
    mesh.faces(fi).vIdx(2) = i2
    mesh.faces(fi).vIdx(3) = i3
End Sub

Sub E3D_AddQuadFace (mesh As E3D_Mesh, i1 As Integer, i2 As Integer, i3 As Integer, i4 As Integer, clr As Long)
    Dim fi As Integer
    fi = mesh.fCount + 1
    mesh.fCount = fi
    mesh.faces(fi).vCount = 4
    mesh.faces(fi).baseClr = clr
    mesh.faces(fi).vIdx(1) = i1
    mesh.faces(fi).vIdx(2) = i2
    mesh.faces(fi).vIdx(3) = i3
    mesh.faces(fi).vIdx(4) = i4
End Sub

' Back-face cull, Z-sort faces, project and fill each visible face.
' Color cycles through the rainbow; each face has a 60-degree hue offset
' so all 6 faces of a cube are always distinct colours simultaneously.
Sub E3D_DrawMesh (mesh As E3D_Mesh, modelMat As E3D_Matrix4, vpMat As E3D_Matrix4, screenW As Single, screenH As Single, camPos As E3D_Coord, tt As Single)
    Dim E3D_worldVerts(1 To 8192) As E3D_Coord
    Dim visIdx(1 To 8192) As Integer
    Dim visDepth(1 To 8192) As Single
    Dim i As Integer, fi As Integer, vi As Integer
    Dim visCount As Integer
    Dim fv1 As Integer, fv2 As Integer, fv3 As Integer, fvn As Integer, fvi As Integer
    Dim ex1 As Single, ey1 As Single, ez1 As Single
    Dim ex2 As Single, ey2 As Single, ez2 As Single
    Dim fnx As Single, fny As Single, fnz As Single
    Dim vvx As Single, vvy As Single, vvz As Single
    Dim depthSum As Single
    Dim didSwap As Integer, stmp As Integer, dtmp As Single
    Dim facePoly As E3D_Polygon, sFacePoly As E3D_Polygon
    Dim hue As Single, fc As Long

    For i = 1 To mesh.vCount
        E3D_MatTransformCoord mesh.verts(i), modelMat, E3D_worldVerts(i)
    Next i

    visCount = 0
    For fi = 1 To mesh.fCount
        fv1 = mesh.faces(fi).vIdx(1)
        fv2 = mesh.faces(fi).vIdx(2)
        fv3 = mesh.faces(fi).vIdx(3)
        ex1 = E3D_worldVerts(fv2).x - E3D_worldVerts(fv1).x
        ey1 = E3D_worldVerts(fv2).y - E3D_worldVerts(fv1).y
        ez1 = E3D_worldVerts(fv2).z - E3D_worldVerts(fv1).z
        ex2 = E3D_worldVerts(fv3).x - E3D_worldVerts(fv1).x
        ey2 = E3D_worldVerts(fv3).y - E3D_worldVerts(fv1).y
        ez2 = E3D_worldVerts(fv3).z - E3D_worldVerts(fv1).z
        fnx = ey1 * ez2 - ez1 * ey2
        fny = ez1 * ex2 - ex1 * ez2
        fnz = ex1 * ey2 - ey1 * ex2
        vvx = camPos.x - E3D_worldVerts(fv1).x
        vvy = camPos.y - E3D_worldVerts(fv1).y
        vvz = camPos.z - E3D_worldVerts(fv1).z
        If fnx * vvx + fny * vvy + fnz * vvz > 0 Then
            fvn = mesh.faces(fi).vCount
            depthSum = 0
            For vi = 1 To fvn
                fvi = mesh.faces(fi).vIdx(vi)
                depthSum = depthSum + E3D_worldVerts(fvi).z
            Next vi
            visCount = visCount + 1
            visIdx(visCount) = fi
            visDepth(visCount) = depthSum / fvn
        End If
    Next fi

    Do
        didSwap = 0
        For i = 1 To visCount - 1
            If visDepth(i) < visDepth(i + 1) Then
                stmp = visIdx(i) : visIdx(i) = visIdx(i + 1) : visIdx(i + 1) = stmp
                dtmp = visDepth(i) : visDepth(i) = visDepth(i + 1) : visDepth(i + 1) = dtmp
                didSwap = 1
            End If
        Next i
    Loop While didSwap

    For i = 1 To visCount
        fi = visIdx(i)
        fvn = mesh.faces(fi).vCount
        E3D_MakePolygon facePoly
        For vi = 1 To fvn
            fvi = mesh.faces(fi).vIdx(vi)
            E3D_AddCoord facePoly, E3D_worldVerts(fvi)
        Next vi
        E3D_ProjectPoly facePoly, vpMat, screenW, screenH, sFacePoly

        ' 3-phase sinusoid hue cycle; fi*1.047 ≈ fi*(PI/3) keeps each face
        ' 60 degrees apart in hue so all 6 cube faces stay distinct
        hue = tt * 0.7 + fi * 1.047
        fc = _RGB(Int((0.5 + 0.5 * Sin(hue)) * 255), _
                  Int((0.5 + 0.5 * Sin(hue + 2.094)) * 255), _
                  Int((0.5 + 0.5 * Sin(hue + 4.189)) * 255))
        E3D_DrawPoly sFacePoly, fc
    Next i
End Sub

' Cull, depth-compute, and color visible faces without drawing.
' Fills caller-supplied arrays so the main loop can Z-sort mesh faces
' alongside other scene objects in a single unified pass.
' Original unlit version — hue-cycles face colors. Used by fun.bas.
Sub E3D_GetMeshFaces (mesh As E3D_Mesh, modelMat As E3D_Matrix4, camPos As E3D_Coord, tt As Single, facePolys() As E3D_Polygon, faceClrs() As Long, faceDepths() As Single, faceCount As Integer)
    Dim E3D_worldVerts(1 To 8192) As E3D_Coord
    Dim i As Integer, fi As Integer, vi As Integer
    Dim fv1 As Integer, fv2 As Integer, fv3 As Integer, fvn As Integer, fvi As Integer
    Dim ex1 As Single, ey1 As Single, ez1 As Single
    Dim ex2 As Single, ey2 As Single, ez2 As Single
    Dim fnx As Single, fny As Single, fnz As Single
    Dim vvx As Single, vvy As Single, vvz As Single
    Dim depthSum As Single
    Dim facePoly As E3D_Polygon
    Dim hue As Single

    For i = 1 To mesh.vCount
        E3D_MatTransformCoord mesh.verts(i), modelMat, E3D_worldVerts(i)
    Next i

    faceCount = 0
    For fi = 1 To mesh.fCount
        fv1 = mesh.faces(fi).vIdx(1)
        fv2 = mesh.faces(fi).vIdx(2)
        fv3 = mesh.faces(fi).vIdx(3)
        ex1 = E3D_worldVerts(fv2).x - E3D_worldVerts(fv1).x
        ey1 = E3D_worldVerts(fv2).y - E3D_worldVerts(fv1).y
        ez1 = E3D_worldVerts(fv2).z - E3D_worldVerts(fv1).z
        ex2 = E3D_worldVerts(fv3).x - E3D_worldVerts(fv1).x
        ey2 = E3D_worldVerts(fv3).y - E3D_worldVerts(fv1).y
        ez2 = E3D_worldVerts(fv3).z - E3D_worldVerts(fv1).z
        fnx = ey1 * ez2 - ez1 * ey2
        fny = ez1 * ex2 - ex1 * ez2
        fnz = ex1 * ey2 - ey1 * ex2
        vvx = camPos.x - E3D_worldVerts(fv1).x
        vvy = camPos.y - E3D_worldVerts(fv1).y
        vvz = camPos.z - E3D_worldVerts(fv1).z
        If fnx * vvx + fny * vvy + fnz * vvz > 0 Then
            fvn = mesh.faces(fi).vCount
            depthSum = 0
            E3D_MakePolygon facePoly
            For vi = 1 To fvn
                fvi = mesh.faces(fi).vIdx(vi)
                E3D_AddCoord facePoly, E3D_worldVerts(fvi)
                depthSum = depthSum + E3D_worldVerts(fvi).z
            Next vi
            faceCount = faceCount + 1
            facePolys(faceCount) = facePoly
            faceDepths(faceCount) = depthSum / fvn
            hue = tt * 0.7 + fi * 1.047
            faceClrs(faceCount) = _RGB(Int((0.5 + 0.5 * Sin(hue)) * 255), _
                                       Int((0.5 + 0.5 * Sin(hue + 2.094)) * 255), _
                                       Int((0.5 + 0.5 * Sin(hue + 4.189)) * 255))
        End If
    Next fi
End Sub

' Strip leading token from s, parse as Single into v; s is advanced past the token.
Sub E3D_TokF (s As String, v As Single)
    Dim p As Integer
    s = LTrim$(s)
    p = InStr(s, " ")
    If p = 0 Then v = Val(s) : s = "" : Exit Sub
    v = Val(Left$(s, p - 1))
    s = LTrim$(Mid$(s, p + 1))
End Sub

' Strip leading token from s, parse as Integer into v; s is advanced past the token.
Sub E3D_TokI (s As String, v As Integer)
    Dim p As Integer
    s = LTrim$(s)
    p = InStr(s, " ")
    If p = 0 Then v = CInt(Val(s)) : s = "" : Exit Sub
    v = CInt(Val(Left$(s, p - 1)))
    s = LTrim$(Mid$(s, p + 1))
End Sub

' Consume the next line from s (handles LF and CRLF); s is advanced past it.
Sub E3D_NextLine (s As String, ln As String)
    Dim p As Integer
    p = InStr(s, Chr$(10))
    If p = 0 Then ln = s : s = "" : Exit Sub
    ln = Left$(s, p - 1)
    s = Mid$(s, p + 1)
    If Len(ln) > 0 Then
        If Right$(ln, 1) = Chr$(13) Then ln = Left$(ln, Len(ln) - 1)
    End If
End Sub

' Load one named mesh from an in-memory .e3d string (pass _EMBEDDED$ result).
' data is consumed line-by-line; sequential calls on the same variable are
' efficient because each call advances data past the mesh it just parsed.
Sub E3D_LoadMesh (mdat As String, meshName As String, mesh As E3D_Mesh, box As E3D_AABB)
    Dim ln As String, tok As String, rest As String
    Dim found As Integer, ci As Integer, sp As Integer
    Dim vx As Single, vy As Single, vz As Single
    Dim thx As Single, thy As Single, thz As Single
    Dim i1 As Integer, i2 As Integer, i3 As Integer, i4 As Integer
    Dim cr As Integer, cg As Integer, cb As Integer

    E3D_MakeMesh mesh
    box.hx = 0 : box.hy = 0 : box.hz = 0
    found = 0

    Do While Len(mdat) > 0
        E3D_NextLine mdat, ln
        ci = InStr(ln, "#")
        If ci > 0 Then ln = Left$(ln, ci - 1)
        ln = LTrim$(RTrim$(ln))
        If Len(ln) > 0 Then
            sp = InStr(ln, " ")
            If sp = 0 Then
                tok = ln : rest = ""
            Else
                tok = Left$(ln, sp - 1)
                rest = LTrim$(Mid$(ln, sp + 1))
            End If
            tok = LCase$(tok)

            If found = 0 Then
                If tok = "o" And rest = meshName Then found = -1
            Else
                Select Case tok
                    Case "end"
                        Exit Do
                    Case "aabb"
                        E3D_TokF rest, thx : E3D_TokF rest, thy : E3D_TokF rest, thz
                        box.hx = thx : box.hy = thy : box.hz = thz
                    Case "v"
                        E3D_TokF rest, vx : E3D_TokF rest, vy : E3D_TokF rest, vz
                        E3D_AddMeshVert mesh, vx, vy, vz
                    Case "f"
                        E3D_TokI rest, i1 : E3D_TokI rest, i2 : E3D_TokI rest, i3
                        E3D_TokI rest, cr : E3D_TokI rest, cg : E3D_TokI rest, cb
                        E3D_AddTriFace mesh, i1, i2, i3, _RGB(cr, cg, cb)
                    Case "q"
                        E3D_TokI rest, i1 : E3D_TokI rest, i2 : E3D_TokI rest, i3 : E3D_TokI rest, i4
                        E3D_TokI rest, cr : E3D_TokI rest, cg : E3D_TokI rest, cb
                        E3D_AddQuadFace mesh, i1, i2, i3, i4, _RGB(cr, cg, cb)
                End Select
            End If
        End If
    Loop
End Sub

' Compute and store normalized face normals in object space after mesh load.
' Call once per mesh after E3D_LoadMesh; amortizes cross-product+sqrt across all frames.
Sub E3D_BakeMeshNormals (mesh As E3D_Mesh)
    Dim fi As Integer
    Dim ex1 As Single, ey1 As Single, ez1 As Single
    Dim ex2 As Single, ey2 As Single, ez2 As Single
    Dim nx As Single, ny As Single, nz As Single, mag As Single
    Dim fv1 As Integer, fv2 As Integer, fv3 As Integer
    For fi = 1 To mesh.fCount
        fv1 = mesh.faces(fi).vIdx(1)
        fv2 = mesh.faces(fi).vIdx(2)
        fv3 = mesh.faces(fi).vIdx(3)
        ex1 = mesh.verts(fv2).x - mesh.verts(fv1).x
        ey1 = mesh.verts(fv2).y - mesh.verts(fv1).y
        ez1 = mesh.verts(fv2).z - mesh.verts(fv1).z
        ex2 = mesh.verts(fv3).x - mesh.verts(fv1).x
        ey2 = mesh.verts(fv3).y - mesh.verts(fv1).y
        ez2 = mesh.verts(fv3).z - mesh.verts(fv1).z
        nx = ey1 * ez2 - ez1 * ey2
        ny = ez1 * ex2 - ex1 * ez2
        nz = ex1 * ey2 - ey1 * ex2
        mag = Sqr(nx * nx + ny * ny + nz * nz)
        If mag > 0.00001 Then
            mesh.faces(fi).nx = nx / mag
            mesh.faces(fi).ny = ny / mag
            mesh.faces(fi).nz = nz / mag
        End If
    Next fi
End Sub

' Lit version — flat shading from a directional light. Used by sss.bas.
' Face baseClr drives the color; if 0, falls back to hue cycle.
Sub E3D_GetMeshFacesLit (mesh As E3D_Mesh, modelMat As E3D_Matrix4, camPos As E3D_Coord, tt As Single, lightDir As E3D_Coord, facePolys() As E3D_Polygon, faceClrs() As Long, faceDepths() As Single, faceCount As Integer)
    Dim E3D_worldVerts(1 To 8192) As E3D_Coord
    Dim i As Integer, fi As Integer, vi As Integer
    Dim fv1 As Integer, fvn As Integer, fvi As Integer
    Dim fnx As Single, fny As Single, fnz As Single
    Dim vvx As Single, vvy As Single, vvz As Single
    Dim depthSum As Single
    Dim facePoly As E3D_Polygon
    Dim hue As Single, lit As Single
    Dim baseR As Integer, baseG As Integer, baseB As Integer

    For i = 1 To mesh.vCount
        E3D_MatTransformCoord mesh.verts(i), modelMat, E3D_worldVerts(i)
    Next i

    faceCount = 0
    For fi = 1 To mesh.fCount
        ' Rotate baked object-space normal by the 3x3 rotation part of modelMat
        fnx = mesh.faces(fi).nx * modelMat.m(0,0) + mesh.faces(fi).ny * modelMat.m(0,1) + mesh.faces(fi).nz * modelMat.m(0,2)
        fny = mesh.faces(fi).nx * modelMat.m(1,0) + mesh.faces(fi).ny * modelMat.m(1,1) + mesh.faces(fi).nz * modelMat.m(1,2)
        fnz = mesh.faces(fi).nx * modelMat.m(2,0) + mesh.faces(fi).ny * modelMat.m(2,1) + mesh.faces(fi).nz * modelMat.m(2,2)
        fv1 = mesh.faces(fi).vIdx(1)
        vvx = camPos.x - E3D_worldVerts(fv1).x
        vvy = camPos.y - E3D_worldVerts(fv1).y
        vvz = camPos.z - E3D_worldVerts(fv1).z
        If fnx * vvx + fny * vvy + fnz * vvz > 0 Then
            fvn = mesh.faces(fi).vCount
            depthSum = 0
            E3D_MakePolygon facePoly
            For vi = 1 To fvn
                fvi = mesh.faces(fi).vIdx(vi)
                E3D_AddCoord facePoly, E3D_worldVerts(fvi)
                depthSum = depthSum + E3D_worldVerts(fvi).x
            Next vi
            faceCount = faceCount + 1
            facePolys(faceCount) = facePoly
            faceDepths(faceCount) = depthSum / fvn

            ' Normal already unit-length after rotation by orthonormal matrix
            lit = fnx * lightDir.x + fny * lightDir.y + fnz * lightDir.z
            If lit < 0.15 Then lit = 0.15

            If mesh.faces(fi).baseClr = 0 Then
                hue = tt * 0.7 + fi * 1.047
                baseR = Int((0.5 + 0.5 * Sin(hue)) * 255)
                baseG = Int((0.5 + 0.5 * Sin(hue + 2.094)) * 255)
                baseB = Int((0.5 + 0.5 * Sin(hue + 4.189)) * 255)
            Else
                baseR = _Red32(mesh.faces(fi).baseClr)
                baseG = _Green32(mesh.faces(fi).baseClr)
                baseB = _Blue32(mesh.faces(fi).baseClr)
            End If
            faceClrs(faceCount) = _RGB(Int(baseR * lit), Int(baseG * lit), Int(baseB * lit))
        End If
    Next fi
End Sub
