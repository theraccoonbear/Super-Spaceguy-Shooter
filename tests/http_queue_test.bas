' http_queue_test.bas -- integration test for the HTTP queue layer
'
' Exercises http.bas (queue, ordering, non-blocking, GET, flush, overflow, errors)
' against a local mock server; requires no real credentials.
'
' Build: ./tools/buildqb tests/http_queue_test.bas
' Run:   builds/http_queue_test http://127.0.0.1:PORT
'        (tools/http_queue_test starts the mock and passes the URL)

$CONSOLE:ONLY
OPTION _EXPLICIT

' --- stubs for http.bas dependencies (normally provided by dims.bas) ---
TYPE HttpResponse
    statusCode AS LONG
    bodyLen    AS LONG
    headerLen  AS LONG
END TYPE

DIM SHARED httpLastResp    AS HttpResponse
DIM SHARED httpLastBody    AS STRING
DIM SHARED httpLastHeaders AS STRING
DIM SHARED httpLastTag     AS STRING

DIM SHARED hqPass AS INTEGER
DIM SHARED hqFail AS INTEGER

'$INCLUDE:'../src/sys/http.bas'

Sub DBG_Print (msg As String)
    ' suppress curl noise; uncomment to debug:
    ' Print "  DBG: " + msg
End Sub

' -----------------------------------------------------------------------
' Test helpers
' -----------------------------------------------------------------------

Sub HQ_Check (label As String, got As String, want As String)
    If got = want Then
        Print "  PASS  " + label
        hqPass = hqPass + 1
    Else
        Print "  FAIL  " + label
        Print "        got  [" + got + "]"
        Print "        want [" + want + "]"
        hqFail = hqFail + 1
    End If
End Sub

Sub HQ_CheckI (label As String, got As Long, want As Long)
    HQ_Check label, LTrim$(Str$(got)), LTrim$(Str$(want))
End Sub

' Pump until both queue and in-flight are empty, or deadline exceeded.
' Returns -1 (true) if fully drained, 0 on timeout.
Function HQ_Drain% (timeoutSec As Single)
    Dim hqdT0 As Double : hqdT0 = Timer
    Do While (httpEasyH <> 0 Or httpQCount > 0) And (Timer - hqdT0 < timeoutSec)
        HTTP_Pump
        _Delay 0.01
    Loop
    HQ_Drain% = (httpEasyH = 0 And httpQCount = 0)
End Function

' -----------------------------------------------------------------------
' Main
' -----------------------------------------------------------------------
Dim hqBaseUrl As String : hqBaseUrl = LTrim$(RTrim$(COMMAND$))
If Len(hqBaseUrl) = 0 Then
    Print "Usage: http_queue_test http://127.0.0.1:PORT"
    End 1
End If

Dim hqKey As String : hqKey = "mock-key"   ' mock ignores auth

Print "=== http_queue_test ==="
Print "Endpoint: " + hqBaseUrl
Print ""

' -----------------------------------------------------------------------
' T1: single POST -- request fires immediately, tag and OK arrive
' -----------------------------------------------------------------------
Print "--- T1: single POST ---"
httpLastTag = "" : httpLastOK = 0
HTTP_Post hqBaseUrl + "/fast", hqKey, "{}", "t1"
Dim hqT1Inflight As Integer : hqT1Inflight = (httpEasyH <> 0)
HQ_CheckI "T1.inflight",   hqT1Inflight, -1
HQ_CheckI "T1.queue_idle", httpQCount, 0
Dim hqOK As Integer : hqOK = HQ_Drain(5)
HQ_CheckI "T1.drained",    hqOK, -1
HQ_Check  "T1.tag",        httpLastTag, "t1"
HQ_CheckI "T1.ok",         httpLastOK, -1
Print ""

' -----------------------------------------------------------------------
' T2: three POSTs -- tags must complete in FIFO order
' -----------------------------------------------------------------------
Print "--- T2: three POSTs (FIFO ordering) ---"
httpLastTag = ""
HTTP_Post hqBaseUrl + "/fast", hqKey, "{}", "ta"
HTTP_Post hqBaseUrl + "/fast", hqKey, "{}", "tb"
HTTP_Post hqBaseUrl + "/fast", hqKey, "{}", "tc"

Dim hqSeq      As String  : hqSeq      = ""
Dim hqPrevTag  As String  : hqPrevTag  = ""
Dim hqDeadline As Double  : hqDeadline = Timer + 5
Do While (httpEasyH <> 0 Or httpQCount > 0) And Timer < hqDeadline
    HTTP_Pump
    If httpLastTag <> hqPrevTag And Len(httpLastTag) > 0 Then
        If Len(hqSeq) > 0 Then hqSeq = hqSeq + ","
        hqSeq    = hqSeq + httpLastTag
        hqPrevTag = httpLastTag
    End If
    _Delay 0.01
Loop
HQ_Check "T2.order", hqSeq, "ta,tb,tc"
Print ""

' -----------------------------------------------------------------------
' T3: slow POST (300 ms server delay) -- each pump call must return
'     well under the server delay (verifies non-blocking curl multi)
' -----------------------------------------------------------------------
Print "--- T3: slow POST (non-blocking pump) ---"
httpLastTag = ""
HTTP_Post hqBaseUrl + "/slow/300", hqKey, "{}", "slow1"

Dim hqMaxMs    As Double  : hqMaxMs  = 0
Dim hqPumpN    As Integer : hqPumpN  = 0
Dim hqPT0      As Double
Dim hqPumpMs   As Double
hqDeadline = Timer + 4
Do While (httpEasyH <> 0 Or httpQCount > 0) And Timer < hqDeadline
    hqPT0    = Timer
    HTTP_Pump
    hqPumpMs = (Timer - hqPT0) * 1000
    If hqPumpMs > hqMaxMs Then hqMaxMs = hqPumpMs
    hqPumpN  = hqPumpN + 1
    _Delay 0.01
