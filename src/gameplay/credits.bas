' credits.bas -- earning credits, and cashing the leftovers in for score at the end of a run (#268)
'
' The credit amounts and the bonus rate come from assets/config/economy.ini (UPG_Load reads
' them). The balance itself (credits, creditsEarned, creditsSpent) is in dims.bas.
'   CR_Add n                       earn n credits
'   CR_StageClear                  a stage-clear's worth (crStage)
'   pts = CR_BonusPoints&(c, rate) leftover credits -> score points, rounded down
'   CR_CashOut                     end of a run (win or death): add the bonus to score once,
'                                  zero the credits, log credit_bonus; later calls do nothing
'   CR_CashOutWin                  the same, then show the tally on the title (HUD_RunTally)
'   CR_ResetRun                    new run (GAME_ResetState): the cash-out may happen again
'   ok = CR_ParseArg%(s$, n)       --credits <n> validation
' No rendering here (HUD_RunTally and the game-over screen show crBonusPts).
' Local variable prefix: cr*

Dim Shared crKill As Long, crBoss As Long, crStage As Long
Dim Shared crAstNear As Long, crAstKill As Long, crAstSurvive As Long
Dim Shared crBonusRate As Double : crBonusRate = 1   ' score points per leftover credit (credit_bonus_rate)
Dim Shared crBonusDone As Integer : crBonusDone = -1   ' -1 = cashed out, or no run started yet (boot reaches the title too)
Dim Shared crBonusCredits As Long, crBonusPts As Long
Dim Shared crTallyTimer As Integer                  ' frames the win tally stays on the title

Sub CR_Add (crN As Long)
    credits = credits + crN
    creditsEarned = creditsEarned + crN
End Sub

Sub CR_StageClear
    CR_Add crStage
End Sub

Function CR_BonusPoints& (crbCredits As Long, crbRate As Double)
    If crbCredits <= 0 Or crbRate <= 0 Then CR_BonusPoints& = 0 : Exit Function
    CR_BonusPoints& = Int(crbCredits * crbRate + 0.000001)   ' e.g. 7 x 0.3 is 2.0999...: still 2
End Function

Sub CR_CashOut
    If crBonusDone Then Exit Sub
    crBonusDone = -1
    crBonusCredits = credits
    crBonusPts = CR_BonusPoints&(crBonusCredits, crBonusRate)
    score = score + crBonusPts
    credits = 0
    TELEM_CreditBonus crBonusCredits, crBonusRate, crBonusPts
End Sub

' Win path (sequence.bas): cash out and keep the tally up on the title for a few seconds.
Sub CR_CashOutWin
    If crBonusDone Then Exit Sub
    CR_CashOut
    If crBonusCredits > 0 Then crTallyTimer = 300
End Sub

Sub CR_ResetRun
    crBonusDone = 0 : crBonusCredits = 0 : crBonusPts = 0 : crTallyTimer = 0
End Sub

' --credits <n>: a whole number 0..999999999. 0 (and crpN untouched) if it isn't one.
Function CR_ParseArg% (crpS As String, crpN As Long)
    Dim crpI As Integer
    CR_ParseArg% = 0
    If Len(crpS) = 0 Or Len(crpS) > 9 Then Exit Function
    For crpI = 1 To Len(crpS)
        If Mid$(crpS, crpI, 1) < "0" Or Mid$(crpS, crpI, 1) > "9" Then Exit Function
    Next crpI
    crpN = Val(crpS)
    CR_ParseArg% = -1
End Function
