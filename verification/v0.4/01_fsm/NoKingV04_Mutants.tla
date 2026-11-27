------------------------- MODULE NoKingV04_Mutants -------------------------
(*
  X0.5 Extended Mutation Testing Suite (12 Mutants) for NoKingV04.
  MutantId:
    1  = M1_DropF1Escalation        (allows R1 50/50 split straight at esc_level=0)
    2  = M2_FlatNonGrowingReward    (escalation bumps failed_attempts without growing curr_reward)
    3  = M3_RestoreD3InRound2       (Round 2 timeout splits 50/50 instead of keeping R1 verdict)
    4  = M4_LeakTallyOnRedraw       (RedrawPanel unseals intermediate tally before Q_arb)
    5  = M5_BypassVMaxInCreate      (Init allows Amount > V_protocol_max; paired with Amount=9000)
    6  = M6_FeeToKeeperInDispute    (Dispute Finalize pays ProtocolFee to Keeper instead of Treasury)
    7  = M7_DefaultOnReviewTimeout  (TimeoutReview buyer inactivity increments seller deadline_defaults)
    8  = M8_RemoveDeadlineInSubmit  (Submit lacks t_now < Deadline guard)
    9  = M9_DoublePayoutInAppealable(ResolveRound1ToAppealable pays out Amount early)
    10 = M10_ZeroVoteWin            (v0.1 Def 5.2 bug: FOR_A iff 2*nA > PanelSize else FOR_B)
    11 = M11_SkipCancelGraceAndDelay(allows instant Cancel in DRAFT from t_now=0)
    12 = M12_DropTimeoutsDeadlock   (removes TimeoutR1Split5050 and TimeoutR2KeepR1)
*)

EXTENDS NoKingV04

CONSTANT MutantId

M5_InitNoVMax ==
  /\ Amount > 0
  /\ state = "DRAFT"
  /\ t_now = 0
  /\ cancel_req_t = -1
  /\ submit_time = -1
  /\ resolve_time = -1
  /\ dispute_open_t = -1
  /\ attempt_open_t = -1
  /\ round = 0
  /\ esc_level = 0
  /\ failed_attempts = 0
  /\ curr_reward = 0
  /\ attempt = 0
  /\ panel_formed = FALSE
  /\ pool_l0_ok \in {TRUE, FALSE}
  /\ pool_l1_ok \in {TRUE, FALSE}
  /\ pool_l2_ok \in {TRUE, FALSE}
  /\ committed = FALSE
  /\ voted = FALSE
  /\ tally_sealed = TRUE
  /\ tally_leaked = FALSE
  /\ votesA = 0
  /\ votesB = 0
  /\ votesUnrevealed = 0
  /\ seats_drawn = 0
  /\ verdict = "NONE"
  /\ r1_verdict = "NONE"
  /\ seller_delivered = FALSE
  /\ buyer_honest \in {TRUE, FALSE}
  /\ payout_count = 0
  /\ n04_delay_paid = FALSE
  /\ deadline_defaults = 0
  /\ f4_keeper_paid_dispute = FALSE
  /\ f4_review_fee_to_keeper = FALSE
  /\ balA = InitSeller - SellerDeposit
  /\ balB = InitBuyer
  /\ balArb = InitArb
  /\ balKeeper = 0
  /\ balTreasury = 0
  /\ escReserve = InitReserve
  /\ escrowBuyer = 0
  /\ escrowSeller = SellerDeposit
  /\ escrowDispute = 0
  /\ escrowAppeal = 0
  /\ escrowArbR1 = 0
  /\ escrowArbCurr = 0
  /\ escrowArbReward = 0

M1_SplitDirect ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ esc_level = 0
  /\ ~panel_formed /\ CurrPoolOk = FALSE
  /\ state' = "RESOLVED"
  /\ verdict' = "SPLIT_50_50"
  /\ resolve_time' = t_now
  /\ payout_count' = payout_count + 1
  /\ balA' = balA + (Amount \div 2) + (escrowSeller - DisputeDeposit)
  /\ balB' = balB + (Amount - (Amount \div 2))
  /\ balTreasury' = balTreasury + DisputeDeposit + escrowDispute + escrowArbReward
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowArbCurr' = 0
  /\ escrowArbReward' = 0
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, dispute_open_t, attempt_open_t,
               esc_level, failed_attempts, curr_reward, round, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               r1_verdict, seller_delivered, buyer_honest, n04_delay_paid, deadline_defaults,
               f4_keeper_paid_dispute, f4_review_fee_to_keeper, balArb, balKeeper, escReserve,
               escrowAppeal, escrowArbR1>>

