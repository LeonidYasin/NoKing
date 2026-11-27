# NoKing Protocol — Formal Specification
**Version:** 0.4-draft  
**Status:** Pre-release (incorporating Decisions F1–F5 and X0–X9 refinements)  
**Baseline:** `protocol/specs/exchange-spec-v0.3.md` (v0.3-draft)  
**License:** MIT  

---

## Abstract

This document specifies **NoKing Protocol v0.4-draft**, revising v0.3 per approved Decisions **F1–F5** to address Round-1 50/50 split incentives (`M-01`), Round-2 arbitrator liquidity exhaustion (`M-04`/`M-05`), intermediate vote leakage during `e_redraw` (`M-03`), `REVIEW` keeper insolvency at `A_min = 50 USDC` (`M-10`), `EXPIRED` accountability (`F5`), and residual Sybil/MEV vectors (`M-02`, `M-07`, `M-08`, `M-09`). Parameters marked **FREE** remain non-binding; **`[RECOMMENDED]`** ranges reflect sensitivity sweeps under explicit behavioral hypotheses documented in `verification/v0.4/`.

---

## 1. Notation and Conventions

Same types as v0.3 (`Address`, `TokenAmount`, `Timestamp`, `TxHash`, `Bytes32`, `Score`, `Weight`, `Role`, `Tier ∈ {1, 2, 3}`), plus `EscLevel ∈ {0, 1, 2}` denoting Round-1 escalation level (`0 = Category`, `1 = Category.parent`, `2 = GLOBAL`).

---

## 2. Primitives

### 2.1 Participant & Reputation Vectors (Updated per F5)
```
Participant := {
  addr                 : Address,
  reg_deposit          : TokenAmount,   -- D_reg = 10 USDC
  active               : Bool,
  arb_opt_in           : Bool,
  reputation           : Map<CategoryId, Map<Role, DimensionScore>>,
  reliability          : ReliabilityScore, -- F5 objective deadline-default tracking
  sbts                 : Set<SBTBadge>
}

ReliabilityScore := {
  committed_count      : uint32,        -- agreements reaching LOCKED+ (excl. DRAFT cancel/timeout)
  deadline_defaults    : uint32,        -- F5: seller defaults ONLY (LOCKED/IN_PROGRESS -> EXPIRED)
  weighted_comm        : Weight,        -- value-weighted committed deals (mitigates wash-dilution)
  weighted_defaults    : Weight,        -- value-weighted seller defaults
  last_default_at      : Timestamp
}
```
> **`[OPEN, v1.0]` (`G-04`):** Withdrawal/refund procedure for `D_reg` remains deferred to v1.0.

### 2.2 Category (Updated for `M-02`)
`Category := { id, name, parent : CategoryId | GLOBAL }`.
- **Category Pool Precondition (`M-02`):** An agreement can select category `c` in `e_create` only if `|E(c)| ≥ OVERSAMPLE · k(tier)` (preventing intentional selection of near-empty custom categories to force immediate routing into a predictable parent pool). `Category.parent` and `GLOBAL` MUST use VRF-indexed Sum-Tree sortition over non-tiny pools (`≥ OVERSAMPLE · k`).

### 2.3 Agreement (Updated per F2, F4, `M-07`, `M-09`)
- **Minimum Deal Amount (F4):** `Agreement.amount ≥ A_min > 0` (`A_min` is **FREE**; `[RECOMMENDED] = 50 USDC`; D9-B barter `amount = 0` and `A_min = 250 USDC` are excluded).
- **Per-Tier Maximum Deal Amount (F2):** `Agreement.amount ≤ V_protocol_max(tier)`, checked on-chain in `e_create`.
- **Rolling Split-Guard Window (`M-07`):** The contract tracks `pair_volume_window[party_a][party_b]` over a rolling window `T_split_window` (**FREE**). Effective tier assignment uses `V_eff = max(Agreement.amount, pair_volume_window[party_a][party_b] + Agreement.amount)` so splitting a Tier-3 deal into `A_min`-sized tranches promotes later tranches into Tier 2/3.
- **Draft Cancel Lock (`M-09`):** `cancel_requested_at : Timestamp | ⊥` supports two-phase cancellation after `T_cancel_grace`.

