' consentlogic.bas -- the telemetry consent screen's input, no drawing (consent.bas draws it)
'
' pick = CONSENT_Input%   once per frame: CONSENT_NONE, CONSENT_OK, CONSENT_SAVE or CONSENT_NO.
' Rows (cursor consentSel, starts on OK): OK, DON'T ASK AGAIN, NO THANKS; up / down move,
' ENTER / pad A picks. Hotkeys: SPACE = OK, S / pad X = don't ask again, ESC / pad B = no.
' uiSfx: move, confirm on any pick, back on ESC / pad B.
' Local variable prefix: cl*

Const CONSENT_NONE = 0
Const CONSENT_OK   = 1
Const CONSENT_SAVE = 2
Const CONSENT_NO   = 3
Const CONSENT_ROWS = 3

Dim Shared consentSel As Integer

Function CONSENT_Input%
    Dim clKey As Long, clPick As Integer, clRes As Integer
    clRes = CONSENT_NONE
    clKey = KEY_Hit&
    Select Case clKey
        Case 32 : clRes = CONSENT_OK
        Case 83, 115 : clRes = CONSENT_SAVE
        Case 27 : clRes = CONSENT_NO
    End Select
    clPick = MENU_Input%(consentSel, CONSENT_ROWS)
    If clPick >= 0 Then clRes = clPick + 1
    If KEY_Pressed%(E3D_KEY_PAD_X) Then clRes = CONSENT_SAVE
    If KEY_Pressed%(E3D_KEY_PAD_B) Then clRes = CONSENT_NO
    If clRes = CONSENT_OK Or clRes = CONSENT_SAVE Then uiSfx = SND_UI_OK
    If clRes = CONSENT_NO And clPick < 0 Then uiSfx = SND_UI_BACK
    CONSENT_Input% = clRes
End Function
