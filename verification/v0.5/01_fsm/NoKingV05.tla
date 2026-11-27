---------------------------- MODULE NoKingV05 ----------------------------
(*
  Formal TLA+ Specification of NoKing Protocol v0.5-draft (Y2).
  Feature-freeze over v0.4 implementing strictly Decisions G1-G3 + retained F1-F5/M-09:
    - G1: Pool capacity admission & reservation at e_create (Init models admitted DRAFT):
          * GLOBAL chain pool capacity guarantees pool_l2_ok = TRUE at admission and
            reserves CapReserved = (2*PanelSize - 1?) -> modeled explicitly as CapReq <= MaxArbCap.
          * CapReserved held until terminal state (CLOSED / EXPIRED / RESOLVED), then released.
          * Last-resort F1 50/50 split unchanged (#15a), but passive GLOBAL exhaustion split
            is unreachable by construction (Inv_G1NoPassiveExhaustionSplit): TimeoutR1Split5050
            can occur ONLY after panel_l2_formed = TRUE (active quorum sabotage).
    - G2: (a) Round 2 Appeal unconditionally uses a pool DISJOINT from Round-1 resolving pool
              (r2_pool_disjoint = TRUE), regardless of OVERSAMPLE.
          (b) Dynamic ceiling V_eff_max = Min(V_protocol_max, V_liq_max), Amount <= V_eff_max.
    - G3: Auto-confirm REVIEW timeout keeper payout capped at Min(R_keeper_max, ProtocolFee),
          with excess (ProtocolFee - Min(...)) routed to balTreasury;
          party_a and party_b excluded from receiving keeper bounty (keeper_payout = 0 -> Treasury).
    - F3 (FSM rule): tally_sealed = TRUE while valid_votes < Q_arb (EVM privacy in §9 IR-01).
*)

EXTENDS Integers, FiniteSets

CONSTANTS
  Amount,            \* 100
  V_protocol_max,    \* 8750 (static 8.75 * S_arb_max ceiling)
  V_liq_max,         \* 5000 (dynamic pool-liquidity ceiling per G2(b))
  SellerDeposit,     \* 10
  Penalty,           \* 5
  ProtocolFee,       \* 5  (> R_keeper_max to exercise G3 split to Treasury!)
  R_keeper_max,      \* 2  (G3 keeper bounty cap)
  DisputeDeposit,    \* 5
  AppealDeposit,     \* 15
  DelayComp,         \* 5
  ArbStake,          \* 20
  ArbPenalty,        \* 5
  ArbUnrevPenalty,   \* 10
  BaseArbReward,     \* 2
  EscBonus,          \* 2
  KeeperFee,         \* 1
  PanelSize,         \* 3 or 5
  Q_arb,             \* 2 or 3
  CapReq,            \* e.g. 80 (G1 capacity reservation held for R1+R2)
  MaxArbCap,         \* e.g. 400 (available pool capacity)
  T_cancel_grace,    \* 1
  T_cancel_delay,    \* 1
  T_accept,          \* 3
  Deadline,          \* 5
  T_review,          \* 2
  T_evidence,        \* 1
  T_commit,          \* 1
  T_reveal,          \* 1
  T_dispute_max,     \* 4 or 3
  T_appeal,          \* 2
  MaxTime,           \* 16 or 15
  InitBuyer,         \* 200
  InitSeller,        \* 200
  InitArb,           \* 400
  InitReserve        \* 50

Min(a, b) == IF a < b THEN a ELSE b
V_eff_max == Min(V_protocol_max, V_liq_max)
KeeperBountyCap == Min(R_keeper_max, ProtocolFee)

VARIABLES
  state,
  t_now,
  cancel_req_t,
  submit_time,
  resolve_time,
  dispute_open_t,
  attempt_open_t,
  round,
  esc_level,         \* 0 = Category, 1 = Parent, 2 = GLOBAL
  failed_attempts,
  curr_reward,
  attempt,
  panel_formed,
  panel_l2_formed,   \* G1 audit: TRUE if a GLOBAL panel was formed in current R1 dispute
  pool_l0_ok,        \* Local category may be sufficient or insufficient
  pool_l1_ok,        \* Parent may be sufficient or insufficient
  pool_l2_ok,        \* G1 admission guarantees GLOBAL pool has sufficient capacity
  cap_reserved,      \* G1: CapReq while non-terminal, 0 when CLOSED/EXPIRED/RESOLVED
  r1_pool,           \* G2(a): resolving pool id for Round 1 (-1, 0, 1, 2)
  r2_pool,           \* G2(a): disjoint pool id for Round 2 (-1 or >= 1)
  r2_pool_disjoint,  \* G2(a): TRUE iff Round 2 uses disjoint pool/set from Round 1
  committed,
  voted,
  tally_sealed,
  tally_leaked,
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
  deadline_defaults,
  f4_keeper_paid_dispute,
  f4_review_fee_to_keeper,
  g3_review_keeper_payout,
  g3_party_paid_keeper,
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
          panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
          cap_reserved, r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
          tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
          verdict, r1_verdict, seller_delivered, buyer_honest, payout_count,
          n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
          g3_review_keeper_payout, g3_party_paid_keeper,
          balA, balB, balArb, balKeeper, balTreasury, escReserve,
          escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
          escrowArbR1, escrowArbCurr, escrowArbReward>>

TotalInitial == InitBuyer + InitSeller + InitArb + InitReserve

CurrPoolOk ==
  IF esc_level = 0 THEN pool_l0_ok
  ELSE IF esc_level = 1 THEN pool_l1_ok
  ELSE pool_l2_ok

\* G1 + G2: Admitted post-e_create DRAFT requires Amount <= Min(V_protocol_max, V_liq_max) and GLOBAL pool capacity
Init ==
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
  /\ pool_l2_ok = TRUE        \* G1 capacity admission guarantees GLOBAL chain sufficiency
  /\ cap_reserved = CapReq   \* G1 reserves worst-case capacity at e_create
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balArb, balKeeper, balTreasury, escReserve,
               escrowSeller, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

RequestCancelDraft ==
  /\ state = "DRAFT"
  /\ cancel_req_t = -1
  /\ t_now >= T_cancel_grace
  /\ t_now < T_accept
  /\ cancel_req_t' = t_now
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

ExecuteCancelDraft ==
  /\ state = "DRAFT"
  /\ cancel_req_t >= 0
  /\ t_now >= cancel_req_t + T_cancel_delay
  /\ t_now < T_accept
  /\ state' = "EXPIRED"
  /\ cap_reserved' = 0
  /\ balA' = balA + escrowSeller
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

TimeoutDraft ==
  /\ state = "DRAFT"
  /\ t_now >= T_accept
  /\ state' = "EXPIRED"
  /\ cap_reserved' = 0
  /\ balA' = balA + escrowSeller
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

Start ==
  /\ state = "LOCKED"
  /\ t_now < Deadline
  /\ state' = "IN_PROGRESS"
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

TimeoutLocked ==
  /\ state = "LOCKED"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ cap_reserved' = 0
  /\ deadline_defaults' = deadline_defaults + 1
  /\ balB' = balB + escrowBuyer + (Penalty - KeeperFee)
  /\ balA' = balA + (escrowSeller - Penalty)
  /\ balKeeper' = balKeeper + KeeperFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

TimeoutInProgress ==
  /\ state = "IN_PROGRESS"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ cap_reserved' = 0
  /\ deadline_defaults' = deadline_defaults + 1
  /\ balB' = balB + escrowBuyer + (Penalty - KeeperFee)
  /\ balA' = balA + (escrowSeller - Penalty)
  /\ balKeeper' = balKeeper + KeeperFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balArb, balTreasury, escReserve,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

Confirm ==
  /\ state = "REVIEW"
  /\ t_now < submit_time + T_review
  /\ buyer_honest = TRUE
  /\ seller_delivered = TRUE
  /\ state' = "CLOSED"
  /\ cap_reserved' = 0
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balTreasury' = balTreasury + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balB, balArb, balKeeper, escReserve,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr, escrowArbReward>>

\* G3 + F4 + F5: Keeper bounty capped at Min(R_keeper_max, ProtocolFee), excess -> Treasury;
\* if caller is party_a or party_b, keeper receives 0 and 100% ProtocolFee -> Treasury.
TimeoutReview ==
  /\ state = "REVIEW"
  /\ t_now >= submit_time + T_review
  /\ \E caller \in {"KEEPER", "PARTY_A", "PARTY_B"} :
       LET kpay == IF caller = "KEEPER" THEN KeeperBountyCap ELSE 0
           tpay == ProtocolFee - kpay
       IN
       /\ state' = "CLOSED"
       /\ cap_reserved' = 0
       /\ f4_review_fee_to_keeper' = (caller = "KEEPER")
       /\ g3_review_keeper_payout' = kpay
       /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
       /\ balKeeper' = balKeeper + kpay
       /\ balTreasury' = balTreasury + tpay
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
               balB, balArb, escReserve,
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
  /\ panel_l2_formed' = FALSE
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
               pool_l0_ok, pool_l1_ok, pool_l2_ok, cap_reserved, r1_pool, r2_pool, r2_pool_disjoint,
               tally_leaked, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balArb, balKeeper, balTreasury,
               escrowBuyer, escrowSeller, escrowAppeal, escrowArbR1, escrowArbCurr>>

FormPanel ==
  /\ state = "DISPUTE"
  /\ panel_formed = FALSE
  /\ CurrPoolOk = TRUE
  /\ t_now < dispute_open_t + T_dispute_max
  /\ panel_formed' = TRUE
  /\ panel_l2_formed' = IF (round = 1 /\ esc_level = 2) THEN TRUE ELSE panel_l2_formed
  /\ seats_drawn' = PanelSize
  /\ balArb' = balArb - (PanelSize * ArbStake)
  /\ escrowArbCurr' = escrowArbCurr + (PanelSize * ArbStake)
  /\ UNCHANGED <<state, t_now, cancel_req_t, submit_time, resolve_time, dispute_open_t,
               attempt_open_t, round, esc_level, failed_attempts, curr_reward, attempt,
               pool_l0_ok, pool_l1_ok, pool_l2_ok, cap_reserved, r1_pool, r2_pool, r2_pool_disjoint,
               committed, voted, tally_sealed, tally_leaked,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balB, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbR1, escrowArbReward>>

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
               panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok, cap_reserved, r1_pool, r2_pool, r2_pool_disjoint,
               tally_leaked, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r1_pool, r2_pool, r2_pool_disjoint, voted, tally_sealed, tally_leaked,
               votesA, votesB, votesUnrevealed, seats_drawn, verdict, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r1_pool, r2_pool, r2_pool_disjoint, committed, tally_leaked,
               seats_drawn, r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbR1, escrowArbCurr, escrowArbReward>>

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
               round, esc_level, panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r1_pool, r2_pool, r2_pool_disjoint, tally_leaked,
               r1_verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balB, balKeeper, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1>>

\* F1 + G1: Split 50/50 allowed ONLY after round=1, esc_level=2 AND active sabotage (or timeout after panel formed);
\* Under G1, pool_l2_ok=TRUE so GLOBAL never fails to form panel passively.
TimeoutR1Split5050 ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ esc_level = 2
  /\ t_now >= dispute_open_t + T_dispute_max
  /\ (~voted \/ verdict = "NO_DECISION")
  /\ state' = "RESOLVED"
  /\ verdict' = "SPLIT_50_50"
  /\ cap_reserved' = 0
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               r1_verdict, seller_delivered, buyer_honest, n04_delay_paid, deadline_defaults,
               f4_keeper_paid_dispute, f4_review_fee_to_keeper, g3_review_keeper_payout, g3_party_paid_keeper,
               escReserve, escrowAppeal, escrowArbR1>>

TimeoutR2KeepR1 ==
  /\ state = "DISPUTE"
  /\ round = 2
  /\ t_now >= dispute_open_t + T_dispute_max
  /\ (~voted \/ verdict = "NO_DECISION")
  /\ state' = "RESOLVED"
  /\ cap_reserved' = 0
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               r1_verdict, seller_delivered, buyer_honest, n04_delay_paid, deadline_defaults,
               f4_keeper_paid_dispute, f4_review_fee_to_keeper, g3_review_keeper_payout, g3_party_paid_keeper,
               balKeeper, escReserve>>

ResolveRound1ToAppealable ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ voted = TRUE
  /\ verdict \in {"FOR_A", "FOR_B"}
  /\ state' = "APPEALABLE"
  /\ resolve_time' = t_now
  /\ r1_verdict' = verdict
  /\ r1_pool' = esc_level
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               cap_reserved, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, seller_delivered, buyer_honest, payout_count,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balA, balB, balKeeper, balTreasury, escReserve,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal>>

\* G2(a): Appeal MUST draw from disjoint higher-tier pool (if R1 in 0 -> 1 or 2; if R1 in 1 -> 2; if R1 in 2 -> 2 disjoint jurors)
Appeal ==
  /\ state = "APPEALABLE"
  /\ round = 1
  /\ t_now < resolve_time + T_appeal
  /\ LET targetR2Pool == IF r1_pool = 0 THEN (IF pool_l1_ok THEN 1 ELSE 2) ELSE 2
         isDisjoint == (r1_pool /= 0) \/ (targetR2Pool /= r1_pool)
     IN
     /\ state' = "DISPUTE"
     /\ round' = 2
     /\ esc_level' = targetR2Pool
     /\ r2_pool' = targetR2Pool
     /\ r2_pool_disjoint' = isDisjoint
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

FinalizeAppealable ==
  /\ state = "APPEALABLE"
  /\ t_now >= resolve_time + T_appeal
  /\ state' = "RESOLVED"
  /\ cap_reserved' = 0
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest,
               n04_delay_paid, deadline_defaults, f4_keeper_paid_dispute, f4_review_fee_to_keeper,
               g3_review_keeper_payout, g3_party_paid_keeper,
               balKeeper, escReserve, escrowArbCurr, escrowArbReward>>

ResolveRound2Final ==
  /\ state = "DISPUTE"
  /\ round = 2
  /\ voted = TRUE
  /\ verdict \in {"FOR_A", "FOR_B"}
  /\ state' = "RESOLVED"
  /\ cap_reserved' = 0
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
               panel_formed, panel_l2_formed, pool_l0_ok, pool_l1_ok, pool_l2_ok,
               r1_pool, r2_pool, r2_pool_disjoint, committed, voted,
               tally_sealed, tally_leaked, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, deadline_defaults,
               f4_keeper_paid_dispute, f4_review_fee_to_keeper, g3_review_keeper_payout, g3_party_paid_keeper,
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

Inv_F1SplitOnlyAfterChain ==
  (state = "RESOLVED" /\ verdict = "SPLIT_50_50") => (round = 1 /\ esc_level = 2)

Inv_F1GrowingReward ==
  (state = "DISPUTE" /\ round = 1) => (curr_reward = BaseArbReward + failed_attempts * EscBonus)

Inv_E1Round2NeverSplits5050 ==
  (round = 2 /\ state = "RESOLVED") => (verdict /= "SPLIT_50_50")

Inv_N01Round2NoBuyerProfit ==
  (round = 2 /\ verdict = "R1_UPHELD" /\ r1_verdict = "FOR_A") => (balB = InitBuyer - Amount - DisputeDeposit)

\* G1: Capacity reservation held non-terminal, released terminal; NO passive GLOBAL shortage split
Inv_G1CapacityReservedNonTerminal ==
  (~(state \in {"CLOSED", "EXPIRED", "RESOLVED"})) => (cap_reserved = CapReq)

Inv_G1AdmissionRequiresL2Cap ==
  pool_l2_ok = TRUE

Inv_G1CapacityReleasedTerminal ==
  (state \in {"CLOSED", "EXPIRED", "RESOLVED"}) => (cap_reserved = 0)

Inv_G1NoPassiveExhaustionSplit ==
  (state = "RESOLVED" /\ verdict = "SPLIT_50_50") => (round = 1 /\ esc_level = 2 /\ pool_l2_ok = TRUE)

\* G2: Disjoint R2 pool & Dynamic ceiling check
Inv_G2DisjointR2Pool ==
  (round = 2) => (r2_pool_disjoint = TRUE /\ ((r1_pool = 0) => (r2_pool /= 0)))

Inv_G2DynamicVProtocolMax ==
  (Amount > 0 /\ Amount <= V_protocol_max /\ Amount <= V_liq_max)

\* G3: Bounded keeper reward & party exclusion
Inv_G3KeeperCappedAndPartiesExcluded ==
  /\ ~g3_party_paid_keeper
  /\ (g3_review_keeper_payout <= R_keeper_max)
  /\ (~f4_keeper_paid_dispute)
  /\ (f4_review_fee_to_keeper => (state = "CLOSED" /\ g3_review_keeper_payout = KeeperBountyCap))

Inv_F3TallySealedUntilQuorum ==
  (~tally_leaked) /\ (((state = "DISPUTE") /\ (~voted \/ verdict = "NO_DECISION")) => (tally_sealed = TRUE))

Inv_F5DefaultOnlyOnSellerTimeout ==
  /\ (deadline_defaults > 0 => (state = "EXPIRED" /\ submit_time = -1))
  /\ (state \in {"DRAFT", "LOCKED", "IN_PROGRESS", "REVIEW", "DISPUTE", "APPEALABLE", "CLOSED", "RESOLVED"} => deadline_defaults = 0)
  /\ (cancel_req_t >= 0 /\ state = "EXPIRED" => deadline_defaults = 0)

Inv_M09CancelGraceAndDelay ==
  (state = "EXPIRED" /\ t_now < T_accept)
    => (cancel_req_t >= T_cancel_grace /\ t_now >= cancel_req_t + T_cancel_delay)

Prop_EventuallyTerminal ==
  <>(state \in {"CLOSED", "EXPIRED", "RESOLVED"})

Prop_DisputeAndAppealableExit ==
  /\ [](state = "DISPUTE" => <>(state \in {"APPEALABLE", "RESOLVED"}))
  /\ [](state = "APPEALABLE" => <>(state \in {"DISPUTE", "RESOLVED"}))

=============================================================================
