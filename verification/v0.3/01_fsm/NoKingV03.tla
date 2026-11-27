----------------------------- MODULE NoKingV03 -----------------------------
(*
  Formal TLA+ model of NoKing Protocol v0.3-draft
  (protocol/specs/exchange-spec-v0.3.md, Decisions E1-E7 & W0-W6 updates).

  Key v0.3 updates modeled:
  - E1 Round 1: Escalation (e_escalate) to parent/global pool before 50/50 split;
                if escalation also fails -> 50/50 split of Amount, BOTH sides lose D_dispute
                (forfeited 2*D_dispute -> KeeperFee + 50% honest arbs + 50% Treasury).
  - E1 Round 2: If appeal panel fails/times out -> Round 1 verdict STANDS; only AppealDeposit returned.
  - E2: Capped proportional USDC stake S_arb.
  - E3: Higher unrevealed penalty (ArbUnrevPenalty > ArbPenalty); partial redraw replaces ONLY missing seats.
  - E4 & E5: amount >= A_min > 0 (D9-B removed).
  - Proposals: Symmetrized FOR_B arbitrator reward (from SellerDeposit); N-04 delay compensation
               on upheld appeal; N-08 DRAFT cancel grace (t_now >= T_cancel_grace).
*)

EXTENDS Integers, FiniteSets

CONSTANTS
  Amount,          \* 100 (>= A_min)
  SellerDeposit,   \* 10
  Penalty,         \* 5  (sigma * SellerDeposit)
  ProtocolFee,     \* 1
  DisputeDeposit,  \* 5
  AppealDeposit,   \* 15
  DelayComp,       \* 5  (N-04: 30% of AppealDeposit to R1 winner on uphold)
  ArbStake,        \* 20 (capped proportional stake)
  ArbPenalty,      \* 5  (lambda = 0.25)
  ArbUnrevPenalty, \* 10 (E3: lambda_unrev = 0.50 > 0.25)
  KeeperFee,       \* 1
  PanelSize,       \* 3 or 5
  Q_arb,           \* 2 or 3 (> PanelSize/2)
  T_cancel_grace,  \* 1 (N-08)
  T_accept,        \* 3
  Deadline,        \* 5
  T_review,        \* 2
  T_evidence,      \* 1
  T_commit,        \* 1
  T_reveal,        \* 1
  T_dispute_max,   \* 5
  T_appeal,        \* 2
  MaxTime,         \* 18
  InitBuyer,       \* 200
  InitSeller,      \* 200
  InitArb          \* 400

VARIABLES
  state,           \* DRAFT, LOCKED, IN_PROGRESS, REVIEW, DISPUTE, APPEALABLE, CLOSED, EXPIRED, RESOLVED
  t_now,
  submit_time,
  resolve_time,
  dispute_open_t,
  attempt_open_t,
  round,           \* 0, 1, 2
  escalated,       \* E1: FALSE initially, TRUE after e_escalate to parent/global pool
  attempt,         \* 0, 1, 2
  panel_formed,
  pool_sufficient, \* Category pool availability
  parent_pool_ok,  \* Parent/global pool availability (E1)
  committed,
  voted,
  votesA,          \* Accumulated valid FOR_A votes (retained across E3 partial redraw)
  votesB,          \* Accumulated valid FOR_B votes (retained across E3 partial redraw)
  votesUnrevealed, \* Missing / unrevealed seats in current attempt
  seats_drawn,     \* Number of seats active in current attempt (PanelSize initially, or missing seats)
  verdict,         \* "NONE", "FOR_A", "FOR_B", "NO_DECISION", "SPLIT_50_50", "R1_UPHELD"
  r1_verdict,      \* "NONE", "FOR_A", "FOR_B"
  seller_delivered,
  buyer_honest,
  payout_count,
  n04_delay_paid,  \* Witness flag for N-04 delay compensation on upheld appeal
  balA,
  balB,
  balArb,
  balTreasury,
  escrowBuyer,
  escrowSeller,
  escrowDispute,
  escrowAppeal,
  escrowArbR1,
  escrowArbCurr

