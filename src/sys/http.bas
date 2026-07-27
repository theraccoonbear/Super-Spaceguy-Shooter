' http.bas -- non-blocking HTTPS via libcurl (multi-interface queue)
'
' HTTP_Post url$, key$, body$, tag$   enqueue POST; returns immediately
' HTTP_Get  url$, key$, tag$          enqueue GET;  returns immediately
' HTTP_Pump                           drive I/O; call each frame
' HTTP_Flush secs                     blocking drain for exit paths
'
' httpEasyH (shared)   non-zero while a transfer is in flight
' httpQCount (shared)  pending requests in queue
' httpLastOK (shared)  -1 if last completed request succeeded; 0 = failed
' httpLastTag (shared) tag string of most-recently completed request (in dims.bas)
'
' Uses DECLARE LIBRARY with a C header (curl_qb64.h) for curl binding.
' Linkage is triggered by _OPENCLIENT in httpForceLink (never called at runtime),
' which sets DEPENDENCY_SOCKETS so QB64-PE adds -lcurl to the link.
'
' Local variable prefix: http*

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

Const HTTP_QUEUE_CAP  = 8
Const HTTP_METHOD_POST = 0
Const HTTP_METHOD_GET  = 1

' Parallel arrays -- QB64-PE TYPE cannot hold variable-length strings
Dim Shared httpQUrl(0 To HTTP_QUEUE_CAP - 1)  As String
Dim Shared httpQKey(0 To HTTP_QUEUE_CAP - 1)  As String
Dim Shared httpQBody(0 To HTTP_QUEUE_CAP - 1) As String
Dim Shared httpQTag(0 To HTTP_QUEUE_CAP - 1)  As String
Dim Shared httpQMethod(0 To HTTP_QUEUE_CAP - 1) As Integer

Dim Shared httpQHead  As Integer  ' index of oldest pending slot
Dim Shared httpQCount As Integer  ' number of pending slots

Dim Shared httpMultiH   As _OFFSET  ' curl_multi handle; 0 = not initialized
Dim Shared httpEasyH    As _OFFSET  ' in-flight easy handle; 0 = idle
Dim Shared httpLastOK   As Long     ' -1 = last completed request succeeded; 0 = failed
Dim Shared httpActiveTag As String  ' tag of the in-flight request

' Pop and start the next queued request.  Internal helper; not for game code.
Sub HTTP_StartNext
    If httpQCount = 0 Then Exit Sub
    If httpEasyH <> 0 Then Exit Sub

    If httpMultiH = 0 Then httpMultiH = http_multi_init%&
    If httpMultiH = 0 Then Exit Sub

    Dim httpH As _OFFSET : httpH = http_curl_init%&
    If httpH = 0 Then DBG_Print "HTTP: curl_easy_init failed" : Exit Sub

    Dim httpSlot As Integer : httpSlot = httpQHead
    Dim httpR    As Long
    If httpQMethod(httpSlot) = HTTP_METHOD_GET Then
        httpR = http_get_setup&(httpH, httpMultiH, _
                                httpQUrl(httpSlot), Len(httpQUrl(httpSlot)), _
                                httpQKey(httpSlot), Len(httpQKey(httpSlot)))
    Else
        httpR = http_post_setup&(httpH, httpMultiH, _
                                 httpQUrl(httpSlot), Len(httpQUrl(httpSlot)), _
                                 httpQKey(httpSlot), Len(httpQKey(httpSlot)), _
                                 httpQBody(httpSlot), Len(httpQBody(httpSlot)))
    End If

    If httpR <> 0 Then
        DBG_Print "HTTP: setup failed rc=" + LTrim$(Str$(httpR)) + " tag=" + httpQTag(httpSlot)
        http_curl_cleanup httpH
    Else
        httpEasyH    = httpH
        httpLastOK   = 0
        httpActiveTag = httpQTag(httpSlot)
        DBG_Print "HTTP: started tag=" + httpActiveTag
    End If

    ' Consume the slot regardless of success so the queue always advances
    httpQHead  = (httpQHead + 1) Mod HTTP_QUEUE_CAP
    httpQCount = httpQCount - 1
End Sub

