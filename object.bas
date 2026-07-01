Sub E3D_BuildObjectMat (objPos As E3D_Coord, objRot As E3D_Coord, scl As Single, mx As E3D_Matrix4)
    Dim mRx As E3D_Matrix4, mRy As E3D_Matrix4, mRz As E3D_Matrix4
    Dim mS  As E3D_Matrix4, mT  As E3D_Matrix4, tmp As E3D_Matrix4
    E3D_MatRotateX mRx, objRot.x
    E3D_MatRotateY mRy, objRot.y
    E3D_MatRotateZ mRz, objRot.z
    E3D_MatScale   mS, scl, scl, scl
    E3D_MatTranslate mT, objPos.x, objPos.y, objPos.z
    E3D_MatMul mRx, mRy, tmp
    E3D_MatMul tmp, mRz, tmp
    E3D_MatMul mS, tmp, tmp
    E3D_MatMul mT, tmp, mx
End Sub
