' imgdiff.bas -- compare two PNGs pixel by pixel (render test suite, tests/render/run.sh)
'
'   imgdiff <expected.png> <actual.png> [--tol N] [--max-frac F] [--mask x,y,w,h]... [--diff out.png]
'
'   --tol N         a pixel differs when any channel (R, G, B, A) is off by more than N (default 0)
'   --max-frac F    pass while at most this fraction of the unmasked pixels differ (default 0)
'   --mask x,y,w,h  skip this rectangle (repeatable)
'   --diff out.png  write a diff image: the actual image dimmed to grey, differing pixels
'                   red, pixels that changed but stay within --tol yellow, masks blue
'
' Exit 0 = match, 1 = differ (or the sizes differ), 2 = bad arguments or unreadable image.
'
' Build: ./tools/buildqb tools/imgdiff.bas    (tests/render/run.sh builds it for you)

$CONSOLE:ONLY

Const IMD_MAX_MASK = 16

Dim Shared imdMaskX(1 To IMD_MAX_MASK) As Long, imdMaskY(1 To IMD_MAX_MASK) As Long
Dim Shared imdMaskW(1 To IMD_MAX_MASK) As Long, imdMaskH(1 To IMD_MAX_MASK) As Long
Dim Shared imdMaskN As Integer

Sub IMD_Fail (imdMsg As String)
    Print "imgdiff: " + imdMsg
    System 2
End Sub

Function IMD_Masked% (imdPX As Long, imdPY As Long)
    Dim imdMI As Integer
    IMD_Masked% = 0
    For imdMI = 1 To imdMaskN
        If imdPX >= imdMaskX(imdMI) And imdPX < imdMaskX(imdMI) + imdMaskW(imdMI) And imdPY >= imdMaskY(imdMI) And imdPY < imdMaskY(imdMI) + imdMaskH(imdMI) Then
            IMD_Masked% = -1
            Exit Function
        End If
    Next imdMI
End Function

Sub IMD_AddMask (imdSpec As String)
    Dim imdPart(1 To 4) As Long, imdPI As Integer, imdRest As String, imdComma As Integer
    If imdMaskN >= IMD_MAX_MASK Then IMD_Fail "at most" + Str$(IMD_MAX_MASK) + " masks"
    imdRest = imdSpec
    For imdPI = 1 To 4
        imdComma = InStr(imdRest, ",")
        If imdPI < 4 And imdComma = 0 Then IMD_Fail "--mask needs x,y,w,h, got '" + imdSpec + "'"
        If imdPI = 4 Then
            imdPart(imdPI) = Val(imdRest)
        Else
            imdPart(imdPI) = Val(Left$(imdRest, imdComma - 1))
            imdRest = Mid$(imdRest, imdComma + 1)
        End If
    Next imdPI
    imdMaskN = imdMaskN + 1
    imdMaskX(imdMaskN) = imdPart(1) : imdMaskY(imdMaskN) = imdPart(2)
    imdMaskW(imdMaskN) = imdPart(3) : imdMaskH(imdMaskN) = imdPart(4)
End Sub

' QB64-PE starts a program in its own folder, so relative paths are taken from the launch folder.
Function IMD_Path$ (imdP As String)
    If Left$(imdP, 1) = "/" Or Left$(imdP, 1) = "\" Or Mid$(imdP, 2, 1) = ":" Then
        IMD_Path$ = imdP
    Else
        IMD_Path$ = _StartDir$ + "/" + imdP
    End If
End Function

Function IMD_Abs& (imdV As Long)
    If imdV < 0 Then IMD_Abs& = -imdV Else IMD_Abs& = imdV
End Function

Dim imdExpPath As String, imdActPath As String, imdDiffPath As String
Dim imdTol As Long, imdMaxFrac As Double
Dim imdArgI As Long, imdArg As String, imdPosN As Integer

For imdArgI = 1 To _CommandCount
    imdArg = Command$(imdArgI)
    Select Case imdArg
    Case "--tol"
        imdArgI = imdArgI + 1 : imdTol = Val(Command$(imdArgI))
    Case "--max-frac"
        imdArgI = imdArgI + 1 : imdMaxFrac = Val(Command$(imdArgI))
    Case "--mask"
        imdArgI = imdArgI + 1 : IMD_AddMask Command$(imdArgI)
    Case "--diff"
        imdArgI = imdArgI + 1 : imdDiffPath = IMD_Path$(Command$(imdArgI))
    Case Else
        If Left$(imdArg, 2) = "--" Then IMD_Fail "unknown option " + imdArg
        imdPosN = imdPosN + 1
        If imdPosN = 1 Then imdExpPath = IMD_Path$(imdArg)
        If imdPosN = 2 Then imdActPath = IMD_Path$(imdArg)
    End Select