vars == <<state, t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
          round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
          committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
          verdict, r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
          balA, balB, balArb, balTreasury,
          escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

TotalInitial == InitBuyer + InitSeller + InitArb

Init ==
  /\ state = "DRAFT"
  /\ t_now = 0
  /\ submit_time = -1
  /\ resolve_time = -1
  /\ dispute_open_t = -1
  /\ attempt_open_t = -1
  /\ round = 0
  /\ escalated = FALSE
  /\ attempt = 0
  /\ panel_formed = FALSE
  /\ pool_sufficient \in {TRUE, FALSE}
  /\ parent_pool_ok \in {TRUE, FALSE}
  /\ committed = FALSE
  /\ voted = FALSE
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
  /\ balA = InitSeller - SellerDeposit
  /\ escrowSeller = SellerDeposit
  /\ balB = InitBuyer
  /\ balArb = InitArb
  /\ balTreasury = 0
  /\ escrowBuyer = 0
  /\ escrowDispute = 0
  /\ escrowAppeal = 0
  /\ escrowArbR1 = 0
  /\ escrowArbCurr = 0

Tick ==
  /\ t_now < MaxTime
  /\ state \notin {"CLOSED", "EXPIRED", "RESOLVED"}
  /\ ~(state = "DRAFT" /\ t_now >= T_accept)
  /\ ~(state \in {"LOCKED", "IN_PROGRESS"} /\ t_now >= Deadline)
  /\ ~(state = "REVIEW" /\ t_now >= submit_time + T_review)
  /\ ~(state = "DISPUTE" /\ voted = TRUE /\ verdict \in {"FOR_A", "FOR_B"})
  /\ ~(state = "DISPUTE" /\ ~panel_formed /\ ~pool_sufficient /\ ~escalated)
  /\ ~(state = "DISPUTE" /\ t_now >= dispute_open_t + T_dispute_max)
  /\ ~(state = "APPEALABLE" /\ t_now >= resolve_time + T_appeal)
  /\ t_now' = t_now + 1
  /\ UNCHANGED <<state, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

Accept ==
  /\ state = "DRAFT"
  /\ t_now < T_accept
  /\ state' = "LOCKED"
  /\ balB' = balB - Amount
  /\ escrowBuyer' = Amount
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balArb, balTreasury, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

\* N-08 mitigation: CancelDraftByA requires t_now >= T_cancel_grace
CancelDraftByA ==
  /\ state = "DRAFT"
  /\ t_now >= T_cancel_grace
  /\ t_now < T_accept
  /\ state' = "EXPIRED"
  /\ balA' = balA + escrowSeller
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, n04_delay_paid,
               balB, balArb, balTreasury, escrowBuyer, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

TimeoutDraft ==
  /\ state = "DRAFT"
  /\ t_now >= T_accept
  /\ state' = "EXPIRED"
  /\ balA' = balA + escrowSeller
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, n04_delay_paid,
               balB, balArb, balTreasury, escrowBuyer, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

Start ==
  /\ state = "LOCKED"
  /\ t_now < Deadline
  /\ state' = "IN_PROGRESS"
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, balArb, balTreasury, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

TimeoutLocked ==
  /\ state = "LOCKED"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ \E kfee \in {0, KeeperFee} :
       /\ balB' = balB + escrowBuyer + (Penalty - kfee)
       /\ balA' = balA + (escrowSeller - Penalty)
       /\ balTreasury' = balTreasury + kfee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, n04_delay_paid,
               balArb, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

Submit ==
  /\ state = "IN_PROGRESS"
  /\ t_now < Deadline
  /\ \E deliv \in {TRUE, FALSE} : seller_delivered' = deliv
  /\ state' = "REVIEW"
  /\ submit_time' = t_now
  /\ UNCHANGED <<t_now, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, balArb, balTreasury, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

