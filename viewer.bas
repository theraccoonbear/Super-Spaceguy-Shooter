' viewer.bas — interactive model viewer for models.e3d
' Usage: viewer [file.obj]   (OBJ loaded as extra mesh; auto-reads .mtl)
' Left/Right: rotate model   Up/Down: tilt camera
' PgUp/PgDn: cycle meshes   R: reset rotation
' L: toggle light mode       ESC/Q: quit

$Resize:stretch
$EMBED:'assets/models.e3d':'MODELS'

'$INCLUDE:'src/engine3d.bi'
'$INCLUDE:'src/3d/obj.bas'

CONST SCR_W      = 640
CONST SCR_H      = 480
CONST MESH_COUNT = 13
CONST MESH_MAX   = 32

DIM meshNames(1 TO MESH_MAX) AS STRING
meshNames(1)  = "PLAYER"
meshNames(2)  = "ENEMY"
meshNames(3)  = "ASTEROID"
meshNames(4)  = "BULLET"
meshNames(5)  = "POWERUP"
meshNames(6)  = "ENEMY_ARROW"
meshNames(7)  = "ENEMY_HLINE"
meshNames(8)  = "ENEMY_VCOL"
meshNames(9)  = "ENEMY_PINCER"
meshNames(10) = "ENEMY_VWEDGE"
meshNames(11) = "THRUSTER"
meshNames(12) = "EBULLET"
meshNames(13) = "BOSS"

DIM meshLib(1 TO MESH_MAX) AS E3D_Mesh
DIM boxLib(1 TO MESH_MAX)  AS E3D_AABB

' Screen must exist before E3D_LoadMesh so _RGB inside the loader
' returns proper 32-bit colors instead of text-mode palette indices.
DIM backBuffer AS LONG
SCREEN _NEWIMAGE(SCR_W, SCR_H, 32)
_TITLE "SSS Model Viewer"
backBuffer = _NEWIMAGE(SCR_W, SCR_H, 32)

DIM mdl AS STRING
mdl = _EMBEDDED$("MODELS")
DIM mi AS INTEGER
FOR mi = 1 TO MESH_COUNT
    E3D_LoadMesh mdl, meshNames(mi), meshLib(mi), boxLib(mi)
    E3D_BakeMeshNormals meshLib(mi)
NEXT mi

DIM totalMeshes AS INTEGER : totalMeshes = MESH_COUNT
DIM objStatus   AS STRING
DIM axisRemap   AS INTEGER : axisRemap = 0   ' 0=none 1=Blender(-Z) 2=(+Z)

' --- load OBJ from command-line path if given ---
DIM cmdPath AS STRING : cmdPath = LTRIM$(RTRIM$(COMMAND$))
' Resolve relative paths against the launch directory (_STARTDIR$),
' since QB64-PE sets CWD to the executable's directory on startup.
IF LEN(cmdPath) > 0 THEN
    IF LEFT$(cmdPath, 1) <> "/" AND LEFT$(cmdPath, 1) <> "\" THEN
        cmdPath = _STARTDIR$ + "/" + cmdPath
    END IF
END IF
IF LEN(cmdPath) > 0 THEN
    IF _FILEEXISTS(cmdPath) THEN
        DIM objF  AS INTEGER : objF  = FREEFILE
        DIM objRawDat AS STRING            ' kept for live-reload on remap toggle
        DIM objDat    AS STRING
        DIM mtlDat    AS STRING
        OPEN cmdPath FOR BINARY AS #objF
        objRawDat = SPACE$(LOF(objF))
        GET #objF, , objRawDat
        CLOSE #objF
        objDat = objRawDat                 ' first load — loader consumes this copy
        DIM mtlPath AS STRING : mtlPath = E3D_OBJMtlPath$(cmdPath, objRawDat)
        IF LEN(mtlPath) > 0 THEN
            IF _FILEEXISTS(mtlPath) THEN
                DIM mtlF AS INTEGER : mtlF = FREEFILE
                OPEN mtlPath FOR BINARY AS #mtlF
                mtlDat = SPACE$(LOF(mtlF))
                GET #mtlF, , mtlDat
                CLOSE #mtlF
            END IF
        END IF
        totalMeshes = MESH_COUNT + 1
        ' Use just the filename (strip directory)
        DIM slashAt AS INTEGER, sli AS INTEGER
        FOR sli = LEN(cmdPath) TO 1 STEP -1
            IF MID$(cmdPath, sli, 1) = "/" OR MID$(cmdPath, sli, 1) = "\" THEN
                slashAt = sli : EXIT FOR
            END IF
        NEXT sli
        meshNames(totalMeshes) = MID$(cmdPath, slashAt + 1)
        E3D_LoadOBJ objDat, mtlDat, meshLib(totalMeshes), boxLib(totalMeshes), axisRemap, 1.0
        E3D_BakeMeshNormals meshLib(totalMeshes)
        objStatus = "OBJ: " + meshNames(totalMeshes) + " [" + LTRIM$(STR$(meshLib(totalMeshes).vCount)) + "v " + LTRIM$(STR$(meshLib(totalMeshes).fCount)) + "f]"
    ELSE
        objStatus = "NOT FOUND: " + cmdPath + "  (cwd=" + CURDIR$ + ")"
    END IF
