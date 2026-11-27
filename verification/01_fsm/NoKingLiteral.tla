--------------------------- MODULE NoKingLiteral ---------------------------
(*
  Formal TLA+ model of the LITERAL NoKing Protocol specification
  (protocol/specs/exchange-spec.md, v0.1-draft).

  Models:
  - Buyer (party_b), Seller (party_a), Keeper, Abstract Arbitration Panel
  - Discrete time t_now \in 0..MaxTime
  - Exact escrow & participant token accounting (integers, scaled: Amount=100)
  - Adversarial actions:
      * Seller may fail to start/deliver or submit fake evidence
      * Buyer may refuse to confirm or open a frivolous dispute
      * Arbitrators may abstain, or vote FOR_A / FOR_B (even erroneously)
      * Eligible pool |E| may be insufficient (< k * 3) for panel formation
      * Appeal in round 1 -> 2 after e_resolve (Sec 5.6 vs Sec 3.3 contradiction)
*)

EXTENDS Integers, FiniteSets

CONSTANTS
  Amount,          \* 100
  SellerDeposit,   \* 10 (alpha = 0.10)
  Penalty,         \* 5  (sigma = 0.50 of SellerDeposit)
  ProtocolFee,     \* 1  (phi = 0.01)
  DisputeDeposit,  \* 5  (5% of Amount)
  AppealDeposit,   \* 15 (3x DisputeDeposit)
  ArbStake,        \* 10 (unspecified in Sec 9; parameterized)
  ArbPenalty,      \* 2  (lambda = 0.25 -> 2 here for integers)
  ArbReward,       \* 1  (unspecified in Sec 9; parameterized)
  PanelSize,       \* 3  (abstract odd k; spec default k=5)
  T_accept,        \* 2
  Deadline,        \* 5
  T_review,        \* 2
  T_evidence,      \* 2
  T_vote,          \* 2
  T_appeal,        \* 2
  MaxTime,         \* 14
  InitBuyer,       \* 200
  InitSeller,      \* 200
  InitArb,         \* 100
  DraftDepositAtCreate \* TRUE models Sec 4.3 implication; FALSE models Sec 4.1

VARIABLES
  state,           \* Agreement state: DRAFT, LOCKED, IN_PROGRESS, REVIEW, CLOSED, EXPIRED, DISPUTE, RESOLVED
  t_now,           \* Current block timestamp
  submit_time,     \* Timestamp of e_submit (-1 if unset)
  resolve_time,    \* Timestamp of e_resolve (-1 if unset)
  dispute_open_t,  \* Timestamp when dispute opened (-1 if unset)
  round,           \* 0 (no dispute), 1 (first instance), 2 (appeal)
  panel_formed,    \* BOOLEAN
  pool_sufficient, \* BOOLEAN: models whether |Eligible(c)| >= k*3 (or 3k+2 * 3)
  votesA,          \* 0..PanelSize
  votesB,          \* 0..PanelSize
  votesAbstain,    \* 0..PanelSize
  voted,           \* BOOLEAN: panel finished voting
  seller_delivered,\* BOOLEAN: ground truth whether Seller honestly delivered
  buyer_honest,    \* BOOLEAN: ground truth whether Buyer acts honestly
  payout_count,    \* Number of times primary escrow payout executed
  \* Token accounting
  balA,            \* party_a wallet balance
  balB,            \* party_b wallet balance
  balArb,          \* aggregate arbitrator wallet balance (incl. arbiter pool)
  balTreasury,     \* protocol treasury
  escrowBuyer,     \* buyer's locked Amount
  escrowSeller,    \* seller's locked SellerDeposit
  escrowDispute,   \* locked DisputeDeposit
  escrowAppeal,    \* locked AppealDeposit
  escrowArbStake,  \* locked arbitrator stakes
  trappedFunds,    \* funds stuck/orphaned with no defined recipient in spec
  burnedFunds,     \* stablecoin "burned" (Sec 5.5 FOR_B)
  doublePayoutErr  \* TRUE if contract attempts payout exceeding locked escrow

vars == <<state, t_now, submit_time, resolve_time, dispute_open_t, round,
          panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
          seller_delivered, buyer_honest, payout_count,
          balA, balB, balArb, balTreasury,
          escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
          escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

TotalInitial == InitBuyer + InitSeller + InitArb

