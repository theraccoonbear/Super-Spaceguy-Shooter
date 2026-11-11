' viewer.bas — interactive model viewer for models.e3d, models_enemies_v2.e3d (E2_* meshes) and models_ships_v2.e3d (S2_* player and boss meshes)
' Usage: viewer [file.obj]   (OBJ loaded as extra mesh; auto-reads .mtl)
'        viewer --sheets <outdir>   (headless: write the old/new enemy, player and boss review PNGs to <outdir>, then exit;
'                                    needs a display for the software renderer, e.g. Xvfb; a relative
'                                    <outdir> is resolved against the launch directory and created if missing)
' Left/Right: rotate model   Up/Down: tilt camera
' PgUp/PgDn: cycle meshes   R: reset rotation
' Gamepad: left stick rotate/tilt, d-pad left/right mesh, d-pad up/down tilt, A light, X reset, Back quit
' L: toggle light mode       ESC/Q: quit

Option _Explicit
'$INCLUDE:'src/sys/failfast.bi'
$Resize:stretch
$EMBED:'assets/models.e3d':'MODELS'
$EMBED:'assets/models_enemies_v2.e3d':'NEWMODELS'
$EMBED:'assets/models_ships_v2.e3d':'SHIPMODELS'

'$INCLUDE:'src/sys/rng.bas'
'$INCLUDE:'src/engine3d.bi'

CONST SCR_W      = 640
CONST SCR_H      = 480
CONST MESH_COUNT = 25
CONST MESH_MAX   = 32

DIM SHARED meshNames(1 TO MESH_MAX) AS STRING
meshNames(1)  = "PLAYER"
meshNames(2)  = "S2_PLAYER"
meshNames(3)  = "ENEMY"
meshNames(4)  = "E2_SOLO"
meshNames(5)  = "ASTEROID"
meshNames(6)  = "BULLET"
meshNames(7)  = "PUP_SHIELD"
meshNames(8)  = "ENEMY_ARROW"
meshNames(9)  = "E2_ARROW"
meshNames(10) = "ENEMY_HLINE"
meshNames(11) = "E2_HLINE"
meshNames(12) = "ENEMY_VCOL"
meshNames(13) = "E2_VCOL"
meshNames(14) = "ENEMY_PINCER"
meshNames(15) = "E2_PINCER"
meshNames(16) = "ENEMY_VWEDGE"
meshNames(17) = "E2_VWEDGE"
meshNames(18) = "THRUSTER"
meshNames(19) = "EBULLET"
meshNames(20) = "BOSS"
meshNames(21) = "S2_BOSS_BASTION"
meshNames(22) = "S2_BOSS_HYDRA"
meshNames(23) = "S2_BOSS_ORBITER"
meshNames(24) = "PUP_FUEL"
meshNames(25) = "PUP_POINTS"

DIM SHARED meshLib(1 TO MESH_MAX) AS E3D_Mesh
DIM SHARED boxLib(1 TO MESH_MAX)  AS E3D_AABB

' --headless review sheets: viewer --sheets <outdir>
DIM SHARED sheetDir AS STRING
DIM argAll AS STRING : argAll = LTRIM$(RTRIM$(COMMAND$))
IF LEFT$(argAll, 8) = "--sheets" THEN sheetDir = LTRIM$(MID$(argAll, 9))

' Screen must exist before E3D_LoadMesh so _RGB inside the loader
' returns proper 32-bit colors instead of text-mode palette indices.
DIM SHARED backBuffer AS LONG
IF LEN(sheetDir) > 0 THEN
    SCREEN _NEWIMAGE(320, 240, 32)
    backBuffer = _NEWIMAGE(320, 240, 32)
ELSE
    SCREEN _NEWIMAGE(SCR_W, SCR_H, 32)
    backBuffer = _NEWIMAGE(SCR_W, SCR_H, 32)
END IF
_TITLE "SSS Model Viewer"

