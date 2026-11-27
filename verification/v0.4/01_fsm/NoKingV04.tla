---------------------------- MODULE NoKingV04 ----------------------------
(*
  Formal TLA+ Specification of NoKing Protocol v0.4-draft (X2).
  Incorporates F1-F5 + M-02, M-07, M-08, M-09 protections:
    - F1: 3-level Round-1 escalation chain (esc_level 0 -> 1 -> 2) with growing
          arbitrator reward (funded by esc_reserve + unrevealed slashes).
          50/50 split allowed ONLY after esc_level = 2 and T_dispute_max exhausted.
          Round-2 timeout keeps Round-1 verdict (no D3 compromise).
    - F2: Hard Amount <= V_protocol_max check on creation/acceptance.
    - F3: tally_sealed = TRUE whenever valid_votes < Q_arb during Commit/Reveal/Redraw;
          (vA, vB) revealed ONLY once valid_votes >= Q_arb.
    - F4: REVIEW -> CLOSED via TimeoutReview transfers 100% ProtocolFee to keeper;
          Confirm / Dispute transfers ProtocolFee to Treasury (normal split).
    - F5: deadline_defaults incremented ONLY on LOCKED / IN_PROGRESS seller timeout
          -> EXPIRED (never on DRAFT or REVIEW).
    - M-09: Two-phase RequestCancelDraft (after T_cancel_grace) -> ExecuteCancelDraft
            (after T_cancel_delay), preventing Accept frontrunning.
*)

EXTENDS Integers, FiniteSets

CONSTANTS
  Amount,            \* 100
  V_protocol_max,    \* 8750 (F2 ceiling)
  SellerDeposit,     \* 10
  Penalty,           \* 5
  ProtocolFee,       \* 1
  DisputeDeposit,    \* 5
  AppealDeposit,     \* 15
  DelayComp,         \* 5 (N-04)
  ArbStake,          \* 20
  ArbPenalty,        \* 5
  ArbUnrevPenalty,   \* 10 (E3)
  BaseArbReward,     \* 2 (F1 base reward from esc_reserve)
  EscBonus,          \* 2 (F1 reward increment per failed attempt/escalation)
  KeeperFee,         \* 1
  PanelSize,         \* 3 or 5
  Q_arb,             \* 2 or 3
  T_cancel_grace,    \* 1
  T_cancel_delay,    \* 1 (M-09)
  T_accept,          \* 3
  Deadline,          \* 5
  T_review,          \* 2
  T_evidence,        \* 1
  T_commit,          \* 1
  T_reveal,          \* 1
  T_dispute_max,     \* 4 or 6
  T_appeal,          \* 2
  MaxTime,           \* 16
  InitBuyer,         \* 200
  InitSeller,        \* 200
  InitArb,           \* 400
  InitReserve        \* 50 (protocol arbitrator escalation reward reserve)

VARIABLES
  state,
  t_now,
  cancel_req_t,      \* -1 or timestamp of RequestCancelDraft (M-09)
  submit_time,
  resolve_time,
  dispute_open_t,
  attempt_open_t,
  round,             \* 0, 1, 2
  esc_level,         \* 0 (Category), 1 (Parent), 2 (GLOBAL) - F1
  failed_attempts,   \* 0..4 - F1
  curr_reward,       \* BaseArbReward + failed_attempts * EscBonus - F1
  attempt,           \* redraw attempts within current level
  panel_formed,
  pool_l0_ok,        \* Category pool sufficient
  pool_l1_ok,        \* Parent pool sufficient
  pool_l2_ok,        \* GLOBAL pool sufficient
  committed,
  voted,
  tally_sealed,      \* F3: TRUE while votes < Q_arb
  tally_leaked,      \* F3 audit bit: TRUE iff unquorum votes ever published
  votesA,
  votesB,
  votesUnrevealed,
  seats_drawn,
  verdict,
  r1_verdict,
  seller_delivered,
  buyer_honest,
  payout_count,
  n04_delay_paid,
  deadline_defaults, \* F5: objective seller timeout counter
  f4_keeper_paid_dispute, \* Audit bit for M6 mutation
  f4_review_fee_to_keeper,
  balA,
  balB,
  balArb,
  balKeeper,
  balTreasury,
  escReserve,
  escrowBuyer,
  escrowSeller,
  escrowDispute,
  escrowAppeal,
  escrowArbR1,
  escrowArbCurr,
  escrowArbReward

