# NoKing Protocol — Formal Specification
**Version:** 0.1-draft  
**Status:** Pre-release  
**License:** MIT  

---

## Abstract

This document provides a complete formal specification of the NoKing Protocol — a decentralised bilateral exchange protocol in which honest behaviour is the dominant strategy for all participants by construction. The specification is intended to be implementation-complete: any conforming implementation derived solely from this document must be interoperable with any other conforming implementation.

---

## Table of Contents

1. [Notation and Conventions](#1-notation-and-conventions)  
2. [Primitives](#2-primitives)  
3. [Agreement State Machine](#3-agreement-state-machine)  
4. [Escrow Mechanics](#4-escrow-mechanics)  
5. [Arbitration Mechanism](#5-arbitration-mechanism)  
6. [Reputation System](#6-reputation-system)  
7. [DAO Governance](#7-dao-governance)  
8. [Security Properties](#8-security-properties)  
9. [Parameter Reference](#9-parameter-reference)  

---

## 1. Notation and Conventions

### 1.1 Mathematical Notation

| Symbol | Meaning |
|--------|---------|
| ℕ | Natural numbers {0, 1, 2, …} |
| ℝ≥0 | Non-negative reals |
| \|X\| | Cardinality of set X |
| ∀ | For all |
| ∃ | There exists |
| ⊥ | Undefined / null |
| [a, b] | Closed interval from a to b |
| t_now | Current block timestamp |
| H(x) | Cryptographic hash of x (SHA-256) |

### 1.2 Types

```
Address     ::= bytes20          -- EVM-compatible wallet address
TokenAmount ::= uint256          -- Amount in smallest denomination (wei)
Timestamp   ::= uint64           -- Unix timestamp in seconds
TxHash      ::= bytes32          -- Transaction hash
Score       ::= ℝ ∩ [0, 5]      -- Rating score
Weight      ::= ℝ ∩ [0, 1]      -- Normalised weight
```

### 1.3 Protocol Constants

All mutable protocol constants are governed by DAO (Section 7) and stored on-chain. Their initial values are listed in Section 9.

---

## 2. Primitives

### 2.1 Participant

```
Participant := {
  address    : Address,          -- unique identifier (wallet)
  joined_at  : Timestamp,        -- block timestamp of first interaction
  reputation : ReputationVector, -- defined in Section 6
  sbt_tokens : Set<SBT>,        -- soul-bound tokens, defined in Section 6.3
  active     : Bool              -- false if deactivated by DAO
}
```

A participant is **registered** upon their first on-chain interaction with the protocol. Registration requires locking a refundable registration deposit `D_reg` (see Section 9).

### 2.2 Category

Every agreement and every arbitration pool is tagged with exactly one Category.

```
Category := {
  id   : uint32,
  name : string,       -- e.g. "software_development", "physical_goods"
  parent : Category | ⊥   -- optional parent for hierarchy
}
```

The initial category set is defined by the genesis DAO proposal. New categories require a DAO vote.

### 2.3 Agreement

```
Agreement := {
  id           : TxHash,          -- hash of creation transaction
  category     : Category,
  party_a      : Address,         -- initiator (typically seller / service provider)
  party_b      : Address,         -- counterparty (typically buyer)
  value_a      : string,          -- human-readable description of A's obligation
  value_b      : string,          -- human-readable description of B's obligation
  amount       : TokenAmount,     -- stablecoin amount locked in escrow (may be 0 for barter)
  token        : Address,         -- ERC-20 token contract for payment (e.g. USDC)
  milestones   : List<Milestone>, -- ∅ means single-phase agreement
  deadline     : Timestamp,       -- absolute deadline for IN_PROGRESS → REVIEW
  state        : AgreementState,  -- current FSM state
  created_at   : Timestamp,
  evidence_uri : string | ⊥,      -- IPFS CID of completion evidence
  dispute_id   : uint32 | ⊥       -- reference to Dispute if state = DISPUTE
}
```

### 2.4 Milestone

```
Milestone := {
  index      : uint8,
  amount     : TokenAmount,   -- fraction of total Agreement.amount
  deadline   : Timestamp,
  state      : AgreementState -- independent FSM per milestone
}
```

**Constraint:** `Σ milestone.amount = Agreement.amount`

### 2.5 Dispute

```
Dispute := {
  id            : uint32,
  agreement_id  : TxHash,
  opened_by     : Address,       -- must be party_b
  opened_at     : Timestamp,
  deposit       : TokenAmount,   -- D_dispute locked by opener
  panel         : List<Address>, -- selected arbitrators
  votes         : Map<Address, Vote>,
  vote_deadline : Timestamp,
  round         : uint8,         -- 1 = first instance, 2 = appeal
  outcome       : Outcome | ⊥
}

Vote    ::= FOR_A | FOR_B | ABSTAIN
Outcome ::= { winner: Address, split: Map<Address, TokenAmount> }
```

---

## 3. Agreement State Machine

### 3.1 State Set

```
S = { DRAFT, LOCKED, IN_PROGRESS, REVIEW, CLOSED, EXPIRED, DISPUTE, RESOLVED }
```

### 3.2 Event Set

```
E = {
  e_accept,       -- party_b accepts and locks funds
  e_start,        -- party_a declares work started
  e_submit,       -- party_a submits result with evidence
  e_confirm,      -- party_b confirms receipt
  e_timeout,      -- blockchain keeper fires after deadline
  e_dispute,      -- party_b opens dispute (with deposit)
  e_resolve,      -- arbitration panel delivers verdict
  e_cancel        -- mutual cancellation before LOCKED
}
```

### 3.3 Transition Function

`δ : S × E → S`

| Current State | Event | Next State | Preconditions |
|---|---|---|---|
| DRAFT | e_accept | LOCKED | `msg.sender = party_b`, funds transferred, `t_now < created_at + T_accept` |
| DRAFT | e_timeout | EXPIRED | `t_now ≥ created_at + T_accept` |
| DRAFT | e_cancel | EXPIRED | `msg.sender ∈ {party_a, party_b}` |
| LOCKED | e_start | IN_PROGRESS | `msg.sender = party_a` |
| LOCKED | e_timeout | EXPIRED | `t_now ≥ deadline` — funds returned to party_b |
| IN_PROGRESS | e_submit | REVIEW | `msg.sender = party_a`, `evidence_uri ≠ ⊥` |
| IN_PROGRESS | e_timeout | EXPIRED | `t_now ≥ deadline` — funds returned to party_b, seller loses `σ` fraction of deposit |
| REVIEW | e_confirm | CLOSED | `msg.sender = party_b` |
| REVIEW | e_timeout | CLOSED | `t_now ≥ submit_time + T_review` — auto-confirmation |
| REVIEW | e_dispute | DISPUTE | `msg.sender = party_b`, dispute deposit `D_dispute` locked |
| DISPUTE | e_resolve | RESOLVED | `msg.sender = ArbitrationContract` |
| EXPIRED | — | — | terminal state |
| CLOSED | — | — | terminal state |
| RESOLVED | — | — | terminal state |

### 3.4 Auto-Confirmation Rule

**Definition 3.1 (Silent Confirmation).** If `t_now ≥ submit_time + T_review` and no `e_confirm` or `e_dispute` event has been emitted by `party_b`, any network participant may call `triggerTimeout(agreement_id)`, transitioning state to CLOSED. The caller receives a gas-compensation reward `R_keeper` from the protocol fee pool.

This rule eliminates the ability to weaponise silence as leverage.

### 3.5 Milestone Agreements

For agreements with `|milestones| > 0`, the top-level state machine governs the overall agreement. Each milestone runs an independent sub-FSM over states `{PENDING, IN_PROGRESS, REVIEW, CLOSED, DISPUTE}`. The top-level agreement reaches CLOSED only when all milestones reach CLOSED.

---

## 4. Escrow Mechanics

### 4.1 Deposits at Lock

When `e_accept` fires:

```
escrow_amount  = Agreement.amount                    -- buyer's payment
seller_deposit = floor(Agreement.amount × α)         -- seller's collateral
```

where `α ∈ (0, 1)` is the **seller deposit ratio** (see Section 9).

Both amounts are transferred to the protocol's escrow contract atomically. If either transfer fails, the transaction reverts.

### 4.2 Happy Path Distribution (CLOSED)

```
protocol_fee  = floor(Agreement.amount × φ)
seller_payout = Agreement.amount - protocol_fee
```

Distributions:
- `party_a` receives `seller_payout + seller_deposit` (collateral returned)
- Protocol treasury receives `protocol_fee`
- `party_b` receives nothing additional (already paid)

### 4.3 Expiry Distribution (EXPIRED)

If expiry is caused by `party_a` missing deadline:

```
penalty       = floor(seller_deposit × σ)
refund_to_b   = Agreement.amount + penalty
refund_to_a   = seller_deposit - penalty
```

where `σ ∈ (0, 1]` is the **seller penalty ratio** (see Section 9).

If expiry is caused by `party_b` not accepting (DRAFT timeout):

- `party_a` receives `seller_deposit` back (none was locked by B yet)

### 4.4 Dispute Distribution (RESOLVED)

See Section 5.5.

### 4.5 Protocol Fee Allocation

```
protocol_fee_split := {
  dao_treasury  : 0.40,   -- 40% to DAO for development grants
  arbitrator_pool: 0.30,  -- 30% to arbitrator reward pool
  keeper_pool   : 0.10,   -- 10% to keeper reward pool
  burn          : 0.20    -- 20% burned (deflationary pressure on governance token)
}
```

---

## 5. Arbitration Mechanism

### 5.1 Theoretical Foundation

The arbitration mechanism is grounded in Schelling (1960)'s theory of focal points. Formally:

**Theorem 5.1 (Schelling Coordination).** In a coordination game where agents independently select from a set of options, and one option is uniquely salient (the "focal point"), rational agents converge on it in the absence of communication.

Applied to dispute resolution: given a well-documented dispute with clear evidence, the truthful verdict is the unique focal point among independently reasoning arbitrators.

**Theorem 5.2 (Incentive Alignment).** Under the reward structure defined in Section 5.4, voting with the majority is a Nash equilibrium. The unique dominant strategy for a rational arbitrator with accurate beliefs is to vote according to the evidence.

*Proof sketch:* Let arbitrator i have belief p_i ∈ [0,1] that party_A is correct. Expected payoff from voting FOR_A = p_i · R_arbitrator. Expected payoff from voting FOR_B = (1 - p_i) · R_arbitrator. Arbitrator votes FOR_A iff p_i > 0.5, which coincides with honest reporting. QED.

### 5.2 Panel Formation

**Definition 5.1 (Eligible Arbitrator).** Address `a` is eligible for a dispute in category `c` iff:
```
a.reputation[c].count ≥ N_arb_min_deals  AND
a.active = true                            AND
a ∉ {party_a, party_b}                    AND
a has no financial relationship with party_a or party_b (self-reported + on-chain check)
```

**Algorithm 5.1 (Panel Selection).**
```
Input:  dispute d, panel size k (odd)
Output: panel P ⊆ Eligible(d.category), |P| = k

1. Compute eligible set E = { a : eligible(a, d.category) }
2. Require |E| ≥ k · PANEL_OVERSAMPLE_FACTOR
3. seed = H(d.id || block.prevrandao)   -- VRF-based randomness
4. Shuffle E using Fisher-Yates with seed
5. P = E[0 : k]
6. Emit PanelFormed(d.id, P)
```

**Note on randomness:** `block.prevrandao` (EIP-4399) provides RANDAO-based randomness. For higher-stakes disputes a Verifiable Random Function (VRF) oracle may be substituted.

### 5.3 Evidence Submission

```
EvidenceWindow := [d.opened_at, d.opened_at + T_evidence]
```

During this window:
- `party_a` may submit evidence supporting their position (IPFS CID)
- `party_b` may submit evidence supporting their position (IPFS CID)
- Panel members may read but not write

After `T_evidence` the evidence record is frozen. No further submissions are accepted.

### 5.4 Voting and Reward Function

```
VotingWindow := [evidence_close, evidence_close + T_vote]
```

Each panel member `p_i` submits `vote_i ∈ { FOR_A, FOR_B }` (abstention is penalised as minority vote for reward purposes).

**Definition 5.2 (Majority).** 
```
majority_vote = FOR_A  if  |{i : vote_i = FOR_A}| > k/2
              = FOR_B  otherwise
```

**Definition 5.3 (Arbitrator Reward).**

For arbitrator `p_i`:
```
R_i = R_arbitrator   if vote_i = majority_vote
    = 0              otherwise
    
Penalty_i = floor(arbitrator_stake × λ)  if vote_i ≠ majority_vote
          = 0                             otherwise
```

where:
- `R_arbitrator` is drawn from the arbitrator pool (Section 4.5)
- `arbitrator_stake` is the stake locked by `p_i` upon panel acceptance
- `λ ∈ (0, 1]` is the minority penalty ratio (see Section 9)

**Corollary:** An arbitrator who does not vote within `T_vote` is treated as minority voter and incurs `Penalty_i`.

### 5.5 Dispute Resolution Distribution

```
If majority_vote = FOR_A (seller wins):
  party_a receives: Agreement.amount - protocol_fee + seller_deposit
  party_b receives: D_dispute is forfeited → split among majority arbitrators
  
If majority_vote = FOR_B (buyer wins):
  party_b receives: Agreement.amount + D_dispute (dispute deposit returned)
  party_a receives: 0 (seller_deposit split: σ fraction to party_b, remainder burned)
```

### 5.6 Appeal

The losing party may invoke appeal within `T_appeal` of `e_resolve`.

```
Appeal panel size k' = 3k + 2   -- e.g. 5 → 17, 7 → 23
Appeal deposit       = D_dispute × APPEAL_DEPOSIT_MULTIPLIER
```

If the appeal panel **overturns** the first-instance verdict:
- First-instance majority arbitrators lose their entire stake
- Appeal deposit is returned to appellant
- Distribution follows Section 5.5 with appeal majority as winner

If the appeal panel **upholds** the verdict:
- Appeal deposit is forfeited to first-instance majority arbitrators
- No further appeal is available (final)

**Corollary:** The cost of organising a corrupt first-instance panel is bounded below by the expected loss from appeal overturn times the probability of a corrupt first panel being detected, which grows with panel size. For k ≥ 5 and k' ≥ 17, the expected cost of systematic corruption exceeds the maximum recoverable value for any realistic dispute amount.

---

## 6. Reputation System

### 6.1 Reputation Vector

```
ReputationVector := Map<CategoryId, DimensionScore>

DimensionScore := {
  count       : ℕ,       -- number of completed deals in this category
  raw_score   : ℝ≥0,    -- cumulative weighted score
  rating      : Score,   -- derived: raw_score / effective_count
  last_active : Timestamp
}
```

### 6.2 Score Update Function

Upon agreement CLOSED or RESOLVED, the reviewer (counterparty) submits a rating `r ∈ {1, 2, 3, 4, 5}`.

**Definition 6.1 (Deal Weight).** The weight of the n-th deal for participant p in category c:

```
w(n) = 1 - exp(-n / N_warmup)
```

where `N_warmup` is the warm-up constant (see Section 9). This ensures early deals have reduced weight, making Sybil accumulation slow and expensive.

**Definition 6.2 (Score Update).**
```
new_raw_score = old_raw_score + r · w(count + 1)
new_count     = count + 1
new_rating    = new_raw_score / Σ_{i=1}^{new_count} w(i)
```

The rating converges to the true mean as `count → ∞` and `w(n) → 1`.

### 6.3 Temporal Decay

**Definition 6.3 (Effective Rating).** The displayed rating applies a decay function to penalise inactivity:

```
Δt          = t_now - last_active
decay_factor = exp(-Δt / T_decay)
effective_rating(c) = rating(c) · decay_factor + baseline · (1 - decay_factor)
```

where `baseline = 2.5` (neutral score) and `T_decay` is the decay half-life (see Section 9).

This prevents account sale: a dormant account with high reputation converges toward neutral over time.

### 6.4 Arbitrator Reputation

Arbitrator performance is tracked in a separate dimension:

```
ArbitratorScore := {
  total_cases        : ℕ,
  majority_votes     : ℕ,
  alignment_rate     : ℝ ∩ [0, 1],   -- majority_votes / total_cases
  overturned_count   : ℕ              -- cases where appeal reversed first-instance vote
}

alignment_rate = majority_votes / max(total_cases, 1)
```

Eligibility to serve as arbitrator requires `alignment_rate ≥ θ_arb` (see Section 9) after at least `N_arb_min_cases` cases.

### 6.5 Soul-Bound Tokens (SBT)

SBTs are ERC-721 tokens with transfer disabled at the contract level.

```
SBT := {
  token_id  : uint256,
  holder    : Address,       -- immutable
  badge_type: BadgeType,
  issued_at : Timestamp,
  metadata  : IPFS_CID
}
```

**Definition 6.4 (Badge Issuance Conditions).**

| Badge | Condition |
|---|---|
| `FOUNDER` | `participant.joined_at < T_genesis + 90 days` |
| `CENTURY_CLEAN` | `∃ category c: count(c) ≥ 100 ∧ dispute_rate(c) < 0.01` |
| `VERIFIED_ARBITRATOR` | `alignment_rate ≥ 0.90 ∧ total_cases ≥ 50` |
| `TRUSTED_SELLER` | `Σ_c count(c) ≥ 500 ∧ global_dispute_rate < 0.02` |
| `MILESTONE_MASTER` | Completed ≥ 50 milestone-based agreements without dispute |

SBTs are non-transferable, non-burnable by the holder, and permanently on-chain.

### 6.6 Portability

All reputation data is stored in public contract storage and queryable via standard view functions:

```solidity
function getReputationVector(address participant) 
  external view 
  returns (DimensionScore[] memory);

function getSBTs(address participant) 
  external view 
  returns (SBT[] memory);
```

Any third-party platform may read and display NoKing reputation without permission.

---

## 7. DAO Governance

### 7.1 Governance Token

The protocol governance token `NKG` is a standard ERC-20 with the following constraints:
- Maximum supply: fixed at genesis, no mint function post-deployment
- 20% of protocol fees are burned (Section 4.5), creating deflationary pressure

### 7.2 Voting Weight

**Definition 7.1 (Effective Voting Weight).** For participant `p` holding `B_p` tokens:

```
activity_factor(p) = min(1, total_deals(p) / N_activity_threshold)

raw_weight(p) = B_p · activity_factor(p)

effective_weight(p) = min(raw_weight(p), MAX_WEIGHT_CAP · Σ_q raw_weight(q))
```

where `MAX_WEIGHT_CAP` (see Section 9) ensures no single address controls more than that fraction of total voting power.

**Rationale:** `activity_factor` ensures dormant whale wallets and bots cannot dominate governance. `MAX_WEIGHT_CAP` prevents oligarchic capture.

### 7.3 Proposal Lifecycle

```
ProposalState = { PENDING, ACTIVE, SUCCEEDED, DEFEATED, EXECUTED, CANCELLED }
```

| Phase | Duration | Condition to advance |
|---|---|---|
| PENDING | T_delay | — (timelock) |
| ACTIVE | T_voting | — |
| SUCCEEDED → EXECUTED | T_timelock | quorum met ∧ For > Against |
| Any → CANCELLED | — | proposer withdraws or guardian veto |

**Quorum condition:**
```
Σ_{votes cast} effective_weight(p) ≥ Q · Σ_all effective_weight(p)
```
where `Q` is the quorum ratio (see Section 9).

### 7.4 Governable Parameters

The following protocol parameters may be changed by DAO vote. All others are immutable.

```
{ α, σ, φ, λ, T_accept, T_review, T_evidence, T_vote, T_appeal,
  T_decay, N_warmup, θ_arb, N_arb_min_deals, N_arb_min_cases,
  MAX_WEIGHT_CAP, Q, D_reg, D_dispute, APPEAL_DEPOSIT_MULTIPLIER,
  R_keeper, PANEL_OVERSAMPLE_FACTOR }
```

---

## 8. Security Properties

### 8.1 Formal Properties

The following properties are required of any conforming implementation:

**P1 (Escrow Safety).** Funds locked in escrow can only exit to `party_a`, `party_b`, arbitrators, or the protocol treasury, as defined by Sections 4 and 5. No other address may extract funds under any sequence of valid transactions.

**P2 (Liveness).** Every agreement in a non-terminal state will eventually reach a terminal state (`CLOSED`, `EXPIRED`, `RESOLVED`) under the timeout mechanism, regardless of participant behaviour.

**P3 (Arbitration Finality).** A RESOLVED state is terminal. No mechanism exists to reverse a RESOLVED agreement after the appeal window has closed.

**P4 (Review Immutability).** An on-chain review may not be modified or deleted after submission. The link between review and `TxHash` is cryptographically permanent.

**P5 (SBT Non-Transferability).** No valid transaction sequence transfers an SBT from its original recipient to any other address.

### 8.2 Attack Vectors and Mitigations

| Attack | Description | Mitigation |
|---|---|---|
| Sybil | Many fake identities accumulate reputation | Registration deposit `D_reg`, warm-up weight function `w(n)` |
| Panel bribery | Attacker bribes first-instance panel | Random selection, stake at risk, appeal with 3x+ panel |
| Silent buyer | Buyer refuses to confirm to extract leverage | Auto-confirmation after `T_review` (Definition 3.1) |
| Fake dispute | Buyer opens frivolous dispute to delay payment | Dispute deposit `D_dispute` forfeited on loss |
| DAO capture | Whale accumulates tokens to control protocol | `MAX_WEIGHT_CAP`, `activity_factor` |
| Account sale | Sell wallet with high reputation | Temporal decay (Definition 6.3) |
| Front-running panel selection | Attacker reads mempool to manipulate panel | RANDAO / VRF randomness, committed before selection |

---

## 9. Parameter Reference

Initial values. All are governable by DAO (Section 7.4).

| Parameter | Symbol | Initial Value | Description |
|---|---|---|---|
| Seller deposit ratio | α | 0.10 | Seller locks 10% of deal value as collateral |
| Seller penalty ratio | σ | 0.50 | 50% of deposit lost on deadline miss |
| Protocol fee ratio | φ | 0.010 | 1.0% of deal value to protocol |
| Minority penalty ratio | λ | 0.25 | 25% of arbitrator stake lost on minority vote |
| Accept timeout | T_accept | 72 hours | DRAFT expires if not accepted |
| Review timeout | T_review | 48 hours | Auto-confirm if buyer silent |
| Evidence window | T_evidence | 48 hours | Both sides submit evidence |
| Vote window | T_vote | 48 hours | Arbitrators vote |
| Appeal window | T_appeal | 72 hours | Loser may invoke appeal |
| Reputation decay half-life | T_decay | 365 days | Score halves after 1 year inactivity |
| Warm-up constant | N_warmup | 20 | First 20 deals have reduced weight |
| Arbitrator alignment threshold | θ_arb | 0.80 | Min 80% majority alignment to stay eligible |
| Min deals to arbitrate | N_arb_min_deals | 10 | Must have ≥10 completed deals in category |
| Min cases before θ_arb applies | N_arb_min_cases | 5 | Grace period for new arbitrators |
| First-instance panel size | k | 5 | Odd number of arbitrators |
| Appeal panel size | k' | 3k + 2 | Scales with first-instance panel |
| Panel oversample factor | — | 3× | Pool must be ≥ 3× panel size |
| Appeal deposit multiplier | — | 3× | Appeal costs 3× original dispute deposit |
| DAO max weight cap | MAX_WEIGHT_CAP | 0.05 | No address > 5% of total voting power |
| DAO quorum | Q | 0.10 | 10% of effective weight must vote |
| Registration deposit | D_reg | 10 USDC | Refundable, locks on first interaction |
| Dispute deposit | D_dispute | 5% of deal | Forfeited on loss |
| Keeper reward | R_keeper | 0.5 USDC | Gas compensation for timeout callers |

---

## References

- Satoshi Nakamoto. *Bitcoin: A Peer-to-Peer Electronic Cash System.* 2008.
- Vitalik Buterin. *Ethereum Whitepaper.* 2014.
- Thomas C. Schelling. *The Strategy of Conflict.* Harvard University Press, 1960.
- Clément Lesaege, Federico Ast. *Kleros: A Decentralized Court System.* 2018.
- Vitalik Buterin, Puja Ohlhaver, E. Glen Weyl. *Decentralized Society: Finding Web3's Soul.* 2022.
- W3C. *Verifiable Credentials Data Model 1.0.* 2019.
- Ethereum Foundation. *EIP-4399: Supplant DIFFICULTY opcode with PREVRANDAO.* 2021.
- John F. Nash Jr. *Equilibrium Points in n-Person Games.* PNAS, 1950.

---

*NoKing Protocol Specification v0.1-draft. Open for community review.*  
*github.com/LeonidYasin/NoKing*
