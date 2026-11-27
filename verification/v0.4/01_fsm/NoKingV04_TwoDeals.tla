------------------------- MODULE NoKingV04_TwoDeals -------------------------
(*
  X0.6 Bounded 2-Deal Concurrent Model of NoKing Protocol v0.4-draft.
  Two concurrent deals d \in {1, 2} share:
    - Participant wallets balA, balB
    - Protocol keeper payouts balKeeper and dao treasury balTreasury
    - Protocol escalation reward reserve escReserve
    - Global arbitrator liquidity pool balArb (finite liquidity contention:
      one deal locking ArbStake*PanelSize can starve the other deal and force F1 escalation!)
  Verifies:
    - Exact conservation across both deals & shared pools
    - Non-negative balances & cross-deal escrow isolation
    - F1 50/50 split only after escalation chain exhausted
    - F4 review timeout keeper payout & F5 seller-only deadline_defaults per deal
    - Bounded Liveness (BothTerminal) under liquidity contention
*)

EXTENDS Integers, FiniteSets

CONSTANTS
  Amount,            \* 100
  V_protocol_max,    \* 8750
  SellerDeposit,     \* 10
  Penalty,           \* 5
  ProtocolFee,       \* 1
  DisputeDeposit,    \* 5
  AppealDeposit,     \* 15
  ArbStake,          \* 10
  PanelSize,         \* 3 (so 1 panel locks 30; InitArb = 45 allows 1 panel at a time -> contention!)
  BaseArbReward,     \* 2
  EscBonus,          \* 2
  KeeperFee,         \* 1
  T_cancel_grace,    \* 1
  T_accept,          \* 1
  Deadline,          \* 3
  T_review,          \* 1
  T_dispute_max,     \* 3
  T_appeal,          \* 1
  MaxTime,           \* 11
  InitBuyer,         \* 400
  InitSeller,        \* 400
  InitArb,           \* 45  (< 2 * 30 = 60 -> real cross-deal liquidity contention!)
  InitReserve        \* 20

Deals == {1, 2}

VARIABLES
  t_now,
  state,
  submit_time,
  resolve_time,
  dispute_open_t,
  round,
  esc_level,         \* [Deals -> 0..2]
  verdict,
  r1_verdict,
  payout_count,
  deadline_defaults, \* [Deals -> 0..1]
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

vars == <<t_now, state, submit_time, resolve_time, dispute_open_t, round, esc_level,
          verdict, r1_verdict, payout_count, deadline_defaults,
          balA, balB, balArb, balKeeper, balTreasury, escReserve,
          eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

TotalInitial == InitBuyer + InitSeller + InitArb + InitReserve
PanelCost == PanelSize * ArbStake

BothTerminal == \A d \in Deals : state[d] \in {"CLOSED", "EXPIRED", "RESOLVED"}

Init ==
  /\ Amount <= V_protocol_max
  /\ t_now = 0
  /\ state = [d \in Deals |-> "DRAFT"]
  /\ submit_time = [d \in Deals |-> -1]
  /\ resolve_time = [d \in Deals |-> -1]
  /\ dispute_open_t = [d \in Deals |-> -1]
  /\ round = [d \in Deals |-> 0]
  /\ esc_level = [d \in Deals |-> 0]
  /\ verdict = [d \in Deals |-> "NONE"]
  /\ r1_verdict = [d \in Deals |-> "NONE"]
  /\ payout_count = [d \in Deals |-> 0]
  /\ deadline_defaults = [d \in Deals |-> 0]
  /\ balA = InitSeller - 2 * SellerDeposit
  /\ balB = InitBuyer
  /\ balArb = InitArb
  /\ balKeeper = 0
  /\ balTreasury = 0
  /\ escReserve = InitReserve
  /\ eBuyer = [d \in Deals |-> 0]
  /\ eSeller = [d \in Deals |-> SellerDeposit]
  /\ eDispute = [d \in Deals |-> 0]
  /\ eAppeal = [d \in Deals |-> 0]
  /\ eArbR1 = [d \in Deals |-> 0]
  /\ eArbCurr = [d \in Deals |-> 0]
  /\ eArbRew = [d \in Deals |-> 0]