### 2.4 Milestone
> **`[OPEN, v1.0]` (`G-03`):** The Milestone Sub-FSM transition table and per-milestone slashing remain deferred to v1.0.

### 2.5 Dispute (Updated per F1, F3)
```
Dispute := {
  id              : uint32,
  agreement_id    : TxHash,
  opened_by       : Address,          -- party_b
  opened_at       : Timestamp,
  deposit         : TokenAmount,
  round           : uint8,            -- 1 = first instance, 2 = appeal
  esc_level       : uint8,            -- F1: 0 (Category) -> 1 (Parent) -> 2 (GLOBAL)
  failed_attempts : uint8,            -- F1: count of failed panel/quorum attempts in R1
  current_reward  : TokenAmount,      -- F1: R_arb_base + bonus(failed_attempts) funded from esc_reserve
  tally_sealed    : Bool,             -- F3: true until valid_votes >= Q_arb
  panel           : List<Address>,
  arb_stakes      : Map<Address, TokenAmount>,
  commits         : Map<Address, Bytes32>,
  votes           : Map<Address, Vote>,        -- FOR_A | FOR_B | UNREVEALED
  commit_deadline : Timestamp,
  vote_deadline   : Timestamp,
  max_deadline    : Timestamp
}
```

---

## 3. Agreement State Machine

### 3.1 State Set & Events
`S = { DRAFT, LOCKED, IN_PROGRESS, REVIEW, DISPUTE, APPEALABLE, CLOSED, EXPIRED, RESOLVED }`.
Events add `e_cancel_request` (`DRAFT` anti-frontrunning per `M-09`) and generalize `e_escalate` across `esc_level ∈ {0 → 1 → 2}` per **F1**.

### 3.2 Transition Table Updates (`v0.3 → v0.4`)

| # | Current | Event | Next | Preconditions & Economic Effect |
|---|---|---|---|---|
| 1 | `∅` | `e_create` | `DRAFT` | `msg.sender = party_a`, `amount ≥ A_min` (**F4**), **`amount ≤ V_protocol_max(tier)`** (**F2**), `\|E(c)\| ≥ OVERSAMPLE·k` (`M-02`), `seller_deposit` transferred |
| 2 | `DRAFT` | `e_accept` | `LOCKED` | `msg.sender = party_b`, `amount` transferred, `t_now < created_at + T_accept`, `cancel_requested_at = ⊥` (or not finalized) |
| 3a | `DRAFT` | `e_cancel_request` | `DRAFT` | `msg.sender = party_a`, `t_now ≥ created_at + T_cancel_grace` (`N-08`, `M-09`): sets `cancel_requested_at = t_now`, blocks subsequent `e_accept` |
| 3b | `DRAFT` | `e_cancel_exec` | `EXPIRED` | `msg.sender = party_a`, `cancel_requested_at ≠ ⊥` ∧ `t_now ≥ cancel_requested_at + T_cancel_delay` — refunds `seller_deposit` |
| 6 | `LOCKED` | `e_timeout` | `EXPIRED` | `t_now ≥ deadline` — refund `amount` to `party_b`, `Penalty` (`σ·seller_deposit` - `keeper_fee`) to `party_b`, **increments `party_a.reliability.deadline_defaults` (F5)** |
| 9 | `IN_PROGRESS` | `e_timeout` | `EXPIRED` | `t_now ≥ deadline` — same payout as #6, **increments `party_a.reliability.deadline_defaults` (F5)** |
| 11 | `REVIEW` | `e_timeout` | `CLOSED` | `t_now ≥ submit_time + T_review` — `party_a` receives `amount - protocol_fee + seller_deposit`; **F4: `100%` of `protocol_fee` is transferred to caller (keeper)**; `deadline_defaults` is **NOT** incremented (**F5**) |
| 12a | `DISPUTE` | `e_redraw` | `DISPUTE` | `UNREVEALED` or tie before `commit/reveal` deadline, `t_now + T_commit + T_reveal ≤ max_deadline`: replaces only missing seats; **F3: intermediate tally `(v_A, v_B)` remains sealed until `v_A + v_B ≥ Q_arb`**; if Round 1, increments `failed_attempts` and updates `current_reward` per **F1** |
| 12b | `DISPUTE` | `e_escalate` | `DISPUTE` | `round = 1`, **`esc_level < 2`** (`0 → 1` Parent, `1 → 2` GLOBAL), pool exhausted or attempt failed before `max_deadline` (**F1**): increments `esc_level` and `failed_attempts`, raises `current_reward` according to schedule `R(failed_attempts)` |
| 15a | `DISPUTE` | `e_dispute_timeout` | `RESOLVED` | `round = 1` ∧ **`esc_level = 2`** (escalation chain exhausted) ∧ `t_now ≥ opened_at + T_dispute_max` — **F1 last-resort 50/50 split** (both forfeit `D_dispute`, excess escalated reward reserve unsettled) |
| 15b | `DISPUTE` | `e_dispute_timeout` | `RESOLVED` | `round = 2` ∧ `t_now ≥ opened_at + T_dispute_max` — Round-1 verdict `r1_verdict` stands; `appeal_deposit` returned to appellant (**E1 retained**) |

