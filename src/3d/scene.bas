CONST E3D_SCENE_MAX  = 8192
CONST E3D_SCENE_VMAX = 8

DIM SHARED E3D_scnVCount(1 TO E3D_SCENE_MAX)                       AS INTEGER
DIM SHARED E3D_scnVX(1 TO E3D_SCENE_MAX, 1 TO E3D_SCENE_VMAX)     AS SINGLE
DIM SHARED E3D_scnVY(1 TO E3D_SCENE_MAX, 1 TO E3D_SCENE_VMAX)     AS SINGLE
DIM SHARED E3D_scnVZ(1 TO E3D_SCENE_MAX, 1 TO E3D_SCENE_VMAX)     AS SINGLE
DIM SHARED E3D_scnClrs(1 TO E3D_SCENE_MAX)                         AS LONG
DIM SHARED E3D_scnDepths(1 TO E3D_SCENE_MAX)                       AS SINGLE
DIM SHARED E3D_scnOrder(1 TO E3D_SCENE_MAX)                        AS INTEGER
DIM SHARED E3D_scnCount AS INTEGER

' Per-mesh face workspace — Shared to avoid stack allocation for large meshes.
DIM SHARED E3D_tmpPolys(1 TO E3D_SCENE_MAX)  AS E3D_Polygon
DIM SHARED E3D_tmpClrs(1 TO E3D_SCENE_MAX)   AS LONG
DIM SHARED E3D_tmpDepths(1 TO E3D_SCENE_MAX) AS SINGLE

SUB E3D_SceneBegin ()
    E3D_scnCount = 0
END SUB

SUB E3D_SceneAddMeshLit (mesh AS E3D_Mesh, modelMat AS E3D_Matrix4, camPos AS E3D_Coord, tt AS SINGLE, lightDir AS E3D_Coord)
    DIM fc AS INTEGER, i AS INTEGER, v AS INTEGER, n AS INTEGER, vc AS INTEGER
    E3D_GetMeshFacesLit mesh, modelMat, camPos, tt, lightDir, E3D_tmpPolys(), E3D_tmpClrs(), E3D_tmpDepths(), fc
    FOR i = 1 TO fc
        IF E3D_scnCount < E3D_SCENE_MAX THEN
            E3D_scnCount = E3D_scnCount + 1
            n = E3D_scnCount
            vc = E3D_tmpPolys(i).count
            E3D_scnVCount(n) = vc
            FOR v = 1 TO vc
                E3D_scnVX(n, v) = E3D_tmpPolys(i).coords(v).x
                E3D_scnVY(n, v) = E3D_tmpPolys(i).coords(v).y
                E3D_scnVZ(n, v) = E3D_tmpPolys(i).coords(v).z
            NEXT v
            E3D_scnClrs(n)   = E3D_tmpClrs(i)
            E3D_scnDepths(n) = E3D_tmpDepths(i)
            E3D_scnOrder(n)  = n
        END IF
    NEXT i
END SUB

SUB E3D_SceneAddMeshLitTinted (mesh AS E3D_Mesh, modelMat AS E3D_Matrix4, camPos AS E3D_Coord, tt AS SINGLE, lightDir AS E3D_Coord, tintR AS SINGLE, tintG AS SINGLE, tintB AS SINGLE)
    DIM scntFc AS INTEGER, scntI AS INTEGER, scntV AS INTEGER, scntN AS INTEGER, scntVc AS INTEGER
    E3D_GetMeshFacesLit mesh, modelMat, camPos, tt, lightDir, E3D_tmpPolys(), E3D_tmpClrs(), E3D_tmpDepths(), scntFc
    FOR scntI = 1 TO scntFc
        IF E3D_scnCount < E3D_SCENE_MAX THEN
            E3D_scnCount = E3D_scnCount + 1
            scntN  = E3D_scnCount
            scntVc = E3D_tmpPolys(scntI).count
            E3D_scnVCount(scntN) = scntVc
            FOR scntV = 1 TO scntVc
                E3D_scnVX(scntN, scntV) = E3D_tmpPolys(scntI).coords(scntV).x
                E3D_scnVY(scntN, scntV) = E3D_tmpPolys(scntI).coords(scntV).y
                E3D_scnVZ(scntN, scntV) = E3D_tmpPolys(scntI).coords(scntV).z
            NEXT scntV
            E3D_scnClrs(scntN)   = _RGB(INT(_Red32(E3D_tmpClrs(scntI)) * tintR), INT(_Green32(E3D_tmpClrs(scntI)) * tintG), INT(_Blue32(E3D_tmpClrs(scntI)) * tintB))
            E3D_scnDepths(scntN) = E3D_tmpDepths(scntI)
            E3D_scnOrder(scntN)  = scntN
        END IF
    NEXT scntI
END SUB

SUB E3D_SceneFlush (vpMat AS E3D_Matrix4, scrW AS SINGLE, scrH AS SINGLE)
    E3D_ZBufClear CINT(scrW), CINT(scrH)
    DIM scI AS INTEGER
    DIM oi1 AS INTEGER, oiTmp AS INTEGER
    DIM facePoly AS E3D_Polygon, screenPoly AS E3D_Polygon
    DIM di AS INTEGER, v AS INTEGER, vc AS INTEGER
    DIM c AS E3D_Coord

    ' Insertion sort — O(n) on nearly-sorted data (typical between frames).
    ' Guard and array access are split across two lines because QB64-PE And
    ' is bitwise (no short-circuit): the array subscript would be evaluated
    ' even when oi1=0, causing a subscript-out-of-range crash.
    FOR scI = 2 TO E3D_scnCount
        oiTmp = E3D_scnOrder(scI)
        oi1 = scI - 1
        DO WHILE oi1 >= 1
            IF E3D_scnDepths(E3D_scnOrder(oi1)) >= E3D_scnDepths(oiTmp) THEN EXIT DO
            E3D_scnOrder(oi1 + 1) = E3D_scnOrder(oi1)
            oi1 = oi1 - 1
        LOOP
        E3D_scnOrder(oi1 + 1) = oiTmp
    NEXT scI

    FOR scI = 1 TO E3D_scnCount
        di = E3D_scnOrder(scI)
        vc = E3D_scnVCount(di)
        E3D_MakePolygon facePoly
        FOR v = 1 TO vc
            c.x = E3D_scnVX(di, v)
            c.y = E3D_scnVY(di, v)
            c.z = E3D_scnVZ(di, v)
            E3D_AddCoord facePoly, c
        NEXT v
        E3D_ProjectPoly facePoly, vpMat, scrW, scrH, screenPoly
        E3D_DrawPoly screenPoly, E3D_scnClrs(di)
    NEXT scI
END SUB
