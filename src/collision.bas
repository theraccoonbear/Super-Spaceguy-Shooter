' Sets hit to -1 if the two world-space AABBs overlap, 0 if not.
' Centers passed as scalars; half-extents in the AABB structs.
Sub E3D_AABBOverlap (ax As Single, ay As Single, az As Single, a As E3D_AABB, _
                     bx As Single, by As Single, bz As Single, b As E3D_AABB, hit As Integer)
    hit = 0
    If Abs(ax - bx) > a.hx + b.hx Then Exit Sub
    If Abs(ay - by) > a.hy + b.hy Then Exit Sub
    If Abs(az - bz) > a.hz + b.hz Then Exit Sub
    hit = -1
End Sub