Loop
HQ_Check  "T3.tag",         httpLastTag, "slow1"
HQ_CheckI "T3.ok",          httpLastOK, -1
' Allow 150 ms slop for a heavily loaded CI runner; server sleeps 300 ms.
' Each individual pump call must return far below that delay.
If hqMaxMs < 150 Then
    Print "  PASS  T3.nonblock  max_pump_ms=" + LTrim$(Str$(Int(hqMaxMs))) _
                             + "  calls=" + LTrim$(Str$(hqPumpN))
    hqPass = hqPass + 1
Else
    Print "  FAIL  T3.nonblock  max_pump_ms=" + LTrim$(Str$(Int(hqMaxMs))) _
                             + " (want <150)  calls=" + LTrim$(Str$(hqPumpN))
    hqFail = hqFail + 1
End If
Print ""

' -----------------------------------------------------------------------
' T4: HTTP_Get -- authenticated GET request completes normally
' -----------------------------------------------------------------------
Print "--- T4: HTTP_Get ---"
httpLastTag = "" : httpLastOK = 0
HTTP_Get hqBaseUrl + "/get_ok", hqKey, "get1"
hqOK = HQ_Drain(5)
HQ_CheckI "T4.drained", hqOK, -1
HQ_Check  "T4.tag",     httpLastTag, "get1"
HQ_CheckI "T4.ok",      httpLastOK, -1
Print ""

' -----------------------------------------------------------------------
' T5: queue overflow -- HTTP_QUEUE_CAP+2 requests; system must not crash
'     and must drain cleanly; exactly HTTP_QUEUE_CAP+1 complete (1 dropped)
' -----------------------------------------------------------------------
Print "--- T5: queue overflow (" + LTrim$(Str$(HTTP_QUEUE_CAP + 2)) + " requests, cap=" + LTrim$(Str$(HTTP_QUEUE_CAP)) + ") ---"
hqOK = HQ_Drain(5)   ' clear any residual state
httpLastTag = ""

Dim hqOvf As Integer
For hqOvf = 1 To HTTP_QUEUE_CAP + 2
    HTTP_Post hqBaseUrl + "/fast", hqKey, "{}", "ovf" + LTrim$(Str$(hqOvf))
Next hqOvf

Dim hqCompletions As Integer : hqCompletions = 0
hqPrevTag  = ""
hqDeadline = Timer + 10
Do While (httpEasyH <> 0 Or httpQCount > 0) And Timer < hqDeadline
    HTTP_Pump
    If httpLastTag <> hqPrevTag And Len(httpLastTag) > 0 Then
        hqCompletions = hqCompletions + 1
        hqPrevTag      = httpLastTag
    End If
    _Delay 0.01
Loop
HQ_CheckI "T5.idle_after",   (httpEasyH = 0 And httpQCount = 0), -1
' 1 in-flight + HTTP_QUEUE_CAP queued = HTTP_QUEUE_CAP+1 admitted; last 1 dropped
HQ_CheckI "T5.completions",  hqCompletions, HTTP_QUEUE_CAP + 1
Print ""

' -----------------------------------------------------------------------
' T6: HTTP_Flush -- blocking drain finishes all pending requests
' -----------------------------------------------------------------------
Print "--- T6: HTTP_Flush ---"
httpLastTag = ""
HTTP_Post hqBaseUrl + "/fast", hqKey, "{}", "fl1"
HTTP_Post hqBaseUrl + "/fast", hqKey, "{}", "fl2"
HTTP_Post hqBaseUrl + "/fast", hqKey, "{}", "fl3"
HTTP_Flush 5
HQ_CheckI "T6.easy_idle",   httpEasyH, 0
HQ_CheckI "T6.queue_empty", httpQCount, 0
HQ_Check  "T6.last_tag",    httpLastTag, "fl3"
Print ""

' -----------------------------------------------------------------------
' T7: 500 response -- queue must continue after a server error
' -----------------------------------------------------------------------
Print "--- T7: 500 response, queue continues ---"
httpLastTag = ""
HTTP_Post hqBaseUrl + "/fail", hqKey, "{}", "fail1"
HTTP_Post hqBaseUrl + "/fast", hqKey, "{}", "after1"

Dim hqResults  As String : hqResults  = ""
hqPrevTag = ""
hqDeadline = Timer + 5
Do While (httpEasyH <> 0 Or httpQCount > 0) And Timer < hqDeadline
    HTTP_Pump
    If httpLastTag <> hqPrevTag And Len(httpLastTag) > 0 Then
        If Len(hqResults) > 0 Then hqResults = hqResults + ","
        hqResults = hqResults + httpLastTag + "=" + LTrim$(Str$(httpLastOK))
        hqPrevTag  = httpLastTag
    End If
    _Delay 0.01
Loop
' fail1 completes with httpLastOK=0; after1 completes with httpLastOK=-1
HQ_Check "T7.sequence", hqResults, "fail1=0,after1=-1"
Print ""

' -----------------------------------------------------------------------
' Summary
' -----------------------------------------------------------------------
Dim hqTotal As Integer : hqTotal = hqPass + hqFail
Print "=== " + LTrim$(Str$(hqTotal)) + " tests: " + LTrim$(Str$(hqPass)) _
    + " passed, " + LTrim$(Str$(hqFail)) + " failed ==="
If hqFail > 0 Then End 1
End
