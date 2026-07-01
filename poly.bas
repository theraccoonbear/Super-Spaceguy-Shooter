Sub E3D_PCoord (co As E3D_Coord)
    Color 14
    Print "(";
    Color 15
    Print LTrim$(Str$(co.x));
    Color 14
    Print ", ";
    Color 15
    Print LTrim$(Str$(co.y));
    Color 14
    Print ")";
End Sub

Sub E3D_PPolygon (poly As E3D_Polygon)
    Dim i As Integer
    Dim lastIdx As Integer
    For i = 1 To poly.count - 1
        E3D_PCoord poly.coords(i)
        Color 2
        Print "-";
    Next i
    lastIdx = poly.count
    E3D_PCoord poly.coords(lastIdx)
End Sub

Sub E3D_MakeCoord (outval As E3D_Coord, x As Single, y As Single, z As Single)
    outval.x = x
    outval.y = y
    outval.z = z
End Sub

Sub E3D_MakePolygon (outval As E3D_Polygon)
    Dim poly As E3D_Polygon
    poly.count = 0
    outval = poly
End Sub

Sub E3D_AddCoord (poly As E3D_Polygon, c As E3D_Coord)
    Dim index As Integer
    index = poly.count + 1
    poly.count = index
    poly.coords(index) = c
End Sub

Sub E3D_AddNode (poly As E3D_Polygon, x As Single, y As Single, z As Single)
    Dim c As E3D_Coord
    E3D_MakeCoord c, x, y, z
    E3D_AddCoord poly, c
End Sub

Sub E3D_CopyPoly (oldPoly As E3D_Polygon, newPoly As E3D_Polygon)
    newPoly = oldPoly
End Sub

Sub E3D_PolyCenter (poly As E3D_Polygon, outCoord As E3D_Coord)
    Dim i As Integer
    Dim c As E3D_Coord
    outCoord = poly.coords(1)
    Dim minX As Single, minY As Single, minZ As Single
    Dim maxX As Single, maxY As Single, maxZ As Single
    minX = outCoord.x : maxX = outCoord.x
    minY = outCoord.y : maxY = outCoord.y
    minZ = outCoord.z : maxZ = outCoord.z
    For i = 2 To poly.count
        c = poly.coords(i)
        If c.x < minX Then minX = c.x
        If c.y < minY Then minY = c.y
        If c.z < minZ Then minZ = c.z
        If c.x > maxX Then maxX = c.x
        If c.y > maxY Then maxY = c.y
        If c.z > maxZ Then maxZ = c.z
    Next i
    outCoord.x = (minX + maxX) * 0.5
    outCoord.y = (minY + maxY) * 0.5
    outCoord.z = (minZ + maxZ) * 0.5
End Sub

Sub E3D_DrawLine (c1 As E3D_Coord, c2 As E3D_Coord, clr As Long)
    Line (c1.x, c1.y)-(c2.x, c2.y), clr
End Sub

Sub E3D_DrawPoly (poly As E3D_Polygon, clr As Long)
    Dim i1 As Integer, i2 As Integer, last As Integer
    Dim c1 As E3D_Coord, c2 As E3D_Coord
    Dim cx As Single, cy As Single
    Dim area As Single

    last = poly.count
    If last < 2 Then Exit Sub

    For i1 = 1 To last - 1
        i2 = i1 + 1
        c1 = poly.coords(i1)
        c2 = poly.coords(i2)
        E3D_DrawLine c1, c2, clr
    Next i1
    E3D_DrawLine poly.coords(last), poly.coords(1), clr

    cx = 0 : cy = 0
    For i1 = 1 To last
        cx = cx + poly.coords(i1).x
        cy = cy + poly.coords(i1).y
    Next i1
    cx = cx / last
    cy = cy / last

    ' Shoelace area — tiny polygons produce gaps in their pixel outline that
    ' let Paint escape and flood the screen. Use PSet for those instead.
    area = 0
    For i1 = 1 To last - 1
        area = area + poly.coords(i1).x * poly.coords(i1 + 1).y - poly.coords(i1 + 1).x * poly.coords(i1).y
    Next i1
    area = area + poly.coords(last).x * poly.coords(1).y - poly.coords(1).x * poly.coords(last).y
    area = Abs(area) * 0.5

    If area < 4 Then
        If cx >= 0 And cx < 32767 And cy >= 0 And cy < 32767 Then PSet (cx, cy), clr
    ElseIf cx > 0 And cx < 32767 And cy > 0 And cy < 32767 Then
        Paint (cx, cy), clr, clr
    End If
End Sub
