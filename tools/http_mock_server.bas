' http_mock_server.bas -- programmable HTTP mock for the HTTP queue test.
'
' Endpoints:
'   POST /fast          200 immediately
'   POST /slow/<ms>     wait N ms (other connections keep being served), then 200
'   POST /fail          500 immediately
'   GET  /get_ok        200 {"ok":true}
'   GET  /requests      JSON log of all received requests in order
'   DELETE /requests    clear the log
'
' Plain HTTP on all local interfaces, one request per connection (Connection: close).
' Prints the bound port on its own line at startup. With --port 0 (or no --port) it
' picks a free port itself, since _OPENHOST can't report an OS-chosen one.
' --max-secs N ends the process after N seconds whatever happens (default 600), so a
' mock whose test died can't linger.
'
' Build: qb64pe -x tools/http_mock_server.bas -o <out>   (the test runner does this)
' Run:   http_mock_server [--port N] [--max-secs N]
' Log "t" is seconds since the mock started (QB64-PE has no epoch clock).

$CONSOLE:ONLY
Option _Explicit

Const MAXC = 32
Dim Shared cH(1 To MAXC) As Long
Dim Shared cBuf(1 To MAXC) As String
Dim Shared cDue(1 To MAXC) As Double
Dim Shared cResp(1 To MAXC) As String
Dim Shared cSent100(1 To MAXC) As Integer

Dim Shared logJson As String
Dim Shared logCount As Long
Dim Shared dayOff As Double, lastTimer As Double, t0 As Double

Function Now# ()
    Dim nwT As Double
    nwT = Timer(0.001)
    If nwT < lastTimer Then dayOff = dayOff + 86400
    lastTimer = nwT
    Now# = nwT + dayOff
End Function

Function JsonEsc$ (s As String)
    Dim jeOut As String, jeI As Long, jeC As Long
    jeOut = ""
    For jeI = 1 To Len(s)
        jeC = Asc(s, jeI)
        Select Case jeC
            Case 34: jeOut = jeOut + "\" + Chr$(34)
            Case 92: jeOut = jeOut + "\\"
            Case 10: jeOut = jeOut + "\n"
            Case 13: jeOut = jeOut + "\r"
            Case 9: jeOut = jeOut + "\t"
            Case Is < 32: jeOut = jeOut + "\u00" + Right$("0" + Hex$(jeC), 2)
            Case Else: jeOut = jeOut + Chr$(jeC)
        End Select
    Next jeI
    JsonEsc$ = jeOut
End Function

