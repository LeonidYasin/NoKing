------------------------- MODULE NoKingV05_TwoDeals -------------------------
(*
  Y2 Bounded 2-Deal Concurrent Model of NoKing Protocol v0.5-draft (G1 Capacity Contention + G3).
  Two agreements d \in {1, 2} start "UNCREATED" and compete to reserve global arbitrator
  capacity (CapReq = 35 out of MaxArbCap = 60, so Deal 2 CANNOT be admitted until Deal 1
  terminates and releases its capacity reservation!).
  Verifies:
    - Exact conservation across both deals & shared pools
    - G1 Admission exclusion: global reserved_cap NEVER exceeds MaxArbCap
    - G1 No passive exhaustion split in GLOBAL
    - G3 Bounded keeper reward (ProtocolFee=5 > R_keeper_max=2 -> Treasury gets excess)
    - Bounded Liveness (BothCreatedAndTerminal): blocked Deal 2 admits & finishes after Deal 1!
*)

EXTENDS Integers, FiniteSets

CONSTANTS
  Amount,            \* 100
  V_protocol_max,    \* 8750
  V_liq_max,         \* 5000
  SellerDeposit,     \* 10
  Penalty,           \* 5
  ProtocolFee,       \* 5
  R_keeper_max,      \* 2
  DisputeDeposit,    \* 5
  AppealDeposit,     \* 15
  ArbStake,          \* 10
  PanelSize,         \* 3 (R1 PanelCost = 30; G1 CapReq = 35 out of MaxArbCap = 60)
  CapReq,            \* 35
  MaxArbCap,         \* 60 (< 2 * 35 = 70 -> real G1 admission contention!)
  BaseArbReward,     \* 2
  EscBonus,          \* 2
  KeeperFee,         \* 1
  T_cancel_grace,    \* 1
  T_accept,          \* 2
  Deadline,          \* 4
  T_review,          \* 1
  T_dispute_max,     \* 3
  T_appeal,          \* 1
  MaxTime,           \* 14
  InitBuyer,         \* 400
  InitSeller,        \* 400
  InitArb,           \* 60
  InitReserve        \* 20

Deals == {1, 2}
Min(a, b) == IF a < b THEN a ELSE b
KeeperBounty == Min(R_keeper_max, ProtocolFee)

VARIABLES
  t_now,
  state,             \* "UNCREATED", "DRAFT", "LOCKED", "IN_PROGRESS", "REVIEW", "DISPUTE", "APPEALABLE", "CLOSED", "EXPIRED", "RESOLVED"
  create_t,
  submit_time,
  resolve_time,
  dispute_open_t,
  round,
  esc_level,
  panel_formed_l2,
  verdict,
  r1_verdict,
  payout_count,
  deadline_defaults,
  passive_shortage_split,
  deal_cap_reserved,
  reserved_global,
  balA,
  balB,
  balArb,
  balKeeper,
  balTreasury,
  escReserve,
  eBuyer,
  eSeller,
  eDispute,
  eAppeal,
  eArbR1,
  eArbCurr,
  eArbRew

vars == <<t_now, state, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
          panel_formed_l2, verdict, r1_verdict, payout_count, deadline_defaults, passive_shortage_split,
          deal_cap_reserved, reserved_global,
          balA, balB, balArb, balKeeper, balTreasury, escReserve,
          eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

TotalInitial == InitBuyer + InitSeller + InitArb + InitReserve
PanelCost == PanelSize * ArbStake

BothTerminal == \A d \in Deals : state[d] \in {"CLOSED", "EXPIRED", "RESOLVED"}

