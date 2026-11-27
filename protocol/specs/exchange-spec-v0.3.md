# NoKing Protocol — Formal Specification
**Version:** 0.3-draft  
**Status:** Pre-release (incorporating Decisions E1–E7 and W0–W6 refinements)  
**Baseline:** `protocol/specs/exchange-spec-v0.2.md` (v0.2-draft)  
**License:** MIT  

---

## Abstract

This document specifies **NoKing Protocol v0.3-draft**, refining v0.2 to resolve Round-1/Round-2 fallback sabotage (`N-01`), arbitrator liquidity bottlenecks (`N-02`), partial commit-reveal attacks (`N-03/N-05`), zero-fee barter loopholes (`N-06`), `REVIEW` keeper insolvency (`N-07`), and loser review retaliation (`N-09`), per approved Decisions **E1–E7**. Parameters marked **FREE** remain open for DAO/author tuning; values marked **`[RECOMMENDED]`** are derived from v0.3 parameter sweeps and are not binding until ratified.

---

## 1. Notation and Conventions

Same mathematical notation and types as v0.2 (`Address`, `TokenAmount`, `Timestamp`, `TxHash`, `Bytes32`, `Score`, `Weight`, `Role`), plus `Tier ∈ {1, 2, 3}` for deal-size arbitration tiers (E2).

---

## 2. Primitives

### 2.1 Participant
Unchanged from v0.2.

> **`[OPEN, v1.0]` (`G-04`):** Refund / withdrawal conditions for registration deposit `D_reg` remain deferred to v1.0.

### 2.2 Category
Unchanged (`id`, `name`, `parent : Category | ⊥`). `parent` (and `GLOBAL` root fallback) is explicitly invoked in **E1** Round-1 escalation (`§5.2`).

### 2.3 Agreement (Updated per E4)

- **Minimum Deal Amount (E4):** `Agreement.amount ≥ A_min > 0`. Zero-amount barter (`amount = 0`, Variant D9-B) is **prohibited** at the protocol layer.
- `buyer_deposit` is removed (only `seller_deposit = floor(Agreement.amount × α)` exists).
- `tier : uint8` records the deal-size tier (`§5.4`, E2) at creation.
- `draft_cancel_lock_until : Timestamp` (optional anti-front-running window or block guard for `N-08`, see `§3.3`).

### 2.4 Milestone

> **`[OPEN, v1.0]` (`G-03`):** The Milestone Sub-FSM transition table and per-milestone slashing remain deferred to v1.0.

### 2.5 Dispute (Updated per E1, E2, E3)

```
Dispute := {
  id              : uint32,
  agreement_id    : TxHash,
  opened_by       : Address,          -- party_b
  opened_at       : Timestamp,
  deposit         : TokenAmount,      -- D_dispute (round 1) or appeal_deposit (round 2)
  round           : uint8,            -- 1 = first instance, 2 = appeal
  escalated       : Bool,             -- true if Round 1 escalated to parent/global pool (E1)
  attempt         : uint8,            -- partial re-draw counter within round (E3)
  panel           : List<Address>,
  arb_stakes      : Map<Address, TokenAmount>, -- capped proportional USDC stake (E2)
  commits         : Map<Address, Bytes32>,
  votes           : Map<Address, Vote>,        -- FOR_A | FOR_B | UNREVEALED
  commit_deadline : Timestamp,
  vote_deadline   : Timestamp,
  max_deadline    : Timestamp,        -- opened_at + T_dispute_max (or T_appeal_dispute_max)
  outcome         : Outcome | ⊥
}

Outcome ::= { verdict: FOR_A | FOR_B | SPLIT_50_50, split: Map<Address, TokenAmount> }
```

---

## 3. Agreement State Machine

### 3.1 State Set & Event Set
State set `S = { DRAFT, LOCKED, IN_PROGRESS, REVIEW, DISPUTE, APPEALABLE, CLOSED, EXPIRED, RESOLVED }` (unchanged from v0.2).  
Events `E` add `e_escalate` (Round-1 escalation to `Category.parent` / `GLOBAL` pool per **E1**) and retain `e_redraw` (partial missing-seat redraw per **E3**).

### 3.2 Transition Table `δ : S × E → S` (Key Updates in v0.3)

