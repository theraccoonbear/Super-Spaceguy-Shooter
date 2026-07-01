' gametext.bas  --  keyed text block loader with token substitution
'
' Two-pass load:
'   1. GTEXT_LoadVars  parses gamevalues.ini  ->  sssTokStore$
'   2. GTEXT_Load      parses gametext.txt    ->  sssBlkStore$
'      Token substitution is applied at load time; GTEXT_Get$ returns final text.
'
' sssTokStore$ format:  key + Chr$(1) + val + Chr$(2) + ...
' sssBlkStore$ format:  key + Chr$(3) + text + Chr$(4) + ...
' sssRawBlocks$ holds pre-render block text for unused-token detection.
'
' Dim Shared with $ suffix: visible to all Subs (QB64-PE include scoping rule).
Dim Shared sssTokStore$
Dim Shared sssBlkStore$
Dim Shared sssRawBlocks$

Sub GTEXT_Log(glgMsg As String)
    Dim glgF As Integer
    If Environ$("TERM") = "" Then Exit Sub
    glgF = FreeFile
    Open "/dev/tty" For Append As #glgF
    Print #glgF, "[gtext] " + glgMsg
    Close #glgF
End Sub

Sub GTEXT_LoadVars(src As String)
    Dim gvP As Long, gvQ As Long, gvE As Long
    Dim gvL As String, gvC As Integer
    sssTokStore$ = ""
    gvP = 1
    Do While gvP <= Len(src)
        gvQ = InStr(gvP, src, Chr$(10))
        If gvQ = 0 Then gvQ = Len(src) + 1
        gvL = Mid$(src, gvP, gvQ - gvP)
        If Right$(gvL, 1) = Chr$(13) Then gvL = Left$(gvL, Len(gvL) - 1)
        gvP = gvQ + 1
        gvL = LTrim$(RTrim$(gvL))
        If Len(gvL) > 0 Then
            If Left$(gvL, 1) <> ";" Then
                gvE = InStr(gvL, "=")
                If gvE > 1 Then
                    sssTokStore$ = sssTokStore$ + Left$(gvL, gvE - 1) + Chr$(1) + Mid$(gvL, gvE + 1) + Chr$(2)
                    GTEXT_Log "  tok: " + Left$(gvL, gvE - 1) + " = " + Mid$(gvL, gvE + 1)
                    gvC = gvC + 1
                End If
            End If
        End If
    Loop
    GTEXT_Log LTrim$(Str$(gvC)) + " tokens loaded from gamevalues.ini"
End Sub

Function GTEXT_Render$(grS As String)
    Dim grR As String, grP As Long, grQ As Long, grE As Long
    Dim grK As String, grV As String, grTok As String, grAt As Long
    grR = grS
    grP = 1
    Do While grP <= Len(sssTokStore$)
        grQ = InStr(grP, sssTokStore$, Chr$(1))
        If grQ = 0 Then Exit Do
        grE = InStr(grQ + 1, sssTokStore$, Chr$(2))
        If grE = 0 Then grE = Len(sssTokStore$) + 1
        grK = Mid$(sssTokStore$, grP, grQ - grP)
        grV = Mid$(sssTokStore$, grQ + 1, grE - grQ - 1)
        grTok = "{{" + grK + "}}"
        grAt = InStr(grR, grTok)
        Do While grAt > 0
            grR = Left$(grR, grAt - 1) + grV + Mid$(grR, grAt + Len(grTok))
            grAt = InStr(grAt + Len(grV), grR, grTok)
        Loop
        grP = grE + 1
    Loop
    GTEXT_Render$ = grR
End Function

