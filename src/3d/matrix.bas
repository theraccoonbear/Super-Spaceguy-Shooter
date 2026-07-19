Sub E3D_MatIdentity (mx As E3D_Matrix4)
    Dim i As Integer, j As Integer
    For i = 0 To 3
        For j = 0 To 3
            mx.m(i, j) = 0
        Next j
        mx.m(i, i) = 1
    Next i
End Sub

Sub E3D_MatMul (a As E3D_Matrix4, b As E3D_Matrix4, mx As E3D_Matrix4)
    Dim tmp As E3D_Matrix4
    Dim i As Integer, j As Integer, k As Integer
    Dim s As Single
    For i = 0 To 3
        For j = 0 To 3
            s = 0
            For k = 0 To 3
                s = s + a.m(i, k) * b.m(k, j)
            Next k
            tmp.m(i, j) = s
        Next j
    Next i
    mx = tmp
End Sub

Sub E3D_MatTranslate (mx As E3D_Matrix4, tx As Single, ty As Single, tz As Single)
    E3D_MatIdentity mx
    mx.m(0, 3) = tx
    mx.m(1, 3) = ty
    mx.m(2, 3) = tz
End Sub

Sub E3D_MatScale (mx As E3D_Matrix4, sx As Single, sy As Single, sz As Single)
    E3D_MatIdentity mx
    mx.m(0, 0) = sx
    mx.m(1, 1) = sy
    mx.m(2, 2) = sz
End Sub

Sub E3D_MatRotateX (mx As E3D_Matrix4, degrees As Single)
    Dim a As Single
    a = _PI * degrees / 180
    E3D_MatIdentity mx
    mx.m(1, 1) =  Cos(a)
    mx.m(1, 2) = -Sin(a)
    mx.m(2, 1) =  Sin(a)
    mx.m(2, 2) =  Cos(a)
End Sub

Sub E3D_MatRotateY (mx As E3D_Matrix4, degrees As Single)
    Dim a As Single
    a = _PI * degrees / 180
    E3D_MatIdentity mx
    mx.m(0, 0) =  Cos(a)
    mx.m(0, 2) =  Sin(a)
    mx.m(2, 0) = -Sin(a)
    mx.m(2, 2) =  Cos(a)
End Sub

Sub E3D_MatRotateZ (mx As E3D_Matrix4, degrees As Single)
    Dim a As Single
    a = _PI * degrees / 180
    E3D_MatIdentity mx
    mx.m(0, 0) =  Cos(a)
    mx.m(0, 1) = -Sin(a)
    mx.m(1, 0) =  Sin(a)
    mx.m(1, 1) =  Cos(a)
End Sub

' --- Vec3 ---

Sub E3D_Vec3Dot (a As E3D_Coord, b As E3D_Coord, result As Single)
    result = a.x * b.x + a.y * b.y + a.z * b.z
End Sub

Sub E3D_Vec3Cross (a As E3D_Coord, b As E3D_Coord, res As E3D_Coord)
    res.x = a.y * b.z - a.z * b.y
    res.y = a.z * b.x - a.x * b.z
    res.z = a.x * b.y - a.y * b.x
End Sub

Sub E3D_Vec3Normalize (v As E3D_Coord, res As E3D_Coord)
    Dim mag As Single
    mag = Sqr(v.x * v.x + v.y * v.y + v.z * v.z)
    If mag > 0.00001 Then
        res.x = v.x / mag
        res.y = v.y / mag
        res.z = v.z / mag
    Else
        res.x = 0 : res.y = 0 : res.z = 1
    End If
End Sub

' --- Transform ---

Sub E3D_MatTransformCoord (c As E3D_Coord, m As E3D_Matrix4, res As E3D_Coord)
    Dim x As Single, y As Single, z As Single, w As Single
    x = c.x * m.m(0,0) + c.y * m.m(0,1) + c.z * m.m(0,2) + m.m(0,3)
    y = c.x * m.m(1,0) + c.y * m.m(1,1) + c.z * m.m(1,2) + m.m(1,3)
    z = c.x * m.m(2,0) + c.y * m.m(2,1) + c.z * m.m(2,2) + m.m(2,3)
    w = c.x * m.m(3,0) + c.y * m.m(3,1) + c.z * m.m(3,2) + m.m(3,3)
    If Abs(w) > 0.00001 Then
        res.x = x / w
        res.y = y / w
        res.z = z / w
    End If
End Sub

Sub E3D_MatTransformPoly (inPoly As E3D_Polygon, m As E3D_Matrix4, outPoly As E3D_Polygon)
    Dim i As Integer
    Dim c As E3D_Coord, tc As E3D_Coord
    E3D_MakePolygon outPoly
    For i = 1 To inPoly.count
        c = inPoly.coords(i)
        E3D_MatTransformCoord c, m, tc
        E3D_AddCoord outPoly, tc
    Next i
End Sub