Next imdArgI
If imdPosN <> 2 Then IMD_Fail "usage: imgdiff <expected.png> <actual.png> [--tol N] [--max-frac F] [--mask x,y,w,h]... [--diff out.png]"

If _FileExists(imdExpPath) = 0 Then IMD_Fail "missing " + imdExpPath
If _FileExists(imdActPath) = 0 Then IMD_Fail "missing " + imdActPath
Dim imdExp As Long, imdAct As Long
imdExp = _LoadImage(imdExpPath, 32)
imdAct = _LoadImage(imdActPath, 32)
If imdExp >= -1 Then IMD_Fail "can't read " + imdExpPath
If imdAct >= -1 Then IMD_Fail "can't read " + imdActPath

Dim imdW As Long, imdH As Long
imdW = _Width(imdExp) : imdH = _Height(imdExp)
If _Width(imdAct) <> imdW Or _Height(imdAct) <> imdH Then
    Print "imgdiff: size differs: expected" + Str$(imdW) + " x" + Str$(imdH) + ", actual" + Str$(_Width(imdAct)) + " x" + Str$(_Height(imdAct))
    System 1
End If

Dim imdDiff As Long
If imdDiffPath <> "" Then imdDiff = _NewImage(imdW, imdH, 32)

Dim imdX As Long, imdY As Long, imdCE As _Unsigned Long, imdCA As _Unsigned Long
Dim imdD As Long, imdDMax As Long, imdPixMax As Long, imdBad As Long, imdNear As Long, imdTotal As Long
Dim imdGrey As Long, imdOut As _Unsigned Long, imdIsMasked As Integer
For imdY = 0 To imdH - 1
    For imdX = 0 To imdW - 1
        imdIsMasked = IMD_Masked%(imdX, imdY)
        _Source imdExp : imdCE = Point(imdX, imdY)
        _Source imdAct : imdCA = Point(imdX, imdY)
        imdPixMax = 0
        If imdIsMasked = 0 Then
            imdTotal = imdTotal + 1
            imdD = IMD_Abs&(_Red32(imdCE) - _Red32(imdCA)) : If imdD > imdPixMax Then imdPixMax = imdD
            imdD = IMD_Abs&(_Green32(imdCE) - _Green32(imdCA)) : If imdD > imdPixMax Then imdPixMax = imdD
            imdD = IMD_Abs&(_Blue32(imdCE) - _Blue32(imdCA)) : If imdD > imdPixMax Then imdPixMax = imdD
            imdD = IMD_Abs&(_Alpha32(imdCE) - _Alpha32(imdCA)) : If imdD > imdPixMax Then imdPixMax = imdD
            If imdPixMax > imdDMax Then imdDMax = imdPixMax
            If imdPixMax > imdTol Then
                imdBad = imdBad + 1
            ElseIf imdPixMax > 0 Then
                imdNear = imdNear + 1
            End If
        End If
        If imdDiff <> 0 Then
            imdGrey = (_Red32(imdCA) + _Green32(imdCA) + _Blue32(imdCA)) \ 12
            If imdIsMasked Then
                imdOut = _RGB32(imdGrey, imdGrey, 60 + imdGrey)
            ElseIf imdPixMax > imdTol Then
                imdOut = _RGB32(255, 0, 0)
            ElseIf imdPixMax > 0 Then
                imdOut = _RGB32(255, 220, 0)
            Else
                imdOut = _RGB32(imdGrey, imdGrey, imdGrey)
            End If
            _Dest imdDiff : PSet (imdX, imdY), imdOut
        End If
    Next imdX
Next imdY

If imdDiff <> 0 Then _SaveImage imdDiffPath, imdDiff
_Dest _Console

Dim imdFrac As Double
If imdTotal > 0 Then imdFrac = imdBad / imdTotal
Print "imgdiff:" + Str$(imdBad) + " of" + Str$(imdTotal) + " pixels differ beyond tol" + Str$(imdTol) + " (" + LTrim$(Str$(Int(imdFrac * 1000000) / 10000)) + "%, allowed " + LTrim$(Str$(imdMaxFrac * 100)) + "%);" + Str$(imdNear) + " more within tol; max channel delta" + Str$(imdDMax)
If imdFrac > imdMaxFrac Then System 1
System 0
