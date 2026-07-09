' obj.bas — tolerant Wavefront OBJ + MTL loader
' Requires E3D_NextLine, E3D_TokF, E3D_MakeMesh, E3D_AddMeshVert,
' E3D_AddTriFace from mesh.bas — include this file after mesh.bas.
'
' Coords pass through unchanged (no axis remap). Orient your model in
' the source tool to match engine convention: X=forward, Y=up, Z=left.
' The loader auto-centers the mesh on the origin and computes the AABB.

' Extract vertex index from an OBJ face token.
' Handles:  "3"  "3/2"  "3/2/1"  "3//1"  and negative (relative) indices.
Sub E3D_OBJVertIdx (tok As String, vCount As Integer, idx As Integer)
    Dim p As Integer
    p = InStr(tok, "/")
    If p > 0 Then
        idx = CInt(Val(Left$(tok, p - 1)))
    Else
        idx = CInt(Val(tok))
    End If
    If idx < 0 Then idx = vCount + idx + 1
End Sub

' Parse MTL data into name/color tables (up to maxMats entries).
' Only reads "newmtl" and "Kd r g b" (0-1 float diffuse). All else ignored.
Sub E3D_LoadOBJMtl (mtlDat As String, matNames() As String, matClrs() As Long, matCount As Integer)
    Dim ln As String, tok As String, rest As String
    Dim sp As Integer, ci As Integer
    Dim r As Single, g As Single, b As Single
    matCount = 0
    Do While Len(mtlDat) > 0
        E3D_NextLine mtlDat, ln
        ci = InStr(ln, "#") : If ci > 0 Then ln = Left$(ln, ci - 1)
        ln = LTrim$(RTrim$(ln))
        If Len(ln) = 0 Then GoTo nextMtlLn
        sp = InStr(ln, " ")
        If sp = 0 Then GoTo nextMtlLn
        tok  = LCase$(Left$(ln, sp - 1))
        rest = LTrim$(RTrim$(Mid$(ln, sp + 1)))
        If tok = "newmtl" Then
            If matCount < UBound(matNames) Then
                matCount = matCount + 1
                matNames(matCount) = rest
                matClrs(matCount)  = _RGB32(180, 180, 180)
            End If
        ElseIf tok = "kd" Then
            If matCount > 0 Then
                E3D_TokF rest, r : E3D_TokF rest, g : E3D_TokF rest, b
                ' Boost dark PBR values so they read in flat shading.
                ' Kd is linear light; we brighten toward white before quantising.
                Dim boost As Single : boost = 1.0
                Dim maxC  As Single : maxC  = r
                If g > maxC Then maxC = g
                If b > maxC Then maxC = b
                If maxC > 0.001 And maxC < 0.55 Then boost = 0.55 / maxC
                If boost > 3.5 Then boost = 3.5
                r = r * boost : If r > 1.0 Then r = 1.0
                g = g * boost : If g > 1.0 Then g = 1.0
                b = b * boost : If b > 1.0 Then b = 1.0
                matClrs(matCount) = _RGB32(Int(r * 255 + 0.5), Int(g * 255 + 0.5), Int(b * 255 + 0.5))
            End If
        End If
        nextMtlLn:
    Loop
End Sub

' Given an OBJ file path and its raw text, find the "mtllib" reference
' and return the full path to the MTL file (same directory as the OBJ).
' Returns empty string if no mtllib line found.
Function E3D_OBJMtlPath$ (objPath As String, objDat As String)
    Dim tmp As String : tmp = objDat
    Dim ln As String, i As Integer, lastSlash As Integer
    Do While Len(tmp) > 0
        E3D_NextLine tmp, ln
        ln = LTrim$(RTrim$(ln))
        If LCase$(Left$(ln, 7)) = "mtllib " Then
            Dim mtlFile As String
            mtlFile = LTrim$(RTrim$(Mid$(ln, 8)))
            ' Find last path separator to build sibling path
            lastSlash = 0
            For i = Len(objPath) To 1 Step -1
                If Mid$(objPath, i, 1) = "/" Or Mid$(objPath, i, 1) = "\" Then
                    lastSlash = i : Exit For
                End If
            Next i
            If lastSlash > 0 Then
                E3D_OBJMtlPath$ = Left$(objPath, lastSlash) + mtlFile
            Else
                E3D_OBJMtlPath$ = mtlFile
            End If
            Exit Function
        End If
    Loop
    E3D_OBJMtlPath$ = ""
End Function

