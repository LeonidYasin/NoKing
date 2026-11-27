# NoKing Protocol — Formal Specification
**Version:** 0.2-draft  
**Status:** Pre-release (revised after independent verification v0.1, incorporating Decisions D1–D11)  
**Baseline:** `protocol/specs/exchange-spec.md` (v0.1-draft)  
**License:** MIT  

---

## Abstract

This document specifies **NoKing Protocol v0.2-draft** — a decentralised bilateral exchange protocol revised to address formal safety, liveness, game-theoretic, and reputation vulnerabilities identified in the v0.1 verification audit. Unlike v0.1, this specification does not claim unconditional dominance of honest strategies; instead, it defines explicit game-theoretic conditions, bounded liveness guarantees, commit-reveal Schelling arbitration, and value-weighted Bayesian reputation. Items marked **`[OPEN]`** remain under community/author design review and are explicitly left unfixed.

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
|---|---|
| ℕ | Natural numbers {0, 1, 2, …} |
| ℝ≥0 | Non-negative reals |
| \|X\| | Cardinality of set X |
| ∀ | For all |
| ∃ | There exists |
| ⊥ | Undefined / null |
| [a, b] | Closed interval from a to b |
| t_now | Current block timestamp |
| H(x) | Cryptographic hash of x (Keccak-256 / SHA-256) |
| ln 2 | Natural logarithm of 2 (≈ 0.693147) |

### 1.2 Types

```
Address     ::= bytes20          -- EVM-compatible wallet address
TokenAmount ::= uint256          -- Amount in smallest denomination (wei / micro-USDC)
Timestamp   ::= uint64           -- Unix timestamp in seconds
TxHash      ::= bytes32          -- Transaction hash
Bytes32     ::= bytes32          -- Commit hash / VRF request ID
Score       ::= ℝ ∩ [0, 5]      -- Rating score
Weight      ::= ℝ≥0              -- Non-negative weight
Role        ::= SELLER | BUYER   -- Participant role in an agreement
```

### 1.3 Protocol Constants

All mutable protocol constants are governed by DAO (Section 7) and stored on-chain. Parameters marked **FREE** in Section 9 do not yet have fixed initial values from the author and are parameterized over admissible domains.

---

## 2. Primitives

### 2.1 Participant

```
Participant := {
  address    : Address,          -- unique identifier (wallet)
  joined_at  : Timestamp,        -- block timestamp of first interaction
  reputation : ReputationVector, -- defined in Section 6
  sbt_tokens : Set<SBT>,        -- soul-bound tokens, defined in Section 6.5
  active     : Bool              -- false if deactivated by DAO
}
```

A participant is **registered** upon their first on-chain interaction with the protocol. Registration requires locking a refundable registration deposit `D_reg` (see Section 9).

> **`[OPEN — G-04]`:** The exact withdrawal / deregistration conditions and cooldown period for refunding `D_reg` (ensuring no active agreements or pending disputes exist) remain to be specified.

### 2.2 Category

Every agreement and every arbitration pool is tagged with exactly one Category.

```
Category := {
  id     : uint32,
  name   : string,         -- e.g. "software_development", "physical_goods"
  parent : Category | ⊥    -- optional parent for hierarchy
}
```

### 2.3 Agreement

```
Agreement := {
  id             : TxHash,          -- hash of creation transaction
  category       : Category,
  party_a        : Address,         -- initiator (typically seller / service provider)
  party_b        : Address,         -- counterparty (typically buyer)
  value_a        : string,          -- human-readable description of A's obligation
  value_b        : string,          -- human-readable description of B's obligation
  amount         : TokenAmount,     -- stablecoin payment locked by party_b at e_accept
  seller_deposit : TokenAmount,     -- collateral locked by party_a at DRAFT creation (D1)
  buyer_deposit  : TokenAmount,     -- 0 for monetary deals; D_barter_min under D9-B
  token          : Address,         -- ERC-20 stablecoin contract (e.g. USDC)
  milestones     : List<Milestone>, -- ∅ means single-phase agreement
  deadline       : Timestamp,       -- absolute deadline for LOCKED/IN_PROGRESS → REVIEW
  submit_time    : Timestamp | ⊥,   -- block timestamp when e_submit executed (added in v0.2)
  resolve_time   : Timestamp | ⊥,   -- block timestamp when round-1 e_resolve entered APPEALABLE (D2)
  state          : AgreementState,  -- current FSM state
  created_at     : Timestamp,
  evidence_uri   : string | ⊥,      -- IPFS CID of completion evidence
  dispute_id     : uint32 | ⊥       -- reference to Dispute if state ∈ {DISPUTE, APPEALABLE}
}
```

