Sub TOOL_Init(tiTitle As String)
    _Title tiTitle
End Sub

Sub TOOL_Cls(tcBgCol As Long)
    Line (0, 0)-(_Width - 1, _Height - 1), tcBgCol, BF
End Sub