DIM mdl AS STRING
DIM mdlNew AS STRING
mdl = _EMBEDDED$("MODELS")
mdlNew = _EMBEDDED$("NEWMODELS")
DIM mdlShip AS STRING
mdlShip = _EMBEDDED$("SHIPMODELS")
DIM mi AS INTEGER
FOR mi = 1 TO MESH_COUNT
    IF LEFT$(meshNames(mi), 3) = "S2_" THEN
        E3D_LoadMesh mdlShip, meshNames(mi), meshLib(mi), boxLib(mi)
    ELSEIF LEFT$(meshNames(mi), 3) = "E2_" THEN
        E3D_LoadMesh mdlNew, meshNames(mi), meshLib(mi), boxLib(mi)
    ELSE
        E3D_LoadMesh mdl, meshNames(mi), meshLib(mi), boxLib(mi)
    END IF
    E3D_BakeMeshNormals meshLib(mi)
    IF meshLib(mi).fCount = 0 THEN
        PRINT "missing mesh " + meshNames(mi)
        SYSTEM 2
    END IF
NEXT mi

IF LEN(sheetDir) > 0 THEN
    ' Renders each old enemy and its E2_ replacement with the game's camera, light and distance dimming.
    ' Writes <outdir>/<old|new>_<type>_<near|far>_<chase|q3|side|front>.png at 320x240.
    ' chase = the in-game camera; the others orbit the enemy at the chase distance (enemies fly nose-first toward -X).
    CONST SH_FOV = 72
    CONST SH_CAM_X = 6.72      ' CAM_CHASE_X in src/sys/dims.bas
    CONST SH_CAM_Y = 1.04      ' CAM_CHASE_Y
    CONST SH_LEAD = 8
    CONST SH_SCL = 1.1         ' mid of the 0.9..1.3 spawn range
    CONST SH_DIM_FAR = 55
    CONST SH_DIM_NEAR = 28
    CONST SH_DIM_AMB = 0.22
    DIM shKey(1 TO 6) AS STRING, shOld(1 TO 6) AS INTEGER
    shKey(1) = "solo"   : shOld(1) = 3
    shKey(2) = "arrow"  : shOld(2) = 8
    shKey(3) = "hline"  : shOld(3) = 10
    shKey(4) = "vcol"   : shOld(4) = 12
    shKey(5) = "pincer" : shOld(5) = 14
    shKey(6) = "vwedge" : shOld(6) = 16
    ' a relative path is taken against the launch directory, since QB64-PE starts in the executable's directory
    IF LEFT$(sheetDir, 1) <> "/" AND MID$(sheetDir, 2, 1) <> ":" THEN sheetDir = _STARTDIR$ + "/" + sheetDir
    DO WHILE LEN(sheetDir) > 1 AND (RIGHT$(sheetDir, 1) = "/" OR RIGHT$(sheetDir, 1) = "\")
        sheetDir = LEFT$(sheetDir, LEN(sheetDir) - 1)
    LOOP
    IF _DIREXISTS(sheetDir) = 0 THEN MKDIR sheetDir
    IF _DIREXISTS(sheetDir) = 0 THEN
        PRINT "cannot create output directory " + sheetDir
        SYSTEM 2
    END IF
    DIM shCam AS E3D_Camera, shViewM AS E3D_Matrix4, shProj AS E3D_Matrix4, shVP AS E3D_Matrix4
    DIM shPos AS E3D_Coord, shRot AS E3D_Coord, shObj AS E3D_Matrix4, shLit AS E3D_Coord, shLightBase AS E3D_Coord
    DIM shSet AS INTEGER, shTy AS INTEGER, shDist AS INTEGER, shView AS INTEGER, shIdx AS INTEGER
    DIM shD AS SINGLE, shDimF AS SINGLE, shR AS SINGLE, shEl AS SINGLE
    DIM shTag AS STRING, shDistName AS STRING, shViewName AS STRING
    shLightBase.x = -0.4 : shLightBase.y = 0.7 : shLightBase.z = -0.5
    FOR shSet = 1 TO 2
        FOR shTy = 1 TO 6
            IF shSet = 1 THEN shIdx = shOld(shTy) : shTag = "old" ELSE shIdx = shOld(shTy) + 1 : shTag = "new"
            PRINT shTag + " " + shKey(shTy) + " " + meshNames(shIdx) + " verts=" + LTRIM$(STR$(meshLib(shIdx).vCount)) + " faces=" + LTRIM$(STR$(meshLib(shIdx).fCount))
            FOR shDist = 1 TO 2
                IF shDist = 1 THEN shD = 3 : shDistName = "near" ELSE shD = 25 : shDistName = "far"
                shDimF = 1.0
                IF shD > SH_DIM_FAR THEN
                    shDimF = SH_DIM_AMB
                ELSEIF shD > SH_DIM_NEAR THEN
                    shDimF = SH_DIM_AMB + (shD - SH_DIM_NEAR) * ((1.0 - SH_DIM_AMB) / (SH_DIM_FAR - SH_DIM_NEAR))
                END IF
                shLit.x = shLightBase.x * shDimF : shLit.y = shLightBase.y * shDimF : shLit.z = shLightBase.z * shDimF
                shR = shD + SH_CAM_X
                FOR shView = 1 TO 4
                    SELECT CASE shView
                        CASE 1 : shViewName = "chase"
                        CASE 2 : shViewName = "q3"    : shEl = 0.35
                        CASE 3 : shViewName = "side"  : shEl = 0.12
                        CASE 4 : shViewName = "front" : shEl = 0.0
                    END SELECT
                    shPos.x = shD : shPos.y = 0 : shPos.z = 0
                    IF shView = 1 THEN
                        E3D_MakeCamera shCam, -SH_CAM_X, SH_CAM_Y, 0, SH_LEAD, 0, 0, SH_FOV
                    ELSEIF shView = 4 THEN
                        E3D_MakeCamera shCam, shD - shR * COS(shEl), shR * SIN(shEl), 0, shD, 0, 0, SH_FOV
                    ELSEIF shView = 2 THEN
                        E3D_MakeCamera shCam, shD - shR * COS(shEl) * 0.7071, shR * SIN(shEl), shR * COS(shEl) * 0.7071, shD, 0, 0, SH_FOV
                    ELSE
                        E3D_MakeCamera shCam, shD, shR * SIN(shEl), shR * COS(shEl), shD, 0, 0, SH_FOV
                    END IF
                    shCam.nearZ = 0.1 : shCam.farZ = 120
                    E3D_MatLookAt shCam, shViewM
                    E3D_MatPerspective shCam, 320 / 240, shProj
                    E3D_MatMul shProj, shViewM, shVP
                    _DEST backBuffer
                    LINE (0, 0)-(319, 239), _RGB(4, 5, 22), BF
                    shRot.x = 0 : shRot.y = 0 : shRot.z = 0
                    E3D_BuildObjectMat shPos, shRot, SH_SCL, shObj
                    E3D_SceneBegin
                    E3D_SceneAddMeshLit meshLib(shIdx), shObj, shCam.POS, 0, shLit
                    E3D_SceneFlush shVP, 320, 240
                    _DEST 0
                    _SAVEIMAGE sheetDir + "/" + shTag + "_" + shKey(shTy) + "_" + shDistName + "_" + shViewName + ".png", backBuffer
                NEXT shView
            NEXT shDist
        NEXT shTy
    NEXT shSet
    SHEET_Ship 1, "old", "player", 0
    SHEET_Ship 2, "new", "player", 0
    SHEET_Ship 20, "old", "boss", -1
    SHEET_Ship 21, "new", "boss_bastion", -1
    SHEET_Ship 22, "new", "boss_hydra", -1
    SHEET_Ship 23, "new", "boss_orbiter", -1
    PRINT "wrote sheets to " + sheetDir
    SYSTEM 0
END IF

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
        objStatus = "NOT FOUND: " + cmdPath + "  (cwd=" + _CWD$ + ")"
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
DIM padPrevWas AS INTEGER, padNextWas AS INTEGER, padAWas AS INTEGER, padXWas AS INTEGER
DIM padHatX AS SINGLE, padHatY AS SINGLE, padStX AS SINGLE, padStY AS SINGLE
DIM padMeshStep AS INTEGER, padLightHit AS INTEGER, padResetHit AS INTEGER
DIM heldPad(0 TO 32767) AS INTEGER
E3D_CtrlInit

' ============================================================
' MAIN LOOP
' ============================================================
DO
    tt = tt + 0.016

    ' --- gamepad: src/3d/input.bas reads and maps the pad; the stick and d-pad are read from its raw axes ---
    E3D_InputUpdate heldPad()
    padStX = 0 : padStY = 0 : padHatX = 0 : padHatY = 0
    IF ctrlDev > 0 THEN
        IF ABS(padRawAxis(E3D_CTRL_AXIS_X)) > E3D_AXIS_DEADZONE THEN padStX = padRawAxis(E3D_CTRL_AXIS_X)
        IF ABS(padRawAxis(E3D_CTRL_AXIS_Y)) > E3D_AXIS_DEADZONE THEN padStY = padRawAxis(E3D_CTRL_AXIS_Y)
        IF ABS(padRawAxis(E3D_CTRL_HAT_X)) > E3D_AXIS_DEADZONE THEN padHatX = padRawAxis(E3D_CTRL_HAT_X)
        IF ABS(padRawAxis(E3D_CTRL_HAT_Y)) > E3D_AXIS_DEADZONE THEN padHatY = padRawAxis(E3D_CTRL_HAT_Y)
    END IF
    padMeshStep = 0
    IF padHatX < 0 THEN
        IF padPrevWas = 0 THEN padMeshStep = -1
        padPrevWas = -1
    ELSE
        padPrevWas = 0
    END IF
    IF padHatX > 0 THEN
        IF padNextWas = 0 THEN padMeshStep = 1
        padNextWas = -1
    ELSE
        padNextWas = 0
    END IF
    padLightHit = 0
    IF heldPad(E3D_KEY_PAD_A) <> 0 THEN
        IF padAWas = 0 THEN padLightHit = -1
        padAWas = -1
    ELSE
        padAWas = 0
    END IF
    padResetHit = 0
    IF heldPad(E3D_KEY_PAD_X) <> 0 THEN
        IF padXWas = 0 THEN padResetHit = -1
        padXWas = -1
    ELSE
        padXWas = 0
    END IF
    IF padMeshStep <> 0 THEN
        currentMesh = currentMesh + padMeshStep
        IF currentMesh < 1 THEN currentMesh = totalMeshes
        IF currentMesh > totalMeshes THEN currentMesh = 1
        rot.x = 0 : rot.y = 0 : rot.z = 0
    END IF
    rot.y = rot.y + padStX * 2.0
    camPitch = camPitch + padStY * 0.02 + SGN(padHatY) * 0.02

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
IF padResetHit THEN rot.x = 0 : rot.y = 0 : rot.z = 0
IF _KEYDOWN(82) OR _KEYDOWN(114) THEN
    IF NOT resetWas THEN rot.x = 0 : rot.y = 0 : rot.z = 0
    resetWas = -1
ELSE
    resetWas = 0
END IF

' --- toggle light mode: L ---
IF padLightHit THEN litMode = NOT litMode
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
LINE (0, SCR_H - 52)-(SCR_W - 1, SCR_H - 1), _RGBA(0, 0, 0, 210), BF
COLOR _RGB(160, 200, 160)
_PRINTSTRING (4, SCR_H - 50), _
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
    _PRINTSTRING (4, SCR_H - 34), _
    "[PgUp/Dn]  [</> rot]  [up/dn tilt]  [R reset]  [L:" + litLabel + "]  [X remap:" + remapLabel + "]  [ESC/Q]"
ELSE
    _PRINTSTRING (4, SCR_H - 34), _
    "[PgUp/Dn mesh]  [</> rotate]  [up/dn tilt]  [R reset]  [L:" + litLabel + "]  [ESC/Q]"
END IF

IF ctrlDev > 0 THEN COLOR _RGB(110, 150, 190) ELSE COLOR _RGB(70, 80, 100)
_PRINTSTRING (4, SCR_H - 18), "PAD: stick rot+tilt  dpad L/R mesh  dpad U/D tilt  A light  X reset  Back quit"

_LIMIT 60
_DISPLAY

LOOP UNTIL _KEYDOWN(27) OR _KEYDOWN(113) OR _KEYDOWN(81) OR heldPad(E3D_KEY_PAD_SELECT) <> 0

END

' src/3d/input.bas logs via the game's DBG_Print (src/sys/debug.bas), which this tool doesn't include
Sub DBG_Print (dbgMsg As String)
End Sub

' Review sheets for the player (rear views) and a boss (front views), 320x240 like the game.
' <outdir>/<old|new>_<key>_<view>.png; "chase" is the in-game camera (boss 20 ahead of the player).
SUB SHEET_Ship (shIdx AS INTEGER, shTag AS STRING, shKey AS STRING, shBoss AS INTEGER)
    DIM shCam AS E3D_Camera, shViewM AS E3D_Matrix4, shProj AS E3D_Matrix4, shVP AS E3D_Matrix4
    DIM shPos AS E3D_Coord, shRot AS E3D_Coord, shObj AS E3D_Matrix4, shLit AS E3D_Coord
    DIM shView AS INTEGER, shViewName AS STRING
    DIM shEx AS SINGLE, shEy AS SINGLE, shEz AS SINGLE, shTx AS SINGLE, shTy AS SINGLE, shTz AS SINGLE
    PRINT shTag + " " + shKey + " " + meshNames(shIdx) + " verts=" + LTRIM$(STR$(meshLib(shIdx).vCount)) + " faces=" + LTRIM$(STR$(meshLib(shIdx).fCount))
    shLit.x = -0.4 : shLit.y = 0.7 : shLit.z = -0.5
    shPos.x = 0 : shPos.y = 0 : shPos.z = 0
    IF shBoss THEN shPos.x = 20
    FOR shView = 1 TO 4
        SELECT CASE shView
            CASE 1 : shViewName = "chase" : shEx = -6.72 : shEy = 1.04 : shEz = 0 : shTx = 8 : shTy = 0 : shTz = 0
            CASE 2
                IF shBoss THEN
                    shViewName = "front" : shEx = shPos.x - 15 : shEy = 1.5 : shEz = 0 : shTx = shPos.x : shTy = 0 : shTz = 0
                ELSE
                    shViewName = "rear_q3" : shEx = -3.4 : shEy = 1.8 : shEz = 2.2 : shTx = 0 : shTy = 0 : shTz = 0
                END IF
            CASE 3
                IF shBoss THEN
                    shViewName = "front_q3" : shEx = shPos.x - 12 : shEy = 3 : shEz = 9 : shTx = shPos.x : shTy = 0 : shTz = 0
                ELSE
                    shViewName = "rear" : shEx = -3.2 : shEy = 1.1 : shEz = 0 : shTx = 0 : shTy = 0 : shTz = 0
                END IF
            CASE 4
                shViewName = "side" : shEx = shPos.x : shEy = 1 : shEz = 4 : IF shBoss THEN shEz = 18
                shTx = shPos.x : shTy = 0 : shTz = 0
        END SELECT
        E3D_MakeCamera shCam, shEx, shEy, shEz, shTx, shTy, shTz, 72
        shCam.nearZ = 0.1 : shCam.farZ = 120
        E3D_MatLookAt shCam, shViewM
        E3D_MatPerspective shCam, 320 / 240, shProj
        E3D_MatMul shProj, shViewM, shVP
        _DEST backBuffer
        LINE (0, 0)-(319, 239), _RGB(4, 5, 22), BF
        shRot.x = 0 : shRot.y = 0 : shRot.z = 0
        E3D_BuildObjectMat shPos, shRot, 1.0, shObj
        E3D_SceneBegin
        E3D_SceneAddMeshLit meshLib(shIdx), shObj, shCam.POS, 0, shLit
        E3D_SceneFlush shVP, 320, 240
        _DEST 0
        _SAVEIMAGE sheetDir + "/" + shTag + "_" + shKey + "_" + shViewName + ".png", backBuffer
    NEXT shView
END SUB
