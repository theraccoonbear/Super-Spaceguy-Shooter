' telem_batch_test.bas -- exercises the QB64-PE HTTP code path end-to-end
' Build: ./tools/buildqb tools/telem_batch_test.bas
' Run:   builds/telem_batch_test
'
' Reads credentials from assets/.env, synthesises a 4-row session batch using
' the same JSON functions and HTTP_PostJSON/HTTP_Pump code the game uses,
' then reports the actual HTTP status + any error body from Supabase.

$CONSOLE:ONLY
OPTION _EXPLICIT

TYPE HttpResponse
    statusCode AS LONG
    bodyLen    AS LONG
    headerLen  AS LONG
END TYPE

DIM SHARED httpLastResp    AS HttpResponse
DIM SHARED httpLastBody    AS STRING
DIM SHARED httpLastHeaders AS STRING
DIM SHARED httpPostBody    AS STRING
DIM SHARED TELEM_NET_URL   AS STRING
DIM SHARED TELEM_NET_KEY   AS STRING

'$INCLUDE:'../src/sys/json.bas'
'$INCLUDE:'../src/sys/http.bas'

' DBG_Print shim -- http.bas calls this; route to console
Sub DBG_Print (msg As String)
    Print msg
End Sub

' --- load credentials from assets/.env ---
Dim tbEnvF As Integer, tbEnvLn As String, tbEnvEq As Integer
If _FileExists(_StartDir$ + "/assets/.env") Then
    tbEnvF = FreeFile
    Open _StartDir$ + "/assets/.env" For Input As #tbEnvF
    Do While Not EOF(tbEnvF)
        Line Input #tbEnvF, tbEnvLn
        tbEnvLn = LTrim$(RTrim$(tbEnvLn))
        If Left$(tbEnvLn, 1) <> "#" And Len(tbEnvLn) > 0 Then
            tbEnvEq = InStr(tbEnvLn, "=")
            If tbEnvEq > 0 Then
                Select Case Left$(tbEnvLn, tbEnvEq - 1)
                    Case "TELEM_NET_URL" : If Len(TELEM_NET_URL) = 0 Then TELEM_NET_URL = Mid$(tbEnvLn, tbEnvEq + 1)
                    Case "TELEM_NET_KEY" : If Len(TELEM_NET_KEY) = 0 Then TELEM_NET_KEY = Mid$(tbEnvLn, tbEnvEq + 1)
                End Select
            End If
        End If
    Loop
    Close #tbEnvF
End If

If Len(TELEM_NET_URL) = 0 Or Len(TELEM_NET_KEY) = 0 Then
    Print "ERROR: no credentials -- populate assets/.env with TELEM_NET_URL and TELEM_NET_KEY"
    End 1
End If

' --- synthesise a session batch (same structure the game POSTs) ---
RANDOMIZE TIMER
Dim tbSession  As String
tbSession = "test_" + Mid$(Date$, 7, 4) + Mid$(Date$, 1, 2) + Mid$(Date$, 4, 2) _
          + Left$(Time$, 2) + Mid$(Time$, 4, 2) + Right$(Time$, 2)

Dim tbPlayer As String : tbPlayer = TB_UUID$
Dim tbT      As Long   : tbT      = Int(Timer)

Dim tbBatch As String
tbBatch = tbBatch + JSON_Obj$(JSON_S$("session", tbSession) + "," + JSON_N$("ev_time", LTrim$(Str$(tbT)))     + "," + JSON_S$("event", "session_start") + "," + JSON_S$("player_id", tbPlayer) + "," + JSON_S$("data", "player_id=" + tbPlayer + "|version=0.1.0-test|nerf=0"))
tbBatch = tbBatch + "," + JSON_Obj$(JSON_S$("session", tbSession) + "," + JSON_N$("ev_time", LTrim$(Str$(tbT+5))) + "," + JSON_S$("event", "enemy_killed")   + "," + JSON_S$("player_id", tbPlayer) + "," + JSON_S$("data", "score=100|kills=1|wave=0"))
tbBatch = tbBatch + "," + JSON_Obj$(JSON_S$("session", tbSession) + "," + JSON_N$("ev_time", LTrim$(Str$(tbT+20)))+ "," + JSON_S$("event", "player_death")    + "," + JSON_S$("player_id", tbPlayer) + "," + JSON_S$("data", "score=100|kills=1|wave=0|boss=0|cause=test"))
tbBatch = tbBatch + "," + JSON_Obj$(JSON_S$("session", tbSession) + "," + JSON_N$("ev_time", LTrim$(Str$(tbT+20)))+ "," + JSON_S$("event", "session_end")     + "," + JSON_S$("player_id", tbPlayer) + "," + JSON_S$("data", "score=100|kills=1|boss=0|shots=5|hits=3|misses=2|escapes=0"))
tbBatch = "[" + tbBatch + "]"

Print "Endpoint:  " + TELEM_NET_URL
Print "Session:   " + tbSession
Print "Player ID: " + tbPlayer
Print "Batch:     " + LTrim$(Str$(Len(tbBatch))) + " bytes, 4 rows"
Print ""
Print "POSTing via QB64-PE libcurl binding..."

HTTP_PostJSON TELEM_NET_URL, TELEM_NET_KEY, tbBatch

Dim tbDeadline As Double : tbDeadline = Timer + 10
Do While httpEasyH <> 0
    HTTP_Pump
    _Delay 0.05
    If Timer > tbDeadline Then
        Print "TIMEOUT: pump loop exceeded 10s -- libcurl never completed"
        End 1
    End If
Loop

Print ""
If httpLastOK Then
    Print "RESULT: SUCCESS  status=" + LTrim$(Str$(httpLastResp.statusCode))
    Print "Check Supabase: session=" + tbSession + "  (4 rows expected)"
Else
    Print "RESULT: FAILED   status=" + LTrim$(Str$(httpLastResp.statusCode))
    If Len(httpLastBody)    > 0 Then Print "body: "    + httpLastBody
    If Len(httpLastHeaders) > 0 Then Print "headers: " + httpLastHeaders
End If

End

Function TB_UUID$
    Dim u As String, b As Integer, i As Integer
    For i = 1 To 16
        b = Int(Rnd * 256)
        If i = 7 Then b = (b And &H0F) Or &H40
        If i = 9 Then b = (b And &H3F) Or &H80
        u = u + Right$("0" + Hex$(b), 2)
        Select Case i : Case 4, 6, 8, 10 : u = u + "-" : End Select
    Next i
    TB_UUID$ = LCase$(u)
End Function