Tick ==
  /\ t_now < MaxTime
  /\ ~BothTerminal
  /\ \A d \in Deals :
       /\ ~((state[d] = "DRAFT") /\ (t_now >= T_accept))
       /\ ~((state[d] = "LOCKED") /\ (t_now >= Deadline))
       /\ ~((state[d] = "IN_PROGRESS") /\ (t_now >= Deadline))
       /\ ~((state[d] = "REVIEW") /\ (submit_time[d] >= 0) /\ (t_now >= submit_time[d] + T_review))
       /\ ~((state[d] = "APPEALABLE") /\ (resolve_time[d] >= 0) /\ (t_now >= resolve_time[d] + T_appeal))
       /\ ~((state[d] = "DISPUTE") /\ (dispute_open_t[d] >= 0) /\ (t_now >= dispute_open_t[d] + T_dispute_max))
  /\ t_now' = t_now + 1
  /\ UNCHANGED <<state, submit_time, resolve_time, dispute_open_t, round, esc_level,
               verdict, r1_verdict, payout_count, deadline_defaults,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

Accept(d) ==
  /\ state[d] = "DRAFT" /\ t_now < T_accept
  /\ state' = [state EXCEPT ![d] = "LOCKED"]
  /\ balB' = balB - Amount
  /\ eBuyer' = [eBuyer EXCEPT ![d] = Amount]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round, esc_level,
               verdict, r1_verdict, payout_count, deadline_defaults,
               balA, balArb, balKeeper, balTreasury, escReserve,
               eSeller, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

CancelOrTimeoutDraft(d) ==
  /\ state[d] = "DRAFT"
  /\ t_now >= T_cancel_grace
  /\ state' = [state EXCEPT ![d] = "EXPIRED"]
  /\ balA' = balA + eSeller[d]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round, esc_level,
               verdict, r1_verdict, deadline_defaults,
               balB, balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

Start(d) ==
  /\ state[d] = "LOCKED" /\ t_now < Deadline
  /\ state' = [state EXCEPT ![d] = "IN_PROGRESS"]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round, esc_level,
               verdict, r1_verdict, payout_count, deadline_defaults,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

TimeoutSeller(d) ==
  /\ state[d] \in {"LOCKED", "IN_PROGRESS"} /\ t_now >= Deadline
  /\ state' = [state EXCEPT ![d] = "EXPIRED"]
  /\ deadline_defaults' = [deadline_defaults EXCEPT ![d] = 1]
  /\ balB' = balB + eBuyer[d] + (Penalty - KeeperFee)
  /\ balA' = balA + (eSeller[d] - Penalty)
  /\ balKeeper' = balKeeper + KeeperFee
  /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round, esc_level,
               verdict, r1_verdict, balArb, balTreasury, escReserve,
               eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

Submit(d) ==
  /\ state[d] = "IN_PROGRESS" /\ t_now < Deadline
  /\ state' = [state EXCEPT ![d] = "REVIEW"]
  /\ submit_time' = [submit_time EXCEPT ![d] = t_now]
  /\ UNCHANGED <<t_now, resolve_time, dispute_open_t, round, esc_level,
               verdict, r1_verdict, payout_count, deadline_defaults,
               balA, balB, balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

\* F4: TimeoutReview sends 100% ProtocolFee to Keeper; Confirm sends to Treasury
CloseReview(d) ==
  /\ state[d] = "REVIEW"
  /\ state' = [state EXCEPT ![d] = "CLOSED"]
  /\ balA' = balA + (eBuyer[d] - ProtocolFee) + eSeller[d]
  /\ IF t_now < submit_time[d] + T_review
     THEN /\ balTreasury' = balTreasury + ProtocolFee
          /\ balKeeper' = balKeeper
     ELSE /\ balKeeper' = balKeeper + ProtocolFee
          /\ balTreasury' = balTreasury
  /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round, esc_level,
               verdict, r1_verdict, deadline_defaults,
               balB, balArb, escReserve, eDispute, eAppeal, eArbR1, eArbCurr, eArbRew>>

