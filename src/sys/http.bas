' http.bas -- non-blocking HTTPS POST via libcurl
'
' HTTP_PostJSON url$, apikey$, body$  enqueue POST; returns immediately (non-blocking)
' HTTP_Pump                           drive I/O; call each frame while httpEasyH <> 0
' httpEasyH (shared)                  non-zero while transfer in flight
' httpLastOK (shared)                 -1 if last completed request succeeded
'
' Uses DECLARE LIBRARY with a C header (curl_qb64.h) so QB64-PE emits proper
' extern "C" declarations and links via the normal -lcurl / libcurl.a mechanism.
' No dlopen, no hardcoded paths.  Works on Windows (QB64-PE static curl),
' Linux, and macOS (system -lcurl).
'
' Linkage is triggered by _OPENCLIENT in httpForceLink (never called at runtime),
' which sets DEPENDENCY_SOCKETS / DEP_HTTP=y so QB64-PE adds -lcurl to the link.
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
    ' qb64_http_post: copies all strings to stable C buffers, then configures curl
    FUNCTION http_post_setup&        ALIAS "qb64_http_post" _
        (BYVAL httpEH%&, BYVAL httpMH%&, _
         httpUrl AS STRING, BYVAL httpUrlLen AS LONG, _
         httpKey AS STRING, BYVAL httpKeyLen AS LONG, _
         httpBody AS STRING, BYVAL httpBodyLen AS LONG)
    SUB     http_cleanup_slist       ALIAS "qb64_http_cleanup_slist"
END DECLARE

Dim Shared httpMultiH As _OFFSET  ' curl_multi handle; 0 = not initialized
Dim Shared httpEasyH  As _OFFSET  ' in-flight easy handle; 0 = idle
Dim Shared httpLastOK As Long     ' -1 = last completed request succeeded; 0 = failed

' Drive the in-flight request; call from the game loop each frame.
Sub HTTP_Pump
    If httpMultiH = 0 Or httpEasyH = 0 Then Exit Sub

    Dim httpPumpN As Long
    http_multi_perform httpMultiH, httpPumpN

    If httpPumpN > 0 Then Exit Sub

    ' Transfer done -- read CURLcode BEFORE removing handle (disappears after remove)
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
    http_curl_cleanup httpEasyH  : httpEasyH = 0
    http_cleanup_slist

    If httpCurlCode > 0 Then
        Dim httpErrStr As String : httpErrStr = Space$(256)
        http_curl_error_str httpCurlCode, httpErrStr, 256
        DBG_Print "HTTP: CURLcode=" + LTrim$(Str$(httpCurlCode)) + " " + RTrim$(httpErrStr)
    End If
    If httpStatus >= 200 And httpStatus < 300 Then
        httpLastOK = -1
        DBG_Print "HTTP: status=" + LTrim$(Str$(httpStatus)) + " OK"
    Else
        httpLastOK = 0
        DBG_Print "HTTP: status=" + LTrim$(Str$(httpStatus)) + " FAILED"
        If Len(httpLastHeaders) > 0 Then DBG_Print "HTTP: headers=" + httpLastHeaders
        If Len(httpLastBody)    > 0 Then DBG_Print "HTTP: body="    + httpLastBody
    End If
End Sub

' Never called -- triggers DEPENDENCY_SOCKETS so QB64-PE links libcurl
Sub httpForceLink
    Dim httpDepX As Long : httpDepX = _OPENCLIENT("TCP:localhost:0") : Close httpDepX
End Sub

Sub HTTP_PostJSON (httpUrl As String, httpKey As String, httpBody As String)
    If Len(httpUrl) = 0 Then Exit Sub

    If httpMultiH = 0 Then httpMultiH = http_multi_init%&
    If httpMultiH = 0 Then Exit Sub

    ' Drain any in-flight request before queuing a new one
    Do While httpEasyH <> 0
        HTTP_Pump
    Loop

    Dim httpH As _OFFSET : httpH = http_curl_init%&
    If httpH = 0 Then DBG_Print "HTTP: curl_easy_init failed" : Exit Sub

    httpPostBody = httpBody
    DBG_Print "HTTP: POST urlLen=" + LTrim$(Str$(Len(httpUrl))) + " bodyLen=" + LTrim$(Str$(Len(httpBody)))

    ' All string copies into stable C buffers, all setopt calls, and multi_add happen
    ' inside qb64_http_post -- no QB64-PE string temps ever outlive their setopt call.
    Dim httpR As Long
    httpR = http_post_setup&(httpH, httpMultiH, _
                             httpUrl, Len(httpUrl), _
                             httpKey, Len(httpKey), _
                             httpBody, Len(httpBody))
    DBG_Print "HTTP: post_setup=" + LTrim$(Str$(httpR))
    If httpR <> 0 Then
        http_curl_cleanup httpH : Exit Sub
    End If

    httpEasyH  = httpH
    httpLastOK = 0
End Sub
