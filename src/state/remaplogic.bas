' remaplogic.bas -- the Controls remap page (GS_REMAP) and the pad setup wizard: input and
' state only; remap.bas draws them (#266, #192).
'
' RMP_Open ret            the page (from Settings or the pause dialog), back to state ret
' RMP_OpenWizard ret      straight into the pad setup wizard (an unknown pad at the title)
' ev = RMP_Input%         once per frame; RMP_EV_* for the UI sound. rmpSaveDue asks the
'                         caller to SETTINGS_Save; on leaving, gameState is ret again.
'
' The wizard, one prompt per action from rmpWizFirst to rmpWizLast:
' RMP_WizStart kind, first, last
' res = RMP_WizStep%(escDown, skipDown, keyHit)  RMP_RUNNING / RMP_FINISHED / RMP_CANCELLED
' It takes the first new press (pad: a padRawBtn edge, never the Guide button; keyboard:
' keyHit), refuses one already given to a clashing action this run (rmpMsg$), skips on a
' stick / d-pad / arrow push or after RMP_TIMEOUT frames, and keyboard ESC cancels it.
' A binding taken from an action not yet set this run leaves that action unbound.
' Local variable prefix: rmp*

Const RMP_TIMEOUT = 600        ' frames per prompt (10 s at 60 fps), then it's skipped
Const RMP_MSG_FRAMES = 120
Const RMP_RELEASE_MAX = 180    ' leave a release wait after this many frames even if a pad axis sticks
Const RMP_RUNNING = 0
Const RMP_FINISHED = 1
Const RMP_CANCELLED = 2

Const RMP_MODE_PAGE = 0
Const RMP_MODE_WIZ = 1
Const RMP_MODE_RELEASE = 2     ' wait for every button and key to come up, so nothing reaches the next screen

Const RMP_ROW_SETUP = E3D_ACT_COUNT
Const RMP_ROW_RESET = E3D_ACT_COUNT + 1
Const RMP_ROWS = E3D_ACT_COUNT + 2

Const RMP_EV_NONE = 0
Const RMP_EV_MOVE = 1
Const RMP_EV_OK = 2
Const RMP_EV_DENY = 3

Dim Shared rmpMode As Integer, rmpReturn As Integer, rmpAuto As Integer, rmpLeaveAfter As Integer
Dim Shared rmpSel As Integer, rmpCol As Integer, rmpEscWas As Integer
Dim Shared rmpSaveDue As Integer, rmpLeft As Integer, rmpRelT As Integer, rmpSnapDue As Integer
Dim Shared rmpMsg$, rmpMsgT As Integer, rmpMsgBad As Integer
Dim Shared rmpWizKind As Integer, rmpWizFirst As Integer, rmpWizLast As Integer, rmpWizAct As Integer
Dim Shared rmpWizTimer As Integer, rmpWizEscWas As Integer, rmpWizSkipWas As Integer
Dim Shared rmpWizSet(1 To E3D_ACT_COUNT) As Integer
Dim Shared rmpWizWork(1 To E3D_ACT_COUNT) As Long
Dim Shared rmpWizPrev(1 To E3D_PAD_MAX_BTNS) As Integer

' Page row -> action: the keyboard movement set first, then the actions a pad button can take.
Function RMP_RowAct% (rraRow As Integer)
    If rraRow < 4 Then RMP_RowAct% = E3D_ACT_UP + rraRow Else RMP_RowAct% = rraRow - 3
End Function

Function RMP_InGame%
    RMP_InGame% = (rmpReturn = GS_PLAYING Or rmpReturn = GS_PLANET Or rmpReturn = GS_CINEMATIC)
End Function

Sub RMP_Say (rsTxt As String, rsBad As Integer)
    rmpMsg$ = rsTxt : rmpMsgT = RMP_MSG_FRAMES : rmpMsgBad = rsBad
End Sub