OpenDispute(d) ==
  /\ state[d] = "REVIEW" /\ t_now < submit_time[d] + T_review
  /\ state' = [state EXCEPT ![d] = "DISPUTE"]
  /\ round' = [round EXCEPT ![d] = 1]
  /\ esc_level' = [esc_level EXCEPT ![d] = 0]
  /\ dispute_open_t' = [dispute_open_t EXCEPT ![d] = t_now]
  /\ verdict' = [verdict EXCEPT ![d] = "NONE"]
  /\ balB' = balB - DisputeDeposit
  /\ eDispute' = [eDispute EXCEPT ![d] = DisputeDeposit]
  /\ escReserve' = escReserve - BaseArbReward
  /\ eArbRew' = [eArbRew EXCEPT ![d] = BaseArbReward]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, r1_verdict, payout_count, deadline_defaults,
               balA, balArb, balKeeper, balTreasury, eBuyer, eSeller, eAppeal, eArbR1, eArbCurr>>

\* Shared arbitrator liquidity: if balArb >= PanelCost, panel forms & resolves; if balArb < PanelCost in R1, escalates!
PanelFormAndVote(d) ==
  /\ state[d] = "DISPUTE"
  /\ verdict[d] = "NONE"
  /\ t_now < dispute_open_t[d] + T_dispute_max
  /\ balArb >= PanelCost
  /\ \E v \in {"FOR_A", "FOR_B"} : verdict' = [verdict EXCEPT ![d] = v]
  /\ balArb' = balArb - PanelCost
  /\ eArbCurr' = [eArbCurr EXCEPT ![d] = PanelCost]
  /\ UNCHANGED <<t_now, state, submit_time, resolve_time, dispute_open_t, round, esc_level,
               r1_verdict, payout_count, deadline_defaults,
               balA, balB, balKeeper, balTreasury, escReserve,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbRew>>

\* Escalation under cross-deal liquidity starvation (or vote timeout)
EscalateDeal(d) ==
  /\ state[d] = "DISPUTE" /\ round[d] = 1 /\ esc_level[d] < 2
  /\ verdict[d] = "NONE"
  /\ ((balArb < PanelCost /\ t_now < dispute_open_t[d] + T_dispute_max)
      \/ (t_now >= dispute_open_t[d] + T_dispute_max))
  /\ esc_level' = [esc_level EXCEPT ![d] = @ + 1]
  /\ escReserve' = escReserve - EscBonus
  /\ eArbRew' = [eArbRew EXCEPT ![d] = @ + EscBonus]
  /\ UNCHANGED <<t_now, state, submit_time, resolve_time, dispute_open_t, round,
               verdict, r1_verdict, payout_count, deadline_defaults,
               balA, balB, balArb, balKeeper, balTreasury,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr>>

ResolveR1(d) ==
  /\ state[d] = "DISPUTE" /\ round[d] = 1 /\ verdict[d] \in {"FOR_A", "FOR_B"}
  /\ state' = [state EXCEPT ![d] = "APPEALABLE"]
  /\ resolve_time' = [resolve_time EXCEPT ![d] = t_now]
  /\ r1_verdict' = [r1_verdict EXCEPT ![d] = verdict[d]]
  /\ eArbR1' = [eArbR1 EXCEPT ![d] = eArbCurr[d]]
  /\ eArbCurr' = [eArbCurr EXCEPT ![d] = 0]
  /\ balArb' = balArb + eArbRew[d]
  /\ eArbRew' = [eArbRew EXCEPT ![d] = 0]
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, round, esc_level, verdict,
               payout_count, deadline_defaults, balA, balB, balKeeper, balTreasury,
               escReserve, eBuyer, eSeller, eDispute, eAppeal>>

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
  /\ UNCHANGED <<t_now, submit_time, resolve_time, r1_verdict, payout_count, deadline_defaults,
               balArb, balKeeper, balTreasury, escReserve,
               eBuyer, eSeller, eDispute, eArbR1, eArbCurr, eArbRew>>