M2_EscalateFlatReward ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ esc_level < 2
  /\ ( (~panel_formed /\ CurrPoolOk = FALSE /\ t_now < dispute_open_t + T_dispute_max)
       \/ (voted = TRUE /\ verdict = "NO_DECISION" /\ t_now < dispute_open_t + T_dispute_max)
       \/ (t_now >= dispute_open_t + T_dispute_max /\ (~voted \/ verdict = "NO_DECISION")) )
  /\ esc_level' = esc_level + 1
  /\ failed_attempts' = failed_attempts + 1
  /\ curr_reward' = curr_reward  \* Bug: reward fails to grow!
  /\ attempt' = 1
  /\ attempt_open_t' = t_now
  /\ panel_formed' = FALSE
  /\ committed' = FALSE
  /\ voted' = FALSE
  /\ tally_sealed' = TRUE
  /\ votesA' = 0
  /\ votesB' = 0
  /\ votesUnrevealed' = 0
  /\ seats_drawn' = 0
  /\ verdict' = "NONE"
  /\ balArb' = balArb + escrowArbCurr
  /\ escrowArbCurr' = 0
  /\ UNCHANGED <<state, t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t, round,
               pool_l0_ok, pool_l1_ok, pool_l2_ok, tally_leaked, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbR1, escrowArbReward>>

M3_R2TimeoutSplit5050 ==
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
  /\ balArb' = balArb + escrowArbR1 + escrowArbCurr + escrowArbReward
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ escrowArbCurr' = 0
  /\ escrowArbReward' = 0
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, dispute_open_t, attempt_open_t,
               esc_level, failed_attempts, curr_reward, round, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               r1_verdict, seller_delivered, buyer_honest, n04_delay_paid, deadline_defaults,
               f4_keeper_paid_dispute, f4_review_fee_to_keeper, balKeeper, balTreasury, escReserve>>

M4_LeakTallyRedraw ==
  /\ state = "DISPUTE"
  /\ voted = TRUE
  /\ verdict = "NO_DECISION"
  /\ attempt < 2
  /\ t_now + T_commit + T_reveal <= dispute_open_t + T_dispute_max
  /\ LET valid == votesA + votesB
         missing == PanelSize - valid
         fullReset == (valid >= Q_arb /\ votesA = votesB)
         need == IF fullReset THEN PanelSize ELSE missing
         unrevSlash == votesUnrevealed * ArbUnrevPenalty
     IN
     /\ need > 0
     /\ voted' = FALSE
     /\ committed' = FALSE
     /\ tally_sealed' = FALSE \* Bug: unseals partial tally before Q_arb!
     /\ tally_leaked' = TRUE
     /\ attempt' = attempt + 1
     /\ attempt_open_t' = t_now
     /\ verdict' = "NONE"
     /\ seats_drawn' = need
     /\ IF fullReset THEN votesA' = 0 /\ votesB' = 0 ELSE UNCHANGED <<votesA, votesB>>
     /\ votesUnrevealed' = 0
     /\ balTreasury' = balTreasury + unrevSlash
     /\ escrowArbCurr' = escrowArbCurr - unrevSlash + (need * ArbStake)
     /\ balArb' = balArb - (need * ArbStake)
     /\ IF round = 1
        THEN /\ failed_attempts' = failed_attempts + 1
             /\ curr_reward' = curr_reward + EscBonus
             /\ escReserve' = escReserve - EscBonus
             /\ escrowArbReward' = escrowArbReward + EscBonus
        ELSE UNCHANGED <<failed_attempts, curr_reward, escReserve, escrowArbReward>>
  /\ UNCHANGED <<state, t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               round, esc_level, panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balKeeper, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1>>

