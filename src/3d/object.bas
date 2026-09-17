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

' Build an object matrix directly from an orthonormal forward/up/right basis,
' bypassing Euler angles entirely. Rx*Ry*Rz composition (E3D_BuildObjectMat)
' cannot represent banking at arbitrary yaw -- at high yaw, neither pitch (Rx)
' nor roll (Rz) can tilt the model correctly, so it pitches when it should bank.
' tools/turn_viz.bas's VIZ_BuildBossObjMat (commit 46547c9) found and fixed
' this for a debug tool; this is the same fix ported to the real renderer.
'
' Canonical mapping, no per-mesh sign-flips here: col0=forward, col1=up,
' col2=right -- identical in form to TrailForge's makeBasis(facing, rolledU,
' rolledR) in tools/TrailForge/src/views/PerspView.tsx. A mesh whose source
' .obj doesn't match this convention (e.g. BOSS, nose authored at local -X)
' is corrected ONCE at load time instead (see the "axisfix" line in
' assets/models.e3d, applied by E3D_LoadMesh) -- not by negating here.
Sub E3D_BuildObjectMatBasis (objPos As E3D_Coord, _
                             fwdX As Single, fwdY As Single, fwdZ As Single, _
                             upX As Single, upY As Single, upZ As Single, _
                             rgtX As Single, rgtY As Single, rgtZ As Single, _
                             scl As Single, mx As E3D_Matrix4)
    E3D_MatIdentity mx
    mx.m(0, 0) = fwdX * scl : mx.m(1, 0) = fwdY * scl : mx.m(2, 0) = fwdZ * scl
    mx.m(0, 1) = upX  * scl : mx.m(1, 1) = upY  * scl : mx.m(2, 1) = upZ  * scl
    mx.m(0, 2) = rgtX * scl : mx.m(1, 2) = rgtY * scl : mx.m(2, 2) = rgtZ * scl
    mx.m(0, 3) = objPos.x : mx.m(1, 3) = objPos.y : mx.m(2, 3) = objPos.z
End Sub