Init ==
  /\ Amount <= Min(V_protocol_max, V_liq_max)
  /\ MaxArbCap <= InitArb
  /\ t_now = 0
  /\ state = [d \in Deals |-> "UNCREATED"]
  /\ create_t = [d \in Deals |-> -1]
  /\ submit_time = [d \in Deals |-> -1]
  /\ resolve_time = [d \in Deals |-> -1]
  /\ dispute_open_t = [d \in Deals |-> -1]
  /\ round = [d \in Deals |-> 0]
  /\ esc_level = [d \in Deals |-> 0]
  /\ panel_formed_l2 = [d \in Deals |-> FALSE]
  /\ verdict = [d \in Deals |-> "NONE"]
  /\ r1_verdict = [d \in Deals |-> "NONE"]
  /\ payout_count = [d \in Deals |-> 0]
  /\ deadline_defaults = [d \in Deals |-> 0]
  /\ passive_shortage_split = FALSE
  /\ deal_cap_reserved = [d \in Deals |-> 0]
  /\ reserved_global = 0
  /\ balA = InitSeller
  /\ balB = InitBuyer
  /\ balArb = InitArb
  /\ balKeeper = 0
  /\ balTreasury = 0
  /\ escReserve = InitReserve
  /\ eBuyer = [d \in Deals |-> 0]
  /\ eSeller = [d \in Deals |-> 0]
  /\ eDispute = [d \in Deals |-> 0]
  /\ eAppeal = [d \in Deals |-> 0]
  /\ eArbR1 = [d \in Deals |-> 0]
  /\ eArbCurr = [d \in Deals |-> 0]
  /\ eArbRew = [d \in Deals |-> 0]

\* G1: e_create checks free capacity (MaxArbCap - reserved_global >= CapReq) & reserves!
CreateDeal(d) ==
  /\ state[d] = "UNCREATED"
  /\ t_now <= MaxTime - 5
  /\ (MaxArbCap - reserved_global) >= CapReq
  /\ state' = [state EXCEPT ![d] = "DRAFT"]
  /\ create_t' = [create_t EXCEPT ![d] = t_now]
  /\ deal_cap_reserved' = [deal_cap_reserved EXCEPT ![d] = CapReq]
  /\ reserved_global' = reserved_global + CapReq
  /\ balA' = balA - SellerDeposit
  /\ eSeller' = [eSeller EXCEPT ![d] = SellerDeposit]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round, esc_level,
               panel_formed_l2, verdict, r1_verdict, payout_count, deadline_defaults, passive_shortage_split,
               balB, balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

Tick ==
  /\ t_now < MaxTime
  /\ ~BothTerminal
  /\ \A d \in Deals :
       /\ ~(state[d] = "UNCREATED" /\ (MaxArbCap - reserved_global) >= CapReq)
       /\ ~((state[d] = "DRAFT") /\ (t_now >= create_t[d] + T_accept))
       /\ ~((state[d] = "LOCKED") /\ (t_now >= create_t[d] + Deadline))
       /\ ~((state[d] = "IN_PROGRESS") /\ (t_now >= create_t[d] + Deadline))
       /\ ~((state[d] = "REVIEW") /\ (submit_time[d] >= 0) /\ (t_now >= submit_time[d] + T_review))
       /\ ~((state[d] = "APPEALABLE") /\ (resolve_time[d] >= 0) /\ (t_now >= resolve_time[d] + T_appeal))
       /\ ~((state[d] = "DISPUTE") /\ (dispute_open_t[d] >= 0) /\ (t_now >= dispute_open_t[d] + T_dispute_max))
  /\ t_now' = t_now + 1
  /\ UNCHANGED <<state, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
               panel_formed_l2, verdict, r1_verdict, payout_count, deadline_defaults, passive_shortage_split,
               deal_cap_reserved, reserved_global,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

Accept(d) ==
  /\ state[d] = "DRAFT" /\ t_now < create_t[d] + T_accept
  /\ state' = [state EXCEPT ![d] = "LOCKED"]
  /\ balB' = balB - Amount
  /\ eBuyer' = [eBuyer EXCEPT ![d] = Amount]
  /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
               panel_formed_l2, verdict, r1_verdict, payout_count, deadline_defaults, passive_shortage_split,
               deal_cap_reserved, reserved_global,
               balA, balArb, balKeeper, balTreasury, escReserve,
               eSeller, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