| # | Current State | Event | Next State | Preconditions & Economic Effect |
|---|---|---|---|---|
| 1 | ∅ | `e_create` | `DRAFT` | `msg.sender = party_a`, `amount ≥ A_min` (E4), `seller_deposit` transferred |
| 2 | `DRAFT` | `e_accept` | `LOCKED` | `msg.sender = party_b`, `amount` transferred, `t_now < created_at + T_accept` |
| 3 | `DRAFT` | `e_cancel` | `EXPIRED` | `msg.sender = party_a`, **`t_now ≥ created_at + T_cancel_grace`** (`N-08` mitigation; prevents same-block/instant griefing) — refunds `seller_deposit` |
| 4 | `DRAFT` | `e_timeout` | `EXPIRED` | `t_now ≥ created_at + T_accept` — refunds `seller_deposit` to `party_a` |
| 5–10 | `LOCKED..REVIEW` | `e_start..e_dispute` | `...` | Same strict guards (`t_now < deadline`, `t_now < submit_time + T_review`), `D10` `σ` penalty on `LOCKED → EXPIRED`, `D7` keeper fee |
| 11 | `DISPUTE` | `e_redraw` | `DISPUTE` | `msg.sender = ArbitrationContract`, `UNREVEALED` or tie; **replaces only missing seats** (`E3`) while `t_now + T_commit + T_reveal ≤ max_deadline` |
| 12 | `DISPUTE` | `e_escalate` | `DISPUTE` | `round = 1`, `escalated = false`, category pool `< 3k` or attempt failed (`E1`) — switches to `Category.parent` / `GLOBAL` pool |
| 13 | `DISPUTE` | `e_resolve` | `APPEALABLE` | `round = 1`, valid majority (`v_A + v_B ≥ Q_arb`, `v_A ≠ v_B`) — sets `resolve_time = t_now` |
| 14 | `DISPUTE` | `e_resolve` | `RESOLVED` | `round = 2`, valid majority — terminal, payouts executed |
| 15a | `DISPUTE` | `e_dispute_timeout` | `RESOLVED` | `round = 1`, `escalated = true` (or no parent) ∧ `t_now ≥ opened_at + T_dispute_max` — **E1 50/50 Fallback Split** (`§4.4`) |
| 15b | `DISPUTE` | `e_dispute_timeout` | `RESOLVED` | `round = 2` ∧ `t_now ≥ opened_at + T_dispute_max` — **E1 Round-2 Finality:** Round-1 verdict `r1_verdict` stands; only `appeal_deposit` returned to appellant |
| 16–17 | `APPEALABLE` | `e_appeal` / `e_finalize` | `DISPUTE` / `RESOLVED` | `e_appeal` (`t_now < resolve_time + T_appeal`, `round = 2`); `e_finalize` (`t_now ≥ resolve_time + T_appeal`, anyone) |

---

## 4. Escrow Mechanics

### 4.1–4.3 Deposits, Happy Path, and Expiry
Same as v0.2 with D9-B removed (**E4**) and `amount ≥ A_min` (**E4, E5**).  
- **Keeper Funding in `REVIEW → CLOSED` (E5):** Keeper reward `R_keeper = 0.50 USDC` is funded from `keeper_pool` (`10%` of `protocol_fee` across all closed deals when `A_min` is set in the `§9` recommended range, or `100%` of `protocol_fee` on auto-confirmed deals if `A_min ≥ 50 USDC`).

### 4.4 Round-1 Fallback Split (`DISPUTE --e_dispute_timeout--> RESOLVED`, E1)

If Round 1 fails even after parent/global escalation by `T_dispute_max`:
```
half_A          = floor(Agreement.amount / 2)
half_B          = Agreement.amount - half_A
forfeit_B       = D_dispute
forfeit_A       = min(seller_deposit, D_dispute)
refund_dep_A    = seller_deposit - forfeit_A
forfeited_total = forfeit_A + forfeit_B
```
**Distribution of `forfeited_total` (`2 × D_dispute`, E1):**
1. `keeper_fee = min(R_keeper, forfeited_total)` to `e_dispute_timeout` caller (if external; `0` if called by `party_a`/`party_b`);
2. `rem = forfeited_total - keeper_fee`:
   - `50%` (`floor(rem / 2)`) distributed pro-rata among **honest committed/revealed arbitrators** from Round-1 attempts (or to `arbitrator_pool` if zero panels formed);
   - `50%` (`rem - floor(rem / 2)`) to `dao_treasury`.

**Rationale:** Paying `party_a` or `party_b` zero rebate from `forfeited_total` preserves maximum deterrence (`2 × D_dispute` loss), pays external keepers for liveness, and compensates honest arbitrators who spent effort `c_e` before others failed or stalled.

### 4.5 Protocol Fee Allocation
Unchanged from v0.2 (`0.40 dao_treasury`, `0.30 arbitrator_pool`, `0.10 keeper_pool`, `0.20 nkg_buy_burn`; zero USDC burning).

---

## 5. Arbitration Mechanism