Sub RecordReq (method As String, path As String, body As String)
    Dim rrQ As String
    rrQ = Chr$(34)
    If logCount > 0 Then logJson = logJson + ","
    logJson = logJson + "{" + rrQ + "seq" + rrQ + ":" + LTrim$(Str$(logCount)) + "," _
        + rrQ + "method" + rrQ + ":" + rrQ + JsonEsc$(method) + rrQ + "," _
        + rrQ + "path" + rrQ + ":" + rrQ + JsonEsc$(path) + rrQ + "," _
        + rrQ + "body" + rrQ + ":" + rrQ + JsonEsc$(body) + rrQ + "," _
        + rrQ + "t" + rrQ + ":" + LTrim$(Str$(Int((Now# - t0) * 1000) / 1000)) + "}"
    logCount = logCount + 1
End Sub

Function StatusText$ (code As Long)
    Select Case code
        Case 200: StatusText$ = "OK"
        Case 404: StatusText$ = "Not Found"
        Case 405: StatusText$ = "Method Not Allowed"
        Case 500: StatusText$ = "Internal Server Error"
        Case Else: StatusText$ = "Status"
    End Select
End Function

Function BuildResp$ (code As Long, body As String)
    BuildResp$ = "HTTP/1.1 " + LTrim$(Str$(code)) + " " + StatusText$(code) + Chr$(13) + Chr$(10) _
        + "Content-Type: application/json" + Chr$(13) + Chr$(10) _
        + "Content-Length: " + LTrim$(Str$(Len(body))) + Chr$(13) + Chr$(10) _
        + "Connection: close" + Chr$(13) + Chr$(10) + Chr$(13) + Chr$(10) + body
End Function

' Route one parsed request: fills the connection's response and due time.
Sub Route (slot As Long, method As String, path As String, body As String)
    Dim rtQ As String, rtCode As Long, rtBody As String, rtDelay As Double
    Dim rtSeg As String, rtP As Long
    rtQ = Chr$(34)
    rtCode = 404 : rtBody = "{" + rtQ + "error" + rtQ + ":" + rtQ + "not found" + rtQ + "}"
    rtDelay = 0
    Select Case method
        Case "POST"
            RecordReq method, path, body
            If path = "/fast" Then
                rtCode = 200 : rtBody = "{" + rtQ + "ok" + rtQ + ":true}"
            ElseIf Left$(path, 6) = "/slow/" Then
                rtSeg = Mid$(path, 7)
                rtP = InStr(rtSeg, "/")
                If rtP > 0 Then rtSeg = Left$(rtSeg, rtP - 1)
                If Len(rtSeg) > 0 And Asc(rtSeg, 1) >= 48 And Asc(rtSeg, 1) <= 57 Then
                    rtDelay = Val(rtSeg) / 1000
                Else
                    rtDelay = 0.1
                End If
                rtCode = 200 : rtBody = "{" + rtQ + "ok" + rtQ + ":true}"
            ElseIf path = "/fail" Then
                rtCode = 500 : rtBody = "{" + rtQ + "error" + rtQ + ":" + rtQ + "mock failure" + rtQ + "}"
            End If
        Case "GET"
            If path = "/get_ok" Then
                RecordReq method, path, ""
                rtCode = 200 : rtBody = "{" + rtQ + "ok" + rtQ + ":true}"
            ElseIf path = "/requests" Then
                rtCode = 200 : rtBody = "[" + logJson + "]"
            End If
        Case "DELETE"
            If path = "/requests" Then
                logJson = "" : logCount = 0
                rtCode = 200 : rtBody = "{" + rtQ + "reset" + rtQ + ":true}"
            End If
        Case Else
            rtCode = 405 : rtBody = "{" + rtQ + "error" + rtQ + ":" + rtQ + "method not allowed" + rtQ + "}"
    End Select
    cResp(slot) = BuildResp$(rtCode, rtBody)
    cDue(slot) = Now# + rtDelay
End Sub

Function HeaderVal$ (hdrs As String, nameLC As String)
    Dim hvL As String, hvP As Long, hvE As Long
    hvL = LCase$(hdrs)
    hvP = InStr(hvL, Chr$(10) + nameLC + ":")
    If hvP = 0 Then HeaderVal$ = "" : Exit Function
    hvP = hvP + Len(nameLC) + 2
    hvE = InStr(hvP, hdrs, Chr$(13))
    If hvE = 0 Then hvE = Len(hdrs) + 1
    HeaderVal$ = LTrim$(RTrim$(Mid$(hdrs, hvP, hvE - hvP)))
End Function

' Parse a connection's buffered bytes; once headers and the whole body are in, route it.
Sub TryParse (slot As Long)
    Dim tpEnd As Long, tpHdrs As String, tpLine As String, tpSp1 As Long, tpSp2 As Long
    Dim tpCont As String
    Dim tpLen As Long, tpBodyStart As Long, tpBody As String, tpMethod As String, tpPath As String
    tpEnd = InStr(cBuf(slot), Chr$(13) + Chr$(10) + Chr$(13) + Chr$(10))
    If tpEnd = 0 Then Exit Sub
    tpHdrs = Left$(cBuf(slot), tpEnd + 1)
    tpBodyStart = tpEnd + 4
    tpLen = Val(HeaderVal$(tpHdrs, "content-length"))
    If Len(cBuf(slot)) - tpBodyStart + 1 < tpLen Then
        If cSent100(slot) = 0 And LCase$(HeaderVal$(tpHdrs, "expect")) = "100-continue" Then
            tpCont = "HTTP/1.1 100 Continue" + Chr$(13) + Chr$(10) + Chr$(13) + Chr$(10)
            Put #cH(slot), , tpCont
            cSent100(slot) = 1
        End If
        Exit Sub
    End If
    tpBody = Mid$(cBuf(slot), tpBodyStart, tpLen)
    tpLine = Left$(tpHdrs, InStr(tpHdrs, Chr$(13)) - 1)
    tpSp1 = InStr(tpLine, " ")
    tpSp2 = InStr(tpSp1 + 1, tpLine, " ")
    If tpSp1 = 0 Then
        tpMethod = tpLine : tpPath = ""
    Else
        tpMethod = Left$(tpLine, tpSp1 - 1)
        If tpSp2 = 0 Then tpPath = Mid$(tpLine, tpSp1 + 1) Else tpPath = Mid$(tpLine, tpSp1 + 1, tpSp2 - tpSp1 - 1)
    End If
    Route slot, tpMethod, tpPath, tpBody
End Sub

Sub FreeSlot (slot As Long)
    Close #cH(slot)
    cH(slot) = 0 : cBuf(slot) = "" : cResp(slot) = "" : cDue(slot) = -1 : cSent100(slot) = 0
End Sub

' --- main ---
Dim cmd As String, mmPort As Long, mmMaxSecs As Double, mmP As Long, mmTok As String
Dim host As Long, tries As Long
Dim sendBuf As String
Dim newC As Long, i As Long, slot As Long, chunk As String, deadline As Double

cmd = COMMAND$
mmPort = 0 : mmMaxSecs = 600
mmP = InStr(cmd, "--port")
If mmP > 0 Then mmPort = Val(Mid$(cmd, mmP + 6))
mmP = InStr(cmd, "--max-secs")
If mmP > 0 Then mmMaxSecs = Val(Mid$(cmd, mmP + 10))

For i = 1 To MAXC
    cDue(i) = -1
Next i

Randomize Timer
host = 0
If mmPort > 0 Then
    host = _OpenHost("TCP/IP:" + LTrim$(Str$(mmPort)))
Else
    For tries = 1 To 200
        mmPort = 49152 + Int(Rnd * 16000)
        host = _OpenHost("TCP/IP:" + LTrim$(Str$(mmPort)))
        If host <> 0 Then Exit For
    Next tries
End If
If host = 0 Then
    Print "ERROR: could not listen on a port"
    System 1
End If

t0 = Now#
deadline = t0 + mmMaxSecs
Print LTrim$(Str$(mmPort))

Do
    newC = _OpenConnection(host)
    Do While newC <> 0
        slot = 0
        For i = 1 To MAXC
            If cH(i) = 0 Then slot = i : Exit For
        Next i
        If slot = 0 Then
            Close #newC
        Else
            cH(slot) = newC : cBuf(slot) = "" : cDue(slot) = -1 : cSent100(slot) = 0
        End If
        newC = _OpenConnection(host)
    Loop

    For i = 1 To MAXC
        If cH(i) <> 0 Then
            If cDue(i) < 0 Then
                chunk = ""
                Get #cH(i), , chunk
                If Len(chunk) > 0 Then
                    cBuf(i) = cBuf(i) + chunk
                    TryParse i
                ElseIf _Connected(cH(i)) = 0 Then
                    FreeSlot i
                End If
            End If
            If cH(i) <> 0 Then
                If cDue(i) >= 0 And Now# >= cDue(i) Then
                    sendBuf = cResp(i)
                    Put #cH(i), , sendBuf
                    FreeSlot i
                End If
            End If
        End If
    Next i

    If Now# > deadline Then Exit Do
    _Delay 0.002
Loop
System 0