' Drive the in-flight request; call from the game loop each frame.
Sub HTTP_Pump
    If httpMultiH = 0 Then Exit Sub

    ' Start a queued request if nothing is in flight
    If httpEasyH = 0 Then HTTP_StartNext

    If httpEasyH = 0 Then Exit Sub

    Dim httpPumpN As Long
    http_multi_perform httpMultiH, httpPumpN

    If httpPumpN > 0 Then Exit Sub

    ' Transfer done -- read CURLcode BEFORE removing handle
    Dim httpCurlCode As Long : httpCurlCode = http_last_curlcode&(httpMultiH)
    Dim httpStatus   As Long : httpStatus   = http_response_code&(httpEasyH)

    httpLastResp.statusCode = httpStatus
    httpLastResp.bodyLen    = http_resp_body_len&
    httpLastResp.headerLen  = http_resp_hdrs_len&
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
    httpLastTag  = httpActiveTag
    httpActiveTag = ""

    If httpCurlCode > 0 Then
        Dim httpErrStr As String : httpErrStr = Space$(256)
        http_curl_error_str httpCurlCode, httpErrStr, 256
        DBG_Print "HTTP: CURLcode=" + LTrim$(Str$(httpCurlCode)) + " " + RTrim$(httpErrStr)
    End If
    If httpStatus >= 200 And httpStatus < 300 Then
        httpLastOK = -1
        DBG_Print "HTTP: status=" + LTrim$(Str$(httpStatus)) + " OK tag=" + httpLastTag
    Else
        httpLastOK = 0
        DBG_Print "HTTP: status=" + LTrim$(Str$(httpStatus)) + " FAILED tag=" + httpLastTag
        If Len(httpLastHeaders) > 0 Then DBG_Print "HTTP: headers=" + httpLastHeaders
        If Len(httpLastBody)    > 0 Then DBG_Print "HTTP: body="    + httpLastBody
    End If

    ' Kick off the next pending request immediately
    If httpQCount > 0 Then HTTP_StartNext
End Sub

' Enqueue a POST request.  Returns immediately; never blocks.
Sub HTTP_Post (httpUrl As String, httpKey As String, httpBody As String, httpTag As String)
    If Len(httpUrl) = 0 Then Exit Sub
    If httpQCount >= HTTP_QUEUE_CAP Then
        DBG_Print "HTTP: queue full, dropping POST tag=" + httpTag : Exit Sub
    End If
    Dim httpTail As Integer : httpTail = (httpQHead + httpQCount) Mod HTTP_QUEUE_CAP
    httpQUrl(httpTail)    = httpUrl
    httpQKey(httpTail)    = httpKey
    httpQBody(httpTail)   = httpBody
    httpQTag(httpTail)    = httpTag
    httpQMethod(httpTail) = HTTP_METHOD_POST
    httpQCount = httpQCount + 1
    DBG_Print "HTTP: enqueued POST tag=" + httpTag + " q=" + LTrim$(Str$(httpQCount))
    If httpEasyH = 0 Then HTTP_StartNext
End Sub

' Enqueue a GET request.  Returns immediately; never blocks.
Sub HTTP_Get (httpUrl As String, httpKey As String, httpTag As String)
    If Len(httpUrl) = 0 Then Exit Sub
    If httpQCount >= HTTP_QUEUE_CAP Then
        DBG_Print "HTTP: queue full, dropping GET tag=" + httpTag : Exit Sub
    End If
    Dim httpTail As Integer : httpTail = (httpQHead + httpQCount) Mod HTTP_QUEUE_CAP
    httpQUrl(httpTail)    = httpUrl
    httpQKey(httpTail)    = httpKey
    httpQBody(httpTail)   = ""
    httpQTag(httpTail)    = httpTag
    httpQMethod(httpTail) = HTTP_METHOD_GET
    httpQCount = httpQCount + 1
    DBG_Print "HTTP: enqueued GET tag=" + httpTag + " q=" + LTrim$(Str$(httpQCount))
    If httpEasyH = 0 Then HTTP_StartNext
End Sub

' Blocking drain; call before System to flush any pending requests.
Sub HTTP_Flush (httpTimeoutSec As Single)
    Dim httpT0 As Double : httpT0 = Timer
    Do While (httpEasyH <> 0 Or httpQCount > 0) And (Timer - httpT0 < httpTimeoutSec)
        HTTP_Pump
        _Delay 0.01
    Loop
End Sub

' Never called -- triggers DEPENDENCY_SOCKETS so QB64-PE links libcurl
Sub httpForceLink
    Dim httpDepX As Long : httpDepX = _OPENCLIENT("TCP:localhost:0") : Close httpDepX
End Sub
