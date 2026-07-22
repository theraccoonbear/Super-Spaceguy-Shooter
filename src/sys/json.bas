' json.bas -- minimal JSON encoder
'
' JSON_Esc$(s$)      -- escape a string value for embedding inside JSON quotes
' JSON_S$(k$, v$)    -- "k":"v" string key-value pair (both escaped)
' JSON_N$(k$, n$)    -- "k":n  numeric key-value pair (n pre-formatted, no quotes)
' JSON_Obj$(body$)   -- {body} wraps comma-joined pairs in braces
'
' Local variable prefix: js*

Function JSON_Esc$ (jsIn As String)
    Dim jsOut As String
    Dim jsI As Integer
    Dim jsC As String
    For jsI = 1 To Len(jsIn)
        jsC = Mid$(jsIn, jsI, 1)
        Select Case jsC
            Case Chr$(34)  : jsOut = jsOut + "\" + Chr$(34)
            Case "\"       : jsOut = jsOut + "\\"
            Case Chr$(10)  : jsOut = jsOut + "\n"
            Case Chr$(13)  : jsOut = jsOut + "\r"
            Case Chr$(9)   : jsOut = jsOut + "\t"
            Case Else      : jsOut = jsOut + jsC
        End Select
    Next jsI
    JSON_Esc$ = jsOut
End Function

Function JSON_S$ (jsKey As String, jsVal As String)
    Dim jsQ As String : jsQ = Chr$(34)
    JSON_S$ = jsQ + JSON_Esc$(jsKey) + jsQ + ":" + jsQ + JSON_Esc$(jsVal) + jsQ
End Function

Function JSON_N$ (jsKey As String, jsNum As String)
    JSON_N$ = Chr$(34) + JSON_Esc$(jsKey) + Chr$(34) + ":" + jsNum
End Function

Function JSON_Obj$ (jsBody As String)
    JSON_Obj$ = "{" + jsBody + "}"
End Function