Sub RMP_Open (roRet As Integer)
    rmpReturn = roRet : rmpAuto = 0
    rmpSel = 0 : rmpCol = 0 : rmpMsgT = 0 : rmpLeft = 0 : rmpSaveDue = 0
    rmpSnapDue = -1
    RMP_Release 0
    gameState = GS_REMAP
End Sub

Sub RMP_OpenWizard (rowRet As Integer)
    RMP_Open rowRet
    rmpAuto = -1
    RMP_WizStart E3D_BIND_PAD, 1, E3D_ACT_PAD_COUNT
End Sub

' Pad buttons can be bound when a pad is in, or when a script plays one.
Function RMP_PadReady%
    RMP_PadReady% = (ctrlDev > 0 Or iscActive <> 0)
End Function

Sub RMP_Release (rrLeave As Integer)
    rmpMode = RMP_MODE_RELEASE : rmpLeaveAfter = rrLeave : rmpRelT = 0
End Sub

' No action button, pad button or the ESC key is down.
Function RMP_AllUp%
    Dim rauI As Integer
    RMP_AllUp% = 0
    For rauI = 1 To E3D_PAD_MAX_BTNS
        If padRawBtn(rauI) <> 0 Then Exit Function
    Next rauI
    For rauI = 1 To 6
        If held(rauI) <> 0 Then Exit Function
    Next rauI
    If held(E3D_KEY_SPACE) Or held(E3D_KEY_ESCAPE) Or held(E3D_KEY_TAB) Or held(E3D_KEY_ENTER) Then Exit Function
    If held(E3D_KEY_E) Or held(E3D_KEY_Q) Or held(E3D_KEY_W) Or held(E3D_KEY_A) Or held(E3D_KEY_S) Or held(E3D_KEY_D) Then Exit Function
    If KEY_Down%(27) Then Exit Function
    RMP_AllUp% = -1
End Function

' Back where the page was opened from, with every debounce armed so the screen we land on
' sees no press until a fresh one.
Sub RMP_Leave
    gameState = rmpReturn
    rmpLeft = -1
    escWas = -1 : optEscWas = -1 : pWas = -1 : tabWas = -1
    escYWas = -1 : escNWas = -1 : escCWas = -1 : escKWas = -1
    optUpWas = -1 : optDnWas = -1 : optLfWas = -1 : optRtWas = -1
End Sub