' Load a mesh from OBJ + optional MTL string data into mesh and box.
' Pass empty string for mtlDat to skip material colours (renders gray).
' axisRemap: 0=none  1=Blender(-Z fwd) → engine(+X fwd)  2=(+Z fwd) → engine(+X fwd)
' scale: uniform scale applied after centering (1.0 = no change; use e.g. 0.0015 for cm→engine units)
' Silently truncates at the mesh vert/face cap.
' Mesh is auto-centred on the origin; AABB computed from actual extents.
Sub E3D_LoadOBJ (objDat As String, mtlDat As String, mesh As E3D_Mesh, box As E3D_AABB, axisRemap As Integer, scale As Single)
    Const MAX_MATS = 64
    Const MAX_FAN  = 32
    Dim matNames(1 To MAX_MATS) As String
    Dim matClrs(1 To MAX_MATS)  As Long
    Dim matCount As Integer
    Dim curClr   As Long
    Dim ln As String, tok As String, rest As String
    Dim sp As Integer, ci As Integer
    Dim vx As Single, vy As Single, vz As Single
    Dim fanIdx(1 To MAX_FAN) As Integer
    Dim fanCount As Integer
    Dim ftok As String
    Dim i1 As Integer, i2 As Integer, i3 As Integer
    Dim fi As Integer, mi As Integer
    Dim vi As Integer
    Dim mnX As Single, mxX As Single
    Dim mnY As Single, mxY As Single
    Dim mnZ As Single, mxZ As Single
    Dim ctrX As Single, ctrY As Single, ctrZ As Single

    ' Parse materials first if provided
    If Len(mtlDat) > 0 Then
        Dim mtlCopy As String : mtlCopy = mtlDat
        E3D_LoadOBJMtl mtlCopy, matNames(), matClrs(), matCount
    End If
    curClr = _RGB32(180, 180, 180)
    If matCount > 0 Then curClr = matClrs(1)

    E3D_MakeMesh mesh
    box.hx = 0 : box.hy = 0 : box.hz = 0

    Do While Len(objDat) > 0
        E3D_NextLine objDat, ln
        ci = InStr(ln, "#") : If ci > 0 Then ln = Left$(ln, ci - 1)
        ln = LTrim$(RTrim$(ln))
        If Len(ln) = 0 Then GoTo nextObjLn
        sp = InStr(ln, " ")
        If sp = 0 Then GoTo nextObjLn
        tok  = LCase$(Left$(ln, sp - 1))
        rest = LTrim$(Mid$(ln, sp + 1))

        Select Case tok
            Case "v"
                If mesh.vCount < UBound(mesh.verts) Then
                    E3D_TokF rest, vx : E3D_TokF rest, vy : E3D_TokF rest, vz
                    Select Case axisRemap
                        Case 1  ' Blender -Z fwd → engine +X fwd: eX=-vZ  eY=vY  eZ=vX
                            E3D_AddMeshVert mesh, -vz, vy, vx
                        Case 2  ' +Z fwd → engine +X fwd: eX=vZ  eY=vY  eZ=-vX
                            E3D_AddMeshVert mesh, vz, vy, -vx
                        Case Else
                            E3D_AddMeshVert mesh, vx, vy, vz
                    End Select
                End If

            Case "usemtl"
                rest = LTrim$(RTrim$(rest))
                For mi = 1 To matCount
                    If matNames(mi) = rest Then
                        curClr = matClrs(mi)
                        Exit For
                    End If
                Next mi

            Case "f"
                ' Collect vertex indices into fan buffer
                fanCount = 0
                Do While Len(rest) > 0
                    rest = LTrim$(rest)
                    If Len(rest) = 0 Then Exit Do
                    sp = InStr(rest, " ")
                    If sp = 0 Then
                        ftok = rest : rest = ""
                    Else
                        ftok = Left$(rest, sp - 1)
                        rest = Mid$(rest, sp + 1)
                    End If
                    If Len(ftok) > 0 And fanCount < MAX_FAN Then
                        fanCount = fanCount + 1
                        E3D_OBJVertIdx ftok, mesh.vCount, fanIdx(fanCount)
                    End If
                Loop
                ' Fan triangulate: pivot on first vert
                For fi = 2 To fanCount - 1
                    If mesh.fCount < UBound(mesh.faces) Then
                        i1 = fanIdx(1) : i2 = fanIdx(fi) : i3 = fanIdx(fi + 1)
                        If i1 >= 1 And i1 <= mesh.vCount Then
                            If i2 >= 1 And i2 <= mesh.vCount Then
                                If i3 >= 1 And i3 <= mesh.vCount Then
                                    E3D_AddTriFace mesh, i1, i2, i3, curClr
                                End If
                            End If
                        End If
                    End If
                Next fi
        End Select
        nextObjLn:
    Loop

    ' Auto-centre on origin and compute AABB
    If mesh.vCount > 0 Then
        mnX = mesh.verts(1).x : mxX = mnX
        mnY = mesh.verts(1).y : mxY = mnY
        mnZ = mesh.verts(1).z : mxZ = mnZ
        For vi = 2 To mesh.vCount
            If mesh.verts(vi).x < mnX Then mnX = mesh.verts(vi).x
            If mesh.verts(vi).x > mxX Then mxX = mesh.verts(vi).x
            If mesh.verts(vi).y < mnY Then mnY = mesh.verts(vi).y
            If mesh.verts(vi).y > mxY Then mxY = mesh.verts(vi).y
            If mesh.verts(vi).z < mnZ Then mnZ = mesh.verts(vi).z
            If mesh.verts(vi).z > mxZ Then mxZ = mesh.verts(vi).z
        Next vi
        ctrX = (mnX + mxX) * 0.5
        ctrY = (mnY + mxY) * 0.5
        ctrZ = (mnZ + mxZ) * 0.5
        Dim sc As Single : sc = scale
        If sc = 0.0 Then sc = 1.0
        For vi = 1 To mesh.vCount
            mesh.verts(vi).x = (mesh.verts(vi).x - ctrX) * sc
            mesh.verts(vi).y = (mesh.verts(vi).y - ctrY) * sc
            mesh.verts(vi).z = (mesh.verts(vi).z - ctrZ) * sc
        Next vi
        box.hx = (mxX - mnX) * 0.5 * sc
        box.hy = (mxY - mnY) * 0.5 * sc
        box.hz = (mxZ - mnZ) * 0.5 * sc
    End If
End Sub