CancelOrTimeoutDraft(d) ==
  /\ state[d] = "DRAFT"
  /\ t_now >= create_t[d] + T_cancel_grace
  /\ state' = [state EXCEPT ![d] = "EXPIRED"]
  /\ reserved_global' = reserved_global - deal_cap_reserved[d]
  /\ deal_cap_reserved' = [deal_cap_reserved EXCEPT ![d] = 0]
  /\ balA' = balA + eSeller[d]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
               panel_formed_l2, verdict, r1_verdict, deadline_defaults, passive_shortage_split,
               balB, balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

Start(d) ==
  /\ state[d] = "LOCKED" /\ t_now < create_t[d] + Deadline
  /\ state' = [state EXCEPT ![d] = "IN_PROGRESS"]
  /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
               panel_formed_l2, verdict, r1_verdict, payout_count, deadline_defaults, passive_shortage_split,
               deal_cap_reserved, reserved_global,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

TimeoutSeller(d) ==
  /\ state[d] \in {"LOCKED", "IN_PROGRESS"} /\ t_now >= create_t[d] + Deadline
  /\ state' = [state EXCEPT ![d] = "EXPIRED"]
  /\ reserved_global' = reserved_global - deal_cap_reserved[d]
  /\ deal_cap_reserved' = [deal_cap_reserved EXCEPT ![d] = 0]
  /\ deadline_defaults' = [deadline_defaults EXCEPT ![d] = 1]
  /\ balB' = balB + eBuyer[d] + (Penalty - KeeperFee)
  /\ balA' = balA + (eSeller[d] - Penalty)
  /\ balKeeper' = balKeeper + KeeperFee
  /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
               panel_formed_l2, verdict, r1_verdict, passive_shortage_split, balArb, balTreasury, escReserve,
               eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

Submit(d) ==
  /\ state[d] = "IN_PROGRESS" /\ t_now < create_t[d] + Deadline
  /\ state' = [state EXCEPT ![d] = "REVIEW"]
  /\ submit_time' = [submit_time EXCEPT ![d] = t_now]
  /\ UNCHANGED <<t_now, create_t, resolve_time, dispute_open_t, round, esc_level,
               panel_formed_l2, verdict, r1_verdict, payout_count, deadline_defaults, passive_shortage_split,
               deal_cap_reserved, reserved_global,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

\* G3: TimeoutReview sends KeeperBounty = Min(R_keeper_max, ProtocolFee) to keeper, excess to Treasury
CloseReview(d) ==
  /\ state[d] = "REVIEW"
  /\ state' = [state EXCEPT ![d] = "CLOSED"]
  /\ reserved_global' = reserved_global - deal_cap_reserved[d]
  /\ deal_cap_reserved' = [deal_cap_reserved EXCEPT ![d] = 0]
  /\ balA' = balA + (eBuyer[d] - ProtocolFee) + eSeller[d]
  /\ IF t_now < submit_time[d] + T_review
     THEN /\ balTreasury' = balTreasury + ProtocolFee
          /\ balKeeper' = balKeeper
     ELSE /\ balKeeper' = balKeeper + KeeperBounty
          /\ balTreasury' = balTreasury + (ProtocolFee - KeeperBounty)
  /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
               panel_formed_l2, verdict, r1_verdict, deadline_defaults, passive_shortage_split,
               balB, balArb, escReserve, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

