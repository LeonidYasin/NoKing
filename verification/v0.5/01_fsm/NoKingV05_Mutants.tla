------------------------- MODULE NoKingV05_Mutants -------------------------
(*
  Y2 Mutation Testing Suite (12 Mutants) + Replay 6 Liveness for NoKingV05.
  Mandatory 6 NEW v0.5 Mutants (1..6) + 6 Core v0.4 Mutants (7..12):
    1  = M1_DropG1CapCheckInCreate   (allows pool_l2_ok = FALSE in Init -> passive GLOBAL split)
    2  = M2_AllowSamePoolR2          (Appeal allows R2 in same pool r1_pool -> breaks Inv_G2DisjointR2Pool)
    3  = M3_RemoveRKeeperMaxCap      (TimeoutReview pays full ProtocolFee > R_keeper_max -> breaks G3)
    4  = M4_AllowPartyKeeperReward   (TimeoutReview pays keeper bounty to PARTY_A -> breaks G3)
    5  = M5_NoCapacityReservation    (Init/e_create sets cap_reserved = 0 -> breaks Inv_G1CapacityReservedNonTerminal)
    6  = M6_AllowPassiveSplitNoEsc   (TimeoutR1Split direct at esc_level=0 -> breaks F1/G1)
    7  = M7_R2TimeoutSplit5050       (Round 2 timeout splits 50/50 instead of R1_UPHELD)
    8  = M8_LeakTallyRedraw          (RedrawPanel unseals intermediate tally before Q_arb)
    9  = M9_BypassDynamicVMax        (Init bypasses V_liq_max cap with Amount > V_liq_max)
    10 = M10_DefaultOnReviewTimeout  (TimeoutReview blames seller deadline_defaults)
    11 = M11_ZeroVoteBug             (Def 5.2 bug: FOR_A iff 2*nA > PanelSize else FOR_B)
    12 = M12_DropTimeoutsDeadlock    (Removes Dispute timeouts -> deadlock)
*)

EXTENDS NoKingV05

CONSTANT MutantId

\* Mutant 1: remove G1 GLOBAL pool sufficiency check at e_create (V4-02 returns!)
M1_InitNoCapCheck ==
  /\ Amount > 0
  /\ Amount <= V_eff_max
  /\ CapReq > 0
  /\ CapReq <= MaxArbCap
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
  /\ panel_l2_formed = FALSE
  /\ pool_l0_ok \in {TRUE, FALSE}
  /\ pool_l1_ok \in {TRUE, FALSE}
  /\ pool_l2_ok \in {TRUE, FALSE}   \* BUG: allows empty GLOBAL pool!
  /\ cap_reserved = CapReq
  /\ r1_pool = -1
  /\ r2_pool = -1
  /\ r2_pool_disjoint = TRUE
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
  /\ g3_review_keeper_payout = 0
  /\ g3_party_paid_keeper = FALSE
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

\* Mutant 5: do not reserve capacity upon admission
M5_InitNoReserve ==
  /\ Amount > 0
  /\ Amount <= V_eff_max
  /\ CapReq > 0
  /\ CapReq <= MaxArbCap
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
  /\ panel_l2_formed = FALSE
  /\ pool_l0_ok \in {TRUE, FALSE}
  /\ pool_l1_ok \in {TRUE, FALSE}
  /\ pool_l2_ok = TRUE
  /\ cap_reserved = 0   \* BUG: fails to reserve capacity!
  /\ r1_pool = -1
  /\ r2_pool = -1
  /\ r2_pool_disjoint = TRUE
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
  /\ g3_review_keeper_payout = 0
  /\ g3_party_paid_keeper = FALSE
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

