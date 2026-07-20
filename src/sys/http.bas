' http.bas -- fire-and-forget HTTPS POST via system curl
'
' HTTP_PostJSON url$, apikey$, body$ -- POST JSON body with Supabase-style auth.
'   Writes body to a temp file then shells out to curl (blocking, max 5s).
'   Called only at session end so the brief stall is acceptable.
'   Requires curl in PATH (pre-installed on Linux, macOS, and Windows 10+).
'
' Local variable prefix: http*

Sub HTTP_PostJSON (httpUrl As String, httpKey As String, httpBody As String)
    Dim httpTmp As String : httpTmp = _StartDir$ + "/sss_telem_pending.json"
    Dim httpF As Integer : httpF = FreeFile
    Open httpTmp For Output As #httpF
    Print #httpF, httpBody
    Close #httpF

    ' -s  = silent (no progress bar)
    ' -f  = fail silently on HTTP errors
    ' -m 5 = max 5-second total time
    ' -o /dev/null = discard response body
    Dim httpQ As String : httpQ = Chr$(34)
    Dim httpCmd As String
    httpCmd = "curl -sfm5 -o /dev/null -X POST " + httpQ + httpUrl + httpQ _
            + " -H " + httpQ + "Content-Type: application/json" + httpQ _
            + " -H " + httpQ + "apikey: " + httpKey + httpQ _
            + " -H " + httpQ + "Authorization: Bearer " + httpKey + httpQ _
            + " -H " + httpQ + "Prefer: return=minimal" + httpQ _
            + " --data-binary @" + httpQ + httpTmp + httpQ
    Shell httpCmd
End Sub
