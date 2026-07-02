' Z-buffer — sized to a safe maximum; actual viewport set by E3D_ZBufClear.
' NDC z/w range is [-1, 1]; init value 2.0 means "nothing drawn here yet".
Const E3D_ZBUF_W = 1280
Const E3D_ZBUF_H = 960
Dim Shared E3D_zBuf(0 To E3D_ZBUF_W - 1, 0 To E3D_ZBUF_H - 1) As Single
Dim Shared E3D_zBufScrW As Integer
Dim Shared E3D_zBufScrH As Integer

Sub E3D_ZBufClear (scrW As Integer, scrH As Integer)
    E3D_zBufScrW = scrW
    E3D_zBufScrH = scrH
    Dim x As Integer, y As Integer
    Dim maxX As Integer, maxY As Integer
    maxX = scrW - 1 : If maxX >= E3D_ZBUF_W Then maxX = E3D_ZBUF_W - 1
    maxY = scrH - 1 : If maxY >= E3D_ZBUF_H Then maxY = E3D_ZBUF_H - 1
    For y = 0 To maxY
        For x = 0 To maxX
            E3D_zBuf(x, y) = 2.0
        Next x
    Next y
End Sub

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
    Dim yMin As Integer, yMax As Integer, scanY As Integer
    Dim ya As Single, yb As Single, t As Single

    last = poly.count
    If last < 2 Then Exit Sub

    ' Y extents, clipped to active viewport
    yMin = Int(poly.coords(1).y) : yMax = yMin
    For i1 = 2 To last
        If Int(poly.coords(i1).y) < yMin Then yMin = Int(poly.coords(i1).y)
        If Int(poly.coords(i1).y) > yMax Then yMax = Int(poly.coords(i1).y)
    Next i1
    If yMin < 0 Then yMin = 0
    If yMax >= E3D_zBufScrH Then yMax = E3D_zBufScrH - 1

    ' Per-scanline edge intersections — track x and z together so the sort keeps them paired.
    Dim xHits(1 To 16) As Single, zHits(1 To 16) As Single
    Dim hitCount As Integer, h As Integer
    Dim hxTmp As Single, hzTmp As Single
    Dim pxL As Integer, pxR As Integer, px As Integer
    Dim xSpan As Single, dzDx As Single, zPx As Single

    For scanY = yMin To yMax
        hitCount = 0
        For i1 = 1 To last
            i2 = (i1 Mod last) + 1
            ya = poly.coords(i1).y
            yb = poly.coords(i2).y
            If (ya <= scanY And yb > scanY) Or (yb <= scanY And ya > scanY) Then
                If hitCount < 16 Then
                    hitCount = hitCount + 1
                    t = (scanY - ya) / (yb - ya)
                    xHits(hitCount) = poly.coords(i1).x + t * (poly.coords(i2).x - poly.coords(i1).x)
                    zHits(hitCount) = poly.coords(i1).z + t * (poly.coords(i2).z - poly.coords(i1).z)
                End If
            End If
        Next i1
        ' Insertion-sort by x, keeping z paired.
        ' Guard and array access split: QB64-PE And has no short-circuit.
        For h = 2 To hitCount
            hxTmp = xHits(h) : hzTmp = zHits(h)
            i1 = h - 1
            Do While i1 >= 1
                If xHits(i1) <= hxTmp Then Exit Do
                xHits(i1 + 1) = xHits(i1)
                zHits(i1 + 1) = zHits(i1)
                i1 = i1 - 1
            Loop
            xHits(i1 + 1) = hxTmp
            zHits(i1 + 1) = hzTmp
        Next h
        ' Fill each span pixel-by-pixel with z-buffer test.
        ' z is interpolated linearly across the span (good enough at these scales).
        For h = 1 To hitCount - 1 Step 2
            pxL = Int(xHits(h))
            pxR = Int(xHits(h + 1))
            If pxL < 0 Then pxL = 0
            If pxR >= E3D_zBufScrW Then pxR = E3D_zBufScrW - 1
            If pxL <= pxR Then
                xSpan = xHits(h + 1) - xHits(h)
                If xSpan > 0.0001 Then
                    dzDx = (zHits(h + 1) - zHits(h)) / xSpan
                Else
                    dzDx = 0
                End If
                zPx = zHits(h) + (pxL - xHits(h)) * dzDx
                For px = pxL To pxR
                    If zPx < E3D_zBuf(px, scanY) Then
                        PSet (px, scanY), clr
                        E3D_zBuf(px, scanY) = zPx
                    End If
                    zPx = zPx + dzDx
                Next px
            End If
        Next h
    Next scanY
End Sub
