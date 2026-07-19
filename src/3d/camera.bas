Sub E3D_MakeCamera (cam As E3D_Camera, px As Single, py As Single, pz As Single, tx As Single, ty As Single, tz As Single, fovDeg As Single)
    cam.pos.x = px    : cam.pos.y = py    : cam.pos.z = pz
    cam.target.x = tx : cam.target.y = ty : cam.target.z = tz
    cam.up.x = 0      : cam.up.y = 1      : cam.up.z = 0
    cam.fov   = fovDeg
    cam.nearZ = 0.1
    cam.farZ  = 100.0
End Sub

' Builds a view matrix from camera position and target (look-at).
' Transforms world-space coords into camera space where the camera
' sits at the origin looking down -Z with Y up.
Sub E3D_MatLookAt (cam As E3D_Camera, mat As E3D_Matrix4)
    Dim fwd As E3D_Coord, rVec As E3D_Coord, upVec As E3D_Coord, tmp As E3D_Coord

    tmp.x = cam.target.x - cam.pos.x
    tmp.y = cam.target.y - cam.pos.y
    tmp.z = cam.target.z - cam.pos.z
    E3D_Vec3Normalize tmp, fwd

    E3D_Vec3Cross fwd, cam.up, tmp
    E3D_Vec3Normalize tmp, rVec

    E3D_Vec3Cross rVec, fwd, upVec

    Dim d0 As Single, d1 As Single, d2 As Single
    E3D_Vec3Dot rVec,  cam.pos, d0
    E3D_Vec3Dot upVec, cam.pos, d1
    E3D_Vec3Dot fwd,   cam.pos, d2

    E3D_MatIdentity mat
    mat.m(0, 0) =  rVec.x
    mat.m(0, 1) =  rVec.y
    mat.m(0, 2) =  rVec.z
    mat.m(0, 3) = -d0
    mat.m(1, 0) =  upVec.x
    mat.m(1, 1) =  upVec.y
    mat.m(1, 2) =  upVec.z
    mat.m(1, 3) = -d1
    mat.m(2, 0) = -fwd.x
    mat.m(2, 1) = -fwd.y
    mat.m(2, 2) = -fwd.z
    mat.m(2, 3) =  d2
    mat.m(3, 3) =  1
End Sub

' Standard perspective projection matrix.
' After multiplying a vertex by this, divide by w (perspective divide)
' to get NDC coords in [-1, 1]. E3D_ProjectPoly handles that step.
Sub E3D_MatPerspective (cam As E3D_Camera, aspectRatio As Single, mat As E3D_Matrix4)
    Dim f As Single, n As Single, fa As Single
    f  = 1.0 / Tan(_PI * cam.fov / 360.0)
    n  = cam.nearZ
    fa = cam.farZ
    E3D_MatIdentity mat
    mat.m(0, 0) =  f / aspectRatio
    mat.m(1, 1) =  f
    mat.m(2, 2) =  (fa + n) / (n - fa)
    mat.m(2, 3) =  (2.0 * fa * n) / (n - fa)
    mat.m(3, 2) = -1.0
    mat.m(3, 3) =  0.0
End Sub

' Projects a world-space polygon to screen-space using a combined
' view-projection matrix. Output coords are in screen pixels.
' Vertices behind the camera (w <= 0) are sent off-screen.
Sub E3D_ProjectPoly (worldPoly As E3D_Polygon, vpMat As E3D_Matrix4, screenW As Single, screenH As Single, outPoly As E3D_Polygon)
    Dim i As Integer
    Dim c As E3D_Coord, sc As E3D_Coord
    Dim x As Single, y As Single, z As Single, w As Single

    E3D_MakePolygon outPoly

    For i = 1 To worldPoly.count
        c = worldPoly.coords(i)

        x = c.x * vpMat.m(0,0) + c.y * vpMat.m(0,1) + c.z * vpMat.m(0,2) + vpMat.m(0,3)
        y = c.x * vpMat.m(1,0) + c.y * vpMat.m(1,1) + c.z * vpMat.m(1,2) + vpMat.m(1,3)
        z = c.x * vpMat.m(2,0) + c.y * vpMat.m(2,1) + c.z * vpMat.m(2,2) + vpMat.m(2,3)
        w = c.x * vpMat.m(3,0) + c.y * vpMat.m(3,1) + c.z * vpMat.m(3,2) + vpMat.m(3,3)

        If w > 0.00001 Then
            sc.x = (x / w + 1.0) * screenW * 0.5
            sc.y = (1.0 - y / w) * screenH * 0.5
            sc.z =  z / w
        Else
            ' vertex behind near plane — abort; caller sees count=0 and skips draw
            E3D_MakePolygon outPoly
            Exit Sub
        End If
        E3D_AddCoord outPoly, sc
    Next i
End Sub