### 5.1 Revised Theoretical Statements (W3)
- **Focal Equilibrium Condition (Theorem 5.1–5.2):** Honest voting is a strict focal Nash equilibrium under commit–reveal when $R_{\text{arb}} + \lambda S_{\text{arb}} > c_e / \min(q, 1-q)$ and round-2 appeal overturn threat is credible; it is **not** a unique or dominant strategy.
- **Reward Symmetrization (Proposal):** To eliminate the pro-seller threshold bias ($p^* < 0.5$), majority arbitrators receive the same `D_dispute`-sized bonus regardless of outcome: `D_dispute` from `party_b` if `FOR_A`, or `D_dispute_eq = min(seller_deposit, D_dispute)` from `party_a`'s `seller_deposit` if `FOR_B`, yielding exact neutrality **$p^* = 0.5000$**.

### 5.2 Scalable VRF Sortition & Escalation (E1 + Proposal)
**Algorithm 5.1 (O(log |E|) Sum-Tree Sortition):**
Eligible set `E(c)` (requiring `count ≥ N_arb_min_deals`, `volume ≥ V_arb_min`, **`unique_counterparties ≥ N_arb_unique_min`** per **E6**, and `alignment_rate ≥ θ_arb`) is indexed in an on-chain **Fenwick / Sortition Sum-Tree**, allowing VRF-seeded selection of `k` seats in `O(k · log |E|)` gas instead of `O(|E|)` Fisher–Yates shuffling.
- **Escalation (E1):** If `|E(c)| < 3k` in Round 1 or panel acceptance fails, `e_escalate` expands `E` to `E(c.parent)` (and then `E(GLOBAL)`).

### 5.3 Commit–Reveal & Partial Redraw (E3)
- Unchanged commit/reveal windows (`T_commit`, `T_reveal`), except:
  - **Partial Redraw (E3):** When `valid_votes < Q_arb`, `e_redraw` **retains valid revealed votes** and draws **only `k - valid_votes`** replacement arbitrators for `UNREVEALED` seats (if all `k` revealed and tied, draws `1` tie-breaker or performs full tie redraw).
  - **Non-Reveal Penalty (E3):**
    $$\text{Penalty}_i = \begin{cases} \text{floor}(S_{\text{arb}}(V) \cdot \lambda), & \text{if } v_i \in \{\text{FOR\_A}, \text{FOR\_B}\} \text{ in minority } (\lambda = 0.25) \\ \text{floor}(S_{\text{arb}}(V) \cdot \lambda_{\text{unrev}}), & \text{if } v_i = \text{UNREVEALED } (\lambda_{\text{unrev}} \in (0.25, 1.0]) \end{cases}$$

### 5.4 Tiered Stake Cap & Deal Tiers (E2)
```
S_arb(V) = min(max(floor(V * β_arb), S_arb_min), S_arb_max)
```

| Tier | Deal Size `V` | `k` (R1) | `k'` (R2) | Stake Cap | Direct-Bribery Safe Bound |
|---|---|---|---|---|---|
| Tier 1 | `A_min ≤ V ≤ T1_max` | `5` | `17` | `S_arb_max` | Protected if `V ≤ (5.25)·S_arb_max` |
| Tier 2 | `T1_max < V ≤ T2_max` | `7` | `23` | `S_arb_max` | Protected if `V ≤ (7.00)·S_arb_max` |
| Tier 3 | `T2_max < V ≤ V_protocol_max` | `9` | `29` | `S_arb_max` | Protected if `V ≤ (8.75)·S_arb_max` |

Deals with `V > V_protocol_max` are explicitly outside decentralized direct-bribery guarantees under `S_arb_max` (`W3.2`) and are rejected or require external insured escrow.

### 5.5–5.6 Dispute Distribution & Appeal Delay Compensation (`N-04` + Symmetrization)
- **If `FOR_A`:** `party_a` gets `amount - protocol_fee + seller_deposit`; majority arbitrators split `D_dispute` (+ `R_arbitrator` + minority penalties).
- **If `FOR_B` (Symmetrized):** `party_b` gets `amount + D_dispute + max(0, floor(seller_deposit × σ) - D_dispute_eq)` (or `floor(seller_deposit × σ)` while `D_dispute_eq = min(seller_deposit - floor(seller_deposit × σ), D_dispute)` funds majority arbitrators); remaining `seller_deposit` (if any) goes to `treasury`/`keeper_pool` (never burned).
- **Appeal Uphold (`N-04` mitigation):** When Round 2 upholds Round 1, `appeal_deposit` (`3·D_dispute`) is split: `70%` to Round-1 majority arbitrators and `30%` as **delay compensation** to the Round-1 winner (`party_a` or `party_b`).