Sub GTEXT_Load(src As String)
    Dim glP As Long, glQ As Long
    Dim glL As String, glK As String, glV As String, glRen As String
    Dim glIn As Integer, glC As Integer
    sssBlkStore$ = ""
    sssRawBlocks$ = ""
    glK = "" : glV = "" : glIn = 0
    glP = 1
    Do While glP <= Len(src)
        glQ = InStr(glP, src, Chr$(10))
        If glQ = 0 Then glQ = Len(src) + 1
        glL = Mid$(src, glP, glQ - glP)
        If Right$(glL, 1) = Chr$(13) Then glL = Left$(glL, Len(glL) - 1)
        glP = glQ + 1
        If Left$(glL, 1) <> ";" Then
            If Left$(glL, 7) = "[BLOCK:" And Right$(glL, 1) = "]" Then
                If glIn And glK <> "" Then
                    sssRawBlocks$ = sssRawBlocks$ + glV
                    glRen = GTEXT_Render$(glV)
                    sssBlkStore$ = sssBlkStore$ + glK + Chr$(3) + glRen + Chr$(4)
                    GTEXT_Log "  blk: " + glK + " (" + LTrim$(Str$(Len(glV))) + " raw -> " + LTrim$(Str$(Len(glRen))) + " rendered)"
                    glC = glC + 1
                End If
                glK = Mid$(glL, 8, Len(glL) - 8)
                glV = "" : glIn = -1
            ElseIf glIn Then
                If glV = "" Then
                    glV = glL
                Else
                    glV = glV + Chr$(10) + glL
                End If
            End If
        End If
    Loop
    If glIn And glK <> "" Then
        sssRawBlocks$ = sssRawBlocks$ + glV
        glRen = GTEXT_Render$(glV)
        sssBlkStore$ = sssBlkStore$ + glK + Chr$(3) + glRen + Chr$(4)
        GTEXT_Log "  blk: " + glK + " (" + LTrim$(Str$(Len(glV))) + " raw -> " + LTrim$(Str$(Len(glRen))) + " rendered)"
        glC = glC + 1
    End If
    GTEXT_Log LTrim$(Str$(glC)) + " blocks loaded from gametext.txt"
End Sub

Sub GTEXT_Diag
    Dim gdP As Long, gdQ As Long, gdE As Long
    Dim gdK As String, gdV As String
    Dim gdUnused As Integer, gdBad As Long
    ' unresolved {{ in rendered output
    gdBad = InStr(sssBlkStore$, "{{")
    If gdBad > 0 Then
        GTEXT_Log "WARNING: unresolved {{ in rendered blocks (pos " + LTrim$(Str$(gdBad)) + ") -- misspelled token?"
    Else
        GTEXT_Log "OK: no unresolved {{ in rendered output"
    End If
    ' unused token check: each key defined in gamevalues.ini vs raw block text
    gdP = 1
    Do While gdP <= Len(sssTokStore$)
        gdQ = InStr(gdP, sssTokStore$, Chr$(1))
        If gdQ = 0 Then Exit Do
        gdE = InStr(gdQ + 1, sssTokStore$, Chr$(2))
        If gdE = 0 Then gdE = Len(sssTokStore$) + 1
        gdK = Mid$(sssTokStore$, gdP, gdQ - gdP)
        gdV = Mid$(sssTokStore$, gdQ + 1, gdE - gdQ - 1)
        If InStr(sssRawBlocks$, "{{" + gdK + "}}") = 0 Then
            GTEXT_Log "UNUSED tok: {{" + gdK + "}} (=" + gdV + ")"
            gdUnused = gdUnused + 1
        End If
        gdP = gdE + 1
    Loop
    If gdUnused = 0 Then GTEXT_Log "OK: all tokens used"
End Sub

Function GTEXT_Var$(gvarK As String)
    Dim gvarP As Long, gvarQ As Long, gvarE As Long
    gvarP = 1
    Do While gvarP <= Len(sssTokStore$)
        gvarQ = InStr(gvarP, sssTokStore$, Chr$(1))
        If gvarQ = 0 Then Exit Do
        If Mid$(sssTokStore$, gvarP, gvarQ - gvarP) = gvarK Then
            gvarE = InStr(gvarQ + 1, sssTokStore$, Chr$(2))
            If gvarE = 0 Then gvarE = Len(sssTokStore$) + 1
            GTEXT_Var$ = Mid$(sssTokStore$, gvarQ + 1, gvarE - gvarQ - 1)
            Exit Function
        End If
        gvarE = InStr(gvarQ + 1, sssTokStore$, Chr$(2))
        If gvarE = 0 Then Exit Do
        gvarP = gvarE + 1
    Loop
    GTEXT_Var$ = ""
End Function

Function GTEXT_Get$(ggK As String)
    Dim ggP As Long, ggE As Long
    Dim ggSep As String
    ggSep = ggK + Chr$(3)
    ggP = 1
    Do While ggP <= Len(sssBlkStore$)
        If Mid$(sssBlkStore$, ggP, Len(ggSep)) = ggSep Then
            ggP = ggP + Len(ggSep)
            ggE = InStr(ggP, sssBlkStore$, Chr$(4))
            If ggE = 0 Then ggE = Len(sssBlkStore$) + 1
            GTEXT_Get$ = Mid$(sssBlkStore$, ggP, ggE - ggP)
            Exit Function
        End If
        ggE = InStr(ggP, sssBlkStore$, Chr$(4))
        If ggE = 0 Then Exit Do
        ggP = ggE + 1
    Loop
    GTEXT_Get$ = ""
End Function