TimeoutInProgress ==
  /\ state = "IN_PROGRESS"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ \E kfee \in {0, KeeperFee} :
       /\ balB' = balB + escrowBuyer + (Penalty - kfee)
       /\ balA' = balA + (escrowSeller - Penalty)
       /\ balTreasury' = balTreasury + kfee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, n04_delay_paid,
               balArb, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

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
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, n04_delay_paid,
               balB, balArb, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

TimeoutReview ==
  /\ state = "REVIEW"
  /\ t_now >= submit_time + T_review
  /\ state' = "CLOSED"
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balTreasury' = balTreasury + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, n04_delay_paid,
               balB, balArb, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

OpenDispute ==
  /\ state = "REVIEW"
  /\ t_now < submit_time + T_review
  /\ (~seller_delivered \/ ~buyer_honest)
  /\ state' = "DISPUTE"
  /\ dispute_open_t' = t_now
  /\ attempt_open_t' = t_now
  /\ round' = 1
  /\ escalated' = FALSE
  /\ attempt' = 1
  /\ panel_formed' = FALSE
  /\ committed' = FALSE
  /\ voted' = FALSE
  /\ votesA' = 0
  /\ votesB' = 0
  /\ votesUnrevealed' = 0
  /\ seats_drawn' = PanelSize
  /\ verdict' = "NONE"
  /\ balB' = balB - DisputeDeposit
  /\ escrowDispute' = DisputeDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, pool_sufficient, parent_pool_ok,
               r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balArb, balTreasury, escrowBuyer, escrowSeller,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

ActivePoolOK == IF escalated THEN parent_pool_ok ELSE pool_sufficient

FormPanel ==
  /\ state = "DISPUTE"
  /\ panel_formed = FALSE
  /\ ActivePoolOK = TRUE
  /\ t_now < dispute_open_t + T_dispute_max
  /\ panel_formed' = TRUE
  /\ balArb' = balArb - (seats_drawn * ArbStake)
  /\ escrowArbCurr' = escrowArbCurr + (seats_drawn * ArbStake)
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, balTreasury, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1>>

\* E1: Escalate to parent/global pool if category pool insufficient
EscalateToParent ==
  /\ state = "DISPUTE"
  /\ escalated = FALSE
  /\ panel_formed = FALSE
  /\ pool_sufficient = FALSE
  /\ t_now < dispute_open_t + T_dispute_max
  /\ escalated' = TRUE
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, balArb, balTreasury, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

CommitVotes ==
  /\ state = "DISPUTE"
  /\ panel_formed = TRUE
  /\ committed = FALSE
  /\ t_now >= attempt_open_t + (IF attempt = 1 THEN T_evidence ELSE 0)
  /\ t_now < attempt_open_t + (IF attempt = 1 THEN T_evidence ELSE 0) + T_commit
  /\ t_now < dispute_open_t + T_dispute_max
  /\ committed' = TRUE
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, balArb, balTreasury, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

\* E3: Partial reveal accumulates on top of prior retained votes (votesA + votesB + seats_drawn = PanelSize)
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
          IN
          /\ votesA' = nA
          /\ votesB' = nB
          /\ votesUnrevealed' = dUnrev
          /\ voted' = TRUE
          /\ verdict' = IF (nA + nB >= Q_arb) /\ (nA > nB) THEN "FOR_A"
                        ELSE IF (nA + nB >= Q_arb) /\ (nB > nA) THEN "FOR_B"
                        ELSE "NO_DECISION"
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, seats_drawn, r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, balArb, balTreasury, escrowBuyer, escrowSeller, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