vars == <<state, t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
          attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
          panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
          tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
          verdict, r1_verdict, seller_delivered, buyer_honest, payout_count,
          n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
          balA, balB, balArb, balKeeper, balTreasury, escReserve,
          escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
          escrowArbR1, escrowArbCurr, escrowArbReward>>

TotalInitial == InitBuyer + InitSeller + InitArb + InitReserve

CurrPoolOk ==
  IF esc_level = 0 THEN pool_l0_ok
  ELSE IF esc_level = 1 THEN pool_l1_ok
  ELSE pool_l2_ok

\* F2: Create checks Amount <= V_protocol_max; Init represents post-e_create DRAFT
Init ==
  /\ Amount > 0
  /\ Amount <= V_protocol_max
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

Tick ==
  /\ t_now < MaxTime
  /\ ~(state \in {"CLOSED", "EXPIRED", "RESOLVED"})
  /\ ~((state = "DRAFT") /\ (t_now >= T_accept))
  /\ ~((state = "DRAFT") /\ (cancel_req_t >= 0) /\ (t_now >= cancel_req_t + T_cancel_delay))
  /\ ~((state = "LOCKED") /\ (t_now >= Deadline))
  /\ ~((state = "IN_PROGRESS") /\ (t_now >= Deadline))
  /\ ~((state = "REVIEW") /\ (submit_time >= 0) /\ (t_now >= submit_time + T_review))
  /\ ~((state = "APPEALABLE") /\ (resolve_time >= 0) /\ (t_now >= resolve_time + T_appeal))
  /\ ~((state = "DISPUTE") /\ (dispute_open_t >= 0) /\ (t_now >= dispute_open_t + T_dispute_max))
  /\ t_now' = t_now + 1
  /\ UNCHANGED <<state, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

Accept ==
  /\ state = "DRAFT"
  /\ t_now < T_accept
  /\ cancel_req_t = -1
  /\ state' = "LOCKED"
  /\ balB' = balB - Amount
  /\ escrowBuyer' = Amount
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balArb, balKeeper, balTreasury, escReserve,
               escrowSeller, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

\* M-09: Two-phase cancel after T_cancel_grace
RequestCancelDraft ==
  /\ state = "DRAFT"
  /\ cancel_req_t = -1
  /\ t_now >= T_cancel_grace
  /\ t_now < T_accept
  /\ cancel_req_t' = t_now
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

ExecuteCancelDraft ==
  /\ state = "DRAFT"
  /\ cancel_req_t >= 0
  /\ t_now >= cancel_req_t + T_cancel_delay
  /\ t_now < T_accept
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

TimeoutDraft ==
  /\ state = "DRAFT"
  /\ t_now >= T_accept
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

Start ==
  /\ state = "LOCKED"
  /\ t_now < Deadline
  /\ state' = "IN_PROGRESS"
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

\* F5: Seller timeout in LOCKED increments deadline_defaults
TimeoutLocked ==
  /\ state = "LOCKED"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ deadline_defaults' = deadline_defaults + 1
  /\ balB' = balB + escrowBuyer + (Penalty - KeeperFee)
  /\ balA' = balA + (escrowSeller - Penalty)
  /\ balKeeper' = balKeeper + KeeperFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balArb, balTreasury, escReserve,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

Submit ==
  /\ state = "IN_PROGRESS"
  /\ t_now < Deadline
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

