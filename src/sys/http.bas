' http.bas -- native HTTPS POST via libcurl DECLARE LIBRARY
'
' HTTP_PostJSON url$, apikey$, body$ -- synchronous fire-and-forget POST.
'   Linux/macOS: DECLARE DYNAMIC LIBRARY "curl" (system libcurl)
'   Windows:     DECLARE LIBRARY "" (libcurl statically bundled by QB64-PE)
'
' Local variable prefix: http*

$IF WIN = 1 THEN
DECLARE LIBRARY ""
$ELSE
DECLARE DYNAMIC LIBRARY "curl"
$END IF
    FUNCTION http_curl_init%&    ALIAS "curl_easy_init"
    SUB     http_setopt_str      ALIAS "curl_easy_setopt"    (BYVAL httpH%&, BYVAL httpOpt%&, httpVal AS STRING)
    SUB     http_setopt_ptr      ALIAS "curl_easy_setopt"    (BYVAL httpH%&, BYVAL httpOpt%&, BYVAL httpVal%&)
    SUB     http_setopt_long     ALIAS "curl_easy_setopt"    (BYVAL httpH%&, BYVAL httpOpt%&, BYVAL httpVal%&)
    SUB     http_curl_perform    ALIAS "curl_easy_perform"   (BYVAL httpH%&)
    FUNCTION http_slist_append%& ALIAS "curl_slist_append"   (BYVAL httpL%&, httpVal AS STRING)
    SUB     http_slist_free      ALIAS "curl_slist_free_all" (BYVAL httpL%&)
    SUB     http_curl_cleanup    ALIAS "curl_easy_cleanup"   (BYVAL httpH%&)
END DECLARE

Const CURLOPT_URL         = 10002
Const CURLOPT_POSTFIELDS  = 10015
Const CURLOPT_HTTPHEADER  = 10023
Const CURLOPT_TIMEOUT     = 13
Const CURLOPT_FAILONERROR = 45

Sub HTTP_PostJSON (httpUrl As String, httpKey As String, httpBody As String)
    Dim httpH As _OFFSET
    Dim httpL As _OFFSET

    httpH = http_curl_init%&
    If httpH = 0 Then Exit Sub

    httpL = http_slist_append%&(0, "Content-Type: application/json")
    httpL = http_slist_append%&(httpL, "apikey: " + httpKey)
    httpL = http_slist_append%&(httpL, "Authorization: Bearer " + httpKey)
    httpL = http_slist_append%&(httpL, "Prefer: return=minimal")

    http_setopt_str  httpH, CURLOPT_URL,         httpUrl
    http_setopt_str  httpH, CURLOPT_POSTFIELDS,  httpBody
    http_setopt_ptr  httpH, CURLOPT_HTTPHEADER,  httpL
    http_setopt_long httpH, CURLOPT_TIMEOUT,     5
    http_setopt_long httpH, CURLOPT_FAILONERROR, 1

    http_curl_perform httpH

    http_slist_free httpL
    http_curl_cleanup httpH
End Sub