FinalizeOrResolveR2(d) ==
  \/ ( /\ state[d] = "APPEALABLE" /\ t_now >= resolve_time[d] + T_appeal
       /\ state' = [state EXCEPT ![d] = "RESOLVED"]
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
       /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round, esc_level,
                    verdict, r1_verdict, deadline_defaults, balKeeper, escReserve, eArbCurr, eArbRew>> )
  \/ ( /\ state[d] = "DISPUTE" /\ round[d] = 2 /\ verdict[d] \in {"FOR_A", "FOR_B"}
       /\ LET overturned == (verdict[d] /= r1_verdict[d]) IN
          /\ state' = [state EXCEPT ![d] = "RESOLVED"]
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
          /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round, esc_level,
                       verdict, r1_verdict, deadline_defaults, balKeeper, escReserve, eArbRew>> )

TimeoutDispute(d) ==
  /\ state[d] = "DISPUTE" /\ verdict[d] = "NONE" /\ t_now >= dispute_open_t[d] + T_dispute_max
  /\ (round[d] = 2 \/ esc_level[d] = 2)
  /\ state' = [state EXCEPT ![d] = "RESOLVED"]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ IF round[d] = 1
     THEN /\ verdict' = [verdict EXCEPT ![d] = "SPLIT_50_50"]
          /\ balA' = balA + (eBuyer[d] \div 2) + (eSeller[d] - DisputeDeposit)
          /\ balB' = balB + (eBuyer[d] - (eBuyer[d] \div 2))
          /\ balKeeper' = balKeeper + KeeperFee
          /\ balTreasury' = balTreasury + (DisputeDeposit + eDispute[d] - KeeperFee) + eArbRew[d]
          /\ balArb' = balArb + eArbCurr[d]
     ELSE /\ verdict' = [verdict EXCEPT ![d] = "R1_UPHELD"]
          /\ IF r1_verdict[d] = "FOR_A"
             THEN /\ balA' = balA + (eBuyer[d] - ProtocolFee) + eSeller[d]
                  /\ balB' = balB + eAppeal[d]
                  /\ balTreasury' = balTreasury + ProtocolFee
                  /\ balArb' = balArb + eDispute[d] + eArbR1[d] + eArbCurr[d] + eArbRew[d]
             ELSE /\ balB' = balB + eBuyer[d] + eDispute[d] + Penalty
                  /\ balA' = balA + eAppeal[d]
                  /\ balTreasury' = balTreasury
                  /\ balArb' = balArb + (eSeller[d] - Penalty) + eArbR1[d] + eArbCurr[d] + eArbRew[d]
          /\ balKeeper' = balKeeper
  /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ eDispute' = [eDispute EXCEPT ![d] = 0]
  /\ eAppeal' = [eAppeal EXCEPT ![d] = 0]
  /\ eArbR1' = [eArbR1 EXCEPT ![d] = 0]
  /\ eArbCurr' = [eArbCurr EXCEPT ![d] = 0]
  /\ eArbRew' = [eArbRew EXCEPT ![d] = 0]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round, esc_level,
               r1_verdict, deadline_defaults, escReserve>>

TerminalStutter == BothTerminal /\ UNCHANGED vars

Next ==
  \/ Tick
  \/ \E d \in Deals :
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
  \/ TerminalStutter

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

Inv_TwoDealNoDoublePayout == \A d \in Deals : payout_count[d] <= 1

Inv_TwoDealCrossIsolation ==
  \A d \in Deals :
    /\ (state[d] \in {"LOCKED", "IN_PROGRESS", "REVIEW", "DISPUTE", "APPEALABLE"}
         => (eBuyer[d] = Amount /\ eSeller[d] = SellerDeposit /\ payout_count[d] = 0))
    /\ (state[d] \in {"CLOSED", "EXPIRED", "RESOLVED"}
         => (eBuyer[d] = 0 /\ eSeller[d] = 0 /\ eDispute[d] = 0 /\ eAppeal[d] = 0
             /\ eArbR1[d] = 0 /\ eArbCurr[d] = 0 /\ eArbRew[d] = 0))

Inv_TwoDealF1SplitOnlyAfterChain ==
  \A d \in Deals : (state[d] = "RESOLVED" /\ verdict[d] = "SPLIT_50_50") => (round[d] = 1 /\ esc_level[d] = 2)

Inv_TwoDealF5SellerOnly ==
  \A d \in Deals : (deadline_defaults[d] > 0) => (state[d] = "EXPIRED" /\ submit_time[d] = -1)

Prop_BothTerminal == <>(BothTerminal)

=============================================================================