Init ==
  /\ state = "DRAFT"
  /\ t_now = 0
  /\ submit_time = -1
  /\ resolve_time = -1
  /\ dispute_open_t = -1
  /\ round = 0
  /\ panel_formed = FALSE
  /\ pool_sufficient \in {TRUE, FALSE}
  /\ votesA = 0
  /\ votesB = 0
  /\ votesAbstain = 0
  /\ voted = FALSE
  /\ seller_delivered = FALSE
  /\ buyer_honest \in {TRUE, FALSE}
  /\ payout_count = 0
  /\ balB = InitBuyer
  /\ balArb = InitArb
  /\ balTreasury = 0
  /\ escrowBuyer = 0
  /\ escrowDispute = 0
  /\ escrowAppeal = 0
  /\ escrowArbStake = 0
  /\ trappedFunds = 0
  /\ burnedFunds = 0
  /\ doublePayoutErr = FALSE
  /\ IF DraftDepositAtCreate
     THEN /\ balA = InitSeller - SellerDeposit
          /\ escrowSeller = SellerDeposit
     ELSE /\ balA = InitSeller
          /\ escrowSeller = 0

\* Time advances
Tick ==
  /\ t_now < MaxTime
  /\ t_now' = t_now + 1
  /\ UNCHANGED <<state, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* DRAFT -> LOCKED (e_accept, Sec 3.3 & 4.1)
Accept ==
  /\ state = "DRAFT"
  /\ t_now < T_accept
  /\ state' = "LOCKED"
  /\ balB' = balB - Amount
  /\ escrowBuyer' = Amount
  /\ IF DraftDepositAtCreate
     THEN /\ UNCHANGED <<balA, escrowSeller>>
     ELSE /\ balA' = balA - SellerDeposit
          /\ escrowSeller' = SellerDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest, payout_count,
               balArb, balTreasury, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* DRAFT -> EXPIRED (e_timeout, Sec 3.3 & 4.3)
TimeoutDraft ==
  /\ state = "DRAFT"
  /\ t_now >= T_accept
  /\ state' = "EXPIRED"
  /\ IF DraftDepositAtCreate
     THEN /\ balA' = balA + escrowSeller
          /\ escrowSeller' = 0
     ELSE UNCHANGED <<balA, escrowSeller>>
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest, payout_count,
               balB, balArb, balTreasury, escrowBuyer, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* DRAFT -> EXPIRED (e_cancel, Sec 3.3; Sec 4 does not specify deposit refund on cancel!)
CancelDraft ==
  /\ state = "DRAFT"
  /\ state' = "EXPIRED"
  /\ IF DraftDepositAtCreate
     THEN \* Spec omits distribution on e_cancel! Modeled as trapped if not specified
          /\ trappedFunds' = trappedFunds + escrowSeller
          /\ escrowSeller' = 0
     ELSE UNCHANGED <<trappedFunds, escrowSeller>>
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury, escrowBuyer, escrowDispute, escrowAppeal,
               escrowArbStake, burnedFunds, doublePayoutErr>>

\* LOCKED -> IN_PROGRESS (e_start, Sec 3.3: note NO t_now < Deadline check in spec!)
Start ==
  /\ state = "LOCKED"
  /\ state' = "IN_PROGRESS"
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* LOCKED -> EXPIRED (e_timeout, Sec 3.3 line 180: "funds returned to party_b", omits penalty!)
TimeoutLocked ==
  /\ state = "LOCKED"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ balB' = balB + escrowBuyer
  /\ balA' = balA + escrowSeller
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest,
               balArb, balTreasury, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* IN_PROGRESS -> REVIEW (e_submit, Sec 3.3: note NO t_now < Deadline check in spec!)
SubmitHonest ==
  /\ state = "IN_PROGRESS"
  /\ state' = "REVIEW"
  /\ submit_time' = t_now
  /\ seller_delivered' = TRUE
  /\ UNCHANGED <<t_now, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

SubmitFake ==
  /\ state = "IN_PROGRESS"
  /\ state' = "REVIEW"
  /\ submit_time' = t_now
  /\ seller_delivered' = FALSE
  /\ UNCHANGED <<t_now, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* IN_PROGRESS -> EXPIRED (e_timeout, Sec 3.3 & 4.3)
TimeoutInProgress ==
  /\ state = "IN_PROGRESS"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ balB' = balB + escrowBuyer + Penalty
  /\ balA' = balA + (escrowSeller - Penalty)
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest,
               balArb, balTreasury, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* REVIEW -> CLOSED (e_confirm, Sec 3.3 & 4.2: note NO t_now < submit_time + T_review check!)
