' http.bas -- non-blocking HTTPS POST and GET via curl multi-interface
'
' Public API:
'   HTTP_Post url$, key$, body$, tag$   enqueue a JSON POST; returns immediately
'   HTTP_Get  url$, key$, tag$          enqueue a GET;       returns immediately
'   HTTP_Pump                           drive I/O one frame; call from the game loop
'   HTTP_Flush timeoutSec!              drain queue before exit (blocking, up to N secs)
'
' Response inspection (set by HTTP_Pump on each completion):
'   httpLastTag             -- tag of the most recently completed request
'   httpLastResp.statusCode -- HTTP status code (200, 204, 404, ...)
'   httpLastBody            -- response body string (empty for 204 / no-body responses)
'
' Usage pattern for leaderboard polling:
'   HTTP_Get LEADER_URL, LEADER_KEY, "leaderboard"
'   ... (each frame) ...
'   If httpLastTag = "leaderboard" Then
'       If httpLastResp.statusCode = 200 Then ... parse httpLastBody ...
'       httpLastTag = ""   ' clear so the same response isn't processed twice
'   End If
'
' Local variable prefix: http*

Const HTTP_QUEUE_CAP    = 8
Const HTTP_METHOD_POST  = 0
Const HTTP_METHOD_GET   = 1

DECLARE LIBRARY "curl_qb64"
    FUNCTION http_curl_init%&        ALIAS "curl_easy_init"
    SUB     http_curl_cleanup        ALIAS "curl_easy_cleanup"        (BYVAL httpH%&)
    FUNCTION http_multi_init%&       ALIAS "curl_multi_init"
    SUB     http_multi_perform       ALIAS "curl_multi_perform"       (BYVAL httpM%&, httpN AS LONG)
    SUB     http_multi_remove        ALIAS "curl_multi_remove_handle" (BYVAL httpM%&, BYVAL httpH%&)
    FUNCTION http_response_code&     ALIAS "qb64_curl_response_code"  (BYVAL httpH%&)
    FUNCTION http_resp_body_len&     ALIAS "qb64_resp_body_length"
    FUNCTION http_resp_hdrs_len&     ALIAS "qb64_resp_hdrs_length"
    SUB     http_get_body            ALIAS "qb64_get_body"            (buf AS STRING, BYVAL maxLen AS LONG)
    SUB     http_get_hdrs            ALIAS "qb64_get_hdrs"            (buf AS STRING, BYVAL maxLen AS LONG)
    FUNCTION http_last_curlcode&     ALIAS "qb64_curl_last_curlcode"  (BYVAL httpM%&)
    SUB     http_curl_error_str      ALIAS "qb64_curl_error_str"      (BYVAL httpCode AS LONG, buf AS STRING, BYVAL maxLen AS LONG)
    FUNCTION http_post_setup&        ALIAS "qb64_http_post" _
        (BYVAL httpEH%&, BYVAL httpMH%&, _
         httpUrl AS STRING, BYVAL httpUrlLen AS LONG, _
         httpKey AS STRING, BYVAL httpKeyLen AS LONG, _
         httpBody AS STRING, BYVAL httpBodyLen AS LONG)
    FUNCTION http_get_setup&         ALIAS "qb64_http_get" _
        (BYVAL httpEH%&, BYVAL httpMH%&, _
         httpUrl AS STRING, BYVAL httpUrlLen AS LONG, _
         httpKey AS STRING, BYVAL httpKeyLen AS LONG)
    SUB     http_cleanup_slist       ALIAS "qb64_http_cleanup_slist"
END DECLARE

' --- internal state ---
Dim Shared httpMultiH    As _OFFSET
Dim Shared httpEasyH     As _OFFSET
Dim Shared httpLastOK    As Long
Dim Shared httpActiveTag As String

