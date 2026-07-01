$Resize:Smooth
'$INCLUDE:'engine3d.bi'

Dim scrW As Single, scrH As Single
scrW = 640 : scrH = 480
Screen _NewImage(scrW, scrH, 32)
Dim backBuffer As Long
backBuffer = _NewImage(scrW, scrH, 32)

' --- star polygon in world space ---
' Original screen coords centered at (320, 185.5), spanned ~300px.
' x = (sx-320)/150,  y = -(sy-185.5)/150  (Y negated for Y-up convention)
Dim modelPoly As E3D_Polygon
E3D_MakePolygon modelPoly
E3D_AddNode modelPoly,  0.000,  0.903, 0.0
E3D_AddNode modelPoly,  0.233,  0.230, 0.0
E3D_AddNode modelPoly,  0.953,  0.210, 0.0
E3D_AddNode modelPoly,  0.380, -0.223, 0.0
E3D_AddNode modelPoly,  0.587, -0.903, 0.0
E3D_AddNode modelPoly,  0.000, -0.497, 0.0
E3D_AddNode modelPoly, -0.587, -0.903, 0.0
E3D_AddNode modelPoly, -0.380, -0.223, 0.0
E3D_AddNode modelPoly, -0.953,  0.210, 0.0
E3D_AddNode modelPoly, -0.233,  0.230, 0.0

' --- background starfield ---
' 200 points scattered in world space. Camera drifts each frame so
' they parallax correctly against the moving polygon instances.
Dim starX(1 To 200) As Single
Dim starY(1 To 200) As Single
Dim starZ(1 To 200) As Single
Dim starClr(1 To 200) As Long
Dim starBrights(0 To 2) As Long
starBrights(0) = _RGB(80, 80, 100) : starBrights(1) = _RGB(160, 160, 180) : starBrights(2) = _RGB(255, 255, 255)
Randomize Timer
Dim si As Integer
For si = 1 To 200
    starX(si) = Rnd * 22 - 11
    starY(si) = Rnd * 14 - 7
    starZ(si) = Rnd * 14 + 0.5   ' 0.5 to 14.5 — all in front of camera
    starClr(si) = starBrights(Int(Rnd * 3))
Next si

' --- camera (drifts each frame for parallax) ---
Dim cam As E3D_Camera
E3D_MakeCamera cam, 0, 0, -4, 0, 0, 0, 60

' --- matrices ---
Dim projMat As E3D_Matrix4
E3D_MatPerspective cam, scrW / scrH, projMat

Dim viewMat As E3D_Matrix4, vpMat As E3D_Matrix4

Dim rxMat As E3D_Matrix4, ryMat As E3D_Matrix4, txMat As E3D_Matrix4
Dim tmpMat As E3D_Matrix4, modelMat As E3D_Matrix4, scaleMat As E3D_Matrix4
E3D_MatRotateX rxMat, 25                           ' constant tilt — baked once

' --- per-instance colors (white, red, cyan) ---
Dim instClr(0 To 2) As Long
instClr(0) = _RGB(255, 255, 255) : instClr(1) = _RGB(255, 80, 50) : instClr(2) = _RGB(50, 210, 255)

Dim phaseStep As Single
phaseStep = _PI * 2.0 / 3.0                        ' 120° between instances

Dim worldPoly As E3D_Polygon, screenPoly As E3D_Polygon

Dim rotY As Single, tt As Single
Dim posX As Single, posY As Single, posZ As Single
Dim phaseOff As Single
Dim inst As Integer

' star projection scratch vars
Dim svx As Single, svy As Single, svw As Single
Dim ssx As Single, ssy As Single

' Z-sort state
Dim instPosX(0 To 2) As Single, instPosY(0 To 2) As Single, instPosZ(0 To 2) As Single
Dim drawOrder(0 To 2) As Integer
Dim di As Integer, didSwap As Integer, swapTmp As Integer
Dim pulse As Single, breathe As Single, drawClr As Long
Dim baseR As Long, baseG As Long, baseB As Long
Dim ripplePoly As E3D_Polygon
Dim vi As Integer, wavePh As Single, vsc As Single
Dim ringPoly As E3D_Polygon, rTransPoly As E3D_Polygon, rScreenPoly As E3D_Polygon
Dim ringMat As E3D_Matrix4, ringClr As Long, ringOffset As Single
Dim ri As Integer, rz As Single, rlast As Integer, rvi As Integer, rAngle As Single

' --- per-instance pre-computed world polys and colors ---
Dim instWorldPoly(0 To 2) As E3D_Polygon
Dim instDrawClr(0 To 2) As Long

' --- E3D_GetMeshFaces output (cube face culling/depth extraction) ---
Dim cbFacePolys(1 To 32) As E3D_Polygon
Dim cbFaceClrs(1 To 32) As Long
Dim cbFaceDepths(1 To 32) As Single
Dim cbFaceCount As Integer