M6_FinalizeToKeeper ==
  /\ state = "APPEALABLE"
  /\ t_now >= resolve_time + T_appeal
  /\ r1_verdict = "FOR_A"
  /\ state' = "RESOLVED"
  /\ payout_count' = payout_count + 1
  /\ f4_keeper_paid_dispute' = TRUE \* Bug: pays dispute protocol_fee to Keeper!
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balKeeper' = balKeeper + ProtocolFee
  /\ balArb' = balArb + escrowDispute + escrowArbR1
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               esc_level, failed_attempts, curr_reward, round, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, deadline_defaults, f4_review_fee_to_keeper,
               balB, balTreasury, escReserve, escrowArbCurr, escrowArbReward>>

M7_DefaultOnReviewTimeout ==
  /\ state = "REVIEW"
  /\ t_now >= submit_time + T_review
  /\ state' = "CLOSED"
  /\ deadline_defaults' = deadline_defaults + 1 \* Bug: blames seller on buyer review timeout!
  /\ f4_review_fee_to_keeper' = TRUE
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balKeeper' = balKeeper + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, esc_level, failed_attempts, curr_reward, round, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, f4_keeper_paid_dispute,
               balB, balArb, balTreasury, escReserve,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

M8_SubmitNoDeadline ==
  /\ state = "IN_PROGRESS"
  /\ \E deliv \in {TRUE, FALSE} : seller_delivered' = deliv
  /\ state' = "REVIEW"
  /\ submit_time' = t_now
  /\ UNCHANGED <<t_now, cancel_req_t, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

M9_DoublePayoutInAppealable ==
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
  /\ balArb' = balArb + escrowArbCurr + escrowArbReward
  /\ escrowArbCurr' = 0
  /\ escrowArbReward' = 0
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, dispute_open_t, attempt_open_t,
               esc_level, failed_attempts, curr_reward, round, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, seller_delivered, buyer_honest, n04_delay_paid, deadline_defaults,
               f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balB, balKeeper, escReserve, escrowSeller, escrowDispute, escrowAppeal, escrowArbR1>>

M10_RevealZeroVoteBug ==
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
          /\ tally_sealed' = FALSE
  /\ UNCHANGED <<state, t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, tally_leaked,
               seats_drawn, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

M11_InstantCancelNoGrace ==
  /\ state = "DRAFT"
  /\ state' = "EXPIRED"
  /\ balA' = balA + escrowSeller
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

MutantInit == IF MutantId = 5 THEN M5_InitNoVMax ELSE Init

MutantNext ==
  \/ Tick
  \/ Accept
  \/ RequestCancelDraft
  \/ IF MutantId = 11 THEN M11_InstantCancelNoGrace ELSE ExecuteCancelDraft
  \/ TimeoutDraft
  \/ Start
  \/ TimeoutLocked
  \/ IF MutantId = 8 THEN M8_SubmitNoDeadline ELSE Submit
  \/ TimeoutInProgress
  \/ Confirm
  \/ IF MutantId = 7 THEN M7_DefaultOnReviewTimeout ELSE TimeoutReview
  \/ OpenDispute
  \/ FormPanel
  \/ IF MutantId = 1 THEN M1_SplitDirect ELSE (IF MutantId = 2 THEN M2_EscalateFlatReward ELSE EscalateLevel)
  \/ CommitVotes
  \/ IF MutantId = 10 THEN M10_RevealZeroVoteBug ELSE RevealVotes
  \/ IF MutantId = 4 THEN M4_LeakTallyRedraw ELSE RedrawPanel
  \/ IF MutantId = 12 THEN FALSE ELSE TimeoutR1Split5050
  \/ IF MutantId = 12 THEN FALSE ELSE (IF MutantId = 3 THEN M3_R2TimeoutSplit5050 ELSE TimeoutR2KeepR1)
  \/ IF MutantId = 9 THEN M9_DoublePayoutInAppealable ELSE ResolveRound1ToAppealable
  \/ Appeal
  \/ IF MutantId = 6 THEN M6_FinalizeToKeeper ELSE FinalizeAppealable
  \/ ResolveRound2Final
  \/ TerminalStutter

MutantSpec == MutantInit /\ [][MutantNext]_vars /\ WF_vars(MutantNext)

\* Replay 6 helper: all 3 escalation pools empty
InitAllPoolsEmpty ==
  /\ Init
  /\ pool_l0_ok = FALSE
  /\ pool_l1_ok = FALSE
  /\ pool_l2_ok = FALSE

SpecAllPoolsEmpty == InitAllPoolsEmpty /\ [][Next]_vars /\ WF_vars(Next)

=============================================================================