Confirm ==
  /\ state = "REVIEW"
  /\ buyer_honest = TRUE
  /\ seller_delivered = TRUE
  /\ state' = "CLOSED"
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balTreasury' = balTreasury + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest,
               balB, balArb, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* REVIEW -> CLOSED (e_timeout auto-confirmation, Sec 3.3 & 3.4)
TimeoutReview ==
  /\ state = "REVIEW"
  /\ submit_time >= 0
  /\ t_now >= submit_time + T_review
  /\ state' = "CLOSED"
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balTreasury' = balTreasury + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest,
               balB, balArb, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* REVIEW -> DISPUTE (e_dispute, Sec 3.3: note NO t_now < submit_time + T_review check!)
OpenDispute ==
  /\ state = "REVIEW"
  /\ (~seller_delivered \/ ~buyer_honest)
  /\ state' = "DISPUTE"
  /\ dispute_open_t' = t_now
  /\ round' = 1
  /\ panel_formed' = FALSE
  /\ voted' = FALSE
  /\ votesA' = 0
  /\ votesB' = 0
  /\ votesAbstain' = 0
  /\ balB' = balB - DisputeDeposit
  /\ escrowDispute' = DisputeDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, pool_sufficient,
               seller_delivered, buyer_honest, payout_count,
               balA, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* Algorithm 5.1: Panel formation (requires |E| >= k * 3; blocked if pool_sufficient = FALSE!)
FormPanel ==
  /\ state = "DISPUTE"
  /\ panel_formed = FALSE
  /\ pool_sufficient = TRUE
  /\ panel_formed' = TRUE
  /\ balArb' = balArb - (PanelSize * ArbStake)
  /\ escrowArbStake' = PanelSize * ArbStake
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, round,
               pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               trappedFunds, burnedFunds, doublePayoutErr>>

\* Arbitrators vote in VotingWindow (Def 5.2: includes ABSTAIN!)
CastVotes ==
  /\ state = "DISPUTE"
  /\ panel_formed = TRUE
  /\ voted = FALSE
  /\ t_now >= dispute_open_t + T_evidence
  /\ t_now < dispute_open_t + T_evidence + T_vote
  /\ \E va, vb, vabs \in 0..PanelSize :
       /\ va + vb + vabs = PanelSize
       /\ votesA' = va
       /\ votesB' = vb
       /\ votesAbstain' = vabs
       /\ voted' = TRUE
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* If vote window expires without votes, all abstain (Corollary 5.4)
VoteWindowExpired ==
  /\ state = "DISPUTE"
  /\ panel_formed = TRUE
  /\ voted = FALSE
  /\ t_now >= dispute_open_t + T_evidence + T_vote
  /\ votesA' = 0
  /\ votesB' = 0
  /\ votesAbstain' = PanelSize
  /\ voted' = TRUE
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* DISPUTE -> RESOLVED (e_resolve, Sec 5.4 & 5.5 literally)
ResolveDispute ==
  /\ state = "DISPUTE"
  /\ voted = TRUE
  /\ state' = "RESOLVED"
  /\ resolve_time' = t_now
  /\ LET winA == (votesA * 2 > PanelSize)
         majCount == IF winA THEN votesA ELSE votesB
         minCount == PanelSize - majCount
         slashed == minCount * ArbPenalty
     IN
     /\ IF escrowBuyer < Amount
        THEN \* Double payout attempt (e.g., after round 2 appeal!)
             /\ doublePayoutErr' = TRUE
             /\ UNCHANGED <<balA, balB, balArb, balTreasury, escrowBuyer, escrowSeller,
                          escrowDispute, escrowAppeal, escrowArbStake, trappedFunds, burnedFunds, payout_count>>
        ELSE
          /\ doublePayoutErr' = FALSE
          /\ payout_count' = payout_count + 1
          /\ IF winA
             THEN \* Sec 5.5 FOR_A: protocol_fee subtracted from A (to treasury), D_dispute to majority arbs
                  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
                  /\ balTreasury' = balTreasury + ProtocolFee
                  /\ balB' = balB
                  /\ balArb' = balArb + escrowDispute + (escrowArbStake - slashed)
                  /\ trappedFunds' = trappedFunds + slashed
                  /\ burnedFunds' = burnedFunds
                  /\ escrowBuyer' = 0
                  /\ escrowSeller' = 0
                  /\ escrowDispute' = 0
                  /\ escrowAppeal' = 0
                  /\ escrowArbStake' = 0
             ELSE \* Sec 5.5 FOR_B: B gets Amount + D_dispute, sigma*SellerDeposit to B, rest BURNED!
                  /\ balB' = balB + escrowBuyer + escrowDispute + Penalty
                  /\ balA' = balA
                  /\ balTreasury' = balTreasury
                  /\ balArb' = balArb + (escrowArbStake - slashed)
                  /\ trappedFunds' = trappedFunds + slashed
                  /\ burnedFunds' = burnedFunds + (escrowSeller - Penalty)
                  /\ escrowBuyer' = 0
                  /\ escrowSeller' = 0
                  /\ escrowDispute' = 0
                  /\ escrowAppeal' = 0
                  /\ escrowArbStake' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted,
               seller_delivered, buyer_honest>>

