' outline_test.bas -- mesh silhouette outlines (src/3d/outline.bas, #195)
'
' Drives the real engine on small hand-built meshes and the shipped models:
'   1. edge adjacency: a cube has 12 edges of two faces each, the same cube with a private vertex
'      per face (as an OBJ conversion can make) gives the same 12, an open quad has 4 boundary
'      edges, an edge shared by three faces keeps two and is counted as non-manifold
'   2. silhouette edges for known camera directions: face-on 4, corner-on 6, from behind 4;
'      an open quad shows its boundary from the front only
'   3. an outline is collected only for a mesh asked to be outlined
'   4. depth test: an edge draws where nothing is nearer, is hidden behind a nearer surface, is
'      skipped behind the camera and clipped at the screen edge; width 2 adds a second row
'   5. render.ini loads, and bad values are rejected without changing anything
'   6. every shipped mesh builds its edges inside the pool
'
' Build: tools/dev test (builds and runs every test)
' Run:   builds/outline_test   (exit 0 = all pass)

$CONSOLE:ONLY
Option _Explicit

$EMBED:'assets/models.e3d':'MODELS'
$EMBED:'assets/config/render.ini':'CFGRENDER'

Sub DBG_Print (otDbg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/config.bas'

Dim Shared otPassed As Integer, otFailed As Integer

Sub OT_Assert (otaCond As Integer, otaName As String)
    _Dest _Console
    If otaCond Then
        Print "PASS  " + otaName
        otPassed = otPassed + 1
    Else
        Print "FAIL  " + otaName
        otFailed = otFailed + 1
    End If
End Sub

Sub OT_Cube (otcMesh As E3D_Mesh, otcSplit As Integer)
    Dim otcI As Integer, otcF As Integer, otcK As Integer
    Dim otcFace(1 To 6, 1 To 4) As Integer
    Dim otcCorner(1 To 8, 1 To 3) As Single
    E3D_MakeMesh otcMesh
    otcCorner(1, 1) = -.5 : otcCorner(1, 2) = -.5 : otcCorner(1, 3) = -.5
    otcCorner(2, 1) = .5 : otcCorner(2, 2) = -.5 : otcCorner(2, 3) = -.5
    otcCorner(3, 1) = .5 : otcCorner(3, 2) = .5 : otcCorner(3, 3) = -.5
    otcCorner(4, 1) = -.5 : otcCorner(4, 2) = .5 : otcCorner(4, 3) = -.5
    otcCorner(5, 1) = -.5 : otcCorner(5, 2) = -.5 : otcCorner(5, 3) = .5
    otcCorner(6, 1) = .5 : otcCorner(6, 2) = -.5 : otcCorner(6, 3) = .5
    otcCorner(7, 1) = .5 : otcCorner(7, 2) = .5 : otcCorner(7, 3) = .5
    otcCorner(8, 1) = -.5 : otcCorner(8, 2) = .5 : otcCorner(8, 3) = .5
    ' faces +x -x +y -y +z -z, wound so the normal points out
    otcFace(1, 1) = 2 : otcFace(1, 2) = 3 : otcFace(1, 3) = 7 : otcFace(1, 4) = 6
    otcFace(2, 1) = 1 : otcFace(2, 2) = 5 : otcFace(2, 3) = 8 : otcFace(2, 4) = 4
    otcFace(3, 1) = 4 : otcFace(3, 2) = 8 : otcFace(3, 3) = 7 : otcFace(3, 4) = 3
    otcFace(4, 1) = 1 : otcFace(4, 2) = 2 : otcFace(4, 3) = 6 : otcFace(4, 4) = 5
    otcFace(5, 1) = 5 : otcFace(5, 2) = 6 : otcFace(5, 3) = 7 : otcFace(5, 4) = 8
    otcFace(6, 1) = 1 : otcFace(6, 2) = 4 : otcFace(6, 3) = 3 : otcFace(6, 4) = 2
    If otcSplit = 0 Then
        For otcI = 1 To 8
            E3D_AddMeshVert otcMesh, otcCorner(otcI, 1), otcCorner(otcI, 2), otcCorner(otcI, 3)
        Next otcI
        For otcF = 1 To 6
            E3D_AddQuadFace otcMesh, otcFace(otcF, 1), otcFace(otcF, 2), otcFace(otcF, 3), otcFace(otcF, 4), _RGB32(200, 200, 200)
        Next otcF
    Else
        For otcF = 1 To 6
            For otcK = 1 To 4
                E3D_AddMeshVert otcMesh, otcCorner(otcFace(otcF, otcK), 1), otcCorner(otcFace(otcF, otcK), 2), otcCorner(otcFace(otcF, otcK), 3)
            Next otcK
            E3D_AddQuadFace otcMesh, (otcF - 1) * 4 + 1, (otcF - 1) * 4 + 2, (otcF - 1) * 4 + 3, (otcF - 1) * 4 + 4, _RGB32(200, 200, 200)
        Next otcF
    End If
    E3D_BakeMeshNormals otcMesh
End Sub

' Silhouette edges collected for mesh seen from (cx, cy, cz), unmoved.
Function OT_Silhouettes% (otsMesh As E3D_Mesh, otsX As Single, otsY As Single, otsZ As Single)
    Dim otsMat As E3D_Matrix4, otsCam As E3D_Coord, otsLight As E3D_Coord, otsFc As Integer
    E3D_MatIdentity otsMat
    otsCam.x = otsX : otsCam.y = otsY : otsCam.z = otsZ
    otsLight.x = 0 : otsLight.y = 1 : otsLight.z = 0
    E3D_GetMeshFacesLit otsMesh, otsMat, otsCam, 0, otsLight, E3D_tmpPolys(), E3D_tmpClrs(), E3D_tmpDepths(), otsFc
    E3D_scnEdgeCount = 0
    E3D_OutlineCollect otsMesh
    OT_Silhouettes% = E3D_scnEdgeCount
End Function

Function OT_Boundary% (otbMesh As E3D_Mesh)
    Dim otbE As Integer, otbN As Integer
    For otbE = otbMesh.eStart To otbMesh.eStart + otbMesh.eCount - 1
        If E3D_edgeF2(otbE) = 0 Then otbN = otbN + 1
    Next otbE
    OT_Boundary% = otbN
End Function

Function OT_Lit%(otlImg As Long, otlX As Integer, otlY As Integer)
    Dim otlP As _Unsigned Long
    _Source otlImg
    otlP = Point(otlX, otlY)
    OT_Lit% = (_Red32(otlP) = _Red32(E3D_outlineClr)) And (_Green32(otlP) = _Green32(E3D_outlineClr)) And (_Blue32(otlP) = _Blue32(E3D_outlineClr))
End Function

Dim Shared otMesh As E3D_Mesh
Dim Shared otMesh2 As E3D_Mesh
Dim Shared otVp As E3D_Matrix4
Dim otImg As Long, otN As Integer, otOk As Integer, otI As Integer, otTotal As Integer
Dim otMdl As String, otName As String, otBoxes As E3D_AABB
Dim otNames(1 To 15) As String

E3D_outlineOn = -1
E3D_outlineClr = _RGB32(8, 8, 16)
E3D_outlineWidth = 1

Print "=== outline_test ==="

' --- 1. adjacency ---
OT_Cube otMesh, 0
E3D_BuildMeshEdges otMesh
OT_Assert otMesh.eCount = 12, "cube has 12 edges (got" + Str$(otMesh.eCount) + ")"
OT_Assert OT_Boundary%(otMesh) = 0, "cube has no boundary edge"
OT_Cube otMesh2, -1
E3D_BuildMeshEdges otMesh2
OT_Assert otMesh2.eCount = 12, "cube with a vertex per face still has 12 edges (got" + Str$(otMesh2.eCount) + ")"
OT_Assert OT_Boundary%(otMesh2) = 0, "welded cube has no boundary edge"
OT_Assert otMesh2.eStart = otMesh.eStart + 12, "the second mesh's edges follow the first's in the pool"

E3D_MakeMesh otMesh
E3D_AddMeshVert otMesh, -.5, -.5, .5
E3D_AddMeshVert otMesh, .5, -.5, .5
E3D_AddMeshVert otMesh, .5, .5, .5
E3D_AddMeshVert otMesh, -.5, .5, .5
E3D_AddQuadFace otMesh, 1, 2, 3, 4, _RGB32(200, 200, 200)
E3D_BakeMeshNormals otMesh
E3D_BuildMeshEdges otMesh
OT_Assert otMesh.eCount = 4 And OT_Boundary%(otMesh) = 4, "open quad has 4 boundary edges"

E3D_MakeMesh otMesh2
E3D_AddMeshVert otMesh2, 0, 0, 0
E3D_AddMeshVert otMesh2, 0, 1, 0
E3D_AddMeshVert otMesh2, 1, 0, 0
E3D_AddMeshVert otMesh2, -1, 0, 0
E3D_AddMeshVert otMesh2, 0, 0, 1
E3D_AddTriFace otMesh2, 1, 2, 3, _RGB32(200, 200, 200)
E3D_AddTriFace otMesh2, 1, 4, 2, _RGB32(200, 200, 200)
E3D_AddTriFace otMesh2, 1, 2, 5, _RGB32(200, 200, 200)
E3D_edgeNonManifold = 0
E3D_BuildMeshEdges otMesh2
OT_Assert otMesh2.eCount = 7, "three triangles on one edge make 7 edges (got" + Str$(otMesh2.eCount) + ")"
OT_Assert E3D_edgeNonManifold = 1, "the third face on an edge is counted as non-manifold"
OT_Assert E3D_edgeF1(otMesh2.eStart) = 1 And E3D_edgeF2(otMesh2.eStart) = 2, "the shared edge keeps its first two faces"

' --- 2. silhouettes ---
OT_Cube otMesh, 0
E3D_BuildMeshEdges otMesh
OT_Assert OT_Silhouettes%(otMesh, 5, 0, 0) = 4, "cube seen face-on: 4 silhouette edges"
OT_Assert OT_Silhouettes%(otMesh, -5, 0, 0) = 4, "cube seen from the other side: 4"
OT_Assert OT_Silhouettes%(otMesh, 0, 0, 5) = 4, "cube seen along z: 4"
OT_Assert OT_Silhouettes%(otMesh, 4, 4, 4) = 6, "cube seen corner-on: the 6-edge hexagon"
OT_Assert OT_Silhouettes%(otMesh, -4, -4, -4) = 6, "cube seen from the opposite corner: 6"
OT_Cube otMesh2, -1
E3D_BuildMeshEdges otMesh2
OT_Assert OT_Silhouettes%(otMesh2, 4, 4, 4) = 6, "cube with a vertex per face: no seam lines, still 6"
OT_Assert OT_Silhouettes%(otMesh2, 5, 0, 0) = 4, "cube with a vertex per face, face-on: 4"

E3D_MakeMesh otMesh
E3D_AddMeshVert otMesh, -.5, -.5, .5
E3D_AddMeshVert otMesh, .5, -.5, .5
E3D_AddMeshVert otMesh, .5, .5, .5
E3D_AddMeshVert otMesh, -.5, .5, .5
E3D_AddQuadFace otMesh, 1, 2, 3, 4, _RGB32(200, 200, 200)
E3D_BakeMeshNormals otMesh
E3D_BuildMeshEdges otMesh
OT_Assert OT_Silhouettes%(otMesh, 0, 0, 5) = 4, "open quad seen from the front: its 4 boundary edges"
OT_Assert OT_Silhouettes%(otMesh, 0, 0, -5) = 0, "open quad seen from behind: none"

' --- 3. only an outlined mesh collects ---
OT_Cube otMesh, 0
E3D_BuildMeshEdges otMesh
E3D_outlineOn = 0
OT_Assert OT_Silhouettes%(otMesh, 5, 0, 0) = 0, "outline off: nothing collected"
E3D_outlineOn = -1
Dim otMat As E3D_Matrix4, otCam As E3D_Coord, otLight As E3D_Coord
E3D_MatIdentity otMat
otCam.x = 5 : otLight.y = 1
E3D_SceneBegin
E3D_SceneAddMeshLit otMesh, otMat, otCam, 0, otLight, 0
OT_Assert E3D_scnEdgeCount = 0 And E3D_scnCount = 1, "scene add without the flag: faces only"
E3D_SceneBegin
E3D_SceneAddMeshLit otMesh, otMat, otCam, 0, otLight, -1
OT_Assert E3D_scnEdgeCount = 4 And E3D_scnCount = 1, "scene add with the flag: faces and 4 edges"
E3D_SceneBegin
OT_Assert E3D_scnEdgeCount = 0, "SceneBegin clears the edges"

' --- 4. drawing ---
otImg = _NewImage(32, 32, 32)
_Dest otImg
Line (0, 0)-(31, 31), _RGB32(0, 0, 0), BF
E3D_outlineClr = _RGB32(255, 255, 255)
E3D_MatIdentity otVp
E3D_ZBufClear 32, 32
E3D_scnEdgeCount = 1
E3D_scnEdge(1, 1) = -.5 : E3D_scnEdge(1, 2) = 0 : E3D_scnEdge(1, 3) = 0
E3D_scnEdge(1, 4) = .5 : E3D_scnEdge(1, 5) = 0 : E3D_scnEdge(1, 6) = 0
E3D_OutlineDraw otVp, 32, 32
OT_Assert OT_Lit%(otImg, 16, 16) And OT_Lit%(otImg, 10, 16) And OT_Lit%(otImg, 22, 16), "edge draws along its row"
OT_Assert OT_Lit%(otImg, 6, 16) = 0 And OT_Lit%(otImg, 26, 16) = 0 And OT_Lit%(otImg, 16, 15) = 0 And OT_Lit%(otImg, 16, 17) = 0, "edge stays on its row and between its ends"

_Dest otImg
Line (0, 0)-(31, 31), _RGB32(0, 0, 0), BF
E3D_ZBufClear 32, 32
E3D_zBuf(16, 16) = -0.5
E3D_zBuf(17, 16) = 0.0 - E3D_OUTLINE_BIAS * 0.5
E3D_zBuf(18, 16) = 0.0 - E3D_OUTLINE_BIAS * 2
E3D_OutlineDraw otVp, 32, 32
OT_Assert OT_Lit%(otImg, 16, 16) = 0, "hidden where a nearer surface was drawn"
OT_Assert OT_Lit%(otImg, 17, 16) <> 0, "the depth bias keeps an edge on its own surface"
OT_Assert OT_Lit%(otImg, 18, 16) = 0, "an edge just beyond the bias is hidden"
OT_Assert OT_Lit%(otImg, 15, 16) <> 0 And OT_Lit%(otImg, 19, 16) <> 0, "visible either side of the hidden pixels"

_Dest otImg
Line (0, 0)-(31, 31), _RGB32(0, 0, 0), BF
E3D_ZBufClear 32, 32
E3D_outlineWidth = 2
E3D_OutlineDraw otVp, 32, 32
OT_Assert OT_Lit%(otImg, 16, 16) And OT_Lit%(otImg, 16, 17) And OT_Lit%(otImg, 16, 15) = 0, "width 2 adds a second row"
E3D_outlineWidth = 1

_Dest otImg
Line (0, 0)-(31, 31), _RGB32(0, 0, 0), BF
E3D_ZBufClear 32, 32
E3D_scnEdge(1, 1) = -5 : E3D_scnEdge(1, 4) = 5
E3D_OutlineDraw otVp, 32, 32
OT_Assert OT_Lit%(otImg, 0, 16) And OT_Lit%(otImg, 31, 16), "an edge running off the screen is clipped, not dropped"

_Dest otImg
Line (0, 0)-(31, 31), _RGB32(0, 0, 0), BF
E3D_ZBufClear 32, 32
E3D_scnEdge(1, 1) = -9 : E3D_scnEdge(1, 4) = -8 : E3D_scnEdge(1, 2) = 20 : E3D_scnEdge(1, 5) = 20
E3D_OutlineDraw otVp, 32, 32
otOk = -1
For otI = 0 To 31
    If OT_Lit%(otImg, otI, 0) Or OT_Lit%(otImg, otI, 31) Or OT_Lit%(otImg, 0, otI) Or OT_Lit%(otImg, 31, otI) Then otOk = 0
Next otI
OT_Assert otOk, "an edge wholly off the screen draws nothing"

_Dest otImg
Line (0, 0)-(31, 31), _RGB32(0, 0, 0), BF
E3D_ZBufClear 32, 32
E3D_scnEdge(1, 1) = -.5 : E3D_scnEdge(1, 4) = .5 : E3D_scnEdge(1, 2) = 0 : E3D_scnEdge(1, 5) = 0
otVp.m(3, 3) = -1
E3D_OutlineDraw otVp, 32, 32
OT_Assert OT_Lit%(otImg, 16, 16) = 0, "an edge with an end behind the camera is skipped"
E3D_MatIdentity otVp

E3D_outlineOn = 0
_Dest otImg
Line (0, 0)-(31, 31), _RGB32(0, 0, 0), BF
E3D_ZBufClear 32, 32
E3D_OutlineDraw otVp, 32, 32
OT_Assert OT_Lit%(otImg, 16, 16) = 0, "outline off: nothing drawn"
E3D_outlineOn = -1
_FreeImage otImg

' --- 5. config ---
cfgRender = CFG_Parse$(_EMBEDDED$("CFGRENDER"))
E3D_outlineOn = 7 : E3D_outlineWidth = 9 : E3D_outlineClr = 0
otOk = E3D_OutlineConfig%(CFG_Get$(cfgRender, "outline"), CFG_Get$(cfgRender, "outline_color"), CFG_Get$(cfgRender, "outline_width"))
OT_Assert otOk <> 0, "the shipped render.ini loads " + E3D_outlineErr
OT_Assert E3D_outlineOn = -1 And E3D_outlineWidth >= 1 And E3D_outlineWidth <= 2, "the shipped values are on and 1 or 2 px"
otOk = E3D_OutlineConfig%("0", "1,2,3", "2")
OT_Assert otOk <> 0 And E3D_outlineOn = 0 And E3D_outlineWidth = 2 And E3D_outlineClr = _RGB32(1, 2, 3), "0 / 1,2,3 / 2 are read"
E3D_outlineOn = -1 : E3D_outlineWidth = 1 : E3D_outlineClr = _RGB32(9, 9, 9)
OT_Assert E3D_OutlineConfig%("2", "1,2,3", "2") = 0 And InStr(E3D_outlineErr, "outline must be") > 0, "outline of 2 is rejected"
OT_Assert E3D_OutlineConfig%("", "1,2,3", "2") = 0, "a missing outline is rejected"
OT_Assert E3D_OutlineConfig%("1", "1,2", "2") = 0 And InStr(E3D_outlineErr, "r,g,b") > 0, "two colour values are rejected"
OT_Assert E3D_OutlineConfig%("1", "1,2,3,4", "2") = 0, "four colour values are rejected"
OT_Assert E3D_OutlineConfig%("1", "1,2,256", "2") = 0 And InStr(E3D_outlineErr, "0-255") > 0, "a colour value above 255 is rejected"
OT_Assert E3D_OutlineConfig%("1", "-1,2,3", "2") = 0, "a negative colour value is rejected"
OT_Assert E3D_OutlineConfig%("1", "1,2,3", "3") = 0 And InStr(E3D_outlineErr, "outline_width") > 0, "width 3 is rejected"
OT_Assert E3D_outlineOn = -1 And E3D_outlineWidth = 1 And E3D_outlineClr = _RGB32(9, 9, 9), "a rejected config changes nothing"

' --- 6. the shipped meshes ---
otNames(1) = "PLAYER" : otNames(2) = "ENEMY" : otNames(3) = "ASTEROID" : otNames(4) = "BULLET"
otNames(5) = "PUP_SHIELD" : otNames(6) = "ENEMY_ARROW" : otNames(7) = "ENEMY_HLINE" : otNames(8) = "ENEMY_VCOL"
otNames(9) = "ENEMY_PINCER" : otNames(10) = "ENEMY_VWEDGE" : otNames(11) = "THRUSTER" : otNames(12) = "EBULLET"
otNames(13) = "BOSS" : otNames(14) = "PUP_FUEL" : otNames(15) = "PUP_POINTS"
otOk = -1
E3D_edgeNonManifold = 0
For otI = 1 To 15
    otMdl = _EMBEDDED$("MODELS")
    E3D_LoadMesh otMdl, otNames(otI), otMesh, otBoxes
    E3D_BakeMeshNormals otMesh
    E3D_BuildMeshEdges otMesh
    If otMesh.eCount < 1 Then otOk = 0
    otTotal = otTotal + otMesh.eCount
    Print otNames(otI) + ": verts" + Str$(otMesh.vCount) + " faces" + Str$(otMesh.fCount) + " edges" + Str$(otMesh.eCount) + " boundary" + Str$(OT_Boundary%(otMesh))
Next otI
OT_Assert otOk, "every shipped mesh has edges"
Print "edge pool used:" + Str$(E3D_edgeUsed) + " of" + Str$(E3D_EDGE_POOL) + ", non-manifold extras" + Str$(E3D_edgeNonManifold)

_Dest _Console
Print "outline_test:" + Str$(otPassed) + " passed," + Str$(otFailed) + " failed"
If otFailed > 0 Then System 1
System 0