**Amount & Barter Variants (D9):**
- **Variant D9-A (Strict Non-Zero Escrow):** `Agreement.amount ≥ A_min > 0`. Zero-amount barter (`amount = 0`) is prohibited at the protocol layer.
- **Variant D9-B (Mutual Minimum Deposits):** `Agreement.amount = 0` is permitted iff both `party_a` (`seller_deposit ≥ D_barter_min`) and `party_b` (`buyer_deposit ≥ D_barter_min`) lock a mutual minimum collateral `D_barter_min > 0`, and either party may trigger `e_dispute` in `REVIEW` (with corresponding `D_dispute` funded or deducted from collateral).

### 2.4 Milestone

```
Milestone := {
  index      : uint8,
  amount     : TokenAmount,   -- fraction of total Agreement.amount
  deadline   : Timestamp,
  state      : AgreementState -- independent sub-FSM per milestone
}
```

**Constraint:** `Σ milestone.amount = Agreement.amount`.

> **`[OPEN — G-03]`:** The Milestone Sub-FSM transition table (handling per-milestone `EXPIRED`, `DISPUTE`, `APPEALABLE`, `RESOLVED`, and proportional `seller_deposit` slashing) remains to be fully specified.

### 2.5 Dispute

```
Dispute := {
  id            : uint32,
  agreement_id  : TxHash,
  opened_by     : Address,            -- party_b (or party_a/party_b under D9-B)
  opened_at     : Timestamp,
  deposit       : TokenAmount,        -- D_dispute (round 1) or appeal_deposit (round 2)
  round         : uint8,              -- 1 = first instance, 2 = appeal
  attempt       : uint8,              -- re-draw counter within round (D5)
  panel         : List<Address>,      -- selected arbitrators
  arb_stakes    : Map<Address, TokenAmount>, -- proportional USDC stake per arbitrator (D4)
  commits       : Map<Address, Bytes32>,     -- H(vote || salt) during T_commit
  votes         : Map<Address, Vote>,        -- revealed votes during T_reveal
  commit_deadline : Timestamp,
  vote_deadline   : Timestamp,
  max_deadline    : Timestamp,        -- opened_at + T_dispute_max (D3)
  outcome         : Outcome | ⊥
}

Vote    ::= FOR_A | FOR_B | UNREVEALED
Outcome ::= { verdict: FOR_A | FOR_B | COMPROMISE, split: Map<Address, TokenAmount> }
```

---

## 3. Agreement State Machine

### 3.1 State Set (Updated per D2)

```
S = { DRAFT, LOCKED, IN_PROGRESS, REVIEW, DISPUTE, APPEALABLE, CLOSED, EXPIRED, RESOLVED }
```

Terminal states: `{ CLOSED, EXPIRED, RESOLVED }`.  
Non-terminal states: `{ DRAFT, LOCKED, IN_PROGRESS, REVIEW, DISPUTE, APPEALABLE }`.

### 3.2 Event Set

```
E = {
  e_create,           -- party_a creates DRAFT and locks seller_deposit (D1)
  e_accept,           -- party_b accepts and locks Agreement.amount (+ buyer_deposit under D9-B) (D1)
  e_cancel,           -- party_a cancels in DRAFT before acceptance (D1)
  e_start,            -- party_a declares work started
  e_submit,           -- party_a submits completion evidence
  e_confirm,          -- party_b confirms receipt
  e_timeout,          -- victim or keeper triggers timeout after deadline
  e_dispute,          -- party_b (or either party under D9-B) opens dispute with D_dispute
  e_redraw,           -- panel re-drawn on tie / missed quorum within T_dispute_max (D5)
  e_dispute_timeout,  -- T_dispute_max reached -> COMPROMISE resolution (D3)
  e_resolve,          -- ArbitrationContract delivers valid majority verdict (D2, D5)
  e_appeal,           -- losing party appeals in APPEALABLE with appeal_deposit (D2)
  e_finalize          -- anyone finalizes APPEALABLE after T_appeal expires (D2)
}
```

### 3.3 Transition Function

`δ : S × E → S`

