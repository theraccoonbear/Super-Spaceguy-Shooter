' http.bas -- non-blocking HTTPS POST via libcurl
'
' HTTP_PostJSON url$, apikey$, body$  enqueue POST; returns immediately (non-blocking)
' HTTP_Pump                           drive I/O; call each frame while httpEasyH <> 0
' httpEasyH (shared)                  non-zero while transfer in flight
' httpLastOK (shared)                 -1 if last completed request succeeded; 0 = failed
' httpAvailable (shared)              -1 if libcurl loaded OK; 0 = missing (telemetry off)
'
' QB64-PE bakes the system libcurl path at compile time via DECLARE DYNAMIC LIBRARY.
' If libcurl is missing or not at that path, ON ERROR GOTO catches error 260 and sets
' httpAvailable=0 -- telemetry silently disables, game continues normally.
'
' Local variable prefix: http*

' Shared state -- initialized to 0 at program start before any code runs.
Dim Shared httpMultiH   As _OFFSET
Dim Shared httpEasyH    As _OFFSET
Dim Shared httpSlistH   As _OFFSET
Dim Shared httpLastOK   As Long
Dim Shared httpAvailable As Long

' Catch error 260 ("Cannot find dynamic library") so a missing libcurl silently
' disables network telemetry instead of crashing.  The DECLARE block below generates
' the dlopen() call at this position in the execution stream; the handler must be
' live before that code runs.
On Error GoTo httpLibMissing
httpAvailable = -1
GoTo httpLibDeclare

httpLibMissing:
httpAvailable = 0
Resume httpLibDone

httpLibDeclare:

$IF WIN THEN
    DECLARE DYNAMIC LIBRARY "libcurl"
$ELSE
    DECLARE DYNAMIC LIBRARY "curl"
$END IF
    FUNCTION http_curl_init%&        ALIAS "curl_easy_init"
    SUB     http_setopt_str          ALIAS "curl_easy_setopt"         (BYVAL httpH%&, BYVAL httpOpt%&, httpVal AS STRING)
    SUB     http_setopt_ptr          ALIAS "curl_easy_setopt"         (BYVAL httpH%&, BYVAL httpOpt%&, BYVAL httpVal%&)
    SUB     http_setopt_long         ALIAS "curl_easy_setopt"         (BYVAL httpH%&, BYVAL httpOpt%&, BYVAL httpVal%&)
    FUNCTION http_slist_append%&     ALIAS "curl_slist_append"        (BYVAL httpL%&, httpVal AS STRING)
    SUB     http_slist_free          ALIAS "curl_slist_free_all"      (BYVAL httpL%&)
    SUB     http_curl_cleanup        ALIAS "curl_easy_cleanup"        (BYVAL httpH%&)
    FUNCTION http_multi_init%&       ALIAS "curl_multi_init"
    SUB     http_multi_add           ALIAS "curl_multi_add_handle"    (BYVAL httpM%&, BYVAL httpH%&)
    SUB     http_multi_perform       ALIAS "curl_multi_perform"       (BYVAL httpM%&, httpN AS LONG)
    SUB     http_multi_remove        ALIAS "curl_multi_remove_handle" (BYVAL httpM%&, BYVAL httpH%&)
END DECLARE

httpLibDone:
On Error GoTo 0

Const CURLOPT_URL         = 10002
Const CURLOPT_POSTFIELDS  = 10015
Const CURLOPT_HTTPHEADER  = 10023
Const CURLOPT_TIMEOUT     = 13
Const CURLOPT_FAILONERROR = 45

' Drive the in-flight request; call from the game loop each frame.
Sub HTTP_Pump
    If httpAvailable = 0 Or httpMultiH = 0 Or httpEasyH = 0 Then Exit Sub

    Dim httpPumpN As Long
    http_multi_perform httpMultiH, httpPumpN

    If httpPumpN > 0 Then Exit Sub

    ' Transfer done -- clean up handles and mark success
    http_multi_remove httpMultiH, httpEasyH
    http_curl_cleanup httpEasyH : httpEasyH = 0
    http_slist_free httpSlistH  : httpSlistH = 0
    httpLastOK = -1
End Sub

Sub HTTP_PostJSON (httpUrl As String, httpKey As String, httpBody As String)
    If httpAvailable = 0 Or Len(httpUrl) = 0 Then Exit Sub

    If httpMultiH = 0 Then httpMultiH = http_multi_init%&
    If httpMultiH = 0 Then Exit Sub

    ' Drain any in-flight request before queuing a new one
    Do While httpEasyH <> 0
        HTTP_Pump
    Loop

    Dim httpH As _OFFSET : httpH = http_curl_init%&
    If httpH = 0 Then Exit Sub

    Dim httpL As _OFFSET
    httpL = http_slist_append%&(0, "Content-Type: application/json")
    httpL = http_slist_append%&(httpL, "apikey: " + httpKey)
    httpL = http_slist_append%&(httpL, "Authorization: Bearer " + httpKey)
    httpL = http_slist_append%&(httpL, "Prefer: return=minimal")

    http_setopt_str  httpH, CURLOPT_URL,         httpUrl
    http_setopt_str  httpH, CURLOPT_POSTFIELDS,  httpBody
    http_setopt_ptr  httpH, CURLOPT_HTTPHEADER,  httpL
    http_setopt_long httpH, CURLOPT_TIMEOUT,     5
    http_setopt_long httpH, CURLOPT_FAILONERROR, 1

    http_multi_add httpMultiH, httpH
    httpEasyH  = httpH
    httpSlistH = httpL
    httpLastOK = 0
End Sub
