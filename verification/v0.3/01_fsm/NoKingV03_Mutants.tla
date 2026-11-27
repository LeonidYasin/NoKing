------------------------- MODULE NoKingV03_Mutants -------------------------
(*
  W0.4 Mutation Testing Harness for NoKingV03.
  MutantId:
    1 = M1_RemoveDeadlineGuard (allows Submit at t_now >= Deadline)
    2 = M2_DoublePayoutInAppealable (pays out Amount early in APPEALABLE)
    3 = M3_RestoreZeroVoteWin (v0.1 Def 5.2 majority bug: FOR_A iff va*2 > PanelSize else FOR_B)
    4 = M4_DropE1Timeout (removes TimeoutR1Split5050 and TimeoutR2KeepR1 -> Liveness deadlock)
    5 = M5_BurnUSDCOnForB (loses 1 USDC in FinalizeAppealable FOR_B -> Conservation fails)
    6 = M6_R2FallsBackTo5050 (allows Round 2 timeout to split 50/50 -> E1 violated)
*)

EXTENDS NoKingV03

CONSTANT MutantId

M1_Submit ==
  /\ state = "IN_PROGRESS"
  /\ \E deliv \in {TRUE, FALSE} : seller_delivered' = deliv
  /\ state' = "REVIEW"
  /\ submit_time' = t_now
  /\ UNCHANGED <<t_now, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, balArb, balTreasury, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

M2_ResolveR1 ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ voted = TRUE
  /\ verdict = "FOR_A"
  /\ state' = "APPEALABLE"
  /\ resolve_time' = t_now
  /\ r1_verdict' = verdict
  /\ balA' = balA + (escrowBuyer - ProtocolFee)
  /\ escrowBuyer' = 0
  /\ balTreasury' = balTreasury + ProtocolFee
  /\ payout_count' = payout_count + 1
  /\ balArb' = balArb + escrowArbCurr
  /\ escrowArbCurr' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, seller_delivered, buyer_honest, n04_delay_paid,
               balB, escrowSeller, escrowDispute, escrowAppeal, escrowArbR1>>

M3_Reveal ==
  /\ state = "DISPUTE"
  /\ panel_formed = TRUE
  /\ committed = TRUE
  /\ voted = FALSE
  /\ t_now >= attempt_open_t + (IF attempt = 1 THEN T_evidence ELSE 0) + T_commit
  /\ t_now < attempt_open_t + (IF attempt = 1 THEN T_evidence ELSE 0) + T_commit + T_reveal
  /\ t_now < dispute_open_t + T_dispute_max
  /\ \E dA, dB, dUnrev \in 0..seats_drawn :
       /\ dA + dB + dUnrev = seats_drawn
       /\ LET nA == votesA + dA
              nB == votesB + dB
          IN
          /\ votesA' = nA
          /\ votesB' = nB
          /\ votesUnrevealed' = dUnrev
          /\ voted' = TRUE
          /\ verdict' = IF (nA * 2 > PanelSize) THEN "FOR_A" ELSE "FOR_B"
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, seats_drawn, r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, balArb, balTreasury, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

M5_Finalize ==
  /\ state = "APPEALABLE"
  /\ t_now >= resolve_time + T_appeal
  /\ state' = "RESOLVED"
  /\ payout_count' = payout_count + 1
  /\ IF r1_verdict = "FOR_A"
     THEN /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
          /\ balB' = balB
          /\ balTreasury' = balTreasury + ProtocolFee
          /\ balArb' = balArb + escrowDispute + escrowArbR1
     ELSE \* Bug: loses 1 unit of escrowSeller ("burned USDC")
          /\ balB' = balB + escrowBuyer + escrowDispute + Penalty
          /\ balA' = balA
          /\ balTreasury' = balTreasury
          /\ balArb' = balArb + (escrowSeller - Penalty - 1) + escrowArbR1
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, n04_delay_paid, escrowArbCurr>>

M6_TimeoutR2Split ==
  /\ state = "DISPUTE"
  /\ round = 2
  /\ t_now >= dispute_open_t + T_dispute_max
  /\ (~voted \/ verdict = "NO_DECISION")
  /\ state' = "RESOLVED"
  /\ verdict' = "SPLIT_50_50"
  /\ resolve_time' = t_now
  /\ payout_count' = payout_count + 1
  /\ balA' = balA + (Amount \div 2) + escrowSeller
  /\ balB' = balB + (Amount - (Amount \div 2)) + escrowDispute + escrowAppeal
  /\ balArb' = balArb + escrowArbR1 + escrowArbCurr
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ escrowArbCurr' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               r1_verdict, seller_delivered, buyer_honest, n04_delay_paid, balTreasury>>

MutantNext ==
  \/ Tick
  \/ Accept
  \/ CancelDraftByA
  \/ TimeoutDraft
  \/ Start
  \/ TimeoutLocked
  \/ (IF MutantId = 1 THEN M1_Submit ELSE Submit)
  \/ TimeoutInProgress
  \/ Confirm
  \/ TimeoutReview
  \/ OpenDispute
  \/ FormPanel
  \/ EscalateToParent
  \/ CommitVotes
  \/ (IF MutantId = 3 THEN M3_Reveal ELSE RevealVotes)
  \/ RedrawPanel
  \/ (IF MutantId = 4 THEN FALSE ELSE TimeoutR1Split5050)
  \/ (IF MutantId = 4 THEN FALSE ELSE IF MutantId = 6 THEN M6_TimeoutR2Split ELSE TimeoutR2KeepR1)
  \/ (IF MutantId = 2 THEN M2_ResolveR1 ELSE ResolveRound1ToAppealable)
  \/ Appeal
  \/ (IF MutantId = 5 THEN M5_Finalize ELSE FinalizeAppealable)
  \/ ResolveRound2Final
  \/ TerminalStutter

MutantSpec == Init /\ [][MutantNext]_vars /\ WF_vars(MutantNext)

\* Witness for Replay 6 small pool (both category and parent fail)
InitAllPoolsEmpty == Init /\ pool_sufficient = FALSE /\ parent_pool_ok = FALSE
SpecAllPoolsEmpty == InitAllPoolsEmpty /\ [][Next]_vars /\ WF_vars(Next)

=============================================================================