' --- request queue (parallel arrays; QB64-PE TYPE cannot hold variable-length strings) ---
Dim Shared httpQUrl(0 To HTTP_QUEUE_CAP - 1)    As String
Dim Shared httpQKey(0 To HTTP_QUEUE_CAP - 1)    As String
Dim Shared httpQBody(0 To HTTP_QUEUE_CAP - 1)   As String
Dim Shared httpQTag(0 To HTTP_QUEUE_CAP - 1)    As String
Dim Shared httpQMethod(0 To HTTP_QUEUE_CAP - 1) As Integer
Dim Shared httpQHead  As Integer
Dim Shared httpQCount As Integer

' Pop and start the head of the queue. Internal -- do not call directly.
Sub HTTP_StartNext
    If httpQCount = 0 Then Exit Sub
    If httpMultiH = 0 Then httpMultiH = http_multi_init%& : If httpMultiH = 0 Then Exit Sub

    Dim httpSUrl    As String  : httpSUrl    = httpQUrl(httpQHead)
    Dim httpSKey    As String  : httpSKey    = httpQKey(httpQHead)
    Dim httpSBody   As String  : httpSBody   = httpQBody(httpQHead)
    Dim httpSTag    As String  : httpSTag    = httpQTag(httpQHead)
    Dim httpSMethod As Integer : httpSMethod = httpQMethod(httpQHead)

    httpQUrl(httpQHead) = "" : httpQKey(httpQHead) = "" : httpQBody(httpQHead) = ""
    httpQHead  = (httpQHead + 1) Mod HTTP_QUEUE_CAP
    httpQCount = httpQCount - 1

    Dim httpH As _OFFSET : httpH = http_curl_init%&
    If httpH = 0 Then DBG_Print "HTTP: curl_easy_init failed [" + httpSTag + "]" : Exit Sub

    Dim httpR As Long
    If httpSMethod = HTTP_METHOD_POST Then
        httpR = http_post_setup&(httpH, httpMultiH, _
                                 httpSUrl, Len(httpSUrl), _
                                 httpSKey, Len(httpSKey), _
                                 httpSBody, Len(httpSBody))
    Else
        httpR = http_get_setup&(httpH, httpMultiH, _
                                httpSUrl, Len(httpSUrl), _
                                httpSKey, Len(httpSKey))
    End If

    If httpR <> 0 Then
        DBG_Print "HTTP: setup failed rc=" + LTrim$(Str$(httpR)) + " [" + httpSTag + "]"
        http_curl_cleanup httpH : Exit Sub
    End If

    httpEasyH    = httpH
    httpActiveTag = httpSTag
    httpLastOK   = 0
    DBG_Print "HTTP: started [" + httpSTag + "]"
End Sub

' Drive the in-flight transfer (non-blocking); call once per frame.
' On completion: sets httpLastTag, httpLastResp.statusCode, httpLastBody,
' then automatically starts the next queued request.
Sub HTTP_Pump
    ' Recover from a failed HTTP_StartNext (easy=0 but queue non-empty)
    If httpEasyH = 0 And httpQCount > 0 Then HTTP_StartNext
    If httpMultiH = 0 Or httpEasyH = 0 Then Exit Sub

    Dim httpPumpN As Long
    http_multi_perform httpMultiH, httpPumpN
    If httpPumpN > 0 Then Exit Sub

    ' Transfer done -- read CURLcode before removing the handle (pointer goes stale after)
    Dim httpCurlCode As Long : httpCurlCode = http_last_curlcode&(httpMultiH)
    Dim httpStatus   As Long : httpStatus   = http_response_code&(httpEasyH)

    httpLastResp.statusCode = httpStatus
    httpLastResp.bodyLen    = http_resp_body_len&
    httpLastResp.headerLen  = http_resp_hdrs_len&
    httpLastTag             = httpActiveTag

    If httpLastResp.bodyLen > 0 Then
        httpLastBody = Space$(httpLastResp.bodyLen)
        http_get_body httpLastBody, httpLastResp.bodyLen
    Else
        httpLastBody = ""
    End If
    If httpLastResp.headerLen > 0 Then
        httpLastHeaders = Space$(httpLastResp.headerLen)
        http_get_hdrs httpLastHeaders, httpLastResp.headerLen
    Else
        httpLastHeaders = ""
    End If

    http_multi_remove httpMultiH, httpEasyH
    http_curl_cleanup httpEasyH : httpEasyH = 0
    http_cleanup_slist
    httpActiveTag = ""

    If httpCurlCode > 0 Then
        Dim httpErrStr As String : httpErrStr = Space$(256)
        http_curl_error_str httpCurlCode, httpErrStr, 256
        DBG_Print "HTTP [" + httpLastTag + "]: CURLcode=" + LTrim$(Str$(httpCurlCode)) + " " + RTrim$(httpErrStr)
    End If
    If httpStatus >= 200 And httpStatus < 300 Then
        httpLastOK = -1
        DBG_Print "HTTP [" + httpLastTag + "]: status=" + LTrim$(Str$(httpStatus)) + " OK"
    Else
        httpLastOK = 0
        DBG_Print "HTTP [" + httpLastTag + "]: status=" + LTrim$(Str$(httpStatus)) + " FAILED"
        If Len(httpLastHeaders) > 0 Then DBG_Print "HTTP: headers=" + httpLastHeaders
        If Len(httpLastBody)    > 0 Then DBG_Print "HTTP: body="    + httpLastBody
    End If

    If httpQCount > 0 Then HTTP_StartNext