---

## 4. Escrow & Keeper Mechanics (F1, F4)

### 4.1 Auto-Confirm Keeper Payment (F4)
- On `REVIEW --e_timeout--> CLOSED`: `protocol_fee = floor(Agreement.amount × φ)` is paid **100% to the keeper caller** (replacing the 10% `keeper_pool` split for auto-confirmed deals). When `A_min = 50 USDC` and `φ = 0.01`, `protocol_fee ≥ 0.50 USDC = R_keeper`, guaranteeing per-deal solvency at `p_rev ∈ [0, 1]`.
- On `CLOSED` via `e_confirm` or `RESOLVED` via arbitration: fee allocation remains `0.40 dao_treasury`, `0.30 arbitrator_pool`, `0.10 keeper_pool`, `0.20 nkg_buy_burn`.

### 4.2 Escalation Reward Growth Funding (F1)
For Round-1 attempt counter `j = failed_attempts ∈ {0 .. J_max}`:
```
R_attempt(j) = R_arb_base + ΔR_schedule(j)     -- FREE schedule (additive j·ΔR or exponential R_base·(1+g)^j)
```
- The incremental bonus `ΔR_schedule(j)` is funded from **(i)** `λ_unrev` slashes collected from non-revealing arbitrators in attempt `j - 1` plus **(ii)** `escrow_arb_subsidy` drawn from `arbitrator_pool` / `dao_treasury` (bounded by a hard per-dispute cap `R_esc_cap`).
- An arbitrator who caused non-reveal or declined without slashing **never** receives `R_attempt(j)` and is barred from re-selection in `attempt ≥ j + 1` of the same dispute (`X3.1a` anti-farming rule).

---

## 5. Arbitration Mechanism (F1, F2, F3)

### 5.1 Deal Tiers, `OVERSAMPLE = 2×`, and Stake Cap (F2)
- Minimum eligible pool size to seat a panel of size `k` (Round 1) or `k' = 3k + 2` (Round 2):
  ```
  N_min(k) = OVERSAMPLE · k,     OVERSAMPLE = 2   (F2; reduced from 3 in v0.3)
  ```
- Arbitrator stake:
  ```
  S_arb(V) = min(max(floor(V · β_arb), S_arb_min), S_arb_max)
  ```
- Direct bribery lower bound across R1 (`m1 = ⌈k/2⌉`) and R2 (`m2 = ⌈k'/2⌉`, minority slash `λ = 0.25`):
  ```
  V_safe_max(tier) = (m1(tier) + m2(tier) · λ) · S_arb_max
  ```

