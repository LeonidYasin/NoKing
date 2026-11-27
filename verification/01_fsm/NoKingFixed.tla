---------------------------- MODULE NoKingFixed ----------------------------
(*
  Formal TLA+ model of the FIXED NoKing Protocol FSM.
  Applies fixes for every contradiction/deadlock found in NoKingLiteral.tla:
  1. Atomic deposit at e_accept (no stranded deposit on DRAFT cancel/timeout).
  2. Strict upper deadline guards (t_now < Deadline, t_now < submit_time + T_review).
  3. Uniform penalty on LOCKED -> EXPIRED and IN_PROGRESS -> EXPIRED (Sec 4.3).
  4. Majority requires quorum (votesA + votesB > PanelSize \div 2); no 0-vote FOR_B win.
  5. Fallback timeout on DISPUTE if pool insufficient or quorum not met -> Liveness holds.
  6. Intermediate APPEALABLE state holds escrow during T_appeal; payout only on RESOLVED.
  7. No USDC burning; slashed stakes & remainder routed explicitly to Treasury / Winner.
*)

EXTENDS Integers, FiniteSets

CONSTANTS
  Amount,          \* 100
  SellerDeposit,   \* 10
  Penalty,         \* 5
  ProtocolFee,     \* 1
  DisputeDeposit,  \* 5
  AppealDeposit,   \* 15
  ArbStake,        \* 10
  ArbPenalty,      \* 2
  PanelSize,       \* 3
  T_accept,        \* 2
  Deadline,        \* 4
  T_review,        \* 2
  T_evidence,      \* 2
  T_vote,          \* 2
  T_appeal,        \* 2
  MaxTime,         \* 20
  InitBuyer,       \* 200
  InitSeller,      \* 200
  InitArb          \* 100

VARIABLES
  state,           \* DRAFT, LOCKED, IN_PROGRESS, REVIEW, DISPUTE, APPEALABLE, CLOSED, EXPIRED, RESOLVED
  t_now,
  submit_time,
  resolve_time,
  dispute_open_t,
  round,           \* 0, 1, 2
  panel_formed,
  pool_sufficient,
  votesA,
  votesB,
  votesAbstain,
  voted,
  verdict,         \* "NONE", "FOR_A", "FOR_B", "NO_QUORUM"
  seller_delivered,
  buyer_honest,
  payout_count,
  balA,
  balB,
  balArb,
  balTreasury,
  escrowBuyer,
  escrowSeller,
  escrowDispute,
  escrowAppeal,
  escrowArbStake

vars == <<state, t_now, submit_time, resolve_time, dispute_open_t, round,
          panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
          seller_delivered, buyer_honest, payout_count,
          balA, balB, balArb, balTreasury,
          escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbStake>>

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
  /\ verdict = "NONE"
  /\ seller_delivered = FALSE
  /\ buyer_honest \in {TRUE, FALSE}
  /\ payout_count = 0
  /\ balA = InitSeller
  /\ balB = InitBuyer
  /\ balArb = InitArb
  /\ balTreasury = 0
  /\ escrowBuyer = 0
  /\ escrowSeller = 0
  /\ escrowDispute = 0
  /\ escrowAppeal = 0
  /\ escrowArbStake = 0

Tick ==
  /\ t_now < MaxTime
  /\ state \notin {"CLOSED", "EXPIRED", "RESOLVED"}
  /\ ~(state = "DISPUTE" /\ voted = TRUE /\ verdict \in {"FOR_A", "FOR_B"})
  /\ t_now' = t_now + 1
  /\ UNCHANGED <<state, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbStake>>

Accept ==
  /\ state = "DRAFT"
  /\ t_now < T_accept
  /\ state' = "LOCKED"
  /\ balB' = balB - Amount
  /\ balA' = balA - SellerDeposit
  /\ escrowBuyer' = Amount
  /\ escrowSeller' = SellerDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest, payout_count,
               balArb, balTreasury, escrowDispute, escrowAppeal, escrowArbStake>>

TimeoutDraft ==
  /\ state = "DRAFT"
  /\ t_now >= T_accept
  /\ state' = "EXPIRED"
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbStake>>

CancelDraft ==
  /\ state = "DRAFT"
  /\ t_now < T_accept
  /\ state' = "EXPIRED"
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbStake>>

Start ==
  /\ state = "LOCKED"
  /\ t_now < Deadline
  /\ state' = "IN_PROGRESS"
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbStake>>