OpenDispute(d) ==
  /\ state[d] = "REVIEW" /\ t_now < submit_time[d] + T_review
  /\ state' = [state EXCEPT ![d] = "DISPUTE"]
  /\ round' = [round EXCEPT ![d] = 1]
  /\ esc_level' = [esc_level EXCEPT ![d] = 0]
  /\ panel_formed_l2' = [panel_formed_l2 EXCEPT ![d] = FALSE]
  /\ dispute_open_t' = [dispute_open_t EXCEPT ![d] = t_now]
  /\ verdict' = [verdict EXCEPT ![d] = "NONE"]
  /\ balB' = balB - DisputeDeposit
  /\ eDispute' = [eDispute EXCEPT ![d] = DisputeDeposit]
  /\ escReserve' = escReserve - BaseArbReward
  /\ eArbRew' = [eArbRew EXCEPT ![d] = BaseArbReward]
  /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, r1_verdict, payout_count, deadline_defaults, passive_shortage_split,
               deal_cap_reserved, reserved_global,
               balA, balArb, balKeeper, balTreasury, eBuyer, eSeller, eAppeal, eArbR1, eArbCurr>>

\* Shared arbitrator liquidity: because G1 limits concurrent reserved_global <= MaxArbCap,
\* an admitted deal at esc_level=2 always finds PanelCost free (or sabotaged after panel formed!)
PanelFormAndVote(d) ==
  /\ state[d] = "DISPUTE"
  /\ verdict[d] = "NONE"
  /\ t_now < dispute_open_t[d] + T_dispute_max
  /\ balArb >= PanelCost
  /\ panel_formed_l2' = [panel_formed_l2 EXCEPT ![d] = IF (round[d]=1 /\ esc_level[d]=2) THEN TRUE ELSE @]
  /\ \E v \in {"FOR_A", "FOR_B", "NO_DECISION"} : verdict' = [verdict EXCEPT ![d] = v]
  /\ balArb' = balArb - PanelCost
  /\ eArbCurr' = [eArbCurr EXCEPT ![d] = PanelCost]
  /\ UNCHANGED <<t_now, state, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
               r1_verdict, payout_count, deadline_defaults, passive_shortage_split, deal_cap_reserved, reserved_global,
               balA, balB, balKeeper, balTreasury, escReserve,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbRew>>

EscalateDeal(d) ==
  /\ state[d] = "DISPUTE" /\ round[d] = 1 /\ esc_level[d] < 2
  /\ (verdict[d] = "NONE" \/ verdict[d] = "NO_DECISION")
  /\ ((verdict[d] = "NO_DECISION") \/ (balArb < PanelCost /\ t_now < dispute_open_t[d] + T_dispute_max)
      \/ (t_now >= dispute_open_t[d] + T_dispute_max))
  /\ esc_level' = [esc_level EXCEPT ![d] = @ + 1]
  /\ escReserve' = escReserve - EscBonus
  /\ eArbRew' = [eArbRew EXCEPT ![d] = @ + EscBonus]
  /\ balArb' = balArb + eArbCurr[d]
  /\ eArbCurr' = [eArbCurr EXCEPT ![d] = 0]
  /\ verdict' = [verdict EXCEPT ![d] = "NONE"]
  /\ UNCHANGED <<t_now, state, create_t, submit_time, resolve_time, dispute_open_t, round,
               panel_formed_l2, r1_verdict, payout_count, deadline_defaults, passive_shortage_split,
               deal_cap_reserved, reserved_global,
               balA, balB, balKeeper, balTreasury,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1>>

ResolveR1(d) ==
  /\ state[d] = "DISPUTE" /\ round[d] = 1 /\ verdict[d] \in {"FOR_A", "FOR_B"}
  /\ state' = [state EXCEPT ![d] = "APPEALABLE"]
  /\ resolve_time' = [resolve_time EXCEPT ![d] = t_now]
  /\ r1_verdict' = [r1_verdict EXCEPT ![d] = verdict[d]]
  /\ eArbR1' = [eArbR1 EXCEPT ![d] = eArbCurr[d]]
  /\ eArbCurr' = [eArbCurr EXCEPT ![d] = 0]
  /\ balArb' = balArb + eArbRew[d]
  /\ eArbRew' = [eArbRew EXCEPT ![d] = 0]
  /\ UNCHANGED <<t_now, create_t, submit_time, dispute_open_t, round, esc_level, panel_formed_l2, verdict,
               payout_count, deadline_defaults, passive_shortage_split, deal_cap_reserved, reserved_global,
               balA, balB, balKeeper, balTreasury, escReserve, eBuyer, eSeller, eDispute, eAppeal>>

