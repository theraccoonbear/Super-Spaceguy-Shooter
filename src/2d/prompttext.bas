' prompttext.bas — prompt token text, without drawing (so tests can include it; ui.bas draws)
'
'   t$ = UI_Tok$(key$, act)              a prompt inside prompt text (see ui.bas)
'   s$ = UI_PromptsKeyText$(txt$)        txt$ as the keyboard shows it, every token resolved

Function UI_Tok$ (utkKey As String, utkAct As Integer)
    UI_Tok$ = "{" + utkKey + "|" + LTrim$(Str$(utkAct)) + "}"
End Function

' Splits the next UI_Tok$ off upnTxt$ from upnPos: upnLit$ is the text before it; returns 0
' when there is no token left (upnLit$ is then the rest).
Function UI_PromptNext% (upnTxt As String, upnPos As Integer, upnLit As String, upnKey As String, upnAct As Integer)
    Dim upnO As Integer, upnC As Integer, upnBar As Integer, upnTok As String
    UI_PromptNext% = 0
    upnO = InStr(upnPos, upnTxt, "{")
    If upnO > 0 Then upnC = InStr(upnO, upnTxt, "}")
    If upnO = 0 Or upnC = 0 Then upnLit = Mid$(upnTxt, upnPos) : upnPos = Len(upnTxt) + 1 : Exit Function
    upnLit = Mid$(upnTxt, upnPos, upnO - upnPos)
    upnTok = Mid$(upnTxt, upnO + 1, upnC - upnO - 1)
    upnBar = InStr(upnTok, "|")
    upnKey = Left$(upnTok, upnBar - 1)
    upnAct = Val(Mid$(upnTok, upnBar + 1))
    If upnKey = "" And upnAct > 0 Then upnKey = E3D_KeyName$(keyBind(upnAct))
    upnPos = upnC + 1
    UI_PromptNext% = -1
End Function

Function UI_PromptsKeyText$ (upkTxt As String)
    Dim upkPos As Integer, upkLit As String, upkKey As String, upkAct As Integer, upkOut As String, upkMore As Integer
    upkPos = 1 : upkOut = ""
    Do
        upkMore = UI_PromptNext%(upkTxt, upkPos, upkLit, upkKey, upkAct)
        upkOut = upkOut + upkLit
        If upkMore = 0 Then Exit Do
        upkOut = upkOut + upkKey
    Loop
    UI_PromptsKeyText$ = upkOut
End Function