\* Appeal from RESOLVED (Sec 5.6 contradiction with Sec 3.3 terminal RESOLVED!)
Appeal ==
  /\ state = "RESOLVED"
  /\ round = 1
  /\ t_now < resolve_time + T_appeal
  /\ state' = "DISPUTE"
  /\ round' = 2
  /\ dispute_open_t' = t_now
  /\ panel_formed' = FALSE
  /\ voted' = FALSE
  /\ votesA' = 0
  /\ votesB' = 0
  /\ votesAbstain' = 0
  /\ LET loser == IF votesA * 2 > PanelSize THEN "B" ELSE "A" IN
     IF loser = "B"
     THEN /\ balB' = balB - AppealDeposit
          /\ balA' = balA
     ELSE /\ balA' = balA - AppealDeposit
          /\ balB' = balB
  /\ escrowAppeal' = AppealDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, pool_sufficient,
               seller_delivered, buyer_honest, payout_count,
               balArb, balTreasury, escrowBuyer, escrowSeller, escrowDispute,
               escrowArbStake, trappedFunds, burnedFunds, doublePayoutErr>>

\* Terminal self-loop ONLY on truly terminal states (note: in literal spec Appeal is enabled in RESOLVED for round 1)
TerminalStutter ==
  /\ state \in {"CLOSED", "EXPIRED"} \/ (state = "RESOLVED" /\ (round /= 1 \/ t_now >= resolve_time + T_appeal))
  /\ UNCHANGED vars

Next ==
  \/ Tick
  \/ Accept
  \/ TimeoutDraft
  \/ CancelDraft
  \/ Start
  \/ TimeoutLocked
  \/ SubmitHonest
  \/ SubmitFake
  \/ TimeoutInProgress
  \/ Confirm
  \/ TimeoutReview
  \/ OpenDispute
  \/ FormPanel
  \/ CastVotes
  \/ VoteWindowExpired
  \/ ResolveDispute
  \/ Appeal
  \/ TerminalStutter

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* ==================== PROPERTIES ====================

\* 1. Conservation of funds across all accounts + escrow + burned + trapped
Inv_Conservation ==
  (balA + balB + balArb + balTreasury
   + escrowBuyer + escrowSeller + escrowDispute + escrowAppeal + escrowArbStake
   + trappedFunds + burnedFunds) = TotalInitial

\* 2. No trapped funds (violated by slashed arbitrator stakes & e_cancel)
Inv_NoTrappedFunds == trappedFunds = 0

\* 3. No burned stablecoin (violated by FOR_B remainder burned)
Inv_NoBurnedStablecoin == burnedFunds = 0

\* 4. No double payout / negative escrow (violated by Appeal after RESOLVED payout)
Inv_NoDoublePayout == (~doublePayoutErr) /\ (payout_count <= 1)

\* 5. No deadline race condition (violated because Start/Submit/Confirm/Dispute lack upper time guards)
Inv_NoDeadlineRace ==
  /\ ~((state = "IN_PROGRESS") /\ (t_now >= Deadline)) \* Submit & Timeout both enabled!
  /\ ~((state = "REVIEW") /\ (submit_time >= 0) /\ (t_now >= submit_time + T_review))

\* 6. Def 5.2 Abstain/Zero-vote bug: Buyer must not win dispute with 0 FOR_B votes when Seller delivered!
Inv_NoZeroVoteBuyerWin ==
  ~((state = "RESOLVED") /\ seller_delivered /\ (votesB = 0) /\ ~(votesA * 2 > PanelSize))

\* 7. Liveness: every agreement eventually reaches a terminal state
Prop_EventuallyTerminal ==
  <>(state \in {"CLOSED", "EXPIRED", "RESOLVED"})

=============================================================================