\* E3: Partial redraw replaces ONLY UNREVEALED seats (or full reset if all revealed and tied)
RedrawPanel ==
  /\ state = "DISPUTE"
  /\ voted = TRUE
  /\ verdict = "NO_DECISION"
  /\ t_now + T_commit + T_reveal <= dispute_open_t + T_dispute_max
  /\ attempt' = attempt + 1
  /\ attempt_open_t' = t_now
  /\ panel_formed' = FALSE
  /\ committed' = FALSE
  /\ voted' = FALSE
  /\ verdict' = "NONE"
  /\ IF votesUnrevealed > 0
     THEN /\ seats_drawn' = votesUnrevealed
          /\ UNCHANGED <<votesA, votesB>>
          \* Slash ONLY unrevealed seats by ArbUnrevPenalty (E3) -> Treasury; keep revealed stakes locked in escrowArbCurr!
          /\ LET unrevSlash == votesUnrevealed * ArbUnrevPenalty
                 unrevRemain == votesUnrevealed * (ArbStake - ArbUnrevPenalty)
             IN
             /\ balArb' = balArb + unrevRemain
             /\ balTreasury' = balTreasury + unrevSlash
             /\ escrowArbCurr' = escrowArbCurr - (votesUnrevealed * ArbStake)
     ELSE \* Full tie with 0 unrevealed -> reset whole panel
          /\ seats_drawn' = PanelSize
          /\ votesA' = 0
          /\ votesB' = 0
          /\ balArb' = balArb + escrowArbCurr
          /\ escrowArbCurr' = 0
          /\ UNCHANGED balTreasury
  /\ votesUnrevealed' = 0
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, round,
               escalated, pool_sufficient, parent_pool_ok, r1_verdict,
               seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbR1>>

\* E1 Round 1 Timeout: 50/50 split of Amount, BOTH lose D_dispute (forfeited 2*D_dispute -> KeeperFee + arbs + Treasury)
TimeoutR1Split5050 ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ t_now >= dispute_open_t + T_dispute_max
  /\ (~voted \/ verdict = "NO_DECISION")
  /\ (escalated = TRUE \/ pool_sufficient = TRUE) \* if category pool failed, must escalate first unless parent also fails
  /\ state' = "RESOLVED"
  /\ verdict' = "SPLIT_50_50"
  /\ resolve_time' = t_now
  /\ payout_count' = payout_count + 1
  /\ LET halfA == Amount \div 2
         halfB == Amount - halfA
         forfeitA == IF escrowSeller >= DisputeDeposit THEN DisputeDeposit ELSE escrowSeller
         forfeitTot == escrowDispute + forfeitA
         kfee == KeeperFee
         rem == forfeitTot - kfee
         arbComp == rem \div 2
         treasShare == rem - arbComp
         unrevSlash == IF voted THEN votesUnrevealed * ArbUnrevPenalty ELSE 0
     IN
     /\ balA' = balA + halfA + (escrowSeller - forfeitA)
     /\ balB' = balB + halfB
     /\ balArb' = balArb + (escrowArbCurr - unrevSlash) + arbComp
     /\ balTreasury' = balTreasury + kfee + treasShare + unrevSlash
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ escrowArbCurr' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               r1_verdict, seller_delivered, buyer_honest, n04_delay_paid>>

\* E1 Round 2 Timeout: Round 1 verdict STANDS! Only AppealDeposit returned to appellant!
TimeoutR2KeepR1 ==
  /\ state = "DISPUTE"
  /\ round = 2
  /\ t_now >= dispute_open_t + T_dispute_max
  /\ (~voted \/ verdict = "NO_DECISION")
  /\ state' = "RESOLVED"
  /\ verdict' = "R1_UPHELD"
  /\ resolve_time' = t_now
  /\ payout_count' = payout_count + 1
  /\ LET unrevSlash == IF voted THEN votesUnrevealed * ArbUnrevPenalty ELSE 0 IN
     IF r1_verdict = "FOR_A"
     THEN /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
          /\ balB' = balB + escrowAppeal \* Appellant (party_b) gets AppealDeposit back
          /\ balArb' = balArb + escrowDispute + escrowArbR1 + (escrowArbCurr - unrevSlash)
          /\ balTreasury' = balTreasury + ProtocolFee + unrevSlash
     ELSE \* Symmetrized FOR_B: arbs get D_dispute_eq from SellerDeposit, buyer gets Penalty
          /\ balB' = balB + escrowBuyer + escrowDispute + Penalty
          /\ balA' = balA + escrowAppeal \* Appellant (party_a) gets AppealDeposit back
          /\ balArb' = balArb + (escrowSeller - Penalty) + escrowArbR1 + (escrowArbCurr - unrevSlash)
          /\ balTreasury' = balTreasury + unrevSlash
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ escrowArbCurr' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               r1_verdict, seller_delivered, buyer_honest, n04_delay_paid>>

