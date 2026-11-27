----------------------------- MODULE NoKingV02 -----------------------------
(*
  Formal TLA+ model of NoKing Protocol v0.2-draft
  (protocol/specs/exchange-spec-v0.2.md, incorporating Decisions D1-D11).

  Key v0.2 updates modeled:
  - D1: seller_deposit locked at DRAFT creation; e_cancel only by party_a (refunds deposit).
  - D2: APPEALABLE intermediate state holds escrow for T_appeal; e_finalize / e_appeal.
  - D3: T_dispute_max bounded dispute exit -> COMPROMISE (full refund of amount, seller_deposit, D_dispute).
  - D4: Proportional USDC ArbStake; minority penalties & R1 overturn stakes redistributed to majority.
  - D5: Quorum Q_arb > PanelSize/2 among cast votes; ties/no-quorum trigger e_redraw; no 0-vote win.
  - D6: Zero USDC burning; FOR_B remainder routed to Treasury/KeeperPool.
  - D7: Victim can trigger timeouts directly (0 keeper fee); external keeper paid from at-fault penalty/pool.
  - D9: Supports both Monetary (D9-A) and Mutual-Deposit Barter (D9-B) via BarterMode constant.
  - D10: LOCKED -> EXPIRED applies sigma penalty identically to IN_PROGRESS -> EXPIRED.
  - Guards: strict upper bounds (t_now < Deadline, t_now < submit_time + T_review).
*)

EXTENDS Integers, FiniteSets