---

## 6. Reputation System (Updated per E6)

1. **Loser Rating Prohibition (E6):** In `RESOLVED` (`FOR_A` or `FOR_B`), **only the winning party** may rate the losing party (`r ∈ {1..5}`). In `CLOSED`, both parties may rate each other (`(CategoryId, Role)`).
2. **Rating on Seller Default (`EXPIRED`, E6):** When `LOCKED / IN_PROGRESS --e_timeout--> EXPIRED`, `party_b` may submit a seller rating `r ∈ {1..5}` (recording default into `party_a`'s `(CategoryId, SELLER)` vector with value weight `w(n, V)`).
3. **Unique Counterparties (E6):** `DimensionScore` tracks `unique_counterparties : uint32` (incremented once per distinct counterparty address with deal value `≥ V_ref`). Arbitrator admission (`§5.2`) and SBTs (`CENTURY_CLEAN`, `TRUSTED_SELLER`) require `unique_counterparties ≥ N_unique_min`.
4. **D11 Formula Retained:** Continuous half-life `2^(-Δt / T_decay)` (`ln 2`), value weight `w(n, V) = (1 - e^(-n/20)) · min(1, V / V_ref)`, Bayesian smoothing `(raw_score + m·prior)/(weight_sum + m)`.

---

## 7. DAO Governance & 8. Security Properties
Unchanged from v0.2 (`guardian` removed, `T_delay/T_voting/T_timelock/T_pause_max` free), with `P2 (Bounded Liveness)` updated for **E1** (Round 1 escalates then 50/50 split; Round 2 defaults to Round-1 verdict).

---

## 9. Parameter Reference (Free Parameters & `[RECOMMENDED]` Ranges per E7)

| Parameter | Symbol | Status in v0.3 | `[RECOMMENDED]` Value / Range (from W4/W5, non-binding) | Justification |
|---|---|---|---|---|
| Min deal amount (E4, E5) | `A_min` | **FREE** | `[50, 250] USDC` (`50` if 100% auto-confirm fee goes to keeper; `250` under 10% split) | Eliminates `REVIEW` keeper deficit (`Exp E`) |
| Arbitrator stake cap (E2) | `S_arb_max` | **FREE** | `[500, 1000] USDC` (paired with `β_arb ∈ [0.10, 0.20]`) | Prevents liquidity crunch up to Tier 2 (`Exp D`) |
| Tier bounds & max deal (E2) | `T1_max, T2_max, V_protocol_max` | **FREE** | `T1=2500, T2=5000, V_max=8750` (for `S_arb_max=1000`) | Matches `V_safe_max = (m1+m2·λ)·S_arb_max` (`W3.2`) |
| Non-reveal penalty (E3) | `λ_unrev` | **FREE** | **`0.50`–`0.75`** (`[0.50, 0.75]`) | `0.50` keeps honest disconnect (`≤5%`) EV > 0 while doubling sabotage cost (`Exp C`) |
| Arbitrator quorum (D5) | `Q_arb` | **FREE** | `⌈(k + 1) / 2⌉` (`3` for `k=5`, `9` for `k'=17`) | Higher `Q_arb` makes quorum-sabotage cheaper (`W3.1`) |
| Commit / Reveal / Max dispute | `T_commit, T_reveal, T_dispute_max` | **FREE** | `T_commit=24h, T_reveal=24h, T_dispute_max=144h` (`6d`) | Fits 2 attempts + 1 escalation within bounded window |
| `DRAFT` cancel grace (`N-08`) | `T_cancel_grace` | **FREE** | `1 hour` (or ≥ 10 blocks) | Prevents instant `e_cancel` front-running |
| Bayesian smoothing (E7) | `m`, `prior`, `V_ref` | **FREE** | **`m ∈ [2, 3]`**, **`prior ∈ [2.5, 3.0]`**, **`V_ref = 50 USDC`** | Suppresses `$0.01` Sybils (`2.5002`) without crushing `$25` sellers (`4.14`, `Exp F`) |
| Unique counterparties (E6) | `N_arb_unique_min`, `N_sbt_unique_min` | **FREE** | `5` (arbitrators), `20` (`CENTURY_CLEAN`) | Multiplies Sybil capital lockup (`5 × $10 = $50`+) |
| Arbitrator base reward (E7) | `R_arbitrator` | **`[RECOMMENDED]`** | `max(5 USDC, floor(0.003 * V / m_maj))` | Covers `c_e = $5` on small deals, scales on large deals |
| `Milestone` & `D_reg` refund | `G-03, G-04` | **`[OPEN, v1.0]`** | Deferred to v1.0 per **E7** | Explicitly outside v0.3 scope |