\* Round 1 e_resolve -> APPEALABLE
ResolveRound1ToAppealable ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ voted = TRUE
  /\ verdict \in {"FOR_A", "FOR_B"}
  /\ state' = "APPEALABLE"
  /\ resolve_time' = t_now
  /\ r1_verdict' = verdict
  /\ LET majCount == IF verdict = "FOR_A" THEN votesA ELSE votesB
         minValid == (votesA + votesB) - majCount
         slashed == (minValid * ArbPenalty) + (votesUnrevealed * ArbUnrevPenalty)
         majStakes == majCount * ArbStake
         minRemainder == ((PanelSize - majCount) * ArbStake) - slashed
     IN
     /\ balArb' = balArb + minRemainder
     /\ escrowArbR1' = majStakes + slashed
     /\ escrowArbCurr' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balA, balB, balTreasury, escrowBuyer, escrowSeller, escrowDispute, escrowAppeal>>

Appeal ==
  /\ state = "APPEALABLE"
  /\ round = 1
  /\ t_now < resolve_time + T_appeal
  /\ state' = "DISPUTE"
  /\ round' = 2
  /\ escalated' = FALSE
  /\ attempt' = 1
  /\ dispute_open_t' = t_now
  /\ attempt_open_t' = t_now
  /\ panel_formed' = FALSE
  /\ committed' = FALSE
  /\ voted' = FALSE
  /\ votesA' = 0
  /\ votesB' = 0
  /\ votesUnrevealed' = 0
  /\ seats_drawn' = PanelSize
  /\ verdict' = "NONE"
  /\ IF r1_verdict = "FOR_A"
     THEN /\ balB' = balB - AppealDeposit
          /\ balA' = balA
     ELSE /\ balA' = balA - AppealDeposit
          /\ balB' = balB
  /\ escrowAppeal' = AppealDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, pool_sufficient, parent_pool_ok,
               r1_verdict, seller_delivered, buyer_honest, payout_count, n04_delay_paid,
               balArb, balTreasury, escrowBuyer, escrowSeller, escrowDispute,
               escrowArbR1, escrowArbCurr>>

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
     ELSE \* Symmetrized FOR_B: SellerDeposit split Penalty to buyer, (SellerDeposit - Penalty) to arbs!
          /\ balB' = balB + escrowBuyer + escrowDispute + Penalty
          /\ balA' = balA
          /\ balTreasury' = balTreasury
          /\ balArb' = balArb + (escrowSeller - Penalty) + escrowArbR1
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest, n04_delay_paid, escrowArbCurr>>

\* Round 2 final resolution (N-04: DelayComp to R1 winner on uphold!)
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
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, attempt_open_t,
               round, escalated, attempt, panel_formed, pool_sufficient, parent_pool_ok,
               committed, voted, votesA, votesB, votesUnrevealed, seats_drawn,
               verdict, r1_verdict, seller_delivered, buyer_honest>>

TerminalStutter ==
  /\ state \in {"CLOSED", "EXPIRED", "RESOLVED"}
  /\ UNCHANGED vars

Next ==
  \/ Tick
  \/ Accept
  \/ CancelDraftByA
  \/ TimeoutDraft
  \/ Start
  \/ TimeoutLocked
  \/ Submit
  \/ TimeoutInProgress
  \/ Confirm
  \/ TimeoutReview
  \/ OpenDispute
  \/ FormPanel
  \/ EscalateToParent
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