\* Mutant 9: bypass dynamic V_liq_max cap (uses Amount = 6000 > V_liq_max = 5000)
M9_InitNoDynamicCap ==
  /\ Amount > 0
  /\ Amount <= V_protocol_max   \* BUG: ignores V_liq_max!
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
  /\ panel_l2_formed = FALSE
  /\ pool_l0_ok \in {TRUE, FALSE}
  /\ pool_l1_ok \in {TRUE, FALSE}
  /\ pool_l2_ok = TRUE
  /\ cap_reserved = CapReq
  /\ r1_pool = -1
  /\ r2_pool = -1
  /\ r2_pool_disjoint = TRUE
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
  /\ g3_review_keeper_payout = 0
  /\ g3_party_paid_keeper = FALSE
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

\* Mutant 2: allow Appeal in the same pool as R1 (V4-09 regression)
M2_AppealSamePool ==
  /\ state = "APPEALABLE"
  /\ round = 1
  /\ t_now < resolve_time + T_appeal
  /\ state' = "DISPUTE"
  /\ round' = 2
  /\ esc_level' = r1_pool
  /\ r2_pool' = r1_pool
  /\ r2_pool_disjoint' = FALSE   \* BUG: allows Round 2 in same captured pool!
  /\ attempt' = 1
  /\ dispute_open_t' = t_now
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
  /\ IF r1_verdict = "FOR_A"
     THEN /\ balB' = balB - AppealDeposit
          /\ balA' = balA
     ELSE /\ balA' = balA - AppealDeposit
          /\ balB' = balB
  /\ escrowAppeal' = AppealDeposit
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, failed_attempts, curr_reward,
               panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, cap_reserved, r1_pool,
               tally_leaked, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowArbR1, escrowArbCurr, escrowArbReward>>

\* Mutant 3: remove R_keeper_max ceiling in TimeoutReview (pays full ProtocolFee > R_keeper_max)
M3_TimeoutReviewUncapped ==
  /\ state = "REVIEW"
  /\ t_now >= submit_time + T_review
  /\ state' = "CLOSED"
  /\ cap_reserved' = 0
  /\ f4_review_fee_to_keeper' = TRUE
  /\ g3_review_keeper_payout' = ProtocolFee   \* BUG: uncapped MEV fee!
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balKeeper' = balKeeper + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, g3_party_paid_keeper,
               balB, balArb, balTreasury, escReserve,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

\* Mutant 4: allow deal party (PARTY_A) to claim keeper reward on own deal (V4-06 kickback!)
M4_TimeoutReviewPartyPaid ==
  /\ state = "REVIEW"
  /\ t_now >= submit_time + T_review
  /\ state' = "CLOSED"
  /\ cap_reserved' = 0
  /\ f4_review_fee_to_keeper' = TRUE
  /\ g3_review_keeper_payout' = KeeperBountyCap
  /\ g3_party_paid_keeper' = TRUE   \* BUG: pays party_a as keeper!
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller + KeeperBountyCap
  /\ balTreasury' = balTreasury + (ProtocolFee - KeeperBountyCap)
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute,
               balB, balArb, balKeeper, escReserve,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

\* Mutant 6: allow passive 50/50 split immediately at esc_level = 0 without escalation chain
M6_PassiveSplitDirect ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ esc_level = 0
  /\ ~panel_formed /\ CurrPoolOk = FALSE
  /\ state' = "RESOLVED"
  /\ verdict' = "SPLIT_50_50"
  /\ cap_reserved' = 0
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               r1_verdict, seller_delivered, buyer_honest, n04_delay_paid, deadline_defaults,
               f4_keeper_paid_dispute, f4_review_fee_to_keeper, g3_review_keeper_payout, g3_party_paid_keeper,
               balArb, balKeeper, escReserve, escrowAppeal, escrowArbR1>>