### 5.2 Commit–Reveal & Intermediate Tally Concealment (F3)
- **Protocol Rule (F3):** While `valid_votes < Q_arb`, `(v_A, v_B)` MUST NOT be disclosed to incoming `e_redraw` arbitrators or external observers.
- **On-chain Implementation Requirement:** Because cleartext EVM `reveal()` transactions leak intermediate votes in mempool/calldata, v0.4 specifies **commit-check-first partial redraw**:
  1. Missing commitments at `T_commit` are replaced via `e_redraw` **before** any vote is decrypted/revealed (`0` vote leakage).
  2. During `T_reveal`, reveals must use **timelock/threshold encryption** (or batched single-block reveal threshold proof) so `(v_A, v_B)` becomes observable **only once `valid_reveals ≥ Q_arb`** (if threshold reveal fails, remaining seats are redrawn without publishing unreached tally; see `02_game_theory.md` §3 for limits if naive plaintext reveal is used on EVM).

### 5.3 Reward Symmetrization & Appeal Delay Compensation
Retained from v0.3: symmetrical `D_dispute`-sized arbitrator bonus regardless of `FOR_A` vs `FOR_B`, and `30%` of `appeal_deposit` paid to Round-1 winner as `DelayComp` upon appeal uphold (`N-04`).

---

## 6. Reputation System (Updated per F5 & `M-08`)

1. **Subjective Rating (`CLOSED`, `RESOLVED`, retained from v0.3 E6):**
   - Only `party_b` / winner in `RESOLVED` (`FOR_A` / `FOR_B`) may rate the losing side (`r ∈ {1..5}`); both may rate in `CLOSED`.
   - `w(n, V) = (1 - e^(-n / N_warmup)) · min(1, V / V_ref)`, `d(Δt) = 2^(-Δt / T_decay)`, Bayesian smoothing `(raw_score + m·prior)/(weight_sum + m)`.
2. **Objective Seller Reliability Dimension (F5):**
   - Subjective buyer reviews are **not** triggered automatically on `EXPIRED` (`1★` auto-rating excluded per F5).
   - Instead, `LOCKED / IN_PROGRESS --e_timeout--> EXPIRED` deterministically updates `party_a.reliability`:
     ```
     default_rate(a)  = (weighted_defaults(a)) / (weighted_comm(a) + m_rel)
     reliability(a)   = 1 - default_rate(a)      ∈ [0, 1]
     ```
     where each agreement adds `V / V_ref` (un-capped linear volume or `min(V, V_protocol_max)/V_ref`, **NOT** capped at `$50`, preventing `$50` wash deals from diluting a `$5 000` default) decayed by `2^(-Δt / T_decay)`.
   - **Composite Display Score:** `effective_rating(a) = rating(a) · (1 - γ_rel · default_rate(a))` (`γ_rel` **FREE**).
   - **Arbitrator Admission (§5.2) & Sybil Mitigation (`M-08`):** Eligible set `E(c)` requires:
     - `count[c] ≥ N_arb_min_deals`
     - `unique_counterparties ≥ N_arb_unique_min` (with deal size `≥ V_ref`)
     - **`cumulative_fee_volume ≥ V_arb_min`** (`M-08`: enforces non-refundable fee floor against Sybil rings)
     - `alignment_rate ≥ θ_arb` (after `N_arb_min_cases`)
     - **`default_rate ≤ θ_default_max`** (**F5**: excludes chronic deadline defaulters from sitting as arbitrators)

---

## 7. DAO Governance & Security Properties

Unchanged from v0.3 (§7), except `P1–P4` explicitly reference `V ≤ V_protocol_max(tier)` as a precondition.

---

## 8. Applicability Boundaries («Границы применимости») — F2

NoKing Protocol v0.4 **does NOT provide direct-bribery economic security above `V_protocol_max`**. Contracts MUST revert in `e_create` if `Agreement.amount > V_protocol_max(tier)`:

| Tier | `k` (R1) | `k'` (R2) | Min Pool (`OVERSAMPLE = 2×`) | Direct-Bribery Bound (`m1 + m2·λ`, `λ=0.25`) | `V_protocol_max` (`[RECOMMENDED] S_arb_max = 1000 USDC`) |
|---|---|---|---|---|---|
| Tier 1 | `5` | `17` | `10` (R1) / `34` (R2) | `5.25 · S_arb_max` | `≤ 2 500` *(cap safe to `5 250`)* |
| Tier 2 | `7` | `23` | `14` (R1) / `46` (R2) | `7.00 · S_arb_max` | `≤ 5 000` *(cap safe to `7 000`)* |
| Tier 3 | `9` | `29` | `18` (R1) / `58` (R2) | `8.75 · S_arb_max` | **`≤ 8 750 USDC`** *(hard protocol ceiling)* |