End Sub

' Enqueue a JSON POST. Returns immediately; never blocks the game loop.
Sub HTTP_Post(httpUrl As String, httpKey As String, httpBody As String, httpTag As String)
    If Len(httpUrl) = 0 Then Exit Sub
    If httpQCount >= HTTP_QUEUE_CAP Then DBG_Print "HTTP: queue full, dropping [" + httpTag + "]" : Exit Sub
    If httpMultiH = 0 Then httpMultiH = http_multi_init%& : If httpMultiH = 0 Then Exit Sub

    Dim httpTail As Integer : httpTail = (httpQHead + httpQCount) Mod HTTP_QUEUE_CAP
    httpQUrl(httpTail)    = httpUrl
    httpQKey(httpTail)    = httpKey
    httpQBody(httpTail)   = httpBody
    httpQTag(httpTail)    = httpTag
    httpQMethod(httpTail) = HTTP_METHOD_POST
    httpQCount = httpQCount + 1

    If httpEasyH = 0 Then HTTP_StartNext
End Sub

' Enqueue a GET request. Returns immediately; never blocks the game loop.
' Check httpLastTag = tag each frame after HTTP_Pump to detect completion.
Sub HTTP_Get(httpUrl As String, httpKey As String, httpTag As String)
    If Len(httpUrl) = 0 Then Exit Sub
    If httpQCount >= HTTP_QUEUE_CAP Then DBG_Print "HTTP: queue full, dropping [" + httpTag + "]" : Exit Sub
    If httpMultiH = 0 Then httpMultiH = http_multi_init%& : If httpMultiH = 0 Then Exit Sub

    Dim httpGTail As Integer : httpGTail = (httpQHead + httpQCount) Mod HTTP_QUEUE_CAP
    httpQUrl(httpGTail)    = httpUrl
    httpQKey(httpGTail)    = httpKey
    httpQBody(httpGTail)   = ""
    httpQTag(httpGTail)    = httpTag
    httpQMethod(httpGTail) = HTTP_METHOD_GET
    httpQCount = httpQCount + 1

    If httpEasyH = 0 Then HTTP_StartNext
End Sub

' Block up to httpFTimeout seconds draining the queue and in-flight request.
' Call before System on a path that may have queued requests to flush.
Sub HTTP_Flush(httpFTimeout As Single)
    Dim httpFT As Double : httpFT = Timer
    Do While (httpEasyH <> 0 Or httpQCount > 0) And Timer - httpFT < httpFTimeout
        HTTP_Pump
        _Delay 0.01
    Loop
End Sub

' Never called at runtime -- referenced so QB64-PE emits DEPENDENCY_SOCKETS
' and links libcurl into the binary.
Sub httpForceLink
    Dim httpDepX As Long : httpDepX = _OPENCLIENT("TCP:localhost:0") : Close httpDepX
End Sub