TimeoutLocked ==
  /\ state = "LOCKED"
  /\ t_now >= Deadline
  /\ state' = "EXPIRED"
  /\ balB' = balB + escrowBuyer + Penalty
  /\ balA' = balA + (escrowSeller - Penalty)
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest,
               balArb, balTreasury, escrowDispute, escrowAppeal, escrowArbStake>>

SubmitHonest ==
  /\ state = "IN_PROGRESS"
  /\ t_now < Deadline
  /\ state' = "REVIEW"
  /\ submit_time' = t_now
  /\ seller_delivered' = TRUE
  /\ UNCHANGED <<t_now, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbStake>>

SubmitFake ==
  /\ state = "IN_PROGRESS"
  /\ t_now < Deadline
  /\ state' = "REVIEW"
  /\ submit_time' = t_now
  /\ seller_delivered' = FALSE
  /\ UNCHANGED <<t_now, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbStake>>

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
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest,
               balArb, balTreasury, escrowDispute, escrowAppeal, escrowArbStake>>

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
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest,
               balB, balArb, escrowDispute, escrowAppeal, escrowArbStake>>

TimeoutReview ==
  /\ state = "REVIEW"
  /\ t_now >= submit_time + T_review
  /\ state' = "CLOSED"
  /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
  /\ balTreasury' = balTreasury + ProtocolFee
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ payout_count' = payout_count + 1
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest,
               balB, balArb, escrowDispute, escrowAppeal, escrowArbStake>>

OpenDispute ==
  /\ state = "REVIEW"
  /\ t_now < submit_time + T_review
  /\ (~seller_delivered \/ ~buyer_honest)
  /\ state' = "DISPUTE"
  /\ dispute_open_t' = t_now
  /\ round' = 1
  /\ panel_formed' = FALSE
  /\ voted' = FALSE
  /\ votesA' = 0
  /\ votesB' = 0
  /\ votesAbstain' = 0
  /\ verdict' = "NONE"
  /\ balB' = balB - DisputeDeposit
  /\ escrowDispute' = DisputeDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, pool_sufficient,
               seller_delivered, buyer_honest, payout_count,
               balA, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowAppeal, escrowArbStake>>

FormPanel ==
  /\ state = "DISPUTE"
  /\ panel_formed = FALSE
  /\ pool_sufficient = TRUE
  /\ t_now < dispute_open_t + T_evidence + T_vote
  /\ panel_formed' = TRUE
  /\ balArb' = balArb - (PanelSize * ArbStake)
  /\ escrowArbStake' = escrowArbStake + (PanelSize * ArbStake)
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, round,
               pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal>>

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
       /\ verdict' = IF (va * 2 > PanelSize) THEN "FOR_A"
                     ELSE IF (vb * 2 > PanelSize) THEN "FOR_B"
                     ELSE "NO_QUORUM"
  /\ UNCHANGED <<state, t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbStake>>

\* Fallback timeout if pool_sufficient = FALSE or panel failed to vote/reach quorum
DisputeFallbackTimeout ==
  /\ state = "DISPUTE"
  /\ t_now >= dispute_open_t + T_evidence + T_vote
  /\ (~panel_formed \/ ~voted \/ verdict = "NO_QUORUM")
  /\ state' = "RESOLVED"
  /\ resolve_time' = t_now
  /\ payout_count' = payout_count + 1
  /\ balB' = balB + escrowBuyer + escrowDispute + (IF round = 2 THEN escrowAppeal ELSE 0)
  /\ balA' = balA + escrowSeller
  /\ balArb' = balArb + escrowArbStake
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbStake' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest, balTreasury>>

\* Round 1 verdict enters APPEALABLE (escrow stays locked for T_appeal!)
ResolveToAppealable ==
  /\ state = "DISPUTE"
  /\ round = 1
  /\ voted = TRUE
  /\ verdict \in {"FOR_A", "FOR_B"}
  /\ state' = "APPEALABLE"
  /\ resolve_time' = t_now
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest, payout_count,
               balA, balB, balArb, balTreasury,
               escrowBuyer, escrowSeller, escrowDispute, escrowAppeal, escrowArbStake>>