Appeal(d) ==
  /\ state[d] = "APPEALABLE" /\ round[d] = 1 /\ t_now < resolve_time[d] + T_appeal
  /\ state' = [state EXCEPT ![d] = "DISPUTE"]
  /\ round' = [round EXCEPT ![d] = 2]
  /\ esc_level' = [esc_level EXCEPT ![d] = 2]
  /\ dispute_open_t' = [dispute_open_t EXCEPT ![d] = t_now]
  /\ verdict' = [verdict EXCEPT ![d] = "NONE"]
  /\ IF r1_verdict[d] = "FOR_A"
     THEN /\ balB' = balB - AppealDeposit
          /\ balA' = balA
     ELSE /\ balA' = balA - AppealDeposit
          /\ balB' = balB
  /\ eAppeal' = [eAppeal EXCEPT ![d] = AppealDeposit]
  /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, panel_formed_l2, r1_verdict,
               payout_count, deadline_defaults, passive_shortage_split, deal_cap_reserved, reserved_global,
               balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eSeller, eDispute, eArbR1, eArbCurr, eArbRew>>

FinalizeOrResolveR2(d) ==
  \/ ( /\ state[d] = "APPEALABLE" /\ t_now >= resolve_time[d] + T_appeal
       /\ state' = [state EXCEPT ![d] = "RESOLVED"]
       /\ reserved_global' = reserved_global - deal_cap_reserved[d]
       /\ deal_cap_reserved' = [deal_cap_reserved EXCEPT ![d] = 0]
       /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
       /\ IF r1_verdict[d] = "FOR_A"
          THEN /\ balA' = balA + (eBuyer[d] - ProtocolFee) + eSeller[d]
               /\ balB' = balB
               /\ balTreasury' = balTreasury + ProtocolFee
               /\ balArb' = balArb + eDispute[d] + eArbR1[d]
          ELSE /\ balB' = balB + eBuyer[d] + eDispute[d] + Penalty
               /\ balA' = balA
               /\ balTreasury' = balTreasury
               /\ balArb' = balArb + (eSeller[d] - Penalty) + eArbR1[d]
       /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
       /\ eSeller' = [eSeller EXCEPT ![d] = 0]
       /\ eDispute' = [eDispute EXCEPT ![d] = 0]
       /\ eAppeal' = [eAppeal EXCEPT ![d] = 0]
       /\ eArbR1' = [eArbR1 EXCEPT ![d] = 0]
       /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
                    panel_formed_l2, verdict, r1_verdict, deadline_defaults, passive_shortage_split, balKeeper, escReserve, eArbCurr, eArbRew>> )
  \/ ( /\ state[d] = "DISPUTE" /\ round[d] = 2 /\ verdict[d] \in {"FOR_A", "FOR_B"}
       /\ LET overturned == (verdict[d] /= r1_verdict[d]) IN
          /\ state' = [state EXCEPT ![d] = "RESOLVED"]
          /\ reserved_global' = reserved_global - deal_cap_reserved[d]
          /\ deal_cap_reserved' = [deal_cap_reserved EXCEPT ![d] = 0]
          /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
          /\ IF verdict[d] = "FOR_A"
             THEN /\ balA' = balA + (eBuyer[d] - ProtocolFee) + eSeller[d] + (IF overturned THEN eAppeal[d] ELSE 0)
                  /\ balB' = balB
                  /\ balTreasury' = balTreasury + ProtocolFee
                  /\ balArb' = balArb + eDispute[d] + eArbCurr[d] + eArbR1[d] + (IF overturned THEN 0 ELSE eAppeal[d])
             ELSE /\ balB' = balB + eBuyer[d] + eDispute[d] + Penalty + (IF overturned THEN eAppeal[d] ELSE 0)
                  /\ balA' = balA
                  /\ balTreasury' = balTreasury
                  /\ balArb' = balArb + (eSeller[d] - Penalty) + eArbCurr[d] + eArbR1[d] + (IF overturned THEN 0 ELSE eAppeal[d])
          /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
          /\ eSeller' = [eSeller EXCEPT ![d] = 0]
          /\ eDispute' = [eDispute EXCEPT ![d] = 0]
          /\ eAppeal' = [eAppeal EXCEPT ![d] = 0]
          /\ eArbR1' = [eArbR1 EXCEPT ![d] = 0]
          /\ eArbCurr' = [eArbCurr EXCEPT ![d] = 0]
          /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
                       panel_formed_l2, verdict, r1_verdict, deadline_defaults, passive_shortage_split, balKeeper, escReserve, eArbRew>> )

