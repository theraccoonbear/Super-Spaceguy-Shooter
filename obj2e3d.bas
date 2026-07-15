' obj2e3d.bas — convert an OBJ file to a models.e3d block
' Usage: obj2e3d <obj_path> <remap> <scale> <slot_name>
'   remap: 0=none  1=Blender(-Z fwd)  2=(+Z fwd)
'   scale: e.g. 0.00225 for cm-range Blender ships
'   slot_name: e.g. PLAYER
' Output: <slot_name>.e3d in the same directory as the binary.

' Defer GL window until _ScreenShow — lets the tool run without a display
$SCREENHIDE

'$INCLUDE:'src/engine3d.bi'
'$INCLUDE:'src/obj.bas'

DIM cmdStr   AS STRING  : cmdStr   = LTRIM$(RTRIM$(COMMAND$))
DIM objPath  AS STRING
DIM remapArg AS INTEGER
DIM scaleArg AS SINGLE
DIM slotName AS STRING
DIM ttyF     AS INTEGER
CmdTok cmdStr, objPath
DIM remapStr AS STRING : CmdTok cmdStr, remapStr
DIM scaleStr AS STRING : CmdTok cmdStr, scaleStr
CmdTok cmdStr, slotName
remapArg = CInt(Val(remapStr))
scaleArg = CSng(Val(scaleStr))

IF LEN(objPath) = 0 OR LEN(slotName) = 0 THEN
    ttyF = FREEFILE
    OPEN "/dev/stdout" FOR APPEND AS #ttyF
    PRINT #ttyF, "Usage: obj2e3d <obj_path> <remap> <scale> <slot_name>"
    CLOSE #ttyF
    SYSTEM
END IF
IF scaleArg = 0.0 THEN scaleArg = 1.0
IF LEFT$(objPath, 1) <> "/" AND LEFT$(objPath, 1) <> "\" THEN
    objPath = _STARTDIR$ + "/" + objPath
END IF
IF NOT _FILEEXISTS(objPath) THEN
    ttyF = FREEFILE
    OPEN "/dev/stdout" FOR APPEND AS #ttyF
    PRINT #ttyF, "File not found: " + objPath
    CLOSE #ttyF
    SYSTEM
END IF

' Load OBJ
DIM objF AS INTEGER : objF = FREEFILE
DIM objDat AS STRING
OPEN objPath FOR BINARY AS #objF
objDat = SPACE$(LOF(objF))
GET #objF, , objDat
CLOSE #objF

DIM mtlPath AS STRING : mtlPath = E3D_OBJMtlPath$(objPath, objDat)
DIM mtlDat  AS STRING
IF LEN(mtlPath) > 0 AND _FILEEXISTS(mtlPath) THEN
    DIM mtlF AS INTEGER : mtlF = FREEFILE
    OPEN mtlPath FOR BINARY AS #mtlF
    mtlDat = SPACE$(LOF(mtlF))
    GET #mtlF, , mtlDat
    CLOSE #mtlF
END IF

DIM mesh AS E3D_Mesh
DIM box  AS E3D_AABB
E3D_LoadOBJ objDat, mtlDat, mesh, box, remapArg, scaleArg

' Write e3d block
DIM outPath AS STRING : outPath = _STARTDIR$ + "/" + slotName + ".e3d"
DIM outF    AS INTEGER : outF = FREEFILE
OPEN outPath FOR OUTPUT AS #outF

PRINT #outF, "o " + slotName
PRINT #outF, "aabb " + FmtF$(box.hx) + " " + FmtF$(box.hy) + " " + FmtF$(box.hz)

DIM vi AS INTEGER
FOR vi = 1 TO mesh.vCount
    PRINT #outF, "v " + FmtF$(mesh.verts(vi).x) + " " + FmtF$(mesh.verts(vi).y) + " " + FmtF$(mesh.verts(vi).z)
NEXT vi

DIM fi AS INTEGER
FOR fi = 1 TO mesh.fCount
    DIM clr AS LONG : clr = mesh.faces(fi).baseClr
    DIM cr  AS LONG : cr = _Red32(clr)
    DIM cg  AS LONG : cg = _Green32(clr)
    DIM cb  AS LONG : cb = _Blue32(clr)
    PRINT #outF, "f " + LTRIM$(STR$(mesh.faces(fi).vIdx(1))) + " " + _
                        LTRIM$(STR$(mesh.faces(fi).vIdx(2))) + " " + _
                        LTRIM$(STR$(mesh.faces(fi).vIdx(3))) + " " + _
                        LTRIM$(STR$(cr)) + " " + _
                        LTRIM$(STR$(cg)) + " " + _
                        LTRIM$(STR$(cb))
NEXT fi

PRINT #outF, "end"
CLOSE #outF

ttyF = FREEFILE
OPEN "/dev/stdout" FOR APPEND AS #ttyF
PRINT #ttyF, "Written: " + outPath
PRINT #ttyF, "  " + LTRIM$(STR$(mesh.vCount)) + " verts, " + LTRIM$(STR$(mesh.fCount)) + " faces"
PRINT #ttyF, "  aabb " + FmtF$(box.hx) + " x " + FmtF$(box.hy) + " x " + FmtF$(box.hz)
CLOSE #ttyF
SYSTEM

Sub CmdTok (s As String, tok As String)
    s = LTRIM$(s)
    Dim p As Integer : p = INSTR(s, " ")
    If p > 0 Then
        tok = LEFT$(s, p - 1)
        s = LTRIM$(MID$(s, p + 1))
    ElseIf LEN(s) > 0 Then
        tok = s : s = ""
    Else
        tok = ""
    End If
End Sub

Function FmtF$ (v As Single)
    DIM s AS STRING
    s = LTRIM$(STR$(INT(v * 10000 + 0.5) / 10000.0))
    ' Trim trailing zeros after decimal
    IF INSTR(s, ".") > 0 THEN
        DO WHILE RIGHT$(s, 1) = "0"
            s = LEFT$(s, LEN(s) - 1)
        LOOP
        IF RIGHT$(s, 1) = "." THEN s = LEFT$(s, LEN(s) - 1)
    END IF
    FmtF$ = s
End Function