' --- unified scene Z-sort (max 9: up to 6 cube faces + 3 star instances) ---
Dim scenePolys(1 To 9) As E3D_Polygon
Dim sceneClrs(1 To 9) As Long
Dim sceneDepths(1 To 9) As Single
Dim sceneOrder(1 To 9) As Integer
Dim sceneCount As Integer, sceneI As Integer

' --- cube mesh ---
' Vertices:  1=LBF 2=RBF 3=RTF 4=LTF  5=LBK 6=RBK 7=RTK 8=LTK
Dim cubeMesh As E3D_Mesh
Dim cbRx As E3D_Matrix4, cbRy As E3D_Matrix4, cbTx As E3D_Matrix4, cbTmp As E3D_Matrix4, cbMat As E3D_Matrix4
Dim cbRotX As Single, cbRotY As Single

E3D_MakeMesh cubeMesh
E3D_AddMeshVert cubeMesh, -0.5, -0.5, -0.5
E3D_AddMeshVert cubeMesh,  0.5, -0.5, -0.5
E3D_AddMeshVert cubeMesh,  0.5,  0.5, -0.5
E3D_AddMeshVert cubeMesh, -0.5,  0.5, -0.5
E3D_AddMeshVert cubeMesh, -0.5, -0.5,  0.5
E3D_AddMeshVert cubeMesh,  0.5, -0.5,  0.5
E3D_AddMeshVert cubeMesh,  0.5,  0.5,  0.5
E3D_AddMeshVert cubeMesh, -0.5,  0.5,  0.5
E3D_AddQuadFace cubeMesh, 1, 4, 3, 2, 0  ' front
E3D_AddQuadFace cubeMesh, 5, 6, 7, 8, 0  ' back
E3D_AddQuadFace cubeMesh, 2, 3, 7, 6, 0  ' right
E3D_AddQuadFace cubeMesh, 1, 5, 8, 4, 0  ' left
E3D_AddQuadFace cubeMesh, 4, 8, 7, 3, 0  ' top
E3D_AddQuadFace cubeMesh, 1, 2, 6, 5, 0  ' bottom

' --- ring tunnel setup (24-sided circle, radius 2.8) ---
ringClr = _RGB(0, 55, 90)
E3D_MakePolygon ringPoly
For ri = 1 To 24
    rAngle = _PI * 2.0 * (ri - 1) / 24
    E3D_AddNode ringPoly, Cos(rAngle) * 2.8, Sin(rAngle) * 2.8, 0
Next ri