Function RMP_Input%
    Dim riRes As Integer, riAct As Integer, riEsc As Integer, riSkip As Integer
    RMP_Input% = RMP_EV_NONE
    If rmpMsgT > 0 Then rmpMsgT = rmpMsgT - 1
    riEsc = KEY_Down%(27)
    Select Case rmpMode
    Case RMP_MODE_RELEASE
        rmpRelT = rmpRelT + 1
        If RMP_AllUp% = 0 And rmpRelT < RMP_RELEASE_MAX Then Exit Function
        rmpEscWas = riEsc
        If rmpLeaveAfter Then RMP_Leave Else rmpMode = RMP_MODE_PAGE
    Case RMP_MODE_WIZ
        riSkip = (held(E3D_KEY_LEFT) <> 0) Or (held(E3D_KEY_RIGHT) <> 0) Or (held(E3D_KEY_UP) <> 0) Or (held(E3D_KEY_DOWN) <> 0)
        riAct = rmpWizAct
        riRes = RMP_WizStep%(riEsc, riSkip, KEY_Hit&)
        If rmpMsgT = RMP_MSG_FRAMES And rmpMsgBad Then RMP_Input% = RMP_EV_DENY
        If rmpWizAct <> riAct And riRes = RMP_RUNNING Then RMP_Input% = RMP_EV_OK
        If riRes = RMP_FINISHED Then
            If rmpWizKind = E3D_BIND_PAD Then E3D_PadRemember
            rmpSaveDue = -1
            RMP_Say "CONTROLS SAVED", 0
            RMP_Input% = RMP_EV_OK
            RMP_Release rmpAuto
        ElseIf riRes = RMP_CANCELLED Then
            ' an unknown pad's first-run setup counts as seen once cancelled: Settings > Controls reruns it
            If rmpAuto Then E3D_PadRemember : rmpSaveDue = -1
            RMP_Say "CANCELLED - NOTHING CHANGED", -1
            RMP_Release rmpAuto
        End If
    Case Else
        If KEY_Pressed%(E3D_KEY_UP) Then rmpSel = (rmpSel + RMP_ROWS - 1) Mod RMP_ROWS : RMP_Input% = RMP_EV_MOVE
        If KEY_Pressed%(E3D_KEY_DOWN) Then rmpSel = (rmpSel + 1) Mod RMP_ROWS : RMP_Input% = RMP_EV_MOVE
        If KEY_Pressed%(E3D_KEY_LEFT) Or KEY_Pressed%(E3D_KEY_RIGHT) Then rmpCol = 1 - rmpCol : RMP_Input% = RMP_EV_MOVE
        If (riEsc And rmpEscWas = 0) Or KEY_Back% Then
            rmpSaveDue = -1
            rmpEscWas = riEsc
            RMP_Release -1
            Exit Function
        End If
        rmpEscWas = riEsc
        If KEY_Confirm% = 0 Then Exit Function
        If rmpSel = RMP_ROW_RESET Then
            E3D_KeyDefaults
            E3D_PadDefaults ctrlLayout
            If ctrlDev > 0 Then E3D_PadRemember
            rmpSaveDue = -1
            RMP_Say "DEFAULTS RESTORED", 0
            RMP_Input% = RMP_EV_OK
        ElseIf rmpSel = RMP_ROW_SETUP Then
            If RMP_PadReady% Then
                RMP_WizStart E3D_BIND_PAD, 1, E3D_ACT_PAD_COUNT
                RMP_Input% = RMP_EV_OK
            Else
                RMP_Say "NO GAMEPAD CONNECTED", -1 : RMP_Input% = RMP_EV_DENY
            End If
        Else
            riAct = RMP_RowAct%(rmpSel)
            If rmpCol = 0 Then
                If E3D_KeyFixed%(riAct) Then
                    RMP_Say "ESC IS ALWAYS " + E3D_ActName$(riAct), -1 : RMP_Input% = RMP_EV_DENY
                Else
                    RMP_WizStart E3D_BIND_KEY, riAct, riAct : RMP_Input% = RMP_EV_OK
                End If
            ElseIf riAct > E3D_ACT_PAD_COUNT Then
                RMP_Say "THE STICK AND D-PAD MOVE", -1 : RMP_Input% = RMP_EV_DENY
            ElseIf RMP_PadReady% = 0 Then
                RMP_Say "NO GAMEPAD CONNECTED", -1 : RMP_Input% = RMP_EV_DENY
            Else
                RMP_WizStart E3D_BIND_PAD, riAct, riAct : RMP_Input% = RMP_EV_OK
            End If
        End If
    End Select
End Function

Sub RMP_WizStart (rwsKind As Integer, rwsFirst As Integer, rwsLast As Integer)
    Dim rwsI As Integer
    rmpWizKind = rwsKind : rmpWizFirst = rwsFirst : rmpWizLast = rwsLast
    For rwsI = 1 To E3D_ACT_COUNT
        rmpWizSet(rwsI) = 0
        If rwsKind = E3D_BIND_PAD Then rmpWizWork(rwsI) = padBind(rwsI) Else rmpWizWork(rwsI) = keyBind(rwsI)
    Next rwsI
    For rwsI = 1 To E3D_PAD_MAX_BTNS : rmpWizPrev(rwsI) = padRawBtn(rwsI) : Next rwsI
    rmpWizEscWas = KEY_Down%(27)
    rmpWizSkipWas = (held(E3D_KEY_LEFT) <> 0) Or (held(E3D_KEY_RIGHT) <> 0) Or (held(E3D_KEY_UP) <> 0) Or (held(E3D_KEY_DOWN) <> 0)
    Do While KEY_Hit& <> 0 : Loop
    rmpWizAct = rwsFirst - 1
    RMP_WizNext
    rmpMode = RMP_MODE_WIZ