TimeoutDispute(d) ==
  \/ ( /\ state[d] = "DISPUTE" /\ round[d] = 1 /\ esc_level[d] = 2
       /\ t_now >= dispute_open_t[d] + T_dispute_max /\ verdict[d] \in {"NONE", "NO_DECISION"}
       /\ state' = [state EXCEPT ![d] = "RESOLVED"]
       /\ reserved_global' = reserved_global - deal_cap_reserved[d]
       /\ deal_cap_reserved' = [deal_cap_reserved EXCEPT ![d] = 0]
       /\ verdict' = [verdict EXCEPT ![d] = "SPLIT_50_50"]
       /\ passive_shortage_split' = ((balArb + eArbCurr[d]) < PanelCost)
       /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
       /\ balA' = balA + (Amount \div 2) + (eSeller[d] - DisputeDeposit)
       /\ balB' = balB + (Amount - (Amount \div 2))
       /\ balKeeper' = balKeeper + KeeperFee
       /\ balTreasury' = balTreasury + (DisputeDeposit + eDispute[d] - KeeperFee) + eArbRew[d]
       /\ balArb' = balArb + eArbCurr[d]
       /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
       /\ eSeller' = [eSeller EXCEPT ![d] = 0]
       /\ eDispute' = [eDispute EXCEPT ![d] = 0]
       /\ eArbCurr' = [eArbCurr EXCEPT ![d] = 0]
       /\ eArbRew' = [eArbRew EXCEPT ![d] = 0]
       /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
                    panel_formed_l2, r1_verdict, deadline_defaults, escReserve, eAppeal, eArbR1>> )
  \/ ( /\ state[d] = "DISPUTE" /\ round[d] = 2
       /\ t_now >= dispute_open_t[d] + T_dispute_max /\ verdict[d] \in {"NONE", "NO_DECISION"}
       /\ state' = [state EXCEPT ![d] = "RESOLVED"]
       /\ reserved_global' = reserved_global - deal_cap_reserved[d]
       /\ deal_cap_reserved' = [deal_cap_reserved EXCEPT ![d] = 0]
       /\ verdict' = [verdict EXCEPT ![d] = "R1_UPHELD"]
       /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
       /\ IF r1_verdict[d] = "FOR_A"
          THEN /\ balA' = balA + (eBuyer[d] - ProtocolFee) + eSeller[d]
               /\ balB' = balB + eAppeal[d]
               /\ balTreasury' = balTreasury + ProtocolFee
               /\ balArb' = balArb + eDispute[d] + eArbR1[d] + eArbCurr[d] + eArbRew[d]
          ELSE /\ balB' = balB + eBuyer[d] + eDispute[d] + Penalty
               /\ balA' = balA + eAppeal[d]
               /\ balTreasury' = balTreasury
               /\ balArb' = balArb + (eSeller[d] - Penalty) + eArbR1[d] + eArbCurr[d] + eArbRew[d]
       /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
       /\ eSeller' = [eSeller EXCEPT ![d] = 0]
       /\ eDispute' = [eDispute EXCEPT ![d] = 0]
       /\ eAppeal' = [eAppeal EXCEPT ![d] = 0]
       /\ eArbR1' = [eArbR1 EXCEPT ![d] = 0]
       /\ eArbCurr' = [eArbCurr EXCEPT ![d] = 0]
       /\ eArbRew' = [eArbRew EXCEPT ![d] = 0]
       /\ UNCHANGED <<t_now, create_t, submit_time, resolve_time, dispute_open_t, round, esc_level,
                    panel_formed_l2, r1_verdict, deadline_defaults, passive_shortage_split, balKeeper, escReserve>> )