M7_R2TimeoutSplit5050 ==
  /\ state = "DISPUTE"
  /\ round = 2
  /\ t_now >= dispute_open_t + T_dispute_max
  /\ (~voted \/ verdict = "NO_DECISION")
  /\ state' = "RESOLVED"
  /\ verdict' = "SPLIT_50_50"
  /\ cap_reserved' = 0
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               r1_verdict, seller_delivered, buyer_honest, n04_delay_paid, deadline_defaults,
               f4_keeper_paid_dispute, f4_review_fee_to_keeper, g3_review_keeper_payout, g3_party_paid_keeper,
               balKeeper, balTreasury, escReserve>>

M8_LeakTallyRedraw ==
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
     /\ tally_sealed' = FALSE   \* BUG: leaks intermediate tally!
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
               round, esc_level, panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r1_pool, r2_pool, r2_pool_disjoint,
               r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balB, balKeeper, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1>>

M10_DefaultOnReviewTimeout ==
  /\ state = "REVIEW"
  /\ t_now >= submit_time + T_review
  /\ state' = "CLOSED"
  /\ cap_reserved' = 0
  /\ deadline_defaults' = deadline_defaults + 1  \* BUG: blames seller!
  /\ f4_review_fee_to_keeper' = TRUE
  /\ g3_review_keeper_payout' = KeeperBountyCap
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balKeeper' = balKeeper + KeeperBountyCap
  /\ balTreasury' = balTreasury + (ProtocolFee - KeeperBountyCap)
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, esc_level, failed_attempts, curr_reward, round, attempt,
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, f4_keeper_paid_dispute, g3_party_paid_keeper,
               balB, balArb, escReserve,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

M11_ZeroVoteBug ==
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r1_pool, r2_pool, r2_pool_disjoint, committed, tally_leaked,
               seats_drawn, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

MutantInit ==
  IF MutantId = 1 THEN M1_InitNoCapCheck
  ELSE IF MutantId = 5 THEN M5_InitNoReserve
  ELSE IF MutantId = 9 THEN M9_InitNoDynamicCap
  ELSE Init

MutantNext ==
  \/ Tick
  \/ Accept
  \/ RequestCancelDraft
  \/ ExecuteCancelDraft
  \/ TimeoutDraft
  \/ Start
  \/ TimeoutLocked
  \/ Submit
  \/ TimeoutInProgress
  \/ Confirm
  \/ IF MutantId = 3 THEN M3_TimeoutReviewUncapped
     ELSE IF MutantId = 4 THEN M4_TimeoutReviewPartyPaid
     ELSE IF MutantId = 10 THEN M10_DefaultOnReviewTimeout
     ELSE TimeoutReview
  \/ OpenDispute
  \/ FormPanel
  \/ IF MutantId = 6 THEN M6_PassiveSplitDirect ELSE EscalateLevel
  \/ CommitVotes
  \/ IF MutantId = 11 THEN M11_ZeroVoteBug ELSE RevealVotes
  \/ IF MutantId = 8 THEN M8_LeakTallyRedraw ELSE RedrawPanel
  \/ IF MutantId = 12 THEN FALSE ELSE TimeoutR1Split5050
  \/ IF MutantId = 12 THEN FALSE ELSE (IF MutantId = 7 THEN M7_R2TimeoutSplit5050 ELSE TimeoutR2KeepR1)
  \/ ResolveRound1ToAppealable
  \/ IF MutantId = 2 THEN M2_AppealSamePool ELSE Appeal
  \/ FinalizeAppealable
  \/ ResolveRound2Final
  \/ TerminalStutter

MutantSpec == MutantInit /\ [][MutantNext]_vars /\ WF_vars(MutantNext)

\* Replay 6 Liveness: L0=FALSE, L1=FALSE, while G1 enforces L2=TRUE -> reaches active resolve or active-sabotage split without deadlock
InitLocalPoolsEmpty ==
  /\ Init
  /\ pool_l0_ok = FALSE
  /\ pool_l1_ok = FALSE

SpecLocalPoolsEmpty == InitLocalPoolsEmpty /\ [][Next]_vars /\ WF_vars(Next)

=============================================================================
