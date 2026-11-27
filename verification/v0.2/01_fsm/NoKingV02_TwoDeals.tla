------------------------- MODULE NoKingV02_TwoDeals -------------------------
(*
  Bounded 2-Deal Concurrent Model of NoKing Protocol v0.2 (V2.4).
  Two concurrent agreements (id=1, id=2) share participant wallets (balA, balB),
  arbitrator pool (balArb), and protocol treasury (balTreasury).
  Models:
    - Independent FSM progression for Deal 1 and Deal 2 (interleaved asynchronously)
    - Arbitrator refusal / pool insufficiency (pool_sufficient \in {TRUE, FALSE})
    - D1, D2, D3, D4, D5, D6, D7, D10 across concurrent deals
  Verifies:
    - Cross-deal escrow isolation (Deal 1 cannot spend Deal 2's locked escrow)
    - Exact global token conservation across all wallets & both escrows
    - No double payout on either deal
    - Bounded Liveness for both deals simultaneously
*)

EXTENDS Integers, FiniteSets

CONSTANTS
  Amount,          \* 100
  SellerDeposit,   \* 10
  Penalty,         \* 5
  ProtocolFee,     \* 1
  DisputeDeposit,  \* 5
  AppealDeposit,   \* 15
  ArbStake,        \* 20
  ArbPenalty,      \* 5
  PanelSize,       \* 3 (abstract odd k for tractable 2-deal product state space)
  Q_arb,           \* 2
  T_accept,        \* 1
  Deadline,        \* 3
  T_review,        \* 1
  T_dispute_max,   \* 2
  T_appeal,        \* 1
  MaxTime,         \* 10
  InitBuyer,       \* 400
  InitSeller,      \* 400
  InitArb          \* 400

Deals == {1, 2}

VARIABLES
  t_now,
  state,           \* [Deals -> States]
  submit_time,     \* [Deals -> Int]
  resolve_time,    \* [Deals -> Int]
  dispute_open_t,  \* [Deals -> Int]
  round,           \* [Deals -> 0..2]
  pool_ok,         \* [Deals -> BOOLEAN]
  voted,           \* [Deals -> BOOLEAN]
  verdict,         \* [Deals -> {"NONE","FOR_A","FOR_B","NO_DECISION","COMPROMISE"}]
  r1_verdict,      \* [Deals -> {"NONE","FOR_A","FOR_B"}]
  payout_count,    \* [Deals -> 0..2]
  \* Shared balances
  balA,
  balB,
  balArb,
  balTreasury,
  \* Per-deal escrow buckets
  eBuyer,
  eSeller,
  eDispute,
  eAppeal,
  eArbR1,
  eArbCurr

vars == <<t_now, state, submit_time, resolve_time, dispute_open_t, round,
          pool_ok, voted, verdict, r1_verdict, payout_count,
          balA, balB, balArb, balTreasury,
          eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr>>

TotalInitial == InitBuyer + InitSeller + InitArb

Init ==
  /\ t_now = 0
  /\ state = [d \in Deals |-> "DRAFT"]
  /\ submit_time = [d \in Deals |-> -1]
  /\ resolve_time = [d \in Deals |-> -1]
  /\ dispute_open_t = [d \in Deals |-> -1]
  /\ round = [d \in Deals |-> 0]
  /\ pool_ok \in [Deals -> {TRUE, FALSE}]
  /\ voted = [d \in Deals |-> FALSE]
  /\ verdict = [d \in Deals |-> "NONE"]
  /\ r1_verdict = [d \in Deals |-> "NONE"]
  /\ payout_count = [d \in Deals |-> 0]
  \* Both deals lock SellerDeposit at DRAFT creation (D1)
  /\ balA = InitSeller - 2 * SellerDeposit
  /\ balB = InitBuyer
  /\ balArb = InitArb
  /\ balTreasury = 0
  /\ eBuyer = [d \in Deals |-> 0]
  /\ eSeller = [d \in Deals |-> SellerDeposit]
  /\ eDispute = [d \in Deals |-> 0]
  /\ eAppeal = [d \in Deals |-> 0]
  /\ eArbR1 = [d \in Deals |-> 0]
  /\ eArbCurr = [d \in Deals |-> 0]

BothTerminal == \A d \in Deals : state[d] \in {"CLOSED", "EXPIRED", "RESOLVED"}

Tick ==
  /\ t_now < MaxTime
  /\ ~BothTerminal
  /\ \A d \in Deals : ~(state[d] = "DISPUTE" /\ voted[d] = TRUE /\ verdict[d] \in {"FOR_A", "FOR_B"})
  /\ \A d \in Deals : ~(state[d] = "DRAFT" /\ t_now >= T_accept)
  /\ \A d \in Deals : ~(state[d] \in {"LOCKED", "IN_PROGRESS"} /\ t_now >= Deadline)
  /\ \A d \in Deals : ~(state[d] = "REVIEW" /\ t_now >= submit_time[d] + T_review)
  /\ \A d \in Deals : ~(state[d] = "DISPUTE" /\ t_now >= dispute_open_t[d] + T_dispute_max)
  /\ \A d \in Deals : ~(state[d] = "APPEALABLE" /\ t_now >= resolve_time[d] + T_appeal)
  /\ t_now' = t_now + 1
  /\ UNCHANGED <<state, submit_time, resolve_time, dispute_open_t, round,
               pool_ok, voted, verdict, r1_verdict, payout_count,
               balA, balB, balArb, balTreasury,
               eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr>>

Accept(d) ==
  /\ state[d] = "DRAFT"
  /\ t_now < T_accept
  /\ state' = [state EXCEPT ![d] = "LOCKED"]
  /\ balB' = balB - Amount
  /\ eBuyer' = [eBuyer EXCEPT ![d] = Amount]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               pool_ok, voted, verdict, r1_verdict, payout_count,
               balA, balArb, balTreasury, eSeller, eDispute, eAppeal, eArbR1, eArbCurr>>

CancelOrTimeoutDraft(d) ==
  /\ state[d] = "DRAFT"
  /\ state' = [state EXCEPT ![d] = "EXPIRED"]
  /\ balA' = balA + eSeller[d]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               pool_ok, voted, verdict, r1_verdict,
               balB, balArb, balTreasury, eBuyer, eDispute, eAppeal, eArbR1, eArbCurr>>

Start(d) ==
  /\ state[d] = "LOCKED"
  /\ t_now < Deadline
  /\ state' = [state EXCEPT ![d] = "IN_PROGRESS"]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               pool_ok, voted, verdict, r1_verdict, payout_count,
               balA, balB, balArb, balTreasury, eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr>>

TimeoutLockedOrInProg(d) ==
  /\ state[d] \in {"LOCKED", "IN_PROGRESS"}
  /\ t_now >= Deadline
  /\ state' = [state EXCEPT ![d] = "EXPIRED"]
  /\ balB' = balB + eBuyer[d] + Penalty
  /\ balA' = balA + (eSeller[d] - Penalty)
  /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               pool_ok, voted, verdict, r1_verdict,
               balArb, balTreasury, eDispute, eAppeal, eArbR1, eArbCurr>>

Submit(d) ==
  /\ state[d] = "IN_PROGRESS"
  /\ t_now < Deadline
  /\ state' = [state EXCEPT ![d] = "REVIEW"]
  /\ submit_time' = [submit_time EXCEPT ![d] = t_now]
  /\ UNCHANGED <<t_now, resolve_time, dispute_open_t, round,
               pool_ok, voted, verdict, r1_verdict, payout_count,
               balA, balB, balArb, balTreasury, eBuyer, eSeller, eDispute, eAppeal, eArbR1, eArbCurr>>

CloseReview(d) ==
  /\ state[d] = "REVIEW"
  /\ state' = [state EXCEPT ![d] = "CLOSED"]
  /\ balA' = balA + (eBuyer[d] - ProtocolFee) + eSeller[d]
  /\ balTreasury' = balTreasury + ProtocolFee
  /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               pool_ok, voted, verdict, r1_verdict,
               balB, balArb, eDispute, eAppeal, eArbR1, eArbCurr>>

OpenDispute(d) ==
  /\ state[d] = "REVIEW"
  /\ t_now < submit_time[d] + T_review
  /\ state' = [state EXCEPT ![d] = "DISPUTE"]
  /\ dispute_open_t' = [dispute_open_t EXCEPT ![d] = t_now]
  /\ round' = [round EXCEPT ![d] = 1]
  /\ voted' = [voted EXCEPT ![d] = FALSE]
  /\ verdict' = [verdict EXCEPT ![d] = "NONE"]
  /\ balB' = balB - DisputeDeposit
  /\ eDispute' = [eDispute EXCEPT ![d] = DisputeDeposit]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, pool_ok, r1_verdict, payout_count,
               balA, balArb, balTreasury, eBuyer, eSeller, eAppeal, eArbR1, eArbCurr>>

PanelVoteOutcome(d) ==
  /\ state[d] = "DISPUTE"
  /\ pool_ok[d] = TRUE
  /\ voted[d] = FALSE
  /\ t_now < dispute_open_t[d] + T_dispute_max
  /\ \E v \in {"FOR_A", "FOR_B", "NO_DECISION"} :
       /\ voted' = [voted EXCEPT ![d] = TRUE]
       /\ verdict' = [verdict EXCEPT ![d] = v]
       /\ balArb' = balArb - (PanelSize * ArbStake)
       /\ eArbCurr' = [eArbCurr EXCEPT ![d] = PanelSize * ArbStake]
  /\ UNCHANGED <<t_now, state, submit_time, resolve_time, dispute_open_t, round,
               pool_ok, r1_verdict, payout_count,
               balA, balB, balTreasury, eBuyer, eSeller, eDispute, eAppeal, eArbR1>>

CompromiseTimeout(d) ==
  /\ state[d] = "DISPUTE"
  /\ t_now >= dispute_open_t[d] + T_dispute_max
  /\ (~voted[d] \/ verdict[d] = "NO_DECISION")
  /\ state' = [state EXCEPT ![d] = "RESOLVED"]
  /\ verdict' = [verdict EXCEPT ![d] = "COMPROMISE"]
  /\ balB' = balB + eBuyer[d] + eDispute[d] + eAppeal[d]
  /\ balA' = balA + eSeller[d]
  /\ balArb' = balArb + eArbR1[d] + eArbCurr[d]
  /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
  /\ eSeller' = [eSeller EXCEPT ![d] = 0]
  /\ eDispute' = [eDispute EXCEPT ![d] = 0]
  /\ eAppeal' = [eAppeal EXCEPT ![d] = 0]
  /\ eArbR1' = [eArbR1 EXCEPT ![d] = 0]
  /\ eArbCurr' = [eArbCurr EXCEPT ![d] = 0]
  /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               pool_ok, voted, r1_verdict, balTreasury>>

ResolveR1(d) ==
  /\ state[d] = "DISPUTE"
  /\ round[d] = 1
  /\ voted[d] = TRUE
  /\ verdict[d] \in {"FOR_A", "FOR_B"}
  /\ state' = [state EXCEPT ![d] = "APPEALABLE"]
  /\ resolve_time' = [resolve_time EXCEPT ![d] = t_now]
  /\ r1_verdict' = [r1_verdict EXCEPT ![d] = verdict[d]]
  /\ eArbR1' = [eArbR1 EXCEPT ![d] = eArbCurr[d]]
  /\ eArbCurr' = [eArbCurr EXCEPT ![d] = 0]
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, round,
               pool_ok, voted, verdict, payout_count,
               balA, balB, balArb, balTreasury, eBuyer, eSeller, eDispute, eAppeal>>

Appeal(d) ==
  /\ state[d] = "APPEALABLE"
  /\ round[d] = 1
  /\ t_now < resolve_time[d] + T_appeal
  /\ state' = [state EXCEPT ![d] = "DISPUTE"]
  /\ round' = [round EXCEPT ![d] = 2]
  /\ dispute_open_t' = [dispute_open_t EXCEPT ![d] = t_now]
  /\ voted' = [voted EXCEPT ![d] = FALSE]
  /\ verdict' = [verdict EXCEPT ![d] = "NONE"]
  /\ IF r1_verdict[d] = "FOR_A"
     THEN /\ balB' = balB - AppealDeposit
          /\ balA' = balA
     ELSE /\ balA' = balA - AppealDeposit
          /\ balB' = balB
  /\ eAppeal' = [eAppeal EXCEPT ![d] = AppealDeposit]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, pool_ok, r1_verdict, payout_count,
               balArb, balTreasury, eBuyer, eSeller, eDispute, eArbR1, eArbCurr>>

FinalizeOrResolveR2(d) ==
  /\ (state[d] = "APPEALABLE" /\ t_now >= resolve_time[d] + T_appeal)
     \/ (state[d] = "DISPUTE" /\ round[d] = 2 /\ voted[d] = TRUE /\ verdict[d] \in {"FOR_A", "FOR_B"})
  /\ LET finV == IF state[d] = "APPEALABLE" THEN r1_verdict[d] ELSE verdict[d]
         overturned == (state[d] = "DISPUTE" /\ verdict[d] /= r1_verdict[d])
     IN
     /\ state' = [state EXCEPT ![d] = "RESOLVED"]
     /\ payout_count' = [payout_count EXCEPT ![d] = @ + 1]
     /\ IF finV = "FOR_A"
        THEN /\ balA' = balA + (eBuyer[d] - ProtocolFee) + eSeller[d] + (IF overturned THEN eAppeal[d] ELSE 0)
             /\ balB' = balB
             /\ balTreasury' = balTreasury + ProtocolFee
             /\ balArb' = balArb + eDispute[d] + eArbCurr[d] + eArbR1[d] + (IF overturned THEN 0 ELSE eAppeal[d])
        ELSE /\ balB' = balB + eBuyer[d] + eDispute[d] + Penalty + (IF overturned THEN eAppeal[d] ELSE 0)
             /\ balA' = balA
             /\ balTreasury' = balTreasury + (eSeller[d] - Penalty)
             /\ balArb' = balArb + eArbCurr[d] + eArbR1[d] + (IF overturned THEN 0 ELSE eAppeal[d])
     /\ eBuyer' = [eBuyer EXCEPT ![d] = 0]
     /\ eSeller' = [eSeller EXCEPT ![d] = 0]
     /\ eDispute' = [eDispute EXCEPT ![d] = 0]
     /\ eAppeal' = [eAppeal EXCEPT ![d] = 0]
     /\ eArbR1' = [eArbR1 EXCEPT ![d] = 0]
     /\ eArbCurr' = [eArbCurr EXCEPT ![d] = 0]
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               pool_ok, voted, verdict, r1_verdict>>

TerminalStutter == BothTerminal /\ UNCHANGED vars

Next ==
  \/ Tick
  \/ \E d \in Deals :
       \/ Accept(d)
       \/ CancelOrTimeoutDraft(d)
       \/ Start(d)
       \/ TimeoutLockedOrInProg(d)
       \/ Submit(d)
       \/ CloseReview(d)
       \/ OpenDispute(d)
       \/ PanelVoteOutcome(d)
       \/ CompromiseTimeout(d)
       \/ ResolveR1(d)
       \/ Appeal(d)
       \/ FinalizeOrResolveR2(d)
  \/ TerminalStutter

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

Inv_TwoDealConservation ==
  (balA + balB + balArb + balTreasury
   + eBuyer[1] + eBuyer[2] + eSeller[1] + eSeller[2]
   + eDispute[1] + eDispute[2] + eAppeal[1] + eAppeal[2]
   + eArbR1[1] + eArbR1[2] + eArbCurr[1] + eArbCurr[2]) = TotalInitial

Inv_TwoDealNoDoublePayout ==
  /\ payout_count[1] <= 1
  /\ payout_count[2] <= 1

Inv_TwoDealNonNegative ==
  /\ balA >= 0 /\ balB >= 0 /\ balArb >= 0 /\ balTreasury >= 0
  /\ \A d \in Deals : eBuyer[d] >= 0 /\ eSeller[d] >= 0 /\ eDispute[d] >= 0 /\ eAppeal[d] >= 0

Prop_BothTerminal == <>(BothTerminal)

=============================================================================