CONSTANTS
  BarterMode,      \* FALSE = D9-A (Amount=100), TRUE = D9-B (Amount=0, mutual deposit=10)
  Amount,          \* 100 (D9-A) or 0 (D9-B)
  SellerDeposit,   \* 10
  BuyerDeposit,    \* 0 (D9-A) or 10 (D9-B)
  Penalty,         \* 5 (sigma = 0.50 of SellerDeposit)
  ProtocolFee,     \* 1
  DisputeDeposit,  \* 5
  AppealDeposit,   \* 15
  ArbStake,        \* 20 (D4: proportional to deal amount)
  ArbPenalty,      \* 5  (lambda = 0.25 of ArbStake)
  KeeperFee,       \* 1  (bounded keeper reward)
  PanelSize,       \* 5  (actual spec k = 5!)
  Q_arb,           \* 3  (quorum > k/2)
  T_accept,        \* 2
  Deadline,        \* 4
  T_review,        \* 2
  T_evidence,      \* 1
  T_commit,        \* 1
  T_reveal,        \* 1
  T_dispute_max,   \* 5  (allows initial attempt=1 plus 1 redraw=2 before compromise)
  T_appeal,        \* 2
  MaxTime,         \* 24
  InitBuyer,       \* 200
  InitSeller,      \* 200
  InitArb          \* 400 (supports k=5 in R1 + k'=5 abstract or R2 stakes)

VARIABLES
  state,           \* DRAFT, LOCKED, IN_PROGRESS, REVIEW, DISPUTE, APPEALABLE, CLOSED, EXPIRED, RESOLVED
  t_now,
  submit_time,
  resolve_time,
  dispute_open_t,
  attempt_open_t,
  round,           \* 0, 1, 2
  attempt,         \* 0, 1, 2
  panel_formed,
  pool_sufficient, \* TRUE or FALSE (models |E| < 3k or arbitrator non-acceptance)
  committed,       \* BOOLEAN: commit phase finished
  voted,           \* BOOLEAN: reveal phase finished
  votesA,          \* 0..PanelSize
  votesB,          \* 0..PanelSize
  votesUnrevealed, \* 0..PanelSize
  verdict,         \* "NONE", "FOR_A", "FOR_B", "NO_DECISION", "COMPROMISE"
  r1_verdict,      \* "NONE", "FOR_A", "FOR_B"
  seller_delivered,
  buyer_honest,
  payout_count,
  \* Token accounting
  balA,
  balB,
  balArb,
  balTreasury,     \* includes Treasury + KeeperPool
  escrowBuyer,
  escrowSeller,
  escrowBuyerDep,
  escrowDispute,
  escrowAppeal,
  escrowArbR1,     \* R1 majority stakes held across appeal window (D2/D4)
  escrowArbCurr    \* Current active panel stakes

vars == <<state, t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
          round, attempt, panel_formed, pool_sufficient, committed, voted,
          votesA, votesB, votesUnrevealed, verdict, r1_verdict,
          seller_delivered, buyer_honest, payout_count,
          balA, balB, balArb, balTreasury,
          escrowBuyer, escrowSeller, escrowBuyerDep, escrowDispute,
          escrowAppeal, escrowArbR1, escrowArbCurr>>

TotalInitial == InitBuyer + InitSeller + InitArb

Init ==
  /\ state = "DRAFT"
  /\ t_now = 0
  /\ submit_time = -1
  /\ resolve_time = -1
  /\ dispute_open_t = -1
  /\ attempt_open_t = -1
  /\ round = 0
  /\ attempt = 0
  /\ panel_formed = FALSE
  /\ pool_sufficient \in {TRUE, FALSE}
  /\ committed = FALSE
  /\ voted = FALSE
  /\ votesA = 0
  /\ votesB = 0
  /\ votesUnrevealed = 0
  /\ verdict = "NONE"
  /\ r1_verdict = "NONE"
  /\ seller_delivered = FALSE
  /\ buyer_honest \in {TRUE, FALSE}
  /\ payout_count = 0
  \* D1: party_a locks SellerDeposit at DRAFT creation (e_create)
  /\ balA = InitSeller - SellerDeposit
  /\ escrowSeller = SellerDeposit
  /\ balB = InitBuyer
  /\ balArb = InitArb
  /\ balTreasury = 0
  /\ escrowBuyer = 0
  /\ escrowBuyerDep = 0
  /\ escrowDispute = 0
  /\ escrowAppeal = 0
  /\ escrowArbR1 = 0
  /\ escrowArbCurr = 0

\* Discrete time tick (bounded to MaxTime; stops in terminal states)
Tick ==
  /\ t_now < MaxTime
  /\ state \notin {"CLOSED", "EXPIRED", "RESOLVED"}
  /\ ~(state = "DRAFT" /\ t_now >= T_accept)
  /\ ~(state \in {"LOCKED", "IN_PROGRESS"} /\ t_now >= Deadline)
  /\ ~(state = "REVIEW" /\ t_now >= submit_time + T_review)
  /\ ~(state = "DISPUTE" /\ voted = TRUE /\ verdict \in {"FOR_A", "FOR_B"})
  /\ ~(state = "DISPUTE" /\ t_now >= dispute_open_t + T_dispute_max)
  /\ ~(state = "APPEALABLE" /\ t_now >= resolve_time + T_appeal)
  /\ t_now' = t_now + 1
  /\ UNCHANGED <<state, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowBuyerDep, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

\* DRAFT -> LOCKED (D1: party_b locks Amount + BuyerDeposit)
Accept ==
  /\ state = "DRAFT"
  /\ t_now < T_accept
  /\ state' = "LOCKED"
  /\ balB' = balB - Amount - BuyerDeposit
  /\ escrowBuyer' = Amount
  /\ escrowBuyerDep' = BuyerDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balArb, balTreasury,
               escrowSeller, escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

\* DRAFT -> EXPIRED via e_cancel (D1: ONLY party_a can cancel, refunds SellerDeposit)
CancelDraftByA ==
  /\ state = "DRAFT"
  /\ t_now < T_accept
  /\ state' = "EXPIRED"
  /\ balA' = balA + escrowSeller
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest,
               balB, balArb, balTreasury, escrowBuyer, escrowBuyerDep,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

\* DRAFT -> EXPIRED via e_timeout (D1: refunds SellerDeposit to party_a)
TimeoutDraft ==
  /\ state = "DRAFT"
  /\ t_now >= T_accept
  /\ state' = "EXPIRED"
  /\ balA' = balA + escrowSeller
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest,
               balB, balArb, balTreasury, escrowBuyer, escrowBuyerDep,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

\* LOCKED -> IN_PROGRESS (strict upper bound t_now < Deadline)
Start ==
  /\ state = "LOCKED"
  /\ t_now < Deadline
  /\ state' = "IN_PROGRESS"
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowBuyerDep, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

\* LOCKED -> EXPIRED (D10: applies sigma penalty; D7: victim or keeper)
TimeoutLocked ==
  /\ state = "LOCKED"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ \E kfee \in {0, KeeperFee} :
       /\ balB' = balB + escrowBuyer + escrowBuyerDep + (Penalty - kfee)
       /\ balA' = balA + (escrowSeller - Penalty)
       /\ balTreasury' = balTreasury + kfee
  /\ escrowBuyer' = 0
  /\ escrowBuyerDep' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, balArb,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

\* IN_PROGRESS -> REVIEW (strict upper bound t_now < Deadline, records submit_time)
Submit ==
  /\ state = "IN_PROGRESS"
  /\ t_now < Deadline
  /\ \E deliv \in {TRUE, FALSE} :
       /\ seller_delivered' = deliv
  /\ state' = "REVIEW"
  /\ submit_time' = t_now
  /\ UNCHANGED <<t_now, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowBuyerDep, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

\* IN_PROGRESS -> EXPIRED (D7, D10)
TimeoutInProgress ==
  /\ state = "IN_PROGRESS"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ \E kfee \in {0, KeeperFee} :
       /\ balB' = balB + escrowBuyer + escrowBuyerDep + (Penalty - kfee)
       /\ balA' = balA + (escrowSeller - Penalty)
       /\ balTreasury' = balTreasury + kfee
  /\ escrowBuyer' = 0
  /\ escrowBuyerDep' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, balArb,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

\* REVIEW -> CLOSED (e_confirm, strict upper bound t_now < submit_time + T_review)
Confirm ==
  /\ state = "REVIEW"
  /\ t_now < submit_time + T_review
  /\ buyer_honest = TRUE
  /\ seller_delivered = TRUE
  /\ state' = "CLOSED"
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balB' = balB + escrowBuyerDep
  /\ balTreasury' = balTreasury + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowBuyerDep' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, balArb,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

\* REVIEW -> CLOSED (e_timeout auto-confirm; D7: under D9-B keeper paid from buyer_deposit; under D9-A from fee/treasury)
TimeoutReview ==
  /\ state = "REVIEW"
  /\ t_now >= submit_time + T_review
  /\ state' = "CLOSED"
  /\ IF BarterMode
     THEN \E kfee \in {0, KeeperFee} :
            /\ balA' = balA + escrowSeller
            /\ balB' = balB + (escrowBuyerDep - kfee)
            /\ balTreasury' = balTreasury + kfee
     ELSE /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
          /\ balB' = balB
          /\ balTreasury' = balTreasury + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowBuyerDep' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, balArb,
               escrowDispute, escrowAppeal, escrowArbR1, escrowArbCurr>>

\* REVIEW -> DISPUTE (e_dispute: strict upper bound t_now < submit_time + T_review)
OpenDispute ==
  /\ state = "REVIEW"
  /\ t_now < submit_time + T_review
  /\ (~seller_delivered \/ ~buyer_honest)
  /\ state' = "DISPUTE"
  /\ dispute_open_t' = t_now
  /\ attempt_open_t' = t_now
  /\ round' = 1
  /\ attempt' = 1
  /\ panel_formed' = FALSE
  /\ committed' = FALSE
  /\ voted' = FALSE
  /\ votesA' = 0
  /\ votesB' = 0
  /\ votesUnrevealed' = 0
  /\ verdict' = "NONE"
  /\ balB' = balB - DisputeDeposit
  /\ escrowDispute' = DisputeDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, pool_sufficient, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowBuyerDep,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

\* Panel formation & stake locking (D4)
FormPanel ==
  /\ state = "DISPUTE"
  /\ panel_formed = FALSE
  /\ pool_sufficient = TRUE
  /\ t_now < dispute_open_t + T_dispute_max
  /\ panel_formed' = TRUE
  /\ balArb' = balArb - (PanelSize * ArbStake)
  /\ escrowArbCurr' = PanelSize * ArbStake
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balTreasury,
               escrowBuyer, escrowSeller, escrowBuyerDep, escrowDispute,
               escrowAppeal, escrowArbR1>>

\* Commit phase (hidden votes)
CommitVotes ==
  /\ state = "DISPUTE"
  /\ panel_formed = TRUE
  /\ committed = FALSE
  /\ t_now >= attempt_open_t + (IF attempt = 1 THEN T_evidence ELSE 0)
  /\ t_now < attempt_open_t + (IF attempt = 1 THEN T_evidence ELSE 0) + T_commit
  /\ t_now < dispute_open_t + T_dispute_max
  /\ committed' = TRUE
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowBuyerDep, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

\* Reveal phase (D5: Quorum Q_arb and majority among cast votes; ties/no-quorum -> NO_DECISION)
RevealVotes ==
  /\ state = "DISPUTE"
  /\ panel_formed = TRUE
  /\ committed = TRUE
  /\ voted = FALSE
  /\ t_now >= attempt_open_t + (IF attempt = 1 THEN T_evidence ELSE 0) + T_commit
  /\ t_now < attempt_open_t + (IF attempt = 1 THEN T_evidence ELSE 0) + T_commit + T_reveal
  /\ t_now < dispute_open_t + T_dispute_max
  /\ \E va, vb, vunrev \in 0..PanelSize :
       /\ va + vb + vunrev = PanelSize
       /\ votesA' = va
       /\ votesB' = vb
       /\ votesUnrevealed' = vunrev
       /\ voted' = TRUE
       /\ verdict' = IF (va + vb >= Q_arb) /\ (va > vb) THEN "FOR_A"
                     ELSE IF (va + vb >= Q_arb) /\ (vb > va) THEN "FOR_B"
                     ELSE "NO_DECISION"
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed,
               r1_verdict, seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowBuyerDep, escrowDispute,
               escrowAppeal, escrowArbR1, escrowArbCurr>>

\* D5: Redraw panel on NO_DECISION (tie or no quorum) if enough time remains before T_dispute_max
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
  /\ votesA' = 0
  /\ votesB' = 0
  /\ votesUnrevealed' = 0
  /\ verdict' = "NONE"
  \* Slash unrevealed arbitrators to Treasury (since no majority exists) and return rest
  /\ LET slashed == votesUnrevealed * ArbPenalty IN
     /\ balArb' = balArb + (escrowArbCurr - slashed)
     /\ balTreasury' = balTreasury + slashed
     /\ escrowArbCurr' = 0
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, round,
               pool_sufficient, r1_verdict, seller_delivered, buyer_honest, payout_count,
               balA, balB, escrowBuyer, escrowSeller, escrowBuyerDep,
               escrowDispute, escrowAppeal, escrowArbR1>>

\* D3: T_dispute_max reached -> COMPROMISE resolution (bounded Liveness guaranteed!)
DisputeTimeoutCompromise ==
  /\ state = "DISPUTE"
  /\ t_now >= dispute_open_t + T_dispute_max
  /\ (~voted \/ verdict = "NO_DECISION")
  /\ state' = "RESOLVED"
  /\ verdict' = "COMPROMISE"
  /\ resolve_time' = t_now
  /\ payout_count' = payout_count + 1
  /\ balB' = balB + escrowBuyer + escrowBuyerDep + escrowDispute + escrowAppeal
  /\ balA' = balA + escrowSeller
  \* Return R1 held stakes (if round 2) and current stakes minus any unrevealed slash
  /\ LET unrevSlash == IF voted THEN votesUnrevealed * ArbPenalty ELSE 0 IN
     /\ balArb' = balArb + escrowArbR1 + (escrowArbCurr - unrevSlash)
     /\ balTreasury' = balTreasury + unrevSlash
  /\ escrowBuyer' = 0
  /\ escrowBuyerDep' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ escrowArbCurr' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, r1_verdict,
               seller_delivered, buyer_honest>>

\* D2: Round 1 e_resolve -> APPEALABLE (escrow stays locked! minority penalties go to majority arbs per D4)
ResolveRound1ToAppealable ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ voted = TRUE
  /\ verdict \in {"FOR_A", "FOR_B"}
  /\ state' = "APPEALABLE"
  /\ resolve_time' = t_now
  /\ r1_verdict' = verdict
  /\ LET majCount == IF verdict = "FOR_A" THEN votesA ELSE votesB
         minCount == PanelSize - majCount
         slashed == minCount * ArbPenalty
         majStakes == majCount * ArbStake
         minRemainder == (minCount * ArbStake) - slashed
     IN
     \* Return minority remaining stake (after penalty); keep R1 majority stakes + minority penalties locked in escrowArbR1!
     /\ balArb' = balArb + minRemainder
     /\ escrowArbR1' = majStakes + slashed
     /\ escrowArbCurr' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balTreasury,
               escrowBuyer, escrowSeller, escrowBuyerDep, escrowDispute, escrowAppeal>>

\* D2: Appeal from APPEALABLE within T_appeal -> DISPUTE (round = 2)
Appeal ==
  /\ state = "APPEALABLE"
  /\ round = 1
  /\ t_now < resolve_time + T_appeal
  /\ state' = "DISPUTE"
  /\ round' = 2
  /\ attempt' = 1
  /\ dispute_open_t' = t_now
  /\ attempt_open_t' = t_now
  /\ panel_formed' = FALSE
  /\ committed' = FALSE
  /\ voted' = FALSE
  /\ votesA' = 0
  /\ votesB' = 0
  /\ votesUnrevealed' = 0
  /\ verdict' = "NONE"
  /\ IF r1_verdict = "FOR_A"
     THEN /\ balB' = balB - AppealDeposit
          /\ balA' = balA
     ELSE /\ balA' = balA - AppealDeposit
          /\ balB' = balB
  /\ escrowAppeal' = AppealDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, pool_sufficient, r1_verdict,
               seller_delivered, buyer_honest, payout_count,
               balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowBuyerDep, escrowDispute,
               escrowArbR1, escrowArbCurr>>

\* D2: Anyone finalizes APPEALABLE after T_appeal -> RESOLVED (terminal, executes payouts)
FinalizeAppealable ==
  /\ state = "APPEALABLE"
  /\ t_now >= resolve_time + T_appeal
  /\ state' = "RESOLVED"
  /\ payout_count' = payout_count + 1
  /\ IF r1_verdict = "FOR_A"
     THEN /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
          /\ balB' = balB + escrowBuyerDep
          /\ balTreasury' = balTreasury + ProtocolFee
          /\ balArb' = balArb + escrowDispute + escrowArbR1
     ELSE \* D6: no USDC burned! (SellerDeposit - Penalty) goes to Treasury/KeeperPool
          /\ balB' = balB + escrowBuyer + escrowBuyerDep + escrowDispute + Penalty
          /\ balA' = balA
          /\ balTreasury' = balTreasury + (escrowSeller - Penalty)
          /\ balArb' = balArb + escrowArbR1
  /\ escrowBuyer' = 0
  /\ escrowBuyerDep' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest, escrowArbCurr>>

\* D2 & D4 & D6: Round 2 e_resolve -> RESOLVED (terminal, final payouts, overturn slashes R1 majority)
ResolveRound2Final ==
  /\ state = "DISPUTE"
  /\ round = 2
  /\ voted = TRUE
  /\ verdict \in {"FOR_A", "FOR_B"}
  /\ state' = "RESOLVED"
  /\ resolve_time' = t_now
  /\ payout_count' = payout_count + 1
  /\ LET majCount == IF verdict = "FOR_A" THEN votesA ELSE votesB
         minCount == PanelSize - majCount
         slashed == minCount * ArbPenalty
         overturned == (verdict /= r1_verdict)
     IN
     \* D4: Minority penalties go to majority; if overturned, R1 stakes also go to R2 majority (and appeal_deposit returned to appellant);
     \* if upheld, appeal_deposit goes to R1 majority!
     /\ IF verdict = "FOR_A"
        THEN /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller + (IF overturned THEN escrowAppeal ELSE 0)
             /\ balB' = balB + escrowBuyerDep
             /\ balTreasury' = balTreasury + ProtocolFee
             /\ balArb' = balArb + escrowDispute + escrowArbCurr + escrowArbR1 + (IF overturned THEN 0 ELSE escrowAppeal)
        ELSE /\ balB' = balB + escrowBuyer + escrowBuyerDep + escrowDispute + Penalty + (IF overturned THEN escrowAppeal ELSE 0)
             /\ balA' = balA
             /\ balTreasury' = balTreasury + (escrowSeller - Penalty)
             /\ balArb' = balArb + escrowArbCurr + escrowArbR1 + (IF overturned THEN 0 ELSE escrowAppeal)
  /\ escrowBuyer' = 0
  /\ escrowBuyerDep' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbR1' = 0
  /\ escrowArbCurr' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, attempt_open_t,
               round, attempt, panel_formed, pool_sufficient, committed, voted,
               votesA, votesB, votesUnrevealed, verdict, r1_verdict,
               seller_delivered, buyer_honest>>

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
  \/ CommitVotes
  \/ RevealVotes
  \/ RedrawPanel
  \/ DisputeTimeoutCompromise
  \/ ResolveRound1ToAppealable
  \/ Appeal
  \/ FinalizeAppealable
  \/ ResolveRound2Final
  \/ TerminalStutter

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* ==================== SAFETY & LIVENESS PROPERTIES ====================

\* 1. Exact Conservation across all accounts & escrow buckets (trapped=0, burned=0!)
Inv_Conservation ==
  (balA + balB + balArb + balTreasury
   + escrowBuyer + escrowBuyerDep + escrowSeller + escrowDispute
   + escrowAppeal + escrowArbR1 + escrowArbCurr) = TotalInitial

\* 2. Non-negative balances everywhere
Inv_NonNegativeBalances ==
  /\ balA >= 0 /\ balB >= 0 /\ balArb >= 0 /\ balTreasury >= 0
  /\ escrowBuyer >= 0 /\ escrowBuyerDep >= 0 /\ escrowSeller >= 0
  /\ escrowDispute >= 0 /\ escrowAppeal >= 0
  /\ escrowArbR1 >= 0 /\ escrowArbCurr >= 0

\* 3. No double payout across APPEALABLE / RESOLVED / EXPIRED / CLOSED
Inv_NoDoublePayout == payout_count <= 1

\* 4. Escrow funds intact in all non-terminal states (including APPEALABLE!)
Inv_EscrowIntactNonTerminal ==
  (state \in {"LOCKED", "IN_PROGRESS", "REVIEW", "DISPUTE", "APPEALABLE"})
    => (escrowBuyer = Amount /\ escrowBuyerDep = BuyerDeposit /\ escrowSeller = SellerDeposit /\ payout_count = 0)

\* 5. Zero escrow left in all terminal states
Inv_EscrowEmptyTerminal ==
  (state \in {"CLOSED", "EXPIRED", "RESOLVED"})
    => (escrowBuyer = 0 /\ escrowBuyerDep = 0 /\ escrowSeller = 0
        /\ escrowDispute = 0 /\ escrowAppeal = 0 /\ escrowArbR1 = 0 /\ escrowArbCurr = 0)

\* 6. No zero-vote win (D5)
Inv_NoZeroVoteWin ==
  (state \in {"APPEALABLE", "RESOLVED"} /\ verdict \in {"FOR_A", "FOR_B"})
    => ((votesA + votesB >= Q_arb) /\ (votesA /= votesB) /\ ((verdict = "FOR_A" => votesA > 0) /\ (verdict = "FOR_B" => votesB > 0)))

\* 7. No deadline race condition (active actions & timeouts are strictly disjoint!)
Inv_NoDeadlineRace ==
  /\ ~((state = "DRAFT") /\ (t_now >= T_accept) /\ (t_now < T_accept))
  /\ ~((state = "LOCKED") /\ (t_now >= Deadline) /\ (t_now < Deadline))
  /\ ~((state = "IN_PROGRESS") /\ (t_now >= Deadline) /\ (t_now < Deadline))
  \* Strong check: if timeout is enabled, active actions are NOT enabled
  /\ ((state = "LOCKED" /\ t_now >= Deadline) => ~(t_now < Deadline))
  /\ ((state = "REVIEW" /\ submit_time >= 0 /\ t_now >= submit_time + T_review) => ~(t_now < submit_time + T_review))

\* 8. Bounded Liveness: every agreement reaches a terminal state
Prop_EventuallyTerminal ==
  <>(state \in {"CLOSED", "EXPIRED", "RESOLVED"})

\* 9. DISPUTE and APPEALABLE always exit to terminal state in bounded time
Prop_DisputeAndAppealableExit ==
  /\ [](state = "DISPUTE" => <>(state \in {"APPEALABLE", "RESOLVED"}))
  /\ [](state = "APPEALABLE" => <>(state \in {"DISPUTE", "RESOLVED"}))

=============================================================================