\* ==================== INVARIANTS & PROPERTIES ====================

Inv_Conservation ==
  (balA + balB + balArb + balTreasury
   + escrowBuyer + escrowSeller + escrowDispute + escrowAppeal + escrowArbR1 + escrowArbCurr) = TotalInitial

Inv_NonNegativeBalances ==
  /\ balA >= 0 /\ balB >= 0 /\ balArb >= 0 /\ balTreasury >= 0
  /\ escrowBuyer >= 0 /\ escrowSeller >= 0 /\ escrowDispute >= 0
  /\ escrowAppeal >= 0 /\ escrowArbR1 >= 0 /\ escrowArbCurr >= 0

Inv_NoDoublePayout == payout_count <= 1

Inv_EscrowIntactNonTerminal ==
  (state \in {"LOCKED", "IN_PROGRESS", "REVIEW", "DISPUTE", "APPEALABLE"})
    => (escrowBuyer = Amount /\ escrowSeller = SellerDeposit /\ payout_count = 0)

Inv_EscrowEmptyTerminal ==
  (state \in {"CLOSED", "EXPIRED", "RESOLVED"})
    => (escrowBuyer = 0 /\ escrowSeller = 0 /\ escrowDispute = 0
        /\ escrowAppeal = 0 /\ escrowArbR1 = 0 /\ escrowArbCurr = 0)

Inv_NoZeroVoteWin ==
  (state \in {"APPEALABLE", "RESOLVED"} /\ verdict \in {"FOR_A", "FOR_B"})
    => ((votesA + votesB >= Q_arb) /\ (votesA /= votesB)
        /\ (verdict = "FOR_A" => votesA > 0) /\ (verdict = "FOR_B" => votesB > 0))

Inv_NoDeadlineRace ==
  /\ ((state = "LOCKED" /\ t_now >= Deadline) => ~(t_now < Deadline))
  /\ ((state = "REVIEW" /\ submit_time >= 0 /\ t_now >= submit_time + T_review) => ~(t_now < submit_time + T_review))
  /\ ((submit_time >= 0) => (submit_time < Deadline))
  /\ ((dispute_open_t >= 0 /\ round = 1 /\ submit_time >= 0) => (dispute_open_t < submit_time + T_review))

Inv_NoSimultaneousEnablement ==
  /\ ~(ENABLED Start /\ ENABLED TimeoutLocked)
  /\ ~(ENABLED Submit /\ ENABLED TimeoutInProgress)
  /\ ~(ENABLED Confirm /\ ENABLED TimeoutReview)
  /\ ~(ENABLED OpenDispute /\ ENABLED TimeoutReview)
  /\ ~(ENABLED Appeal /\ ENABLED FinalizeAppealable)

\* E1 Round 2 must NEVER split 50/50, and N-01 buyer appeal timeout never refunds Amount when r1_verdict = FOR_A
Inv_E1Round2NeverSplits5050 ==
  (round = 2 /\ state = "RESOLVED") => (verdict /= "SPLIT_50_50")

Inv_N01Round2NoBuyerProfit ==
  (round = 2 /\ verdict = "R1_UPHELD" /\ r1_verdict = "FOR_A") => (balB = InitBuyer - Amount - DisputeDeposit)

\* N-08: CancelDraftByA cannot fire at t_now = 0
Inv_N08CancelGrace ==
  (state = "EXPIRED" /\ t_now < T_cancel_grace) => FALSE

Prop_EventuallyTerminal ==
  <>(state \in {"CLOSED", "EXPIRED", "RESOLVED"})

Prop_DisputeAndAppealableExit ==
  /\ [](state = "DISPUTE" => <>(state \in {"APPEALABLE", "RESOLVED"}))
  /\ [](state = "APPEALABLE" => <>(state \in {"DISPUTE", "RESOLVED"}))

=============================================================================