| # | Current State | Event | Next State | Preconditions |
|---|---|---|---|---|
| 1 | ∅ | `e_create` | `DRAFT` | `msg.sender = party_a`, `seller_deposit` transferred to escrow (D1), amount constraint holds (D9) |
| 2 | `DRAFT` | `e_accept` | `LOCKED` | `msg.sender = party_b`, `amount` (+ `buyer_deposit` under D9-B) transferred, `t_now < created_at + T_accept` (D1) |
| 3 | `DRAFT` | `e_cancel` | `EXPIRED` | `msg.sender = party_a` ONLY (D1) — `seller_deposit` refunded to `party_a` |
| 4 | `DRAFT` | `e_timeout` | `EXPIRED` | `t_now ≥ created_at + T_accept` — `seller_deposit` refunded to `party_a` (D1) |
| 5 | `LOCKED` | `e_start` | `IN_PROGRESS` | `msg.sender = party_a`, `t_now < deadline` |
| 6 | `LOCKED` | `e_timeout` | `EXPIRED` | `t_now ≥ deadline` — `amount` (+ `buyer_deposit`) to `party_b`, `σ` penalty on `seller_deposit` (D10) |
| 7 | `IN_PROGRESS` | `e_submit` | `REVIEW` | `msg.sender = party_a`, `evidence_uri ≠ ⊥`, `t_now < deadline`; sets `submit_time = t_now` |
| 8 | `IN_PROGRESS` | `e_timeout` | `EXPIRED` | `t_now ≥ deadline` — `amount` (+ `buyer_deposit`) to `party_b`, `σ` penalty on `seller_deposit` |
| 9 | `REVIEW` | `e_confirm` | `CLOSED` | `msg.sender = party_b`, `t_now < submit_time + T_review` |
| 10 | `REVIEW` | `e_timeout` | `CLOSED` | `t_now ≥ submit_time + T_review` — auto-confirmation |
| 11 | `REVIEW` | `e_dispute` | `DISPUTE` | `msg.sender = party_b` (or `∈ {party_a, party_b}` under D9-B), `t_now < submit_time + T_review`, `D_dispute` locked; `round = 1`, `opened_at = t_now` |
| 12 | `DISPUTE` | `e_redraw` | `DISPUTE` | `msg.sender = ArbitrationContract`, quorum not met or tie (D5), `t_now + T_commit + T_reveal ≤ opened_at + T_dispute_max` |
| 13 | `DISPUTE` | `e_resolve` | `APPEALABLE` | `msg.sender = ArbitrationContract`, `round = 1`, valid majority verdict (`FOR_A` or `FOR_B`, D5); sets `resolve_time = t_now`, funds remain locked (D2) |
| 14 | `DISPUTE` | `e_resolve` | `RESOLVED` | `msg.sender = ArbitrationContract`, `round = 2`, valid majority verdict (`FOR_A` or `FOR_B`, D5) — terminal, payouts executed (D2) |
| 15 | `DISPUTE` | `e_dispute_timeout` | `RESOLVED` | `t_now ≥ opened_at + T_dispute_max` (panel unformed or no valid verdict) — `COMPROMISE` payouts executed (D3) |
| 16 | `APPEALABLE` | `e_appeal` | `DISPUTE` | `msg.sender = round1_loser`, `t_now < resolve_time + T_appeal`, `appeal_deposit` locked; sets `round = 2`, `opened_at = t_now` (D2) |
| 17 | `APPEALABLE` | `e_finalize` | `RESOLVED` | `t_now ≥ resolve_time + T_appeal` (callable by anyone, D2) — executes round-1 payouts |
| 18 | `CLOSED` / `EXPIRED` / `RESOLVED` | — | — | Terminal states |

### 3.4 Keeper Triggering & Auto-Confirmation (Updated per D7)