End Sub

' Next action to prompt for (ESC-fixed ones have no key to ask about).
Sub RMP_WizNext
    rmpWizTimer = 0
    Do
        rmpWizAct = rmpWizAct + 1
        If rmpWizAct > rmpWizLast Then Exit Do
        If rmpWizKind = E3D_BIND_PAD Then Exit Do
        If E3D_KeyFixed%(rmpWizAct) = 0 Then Exit Do
    Loop
End Sub

Function RMP_BindName$ (rbnKind As Integer, rbnV As Long)
    If rbnKind = E3D_BIND_PAD Then RMP_BindName$ = E3D_PadBtnName$(rbnV, ctrlLayout) Else RMP_BindName$ = E3D_KeyName$(rbnV)
End Function

Function RMP_WizStep% (rwEsc As Integer, rwSkip As Integer, rwHit As Long)
    Dim rwI As Integer, rwGot As Long, rwClash As Integer
    RMP_WizStep% = RMP_RUNNING
    If rwEsc And rmpWizEscWas = 0 Then RMP_WizStep% = RMP_CANCELLED : Exit Function
    rmpWizEscWas = rwEsc

    rwGot = 0
    If rmpWizKind = E3D_BIND_PAD Then
        For rwI = 1 To E3D_PAD_MAX_BTNS
            If rwGot = 0 And padRawBtn(rwI) <> 0 And rmpWizPrev(rwI) = 0 And rwI <> ctrlGuideBtn Then rwGot = rwI
            rmpWizPrev(rwI) = padRawBtn(rwI)
        Next rwI
    ElseIf rwHit > 0 Then
        rwGot = rwHit
        If rwGot >= 65 And rwGot <= 90 Then rwGot = rwGot + 32
        Select Case rwGot
            Case E3D_KEY_ESCAPE, E3D_KEY_LEFT, E3D_KEY_RIGHT, E3D_KEY_UP, E3D_KEY_DOWN
                rwGot = 0
            Case Else
                If E3D_KeyReserved%(rwGot) Then RMP_Say E3D_KeyName$(rwGot) + " IS RESERVED", -1 : rwGot = 0
        End Select
    End If

    rwClash = 0
    If rwGot <> 0 Then
        For rwI = 1 To E3D_ACT_COUNT
            If rwClash = 0 And rmpWizSet(rwI) And rmpWizWork(rwI) = rwGot And E3D_BindClash%(rwI, rmpWizAct) Then rwClash = rwI
        Next rwI
        If rwClash Then
            RMP_Say RMP_BindName$(rmpWizKind, rwGot) + " IS ALREADY " + E3D_ActName$(rwClash), -1
        Else
            For rwI = 1 To E3D_ACT_COUNT
                If rmpWizWork(rwI) = rwGot And E3D_BindClash%(rwI, rmpWizAct) Then rmpWizWork(rwI) = 0
            Next rwI
            rmpWizWork(rmpWizAct) = rwGot : rmpWizSet(rmpWizAct) = -1
            RMP_WizNext
        End If
    ElseIf rwSkip And rmpWizSkipWas = 0 Then
        RMP_WizNext
    Else
        rmpWizTimer = rmpWizTimer + 1
        If rmpWizTimer >= RMP_TIMEOUT Then RMP_WizNext
    End If
    rmpWizSkipWas = rwSkip

    If rmpWizAct > rmpWizLast Then
        For rwI = 1 To E3D_ACT_COUNT
            If rmpWizKind = E3D_BIND_PAD Then padBind(rwI) = rmpWizWork(rwI) Else keyBind(rwI) = rmpWizWork(rwI)
        Next rwI
        RMP_WizStep% = RMP_FINISHED
    End If
End Function