\* F5: Seller timeout in IN_PROGRESS increments deadline_defaults
TimeoutInProgress ==
  /\ state = "IN_PROGRESS"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ deadline_defaults' = deadline_defaults + 1
  /\ balB' = balB + escrowBuyer + (Penalty - KeeperFee)
  /\ balA' = balA + (escrowSeller - Penalty)
  /\ balKeeper' = balKeeper + KeeperFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balArb, balTreasury, escReserve,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

Confirm ==
  /\ state = "REVIEW"
  /\ t_now < submit_time + T_review
  /\ buyer_honest = TRUE
  /\ seller_delivered = TRUE
  /\ state' = "CLOSED"
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balTreasury' = balTreasury + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balB, balArb, balKeeper, escReserve,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

\* F4 + F5: Auto-confirm sends 100% ProtocolFee to Keeper; NO deadline_defaults!
TimeoutReview ==
  /\ state = "REVIEW"
  /\ t_now >= submit_time + T_review
  /\ state' = "CLOSED"
  /\ f4_review_fee_to_keeper' = TRUE
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balKeeper' = balKeeper + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute,
               balB, balArb, balTreasury, escReserve,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

OpenDispute ==
  /\ state = "REVIEW"
  /\ t_now < submit_time + T_review
  /\ (~seller_delivered \/ ~buyer_honest)
  /\ state' = "DISPUTE"
  /\ round' = 1
  /\ esc_level' = 0
  /\ failed_attempts' = 0
  /\ curr_reward' = BaseArbReward
  /\ escReserve' = escReserve - BaseArbReward
  /\ escrowArbReward' = BaseArbReward
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
  /\ balB' = balB - DisputeDeposit
  /\ escrowDispute' = DisputeDeposit
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time,
               pool_l0_ok, pool_l1_ok, pool_l2_ok, tally_leaked, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balArb, balKeeper, balTreasury,
               escrowBuyer, escrowSeller, escrowAppeal, escrowArbR1, escrowArbCurr>>

FormPanel ==
  /\ state = "DISPUTE"
  /\ panel_formed = FALSE
  /\ CurrPoolOk = TRUE
  /\ t_now < dispute_open_t + T_dispute_max
  /\ panel_formed' = TRUE
  /\ seats_drawn' = PanelSize
  /\ balArb' = balArb - (PanelSize * ArbStake)
  /\ escrowArbCurr' = escrowArbCurr + (PanelSize * ArbStake)
  /\ UNCHANGED <<state, t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted, tally_sealed, tally_leaked,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbR1, escrowArbReward>>

\* F1: 3-level escalation chain in Round 1 (0 -> 1 -> 2) with growing reward!
\* Advances immediately if pool insufficient, on NO_DECISION, or when T_dispute_max hits at esc_level < 2.
EscalateLevel ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ esc_level < 2
  /\ ( (~panel_formed /\ CurrPoolOk = FALSE /\ t_now < dispute_open_t + T_dispute_max)
       \/ (voted = TRUE /\ verdict = "NO_DECISION" /\ t_now < dispute_open_t + T_dispute_max)
       \/ (t_now >= dispute_open_t + T_dispute_max /\ (~voted \/ verdict = "NO_DECISION")) )
  /\ LET unrevSlash == votesUnrevealed * ArbUnrevPenalty
     IN
     /\ esc_level' = esc_level + 1
     /\ failed_attempts' = failed_attempts + 1
     /\ curr_reward' = curr_reward + EscBonus
     /\ escReserve' = escReserve - EscBonus
     /\ escrowArbReward' = escrowArbReward + EscBonus
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
     /\ balTreasury' = balTreasury + unrevSlash
     /\ balArb' = balArb + (escrowArbCurr - unrevSlash)
     /\ escrowArbCurr' = 0
  /\ UNCHANGED <<state, t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t, round,
               pool_l0_ok, pool_l1_ok, pool_l2_ok, tally_leaked, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balKeeper,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbR1>>