END IF

DIM cam      AS E3D_Camera
DIM viewMat  AS E3D_Matrix4
DIM projMat  AS E3D_Matrix4
DIM vpMat    AS E3D_Matrix4
DIM objMat   AS E3D_Matrix4
DIM objPos   AS E3D_Coord
DIM rot      AS E3D_Coord
DIM lightDir AS E3D_Coord
DIM diagLight AS E3D_Coord : diagLight.x = 0.577 : diagLight.y = 0.577 : diagLight.z = -0.577

DIM currentMesh AS INTEGER : currentMesh = 1
IF totalMeshes > MESH_COUNT THEN currentMesh = totalMeshes
DIM camPitch    AS SINGLE  : camPitch    = 0.4
DIM camAngle    AS SINGLE  : camAngle    = 0.6
DIM camDist     AS SINGLE  : camDist     = 6.0
DIM autoRotY    AS SINGLE  : autoRotY    = 0.015
DIM litMode     AS INTEGER : litMode     = 0    ' 0=headlamp  -1=dramatic
DIM tt          AS SINGLE

' Edge-trigger state
DIM pgupWas  AS INTEGER, pgdnWas  AS INTEGER
DIM resetWas AS INTEGER, litWas   AS INTEGER
DIM xWas     AS INTEGER

' ============================================================
' MAIN LOOP
' ============================================================
DO
    tt = tt + 0.016

    ' --- mesh cycle: PgUp / PgDn ---
    IF _KEYDOWN(18688) THEN          ' PgUp
    IF NOT pgupWas THEN
        currentMesh = currentMesh - 1
        IF currentMesh < 1 THEN currentMesh = totalMeshes
        rot.x = 0 : rot.y = 0 : rot.z = 0
    END IF
    pgupWas = -1
ELSE
    pgupWas = 0
END IF
IF _KEYDOWN(20736) THEN          ' PgDn
IF NOT pgdnWas THEN
    currentMesh = currentMesh + 1
    IF currentMesh > totalMeshes THEN currentMesh = 1
    rot.x = 0 : rot.y = 0 : rot.z = 0
END IF
pgdnWas = -1
ELSE
    pgdnWas = 0
END IF

' --- manual rotation: Left/Right arrows ---
IF _KEYDOWN(19200) THEN rot.y = rot.y - 2.0   ' left  arrow
IF _KEYDOWN(19712) THEN rot.y = rot.y + 2.0   ' right arrow

' --- camera tilt: Up/Down arrows ---
IF _KEYDOWN(18432) THEN camPitch = camPitch - 0.02   ' up   arrow
IF _KEYDOWN(20480) THEN camPitch = camPitch + 0.02   ' down arrow
IF camPitch < -1.4 THEN camPitch = -1.4
IF camPitch >  1.4 THEN camPitch =  1.4

' --- reset rotation: R ---
IF _KEYDOWN(82) OR _KEYDOWN(114) THEN
    IF NOT resetWas THEN rot.x = 0 : rot.y = 0 : rot.z = 0
    resetWas = -1
ELSE
    resetWas = 0
END IF

' --- toggle light mode: L ---
IF _KEYDOWN(76) OR _KEYDOWN(108) THEN
    IF NOT litWas THEN litMode = NOT litMode
    litWas = -1
ELSE
    litWas = 0
END IF

' --- cycle axis remap: X (OBJ only) ---
IF LEN(objRawDat) > 0 THEN
    IF _KEYDOWN(88) OR _KEYDOWN(120) THEN
        IF NOT xWas THEN
            axisRemap = (axisRemap + 1) MOD 3
            DIM reloadDat AS STRING : reloadDat = objRawDat
            E3D_LoadOBJ reloadDat, mtlDat, meshLib(totalMeshes), boxLib(totalMeshes), axisRemap, 1.0
            E3D_BakeMeshNormals meshLib(totalMeshes)
            rot.x = 0 : rot.y = 0 : rot.z = 0
        END IF
        xWas = -1
    ELSE
        xWas = 0
    END IF
END IF

' --- auto rotate ---
rot.y = rot.y + autoRotY

' --- display scale: normalise largest AABB extent to ~2 units ---
DIM maxExt AS SINGLE
maxExt = boxLib(currentMesh).hx
IF boxLib(currentMesh).hy > maxExt THEN maxExt = boxLib(currentMesh).hy
IF boxLib(currentMesh).hz > maxExt THEN maxExt = boxLib(currentMesh).hz
IF maxExt < 0.05 THEN maxExt = 0.3
DIM dispScale AS SINGLE
dispScale = 2.2 / maxExt

' --- camera ---
DIM cx AS SINGLE, cy AS SINGLE, cz AS SINGLE
cx = camDist * COS(camPitch) * COS(camAngle)
cy = camDist * SIN(camPitch)
cz = camDist * COS(camPitch) * SIN(camAngle)
E3D_MakeCamera cam, cx, cy, cz, 0, 0, 0, 55
cam.nearZ = 0.1 : cam.farZ = 60
E3D_MatLookAt cam, viewMat
E3D_MatPerspective cam, SCR_W / SCR_H, projMat
E3D_MatMul projMat, viewMat, vpMat