StepDeal(d) ==
  \/ CreateDeal(d)
  \/ Accept(d)
  \/ CancelOrTimeoutDraft(d)
  \/ Start(d)
  \/ TimeoutSeller(d)
  \/ Submit(d)
  \/ CloseReview(d)
  \/ OpenDispute(d)
  \/ PanelFormAndVote(d)
  \/ EscalateDeal(d)
  \/ ResolveR1(d)
  \/ Appeal(d)
  \/ FinalizeOrResolveR2(d)
  \/ TimeoutDispute(d)

TerminalStutter == BothTerminal /\ UNCHANGED vars

Next == Tick \/ StepDeal(1) \/ StepDeal(2) \/ TerminalStutter

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

Inv_TwoDealConservation ==
  (balA + balB + balArb + balKeeper + balTreasury + escReserve
   + eBuyer[1] + eBuyer[2] + eSeller[1] + eSeller[2]
   + eDispute[1] + eDispute[2] + eAppeal[1] + eAppeal[2]
   + eArbR1[1] + eArbR1[2] + eArbCurr[1] + eArbCurr[2]
   + eArbRew[1] + eArbRew[2]) = TotalInitial

Inv_TwoDealNonNeg ==
  /\ balA >= 0 /\ balB >= 0 /\ balArb >= 0 /\ balKeeper >= 0 /\ balTreasury >= 0 /\ escReserve >= 0
  /\ \A d \in Deals : eBuyer[d] >= 0 /\ eSeller[d] >= 0 /\ eDispute[d] >= 0 /\ eAppeal[d] >= 0
                      /\ eArbR1[d] >= 0 /\ eArbCurr[d] >= 0 /\ eArbRew[d] >= 0

Inv_TwoDealNoDoublePayout == \A d \in Deals : payout_count[d] <= 1

Inv_TwoDealCrossIsolation ==
  \A d \in Deals :
    (state[d] \in {"LOCKED", "IN_PROGRESS", "REVIEW", "DISPUTE", "APPEALABLE"})
      => (eBuyer[d] = Amount /\ eSeller[d] = SellerDeposit /\ payout_count[d] = 0)

Inv_TwoDealG1CapacityBound ==
  /\ reserved_global >= 0
  /\ reserved_global <= MaxArbCap
  /\ reserved_global = deal_cap_reserved[1] + deal_cap_reserved[2]
  /\ \A d \in Deals : (state[d] \in {"CLOSED", "EXPIRED", "RESOLVED", "UNCREATED"}) => deal_cap_reserved[d] = 0
  /\ \A d \in Deals : (state[d] \in {"DRAFT", "LOCKED", "IN_PROGRESS", "REVIEW", "DISPUTE", "APPEALABLE"})
                        => deal_cap_reserved[d] = CapReq

Inv_TwoDealG1NoPassiveSplit ==
  (~passive_shortage_split) /\
  (\A d \in Deals :
    (state[d] = "RESOLVED" /\ verdict[d] = "SPLIT_50_50")
      => (round[d] = 1 /\ esc_level[d] = 2))

Inv_TwoDealF5SellerOnly ==
  \A d \in Deals : (deadline_defaults[d] > 0) => (state[d] = "EXPIRED" /\ submit_time[d] = -1)

Prop_BothTerminal == <>BothTerminal

=============================================================================