\* Appeal from APPEALABLE (only before T_appeal expires, transitions to DISPUTE round 2)
Appeal ==
  /\ state = "APPEALABLE"
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
  /\ verdict' = "NONE"
  /\ IF verdict = "FOR_A"
     THEN /\ balB' = balB - AppealDeposit
          /\ balA' = balA
     ELSE /\ balA' = balA - AppealDeposit
          /\ balB' = balB
  /\ escrowAppeal' = AppealDeposit
  /\ UNCHANGED <<t_now, submit_time, resolve_time, pool_sufficient,
               seller_delivered, buyer_honest, payout_count,
               balArb, balTreasury, escrowBuyer, escrowSeller, escrowDispute, escrowArbStake>>

\* Finalize after T_appeal expires OR directly from round = 2 DISPUTE
FinalizeAppealWindow ==
  /\ state = "APPEALABLE"
  /\ t_now >= resolve_time + T_appeal
  /\ state' = "RESOLVED"
  /\ payout_count' = payout_count + 1
  /\ LET majCount == IF verdict = "FOR_A" THEN votesA ELSE votesB
         minCount == PanelSize - majCount
         slashed == minCount * ArbPenalty
     IN
     IF verdict = "FOR_A"
     THEN /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
          /\ balB' = balB
          /\ balArb' = balArb + escrowDispute + (escrowArbStake - slashed)
          /\ balTreasury' = balTreasury + ProtocolFee + slashed
     ELSE /\ balB' = balB + escrowBuyer + escrowDispute + Penalty
          /\ balA' = balA
          /\ balArb' = balArb + (escrowArbStake - slashed)
          /\ balTreasury' = balTreasury + (escrowSeller - Penalty) + slashed
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbStake' = 0
  /\ UNCHANGED <<t_now, submit_time, resolve_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest>>

FinalizeRound2 ==
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
     IN
     IF verdict = "FOR_A"
     THEN /\ balA' = balA + (escrowBuyer - ProtocolFee) + escrowSeller
          /\ balB' = balB
          /\ balArb' = balArb + escrowDispute + escrowAppeal + (escrowArbStake - slashed)
          /\ balTreasury' = balTreasury + ProtocolFee + slashed
     ELSE /\ balB' = balB + escrowBuyer + escrowDispute + Penalty
          /\ balA' = balA
          /\ balArb' = balArb + escrowAppeal + (escrowArbStake - slashed)
          /\ balTreasury' = balTreasury + (escrowSeller - Penalty) + slashed
  /\ escrowBuyer' = 0
  /\ escrowSeller' = 0
  /\ escrowDispute' = 0
  /\ escrowAppeal' = 0
  /\ escrowArbStake' = 0
  /\ UNCHANGED <<t_now, submit_time, dispute_open_t, round,
               panel_formed, pool_sufficient, votesA, votesB, votesAbstain, voted, verdict,
               seller_delivered, buyer_honest>>

\* Terminal self-loop so TLC distinguishes true deadlocks from normal termination
TerminalStutter ==
  /\ state \in {"CLOSED", "EXPIRED", "RESOLVED"}
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
  \/ DisputeFallbackTimeout
  \/ ResolveToAppealable
  \/ Appeal
  \/ FinalizeAppealWindow
  \/ FinalizeRound2
  \/ TerminalStutter

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* ==================== PROPERTIES ====================

Inv_Conservation ==
  (balA + balB + balArb + balTreasury
   + escrowBuyer + escrowSeller + escrowDispute + escrowAppeal + escrowArbStake) = TotalInitial

Inv_NonNegativeBalances ==
  /\ balA >= 0 /\ balB >= 0 /\ balArb >= 0 /\ balTreasury >= 0
  /\ escrowBuyer >= 0 /\ escrowSeller >= 0 /\ escrowDispute >= 0
  /\ escrowAppeal >= 0 /\ escrowArbStake >= 0

Inv_NoDoublePayout == payout_count <= 1

Inv_NoEscrowLeakInNonTerminal ==
  (state \in {"LOCKED", "IN_PROGRESS", "REVIEW", "DISPUTE", "APPEALABLE"})
    => (escrowBuyer = Amount /\ escrowSeller = SellerDeposit /\ payout_count = 0)

Inv_NoZeroVoteWin ==
  (state \in {"APPEALABLE", "RESOLVED"} /\ verdict \in {"FOR_A", "FOR_B"})
    => (votesA + votesB > PanelSize \div 2)

Prop_EventuallyTerminal ==
  <>(state \in {"CLOSED", "EXPIRED", "RESOLVED"})

=============================================================================