' Camera-headlamp: light from camera toward origin, scale-compensated.
' E3D_BuildObjectMat bakes dispScale into the 3x3 of modelMat, so rotated
' normals have magnitude dispScale rather than 1. Dividing lightDir by
' dispScale cancels this out, giving scale-independent dot products.
DIM lmag AS SINGLE
lmag = SQR(cx * cx + cy * cy + cz * cz)
IF lmag > 0.0001 AND dispScale > 0.0001 THEN
    lightDir.x = (cx / lmag) / dispScale * 1.0
    lightDir.y = (cy / lmag) / dispScale * 1.0
    lightDir.z = (cz / lmag) / dispScale * 1.0
END IF

' --- render ---
_DEST backBuffer
LINE (0, 0)-(SCR_W - 1, SCR_H - 1), _RGB(8, 8, 20), BF

' Floor grid for depth reference
DIM gi AS INTEGER
FOR gi = -5 TO 5
    DIM ga AS E3D_Coord, gb AS E3D_Coord
    DIM gsa AS E3D_Polygon, gsb AS E3D_Polygon
    ga.x = gi : ga.y = -2.3 : ga.z = -5
    gb.x = gi : gb.y = -2.3 : gb.z =  5
    E3D_MakePolygon gsa : E3D_AddCoord gsa, ga : E3D_AddCoord gsa, gb
    E3D_ProjectPoly gsa, vpMat, SCR_W, SCR_H, gsb
    IF gsb.count = 2 THEN E3D_DrawLine gsb.coords(1), gsb.coords(2), _RGBA(30, 30, 50, 255)
    ga.x = -5 : ga.z = gi : gb.x = 5 : gb.z = gi
    E3D_MakePolygon gsa : E3D_AddCoord gsa, ga : E3D_AddCoord gsa, gb
    E3D_ProjectPoly gsa, vpMat, SCR_W, SCR_H, gsb
    IF gsb.count = 2 THEN E3D_DrawLine gsb.coords(1), gsb.coords(2), _RGBA(30, 30, 50, 255)
NEXT gi

objPos.x = 0 : objPos.y = 0 : objPos.z = 0
E3D_BuildObjectMat objPos, rot, dispScale, objMat

E3D_SceneBegin
IF litMode THEN
    E3D_SceneAddMeshLit meshLib(currentMesh), objMat, cam.POS, tt, diagLight
ELSE
    E3D_SceneAddMeshLit meshLib(currentMesh), objMat, cam.POS, tt, lightDir
END IF
E3D_SceneFlush vpMat, SCR_W, SCR_H

' --- HUD ---
_DEST 0
_PUTIMAGE , backBuffer, 0

' top bar: mesh name and index
LINE (0, 0)-(SCR_W - 1, 18), _RGBA(0, 0, 0, 210), BF
COLOR _RGB(255, 220, 80)
_PRINTSTRING (4, 2), "[" + LTRIM$(STR$(currentMesh)) + "/" + LTRIM$(STR$(totalMeshes)) + "]  " + meshNames(currentMesh)

' bottom bar: stats + controls
LINE (0, SCR_H - 36)-(SCR_W - 1, SCR_H - 1), _RGBA(0, 0, 0, 210), BF
COLOR _RGB(160, 200, 160)
_PRINTSTRING (4, SCR_H - 34), _
"V:" + LTRIM$(STR$(meshLib(currentMesh).vCount)) + _
"  F:" + LTRIM$(STR$(meshLib(currentMesh).fCount)) + _
"  AABB " + LEFT$(STR$(boxLib(currentMesh).hx + 100), 5) + _
" x" + LEFT$(STR$(boxLib(currentMesh).hy + 100), 5) + _
" x" + LEFT$(STR$(boxLib(currentMesh).hz + 100), 5)
DIM litLabel  AS STRING
DIM remapLabel AS STRING
IF litMode THEN litLabel = "dramatic" ELSE litLabel = "headlamp"
SELECT CASE axisRemap
    CASE 1 : remapLabel = "-Z→X"
    CASE 2 : remapLabel = "+Z→X"
    CASE ELSE : remapLabel = "none"
END SELECT
COLOR _RGB(130, 140, 160)
IF LEN(objRawDat) > 0 THEN
    _PRINTSTRING (4, SCR_H - 18), _
    "[PgUp/Dn]  [</> rot]  [up/dn tilt]  [R reset]  [L:" + litLabel + "]  [X remap:" + remapLabel + "]  [ESC/Q]"
ELSE
    _PRINTSTRING (4, SCR_H - 18), _
    "[PgUp/Dn mesh]  [</> rotate]  [up/dn tilt]  [R reset]  [L:" + litLabel + "]  [ESC/Q]"
END IF

_LIMIT 60
_DISPLAY

LOOP UNTIL _KEYDOWN(27) OR _KEYDOWN(113) OR _KEYDOWN(81)

END