CommitVotes ==
  /\ state = "DISPUTE"
  /\ panel_formed = TRUE
  /\ committed = FALSE
  /\ t_now >= attempt_open_t + (IF attempt = 1 THEN T_evidence ELSE 0)
  /\ t_now < attempt_open_t + (IF attempt = 1 THEN T_evidence ELSE 0) + T_commit
  /\ t_now < dispute_open_t + T_dispute_max
  /\ committed' = TRUE
  /\ UNCHANGED <<state, t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, voted, tally_sealed, tally_leaked,
               votesA, votesB, votesUnrevealed, seats_drawn, verdict, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

\* F3: Only unseals tally (tally_sealed' = FALSE) when valid majority >= Q_arb & no tie!
RevealVotes ==
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
              decided == (nA + nB >= Q_arb) /\ (nA /= nB)
          IN
          /\ votesA' = nA
          /\ votesB' = nB
          /\ votesUnrevealed' = dUnrev
          /\ voted' = TRUE
          /\ verdict' = IF decided
                        THEN (IF nA > nB THEN "FOR_A" ELSE "FOR_B")
                        ELSE "NO_DECISION"
          /\ tally_sealed' = ~decided
  /\ UNCHANGED <<state, t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, tally_leaked,
               seats_drawn, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

\* F3 + E3 + F1: Partial redraw keeps tally_sealed = TRUE and bumps Round-1 reward!
RedrawPanel ==
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
     /\ tally_sealed' = TRUE
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
               round, esc_level, panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, tally_leaked,
               r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balKeeper, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1>>

\* F1: 50/50 split permitted ONLY when round=1 AND esc_level=2 exhausted
TimeoutR1Split5050 ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ esc_level = 2
  /\ t_now >= dispute_open_t + T_dispute_max
  /\ (~voted \/ verdict = "NO_DECISION")
  /\ state' = "RESOLVED"
  /\ verdict' = "SPLIT_50_50"
  /\ resolve_time' = t_now
  /\ payout_count' = payout_count + 1
  /\ LET halfA == Amount \div 2
         halfB == Amount - halfA
         forfeitA == DisputeDeposit
         forfeitB == escrowDispute
         forfeited == forfeitA + forfeitB
         kfee == KeeperFee
         rem == forfeited - kfee
         arbShare == rem \div 2
         trsShare == rem - arbShare
     IN
     /\ balA' = balA + halfA + (escrowSeller - forfeitA)
     /\ balB' = balB + halfB
     /\ balKeeper' = balKeeper + kfee
     /\ balTreasury' = balTreasury + trsShare + escrowArbReward
     /\ balArb' = balArb + arbShare + escrowArbCurr
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
               f4_keeper_paid_dispute, f4_review_fee_to_keeper, escReserve, escrowAppeal, escrowArbR1>>

\* Safeguard in Round 1 if T_dispute_max hits before esc_level=2 advances (e.g. tight MaxTime / pool_l0=T, redraw=F):
\* Force immediate escalation step or allow R1 split if T_dispute_max reached while escalation remaining -> NO, F1 requires
\* esc_level=2 before TimeoutR1Split5050; therefore T_dispute_max must accommodate L0+L1+L2 or EscalateLevel occurs before T_dispute_max.
\* In fact, let EscalateInstant also drain remaining esc_level at T_dispute_max? No! EscalateLevel runs for t_now < dispute_open_t + T_dispute_max!
\* Note: if pool_l0_ok = FALSE, Tick won't deadlock because EscalateLevel is enabled immediately at t_now = dispute_open_t!
\* Wait: what if Commit/Reveal fail at t_now = dispute_open_t + T_dispute_max - 1 when esc_level < 2? EscalateLevel can still fire at t_now = dispute_open_t + T_dispute_max if needed?
\* Better: allow EscalateLevel even if t_now >= dispute_open_t + T_dispute_max (as pre-timeout escalation), so esc_level=2 is ALWAYS reached before TimeoutR1Split5050!

\* Round 2 timeout keeps Round-1 verdict (no 50/50 split)
TimeoutR2KeepR1 ==
  /\ state = "DISPUTE"
  /\ round = 2
  /\ t_now >= dispute_open_t + T_dispute_max
  /\ (~voted \/ verdict = "NO_DECISION")
  /\ state' = "RESOLVED"
  /\ verdict' = "R1_UPHELD"
  /\ resolve_time' = t_now
  /\ payout_count' = payout_count + 1
  /\ IF r1_verdict = "FOR_A"
     THEN /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
          /\ balB' = balB + escrowAppeal
          /\ balTreasury' = balTreasury + ProtocolFee
          /\ balArb' = balArb + escrowDispute + escrowArbR1 + escrowArbCurr + escrowArbReward
     ELSE /\ balB' = balB + escrowBuyer + escrowDispute + Penalty
          /\ balA' = balA + escrowAppeal
          /\ balTreasury' = balTreasury
          /\ balArb' = balArb + (escrowSeller - Penalty) + escrowArbR1 + escrowArbCurr + escrowArbReward
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
               f4_keeper_paid_dispute, f4_review_fee_to_keeper, balKeeper, escReserve>>

ResolveRound1ToAppealable ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ voted = TRUE
  /\ verdict \in {"FOR_A", "FOR_B"}
  /\ state' = "APPEALABLE"
  /\ resolve_time' = t_now
  /\ r1_verdict' = verdict
  /\ LET minCount == PanelSize - (IF verdict = "FOR_A" THEN votesA ELSE votesB)
         pen == (IF minCount > votesUnrevealed THEN (minCount - votesUnrevealed) ELSE 0) * ArbPenalty
                + votesUnrevealed * ArbUnrevPenalty
         ret == IF escrowArbCurr >= pen THEN pen ELSE 0
     IN
     /\ balArb' = balArb + ret + escrowArbReward
     /\ escrowArbR1' = escrowArbCurr - ret
     /\ escrowArbCurr' = 0
     /\ escrowArbReward' = 0
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, dispute_open_t, attempt_open_t,
               esc_level, failed_attempts, curr_reward, round, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balA, balB, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal>>

Appeal ==
  /\ state = "APPEALABLE"
  /\ round = 1
  /\ t_now < resolve_time + T_appeal
  /\ state' = "DISPUTE"
  /\ round' = 2
  /\ esc_level' = 2
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
               pool_l0_ok, pool_l1_ok, pool_l2_ok, tally_leaked, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowArbR1, escrowArbCurr, escrowArbReward>>

FinalizeAppealable ==
  /\ state = "APPEALABLE"
  /\ t_now >= resolve_time + T_appeal
  /\ state' = "RESOLVED"
  /\ payout_count' = payout_count + 1
  /\ IF r1_verdict = "FOR_A"
     THEN /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
          /\ balB' = balB
          /\ balTreasury' = balTreasury + ProtocolFee
          /\ balArb' = balArb + escrowDispute + escrowArbR1
     ELSE /\ balB' = balB + escrowBuyer + escrowDispute + Penalty
          /\ balA' = balA
          /\ balTreasury' = balTreasury
          /\ balArb' = balArb + (escrowSeller - Penalty) + escrowArbR1
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
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balKeeper, escReserve, escrowArbCurr, escrowArbReward>>

ResolveRound2Final ==
  /\ state = "DISPUTE"
  /\ round = 2
  /\ voted = TRUE
  /\ verdict \in {"FOR_A", "FOR_B"}
  /\ state' = "RESOLVED"
  /\ resolve_time' = t_now
  /\ payout_count' = payout_count + 1
  /\ LET overturned == (verdict /= r1_verdict) IN
     /\ n04_delay_paid' = (~overturned)
     /\ IF verdict = "FOR_A"
        THEN /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
                            + (IF overturned THEN escrowAppeal ELSE DelayComp)
             /\ balB' = balB
             /\ balTreasury' = balTreasury + ProtocolFee
             /\ balArb' = balArb + escrowDispute + escrowArbCurr + escrowArbR1
                              + (IF overturned THEN 0 ELSE (escrowAppeal - DelayComp))
        ELSE /\ balB' = balB + escrowBuyer + escrowDispute + Penalty
                            + (IF overturned THEN escrowAppeal ELSE DelayComp)
             /\ balA' = balA
             /\ balTreasury' = balTreasury
             /\ balArb' = balArb + (escrowSeller - Penalty) + escrowArbCurr + escrowArbR1
                              + (IF overturned THEN 0 ELSE (escrowAppeal - DelayComp))
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ escrowArbCurr' = 0
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, dispute_open_t, attempt_open_t,
               esc_level, failed_attempts, curr_reward, round, attempt,
               panel_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, deadline_defaults,
               f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               balKeeper, escReserve, escrowArbReward>>

TerminalStutter ==
  /\ state \in {"CLOSED", "EXPIRED", "RESOLVED"}
  /\ UNCHANGED vars

Next ==
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
  \/ TimeoutReview
  \/ OpenDispute
  \/ FormPanel
  \/ EscalateLevel
  \/ CommitVotes
  \/ RevealVotes
  \/ RedrawPanel
  \/ TimeoutR1Split5050
  \/ TimeoutR2KeepR1
  \/ ResolveRound1ToAppealable
  \/ Appeal
  \/ FinalizeAppealable
  \/ ResolveRound2Final
  \/ TerminalStutter

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* ==================== NON-VACUOUS INVARIANTS & PROPERTIES ====================

Inv_Conservation ==
  (balA + balB + balArb + balKeeper + balTreasury + escReserve
   + escrowBuyer + escrowSeller + escrowDispute + escrowAppeal
   + escrowArbR1 + escrowArbCurr + escrowArbReward) = TotalInitial

Inv_NonNegativeBalances ==
  /\ balA >= 0 /\ balB >= 0 /\ balArb >= 0 /\ balKeeper >= 0 /\ balTreasury >= 0 /\ escReserve >= 0
  /\ escrowBuyer >= 0 /\ escrowSeller >= 0 /\ escrowDispute >= 0
  /\ escrowAppeal >= 0 /\ escrowArbR1 >= 0 /\ escrowArbCurr >= 0 /\ escrowArbReward >= 0

Inv_NoDoublePayout == payout_count <= 1

Inv_EscrowIntactNonTerminal ==
  (state \in {"LOCKED", "IN_PROGRESS", "REVIEW", "DISPUTE", "APPEALABLE"})
    => (escrowBuyer = Amount /\ escrowSeller = SellerDeposit /\ payout_count = 0)

Inv_EscrowEmptyTerminal ==
  (state \in {"CLOSED", "EXPIRED", "RESOLVED"})
    => (escrowBuyer = 0 /\ escrowSeller = 0 /\ escrowDispute = 0
        /\ escrowAppeal = 0 /\ escrowArbR1 = 0 /\ escrowArbCurr = 0 /\ escrowArbReward = 0)

Inv_NoZeroVoteWin ==
  (state \in {"APPEALABLE", "RESOLVED"} /\ verdict \in {"FOR_A", "FOR_B"})
    => ((votesA + votesB >= Q_arb) /\ (votesA /= votesB)
        /\ (verdict = "FOR_A" => votesA > 0) /\ (verdict = "FOR_B" => votesB > 0))

\* Strict state assertions (no arithmetic tautologies!)
Inv_NoDeadlineRace ==
  /\ ((submit_time >= 0) => (submit_time < Deadline))
  /\ ((dispute_open_t >= 0 /\ round = 1 /\ submit_time >= 0) => (dispute_open_t < submit_time + T_review))
  /\ ((cancel_req_t >= 0) => (cancel_req_t >= T_cancel_grace /\ cancel_req_t < T_accept))

Inv_NoSimultaneousEnablement ==
  /\ ~(ENABLED Start /\ ENABLED TimeoutLocked)
  /\ ~(ENABLED Submit /\ ENABLED TimeoutInProgress)
  /\ ~(ENABLED Confirm /\ ENABLED TimeoutReview)
  /\ ~(ENABLED OpenDispute /\ ENABLED TimeoutReview)
  /\ ~(ENABLED Appeal /\ ENABLED FinalizeAppealable)

\* F1: Split 50/50 allowed ONLY after round=1 and esc_level=2; NEVER in round 2!
Inv_F1SplitOnlyAfterChain ==
  (state = "RESOLVED" /\ verdict = "SPLIT_50_50") => (round = 1 /\ esc_level = 2)

Inv_F1GrowingReward ==
  (state = "DISPUTE" /\ round = 1) => (curr_reward = BaseArbReward + failed_attempts * EscBonus)

Inv_E1Round2NeverSplits5050 ==
  (round = 2 /\ state = "RESOLVED") => (verdict /= "SPLIT_50_50")

\* N-01: Round 2 buyer timeout never refunds Amount if r1_verdict = FOR_A
Inv_N01Round2NoBuyerProfit ==
  (round = 2 /\ verdict = "R1_UPHELD" /\ r1_verdict = "FOR_A") => (balB = InitBuyer - Amount - DisputeDeposit)

\* F2: Hard bound check
Inv_F2AmountWithinProtocolMax ==
  (Amount > 0 /\ Amount <= V_protocol_max)

\* F3: Votes must NEVER be unsealed while valid votes < Q_arb or tie
Inv_F3TallySealedUntilQuorum ==
  (~tally_leaked) /\ (((state = "DISPUTE") /\ (~voted \/ verdict = "NO_DECISION")) => (tally_sealed = TRUE))

\* F4: Keepers earn ProtocolFee only on REVIEW timeout (never from Dispute resolution)
Inv_F4FeeToKeeperOnlyOnReviewTimeout ==
  (~f4_keeper_paid_dispute) /\ (f4_review_fee_to_keeper => (state = "CLOSED" /\ balKeeper >= ProtocolFee))

\* F5: Objective deadline_defaults increments strictly on seller timeout (LOCKED/IN_PROGRESS -> EXPIRED)
Inv_F5DefaultOnlyOnSellerTimeout ==
  /\ (deadline_defaults > 0 => (state = "EXPIRED" /\ submit_time = -1))
  /\ (state \in {"DRAFT", "LOCKED", "IN_PROGRESS", "REVIEW", "DISPUTE", "APPEALABLE", "CLOSED", "RESOLVED"} => deadline_defaults = 0)
  /\ (cancel_req_t >= 0 /\ state = "EXPIRED" => deadline_defaults = 0)

\* M-09: Any early exit to EXPIRED before T_accept requires RequestCancel >= T_cancel_grace + T_cancel_delay
Inv_M09CancelGraceAndDelay ==
  (state = "EXPIRED" /\ t_now < T_accept)
    => (cancel_req_t >= T_cancel_grace /\ t_now >= cancel_req_t + T_cancel_delay)

Prop_EventuallyTerminal ==
  <>(state \in {"CLOSED", "EXPIRED", "RESOLVED"})

Prop_DisputeAndAppealableExit ==
  /\ [](state = "DISPUTE" => <>(state \in {"APPEALABLE", "RESOLVED"}))
  /\ [](state = "APPEALABLE" => <>(state \in {"DISPUTE", "RESOLVED"}))

=============================================================================