Do
    If _Resize Then
        scrW = _ResizeWidth : scrH = _ResizeHeight
        _FreeImage backBuffer
        Screen _NewImage(scrW, scrH, 32)
        backBuffer = _NewImage(scrW, scrH, 32)
        E3D_MatPerspective cam, scrW / scrH, projMat
    End If

    tt = tt + 0.025

    ' Gently drift camera so background stars parallax
    cam.pos.x = Sin(tt * 0.11) * 0.8
    cam.pos.y = Cos(tt * 0.17) * 0.4
    cam.pos.z = -4
    cam.target.x = Sin(tt * 0.09) * 0.3
    cam.target.y = Cos(tt * 0.13) * 0.2
    cam.target.z = 0
    E3D_MatLookAt cam, viewMat
    E3D_MatMul projMat, viewMat, vpMat

    _Dest backBuffer
    Line (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 0, 40), BF

    ' --- ring tunnel ---
    ' Rings span rz = -2.0 to 14.0 (16 units). At rz=-2 the projected radius
    ' (~580px) exceeds the screen half-diagonal (~400px), so rings enter from
    ' off-screen and shrink toward the vanishing point — no visible pop-in.
    ringOffset = ringOffset + 0.022
    If ringOffset >= 1.333 Then ringOffset = ringOffset - 1.333
    For ri = 0 To 11
        rz = -2.0 + ri * 1.333 + ringOffset
        If rz > 14.0 Then rz = rz - 16.0
        If rz > -3.5 Then
            E3D_MatTranslate ringMat, 0, 0, rz
            E3D_MatTransformPoly ringPoly, ringMat, rTransPoly
            E3D_ProjectPoly rTransPoly, vpMat, scrW, scrH, rScreenPoly
            rlast = rScreenPoly.count
            For rvi = 1 To rlast - 1
                E3D_DrawLine rScreenPoly.coords(rvi), rScreenPoly.coords(rvi + 1), ringClr
            Next rvi
            E3D_DrawLine rScreenPoly.coords(rlast), rScreenPoly.coords(1), ringClr
        End If
    Next ri

    ' --- starfield ---
    For si = 1 To 200
        svx = starX(si) * vpMat.m(0,0) + starY(si) * vpMat.m(0,1) + starZ(si) * vpMat.m(0,2) + vpMat.m(0,3)
        svy = starX(si) * vpMat.m(1,0) + starY(si) * vpMat.m(1,1) + starZ(si) * vpMat.m(1,2) + vpMat.m(1,3)
        svw = starX(si) * vpMat.m(3,0) + starY(si) * vpMat.m(3,1) + starZ(si) * vpMat.m(3,2) + vpMat.m(3,3)
        If svw > 0.00001 Then
            ssx = (svx / svw + 1.0) * (scrW * 0.5)
            ssy = (1.0 - svy / svw) * (scrH * 0.5)
            If ssx >= 0 And ssx < scrW And ssy >= 0 And ssy < scrH Then
                PSet (ssx, ssy), starClr(si)
            End If
        End If
    Next si

    ' --- cube: build model matrix, extract visible faces into scene arrays ---
    cbRotX = cbRotX + 0.5
    cbRotY = cbRotY + 0.8
    E3D_MatRotateX cbRx, cbRotX
    E3D_MatRotateY cbRy, cbRotY
    E3D_MatMul cbRx, cbRy, cbTmp
    E3D_MatTranslate cbTx, 0, 0, 2.5
    E3D_MatMul cbTx, cbTmp, cbMat
    E3D_GetMeshFaces cubeMesh, cbMat, cam.pos, tt, cbFacePolys(), cbFaceClrs(), cbFaceDepths(), cbFaceCount

    ' --- star instances: compute world-space polys and colors ---
    For inst = 0 To 2
        phaseOff = inst * phaseStep
        instPosX(inst) = Sin(tt * 0.5 + phaseOff) * 1.8
        instPosY(inst) = Sin(tt * 0.3 + phaseOff) * 0.5
        instPosZ(inst) = 2.5 + Cos(tt * 0.5 + phaseOff) * 1.8

        pulse = 0.6 + 0.4 * Sin(tt * 2.7 + inst * phaseStep)
        baseR = _Red32(instClr(inst))
        baseG = _Green32(instClr(inst))
        baseB = _Blue32(instClr(inst))
        instDrawClr(inst) = _RGB(Int(baseR * pulse), Int(baseG * pulse), Int(baseB * pulse))

        breathe = 0.85 + 0.15 * Sin(tt * 1.3 + inst * phaseStep)

        E3D_MatRotateY ryMat, rotY + inst * 40
        E3D_MatMul rxMat, ryMat, tmpMat
        E3D_MatScale scaleMat, breathe, breathe, breathe
        E3D_MatMul tmpMat, scaleMat, tmpMat
        E3D_MatTranslate txMat, instPosX(inst), instPosY(inst), instPosZ(inst)
        E3D_MatMul txMat, tmpMat, modelMat
        ripplePoly = modelPoly
        For vi = 1 To ripplePoly.count
            wavePh = tt * 4.1 + vi * _PI * 0.4 + inst * phaseStep
            vsc = 1.0 + 0.18 * Sin(wavePh)
            ripplePoly.coords(vi).x = modelPoly.coords(vi).x * vsc
            ripplePoly.coords(vi).y = modelPoly.coords(vi).y * vsc
        Next vi
        E3D_MatTransformPoly ripplePoly, modelMat, instWorldPoly(inst)
    Next inst

    ' --- build unified scene list: cube faces then star instances ---
    sceneCount = 0
    For sceneI = 1 To cbFaceCount
        sceneCount = sceneCount + 1
        scenePolys(sceneCount) = cbFacePolys(sceneI)
        sceneClrs(sceneCount) = cbFaceClrs(sceneI)
        sceneDepths(sceneCount) = cbFaceDepths(sceneI)
        sceneOrder(sceneCount) = sceneCount
    Next sceneI
    For inst = 0 To 2
        sceneCount = sceneCount + 1
        scenePolys(sceneCount) = instWorldPoly(inst)
        sceneClrs(sceneCount) = instDrawClr(inst)
        sceneDepths(sceneCount) = instPosZ(inst)
        sceneOrder(sceneCount) = sceneCount
    Next inst

    ' --- unified painter's sort: back-to-front (highest Z first) ---
    Do
        didSwap = 0
        For sceneI = 1 To sceneCount - 1
            If sceneDepths(sceneOrder(sceneI)) < sceneDepths(sceneOrder(sceneI + 1)) Then
                swapTmp = sceneOrder(sceneI)
                sceneOrder(sceneI) = sceneOrder(sceneI + 1)
                sceneOrder(sceneI + 1) = swapTmp
                didSwap = 1
            End If
        Next sceneI
    Loop While didSwap

    ' --- draw unified scene in sorted order ---
    For sceneI = 1 To sceneCount
        di = sceneOrder(sceneI)
        E3D_ProjectPoly scenePolys(di), vpMat, scrW, scrH, screenPoly
        E3D_DrawPoly screenPoly, sceneClrs(di)
    Next sceneI

    _Dest 0
    _PutImage , backBuffer, 0
    _Limit 60

    rotY = rotY + 1.5
    If rotY >= 360 Then rotY = 0

Loop Until InKey$ <> ""