**Definition 3.1 (Timeout Callers and Keeper Reward).** Any timeout transition (`e_timeout`, `e_dispute_timeout`, `e_finalize`) may be triggered by the affected/victim party directly or by any external keeper. Per **Decision D7**:
- On `LOCKED → EXPIRED` and `IN_PROGRESS → EXPIRED`: the at-fault party is `party_a`; keeper reward `R_keeper` (when called by a third party, bounded by `penalty`) is deducted from `party_a`'s forfeited `penalty` before crediting `party_b` (or `0` if called directly by `party_b`).
- On `REVIEW → CLOSED` (`e_timeout`): the silent party is `party_b`; keeper reward `R_keeper` is charged to the at-fault side (`party_b` if `buyer_deposit > 0`, otherwise from `protocol_fee` / `keeper_pool` since `party_b`'s escrow `Agreement.amount` is owed to `party_a` — see Section 4.2 and Red-Team analysis).
- On `DRAFT → EXPIRED` (`e_timeout`): `party_b` never deposited funds; `party_a` may reclaim `seller_deposit` directly (`R_keeper = 0` or paid only if `party_a` optionally attaches a bounty).

---

## 4. Escrow Mechanics

### 4.1 Deposits at Creation and Lock (Updated per D1, D9)

1. At **`e_create` (`DRAFT`)**: `party_a` transfers `seller_deposit` to escrow:
   - Under D9-A (`amount ≥ A_min`): `seller_deposit = floor(Agreement.amount × α)`.
   - Under D9-B (`amount = 0` barter): `seller_deposit = D_barter_min`.
2. At **`e_accept` (`DRAFT → LOCKED`)**: `party_b` transfers `escrow_amount = Agreement.amount` (plus `buyer_deposit = D_barter_min` if `amount = 0` under D9-B) atomically to escrow.

### 4.2 Happy Path Distribution (`CLOSED`)

```
protocol_fee  = floor(Agreement.amount × φ)
seller_payout = Agreement.amount - protocol_fee
```

- `party_a` receives `seller_payout + seller_deposit`
- `party_b` receives `buyer_deposit` (0 under D9-A; `D_barter_min` under D9-B)
- Protocol fee allocation receives `protocol_fee` (Section 4.5)
- If `CLOSED` occurred via `e_timeout` by an external keeper: `R_keeper` is paid from `keeper_pool` (or `buyer_deposit` under D9-B) so `party_a` is not penalized for `party_b`'s silence (see D7 edge case analysis).

### 4.3 Expiry Distribution (`EXPIRED`, Updated per D1, D7, D10)

1. **Draft Cancel (`DRAFT --e_cancel--> EXPIRED`, D1):**
   - `party_a` receives `seller_deposit` back in full.
2. **Draft Timeout (`DRAFT --e_timeout--> EXPIRED`, D1):**
   - `party_a` receives `seller_deposit` back in full.
3. **Locked or In-Progress Timeout (`LOCKED / IN_PROGRESS --e_timeout--> EXPIRED`, D7, D10):**
   ```
   penalty       = floor(seller_deposit × σ)
   keeper_fee    = R_keeper_if_external (≤ penalty)   -- 0 if called by party_b
   refund_to_b   = Agreement.amount + buyer_deposit + (penalty - keeper_fee)
   refund_to_a   = seller_deposit - penalty
   ```
   *(D10 ensures identical `σ` slashing whether `party_a` failed before or after `e_start`.)*

### 4.4 Compromise Distribution (`DISPUTE --e_dispute_timeout--> RESOLVED`, D3)

If `t_now ≥ opened_at + T_dispute_max` without a valid majority verdict:
- `party_b` receives `Agreement.amount + buyer_deposit`
- `party_a` receives `seller_deposit`
- `D_dispute` (round 1) is refunded to `opened_by`
- `appeal_deposit` (if round 2) is refunded to `round1_loser`
- Any unslashed `arbitrator_stake` locked by non-defaulting arbitrators is returned; defaulting (non-committing / non-revealing) arbitrators are slashed per Section 5.4.

### 4.5 Protocol Fee Allocation (Updated per D6)

```
protocol_fee_split := {
  dao_treasury    : 0.40,   -- 40% to DAO for development grants
  arbitrator_pool : 0.30,   -- 30% to arbitrator reward pool
  keeper_pool     : 0.10,   -- 10% to keeper reward pool
  nkg_buy_burn    : 0.20    -- 20% used exclusively to buy & burn NKG (never USDC, D6)
}
```

**No Stablecoin Burning (D6):** Under no transition is `Agreement.token` (USDC/DAI) burned or sent to `address(0)`.

---

## 5. Arbitration Mechanism

### 5.1 Theoretical Foundation (Revised Theorem 5.1–5.2)

**Theorem 5.1 (Schelling Coordination with Hidden Votes).** In a simultaneous hidden-action coordination game where independent arbitrators observe a noisy signal of true state $\omega \in \{A, B\}$ with accuracy $1 - \eta > 0.5$ and are rewarded iff they match the majority, truthful reporting according to evidence is a **strict focal Nash equilibrium** if:
1. Votes are hidden during submission via **commit-reveal** (eliminating sequential herding);
2. Expected marginal gain of matching the majority outweighs investigation cost $c_e$:
   $$R_{\text{arb}} + \lambda S_{\text{arb}} > \frac{c_e}{\min(q, 1-q)}$$
   where $q = \Pr(\omega = A)$ is the prior;
3. Expected payouts are symmetric between `FOR_A` and `FOR_B` (or offset by $S_{\text{arb}}$).

**Non-Uniqueness / Non-Dominance (Corrected Theorem 5.2):** Honest voting is **NOT a dominant strategy**. Any unanimous profile (e.g., all vote `FOR_A` or all vote `FOR_B` regardless of evidence) is also a strict Nash equilibrium in a single-shot coordination game. Truthful reporting relies on focal salience of shared evidence plus round-2 appeal deterrence.

### 5.2 Panel Formation (Updated with VRF & Eligibility Consistency)

**Definition 5.1 (Eligible Arbitrator).** Address `a` is eligible for category `c` iff:
```
a.reputation[(c, SELLER)].count + a.reputation[(c, BUYER)].count ≥ N_arb_min_deals  AND
a.reputation_volume[c] ≥ V_arb_min                                                 AND
(a.arb_score.total_cases < N_arb_min_cases OR a.arb_score.alignment_rate ≥ θ_arb)  AND
a.active = true                                                                    AND
a ∉ {party_a, party_b}                                                             AND
a has no detected financial relationship with party_a or party_b
```

> **`[OPEN — G-06]`:** On-chain financial relationship checks cannot detect off-chain collusion, CEX-funded wallets, or mixers; self-reporting remains non-enforceable cryptographically.

**Algorithm 5.1 (VRF Panel Selection).**
1. Compute eligible set `E = { a : eligible(a, d.category) }`.
2. Require `|E| ≥ k · PANEL_OVERSAMPLE_FACTOR` (if unsatisfied throughout `T_dispute_max`, D3 Compromise triggers).
3. Request verifiable randomness `vrf_seed` from a decentralized VRF oracle (e.g., Chainlink VRF / drand); `block.prevrandao` MUST NOT be used alone for disputes above trivial thresholds.
4. Shuffle `E` with `vrf_seed` using Fisher–Yates and select `P = E[0 : k]` (or fallback pool if `category.parent ≠ ⊥`, optional).
5. Selected arbitrators lock `arbitrator_stake` within `T_panel_accept` (D4). Missing seats are redrawn via `e_redraw` up to `T_dispute_max`.

### 5.3 Evidence and Commit-Reveal Voting (Added per v0.2 instructions & D5)

```
EvidenceWindow := [opened_at, opened_at + T_evidence]
CommitWindow   := [opened_at + T_evidence, opened_at + T_evidence + T_commit]
RevealWindow   := [commit_deadline, commit_deadline + T_reveal]
```

1. **Evidence:** `party_a` and `party_b` submit IPFS CIDs during `EvidenceWindow`. Record freezes at `opened_at + T_evidence`.
2. **Commit:** Each panelist `p_i ∈ P` submits `commit_i = H(d.id || d.round || d.attempt || p_i || vote_i || salt_i)` where `vote_i ∈ {FOR_A, FOR_B}`.
3. **Reveal:** Each panelist reveals `(vote_i, salt_i)`. Uncommitted or unrevealed votes are marked `UNREVEALED` and penalized identically to minority votes (`Penalty_i`).

### 5.4 Quorum, Majority, Stakes, and Rewards (Updated per D4, D5)

**Definition 5.2 (Quorum & Majority, D5).** Let `valid_votes = |{i : vote_i ∈ {FOR_A, FOR_B}}|`, `v_A = |{i : vote_i = FOR_A}|`, `v_B = |{i : vote_i = FOR_B}|`.
- **Quorum condition:** `valid_votes ≥ Q_arb` (where `Q_arb > k / 2` is a governable parameter; minimum `⌊k/2⌋ + 1`).
- **Verdict:**
  - `FOR_A` iff `valid_votes ≥ Q_arb` AND `v_A > v_B`
  - `FOR_B` iff `valid_votes ≥ Q_arb` AND `v_B > v_A`
  - `NO_DECISION` (quorum missed or `v_A = v_B`) → triggers `e_redraw` (new panel / extended window) if time permits before `T_dispute_max`, else triggers `e_dispute_timeout` (D3 Compromise).
  - **Zero-vote impossibility:** Neither `party_a` nor `party_b` can win with `0` votes.

**Definition 5.3 (Proportional Arbitrator Stake and Minority Penalty Redistribution, D4).**
- **Stake per arbitrator:**
  $$S_{\text{arb}}(V) = \max\big(\text{floor}(V \cdot \beta_{\text{arb}}),\; S_{\text{arb\_min}}\big)$$
  denominated in **USDC**, where `β_arb > 0` and `S_arb_min` (needed for D9-B `V = 0`) are free governable parameters.
- **Minority / Non-Reveal Penalty:**
  $$\text{Penalty}_i = \text{floor}(S_{\text{arb}}(V) \cdot \lambda) \quad \text{if } v_i \ne \text{majority\_verdict (incl. UNREVEALED)}$$
- **Reward Distribution (D4):** Total minority penalties `Σ_{j ∈ minority} Penalty_j` are distributed **pro-rata to majority arbitrators**, in addition to `R_arbitrator` from `arbitrator_pool` (and `D_dispute` when `FOR_A`, or `appeal_deposit` if appeal upholds).

> **`[OPEN]`:** The exact formula for `R_arbitrator` (fixed minimum vs percentage of `V` vs dynamic `arbitrator_pool` share) remains unfixed in Section 9.

### 5.5 Dispute Distribution at `RESOLVED` (Updated per D2, D6)

Payouts execute **only upon transitioning to `RESOLVED`** (via `e_finalize` after `T_appeal`, or `e_resolve` in round 2):
- **If `FOR_A`:**
  - `party_a` receives `(Agreement.amount - protocol_fee) + seller_deposit`
  - `protocol_fee` allocated per Section 4.5
  - `D_dispute` (round 1) distributed pro-rata to winning majority arbitrators
  - `party_b` receives `buyer_deposit` (0 under D9-A)
- **If `FOR_B`:**
  - `party_b` receives `Agreement.amount + buyer_deposit + D_dispute + floor(seller_deposit × σ)`
  - Remaining `(seller_deposit - floor(seller_deposit × σ))` goes to **Treasury / `keeper_pool`** per `remainder_split` (never burned, D6)
  - `party_a` receives `0`

### 5.6 Appeal & Bribery Cost Bound (Updated per D2, D4)

- Appeal panel size: `k' = 3k + 2` (17 when `k = 5`).
- Appeal deposit: `appeal_deposit = D_dispute × APPEAL_DEPOSIT_MULTIPLIER` (3×).
- **Overturn:** If round-2 verdict ≠ round-1 verdict:
  - Round-1 majority arbitrators lose `100%` of `S_arb(V)`; confiscated stakes are transferred to round-2 majority arbitrators (or split between round-2 majority and appellant per governance config, D4).
  - `appeal_deposit` is returned to appellant; round-1 `D_dispute` follows final verdict.
- **Uphold:** `appeal_deposit` is distributed pro-rata to round-1 majority arbitrators.

**Corrected Bribery Cost Bound (Theorem 5.6):** Ignoring $p + \varepsilon$ conditional smart-contract attacks (which require off-protocol anti-collusion such as MACI), the direct stake-backed cost to bribe a majority in round 1 ($m_1 = \lceil k/2 \rceil$) and round 2 ($m_2 = \lceil k'/2 \rceil$) scales linearly with $V$ under D4:
$$C_{\text{direct}}(V) \ge \big(m_1 + m_2 \lambda\big) S_{\text{arb}}(V) \approx \big(m_1 + m_2 \lambda\big) \beta_{\text{arb}} V$$
Thus direct bribery is unprofitable ($C_{\text{direct}}(V) > V$) iff $\beta_{\text{arb}} > \frac{1}{m_1 + m_2 \lambda}$ (for $k=5, k'=17, \lambda=0.25$: $\beta_{\text{arb}} > \frac{1}{5.25} \approx 0.1905$).

---

## 6. Reputation System (Updated per D11)

### 6.1 Bidirectional Reputation Vector

```
DimensionKey ::= (CategoryId, Role)   -- Role ∈ { SELLER, BUYER }

DimensionScore := {
  count         : ℕ,       -- completed deals in (category, role)
  raw_score     : ℝ≥0,    -- decayed weighted rating sum
  weight_sum    : ℝ≥0,    -- decayed cumulative weight
  volume_usdc   : ℝ≥0,    -- cumulative USDC volume
  rating        : Score,   -- derived smoothed rating
  last_active   : Timestamp
}
```

### 6.2 Bidirectional Update, Value Weighting, and Bayesian Smoothing (D11)

Upon `CLOSED` or `RESOLVED` (with outcome `FOR_A` or `FOR_B`, not `COMPROMISE`), **both** parties may rate each other with `r ∈ {1, 2, 3, 4, 5}` (recorded in the counterparty's respective `(category, Role)` dimension).

> **`[OPEN]`:** Ratings on `EXPIRED` (seller default) remain unspecified in D11 and should be evaluated in v0.3.

**Deal Weight (D11):** For the $n$-th deal of value $V$ (or `D_barter_min` under D9-B):
$$w(n, V) = \big(1 - e^{-n / N_{\text{warmup}}}\big) \cdot g(V), \qquad g(V) = \min\!\left(1,\; \frac{V}{V_{\text{ref}}}\right) \text{ or } \frac{\ln(1 + V/V_{\text{ref}})}{\ln 2}$$
where $V_{\text{ref}} > 0$ is a free governable reference value.

**Continuous Decay + Bayesian Smoothing (D11):** To prevent a single `$0.01` transaction from resetting years of dormancy, stored accumulators decay **continuously** before adding the new deal (using true half-life `ln 2` per D11):
$$\Delta t = t_{\text{now}} - \text{last\_active}, \qquad d(\Delta t) = 2^{-\Delta t / T_{\text{decay}}} = \exp\!\left(-\frac{\Delta t \cdot \ln 2}{T_{\text{decay}}}\right)$$
$$\text{raw\_score}_{\text{new}} = \text{raw\_score}_{\text{old}} \cdot d(\Delta t) + r \cdot w(n, V)$$
$$\text{weight\_sum}_{\text{new}} = \text{weight\_sum}_{\text{old}} \cdot d(\Delta t) + w(n, V)$$
$$\text{rating}_{\text{new}} = \frac{\text{raw\_score}_{\text{new}} + m \cdot \text{prior}}{\text{weight\_sum}_{\text{new}} + m}$$
where `m > 0` (smoothing strength) and `prior ∈ [1, 5]` are free parameters. For display between transactions at time `t_now`:
$$\text{effective\_rating}(t_{\text{now}}) = \frac{\text{raw\_score} \cdot d(t_{\text{now}} - \text{last\_active}) + m \cdot \text{prior}}{\text{weight\_sum} \cdot d(t_{\text{now}} - \text{last\_active}) + m}$$

*(Under this formulation, a micro-deal with $V = 0.01\text{ USDC} \ll V_{\text{ref}}$ contributes $w \approx 0$ and CANNOT restore decayed `raw_score`!)*

---

## 7. DAO Governance (Updated per D8 & Free Timing Parameters)

### 7.1–7.2 Token & Voting Weight
Unchanged from v0.1, except `N_activity_threshold` is explicitly listed as a **FREE** parameter in Section 9 (and recommended to be paired with minimum cumulative volume).

### 7.3 Proposal Lifecycle (Guardian Removed per D8)

```
ProposalState = { PENDING, ACTIVE, SUCCEEDED, DEFEATED, EXECUTED, CANCELLED }
```

| Phase | Duration | Condition to advance |
|---|---|---|
| `PENDING → ACTIVE` | `T_delay` (FREE) | Timelock before voting starts |
| `ACTIVE → SUCCEEDED` | `T_voting` (FREE) | Quorum met (`≥ Q`) ∧ `For > Against` |
| `ACTIVE → DEFEATED` | `T_voting` (FREE) | Quorum not met ∨ `For ≤ Against` |
| `SUCCEEDED → EXECUTED` | `T_timelock` (FREE) | Execution delay elapsed |
| `PENDING / ACTIVE → CANCELLED` | — | **Proposer withdraws ONLY** (`guardian veto` removed per D8) |

**Auto-Expiring Emergency Pause (D8):** If enabled by DAO, a `Paused` state (halting *new* `e_create` / `e_accept` only — never freezing existing withdrawals, `e_finalize`, or `e_dispute_timeout`) MUST automatically expire after `T_pause_max` (`paused_at + T_pause_max`), with no privileged extension without a full DAO vote.

---

## 8. Security Properties (Updated for v0.2)

- **P1 (Escrow Safety):** Funds in escrow are conserved across all states (`trappedFunds = 0`, `burnedStablecoin = 0`) and exit only to `party_a`, `party_b`, arbitrators, keepers, or `treasury`.
- **P2 (Bounded Liveness):** Every agreement in a non-terminal state reaches `{CLOSED, EXPIRED, RESOLVED}` within bounded time (`T_accept`, `deadline`, `T_review`, `T_dispute_max`, `T_appeal`), assuming block progression.
- **P3 (Appealable Finality):** `APPEALABLE` holds funds during `T_appeal`; `RESOLVED` is strictly terminal and immutable.
- **P4 (Commit-Reveal Fairness):** Votes are hidden until `CommitWindow` closes; zero-vote victories are impossible.

---

## 9. Parameter Reference

| Parameter | Symbol | Value / Status | Constraints / Notes |
|---|---|---|---|
| Seller deposit ratio | `α` | `0.10` | `∈ (0, 1)` |
| Seller penalty ratio | `σ` | `0.50` | `∈ (0, 1]` |
| Protocol fee ratio | `φ` | `0.010` | `∈ [0, 0.05]` |
| Minority penalty ratio | `λ` | `0.25` | `∈ (0, 1]` |
| Accept timeout | `T_accept` | `72 hours` | `> 0` |
| Review timeout | `T_review` | `48 hours` | `> 0` |
| Evidence window | `T_evidence` | `48 hours` | `> 0` |
| Commit window | `T_commit` | **FREE** | `> 0` |
| Reveal window | `T_reveal` | **FREE** | `> 0` |
| Max dispute duration | `T_dispute_max` | **FREE** (D3) | `≥ T_evidence + T_commit + T_reveal` |
| Appeal window | `T_appeal` | `72 hours` | `> 0` |
| Reputation half-life | `T_decay` | `365 days` | Exact half-life via `ln 2` (D11) |
| Warm-up constant | `N_warmup` | `20` | `> 0` |
| Arbitrator stake ratio | `β_arb` | **FREE** (D4) | `> 0`; direct-bribery resistance requires `β_arb > 1/(m1 + m2·λ)` |
| Min arb stake (barter) | `S_arb_min` | **FREE** (D4/D9) | `> 0` |
| Arb quorum threshold | `Q_arb` | **FREE** (D5) | `> k / 2` and `≤ k` |
| Min deal amount (D9-A) | `A_min` | **FREE** (D9-A) | `> 0`, e.g., covers `R_keeper` |
| Barter mutual deposit (D9-B) | `D_barter_min` | **FREE** (D9-B) | `> 0`, covers `D_dispute + R_keeper` |
| Remainder split (D6) | `remainder_split` | **FREE** (D6) | Split between `dao_treasury` and `keeper_pool` |
| Bayesian prior & weight | `prior`, `m` | **FREE** (D11) | `prior ∈ [1, 5]`, `m > 0` |
| Reference deal value | `V_ref` | **FREE** (D11) | `> 0` USDC |
| DAO proposal delays | `T_delay, T_voting, T_timelock` | **FREE** | `> 0` |
| DAO emergency pause cap | `T_pause_max` | **FREE** (D8) | Bounded auto-expiry |
| DAO activity threshold | `N_activity_threshold` | **FREE** | `≥ 1` |
| Arbitrator reward | `R_arbitrator` | **`[OPEN]`** | Needs explicit formula |
| First-instance panel size | `k` | `5` (governable) | Odd `≥ 3` |
| Appeal panel size | `k'` | `3k + 2` | `17` for `k = 5` |
| Panel oversample factor | `PANEL_OVERSAMPLE_FACTOR` | `3×` | Pool `≥ 3k` |
| Appeal deposit multiplier | `APPEAL_DEPOSIT_MULTIPLIER` | `3×` | `appeal_deposit = 3·D_dispute` |
| Dispute deposit | `D_dispute` | `5% of deal` | Forfeited on loss (except D3) |
| Keeper reward | `R_keeper` | `0.5 USDC` | Paid per D7 |
| Registration deposit | `D_reg` | `10 USDC` | Refund mechanism `[OPEN — G-04]` |
