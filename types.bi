Type E3D_Coord
    x As Single
    y As Single
    z As Single
End Type

Type E3D_Polygon
    count As Integer
    coords(1 To 8) As E3D_Coord
End Type

Type E3D_Matrix4
    m(0 To 3, 0 To 3) As Single
End Type

Type E3D_Camera
    pos    As E3D_Coord
    target As E3D_Coord
    up     As E3D_Coord
    fov    As Single
    nearZ  As Single
    farZ   As Single
End Type

Type E3D_Face
    vIdx(1 To 8) As Integer
    vCount As Integer
    baseClr As Long
    nx As Single
    ny As Single
    nz As Single
End Type

Type E3D_Mesh
    verts(1 To 8192) As E3D_Coord
    vCount As Integer
    faces(1 To 8192) As E3D_Face
    fCount As Integer
End Type

Type E3D_AABB
    hx As Single
    hy As Single
    hz As Single
End Type