**Explicit Non-Guarantees:**
1. Above `V_protocol_max` (or if `S_arb_max` is lowered without scaling `V_protocol_max`), rational direct bribery costs `< V`.
2. Honest voting is a **focal Nash equilibrium**, not a unique equilibrium (`p + ε` smart-contract bribes remain unaddressed on open EVM).
3. Quantitative simulation metrics are **conditional** on assumed behavioral parameters (`herd`, `p_unrev`, `η`, arbitrator capital, coalition behavior).

---

## 9. Parameter Reference (Free Parameters & `[RECOMMENDED]` Ranges)

*(Updated after X3/X4/X5 parameter sweeps in `verification/v0.4/`.)*

| Parameter | Symbol | Status | `[RECOMMENDED]` Value / Range (non-binding) | Conditional Basis / Justification |
|---|---|---|---|---|
| Min deal amount (F4) | `A_min` | **FREE** (`F4 = 50`) | **`50 USDC`** *(acceptable range `≥ 50` under 100% auto-confirm keeper fee)* | `100%` of `φ=1%` covers `$0.50` keeper fee on every deal ≥ `$50` (`Exp 6`) |
| Oversample factor (F2) | `OVERSAMPLE` | **FREE** (`F2 = 2×`) | **`2×`** *(1.5× cuts R2 failure further to `<5%` in Mid)* | Cuts R2 seats needed from `51–87` to `34–58` (`Exp 4`) |
| Stake cap & Tier bounds (F2) | `S_arb_max`, `V_protocol_max` | **FREE** | `S_arb_max ∈ [500, 1000]`, `V_max = 8.75 · S_arb_max` (`$8 750`) | Direct bribery unprofitable iff `V ≤ 8.75 · S_arb_max` (`W3.2`/`X3.2`) |
| F1 escalation chain & growth | `L_esc`, `ΔR_schedule`, `R_esc_cap` | **FREE** | `3` levels (`0,1,2`), `2` attempts/level (`6` total), **additive `ΔR ≤ 0.5 · λ_unrev · S_arb · N / k`** | Keeps sabotage cost `> 0.55 V` up to `$16.3k` (`λ_unrev=0.50, S_max=1000`) while blocking arbitrator reward farming (`X3.1`) |
| Non-reveal penalty | `λ_unrev` | **FREE** | **`[0.50, 0.75]`** | Conditional on `p_unrev ≤ 0.08`; doubles sabotage cost vs `0.25` |
| Arbitrator admission (`M-08`, `F5`) | `V_arb_min`, `θ_default_max` | **FREE** | `V_arb_min ∈ [1000, 2500] USDC`, `θ_default_max = 0.05` | Enforces `$10–$25` Sybil fee cost; blocks chronic defaulters |
| Reliability weight (`F5`) | `m_rel`, `γ_rel` | **FREE** | `m_rel ∈ [3, 5]` (in `V_ref` units), `γ_rel ∈ [0.5, 1.0]` | Value-weighted `V/V_ref` stops `$50` wash dilution of `$2000` defaults (`Exp 7`) |
| Split-guard window (`M-07`) | `T_split_window` | **FREE** | `7 days` (`168 hours`) | Aggregates `(party_a, party_b)` tranche volume to prevent tier bypass |
| Draft cancel delay (`M-09`) | `T_cancel_grace`, `T_cancel_delay` | **FREE** | `T_cancel_grace = 1h`, `T_cancel_delay = 10 min` | Stops instant cancel-accept MEV race |
| Bayesian rating smoothing | `m`, `prior`, `V_ref` | **FREE** | `m ∈ [2, 3]`, `prior ∈ [2.5, 3.0]`, `V_ref = 50 USDC` | Matches `A_min = 50` so honest small deals have `g(V) = 1.0` |
| Deferred modules (`G-03`, `G-04`) | — | **`[OPEN, v1.0]`** | Unchanged | Milestone Sub-FSM & `D_reg` withdrawal outside v0.4 |
