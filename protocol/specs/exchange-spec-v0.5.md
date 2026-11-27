# NoKing Protocol — Formal Specification
**Version:** 0.5-draft  
**Status:** Feature-freeze pre-release (incorporating Decisions **G1–G3**, F3 implementation classification, and narrow §8 scope)  
**Baseline:** `protocol/specs/exchange-spec-v0.4.md` (v0.4-draft)  
**License:** MIT

---

## Abstract

This document specifies **NoKing Protocol v0.5-draft**, a **feature-freeze** iteration over v0.4 implementing only Decisions **G1–G3** plus mandatory specification clarifications:
- **G1:** Capacity admission control & pool reservation at `e_create` (eliminating passive `GLOBAL` exhaustion paths into Round-1 50/50 split, `V4-02`).
- **G2:** Unconditional disjoint-pool Round-2 appeal routing regardless of `OVERSAMPLE` + dynamic liquidity-aware ceiling `V_protocol_max(c, tier)` (eliminating `V4-09`).
- **G3:** Capped `REVIEW` auto-confirm keeper reward `R_keeper_max` with excess routed to `dao_treasury` and strict exclusion of `party_a`/`party_b` (mitigating `V4-06`).
- **Scope & Cryptography:** Elevated **§9 Implementation Requirements** clarifying that **F3** intermediate tally concealment requires threshold/timelock cryptography on open EVM, and narrowing **§8** `V_protocol_max` claims strictly to **direct bribery** (non-effective against conditional `p + ε` / Dark DAO bribes).

Parameters marked **FREE** remain non-binding; **`[RECOMMENDED]`** ranges reflect conditional sweeps under explicit behavioral hypotheses in `verification/v0.5/`.

---

## 1. Notation and Conventions

Types and roles match v0.4 (`Address`, `TokenAmount`, `Timestamp`, `TxHash`, `Bytes32`, `Score`, `Weight`, `Role`, `Tier ∈ {1, 2, 3}`, `EscLevel ∈ {0, 1, 2}`), extended with pool capacity accounting primitives `PoolId ∈ Categories ∪ {GLOBAL}` and capacity headroom multiplier `κ_cap ≥ 1` (**FREE**).

---

## 2. Primitives (Updated for G1, G2)

### 2.1 Participant & Reputation Vectors
Retained unchanged from v0.4 (`ReliabilityScore` with volume-weighted `deadline_defaults` per **F5**, arbitrator admission per **M-08** + `default_rate ≤ θ_default_max`).
> **`[OPEN, v1.0]` (`G-04`):** Withdrawal/refund procedure for `D_reg` remains deferred to v1.0.

### 2.2 Category & Escalation Pool State (Updated for G1, G2)
`Category := { id, name, parent : CategoryId | GLOBAL }`.

For each pool `P ∈ Categories ∪ {GLOBAL}` and required per-juror stake `S_req`:
- `E(P)` denotes active eligible arbitrators registered in `P` (`active = TRUE ∧ arb_opt_in = TRUE ∧ default_rate ≤ θ_default_max ∧ cumulative_fee_volume ≥ V_arb_min`).
- `FreeCount(P, S_req)` = count of `u ∈ E(P)` whose unencumbered free arbitrator balance satisfies `free_stake(u) ≥ S_req` and who are not currently reserved/barred.
- `FreeCap(P, S_req)` = `Σ_{u ∈ E(P), free_stake(u) ≥ S_req} free_stake(u) - reserved_cap[P]`, where `reserved_cap[P]` tracks worst-case capital reserved by currently open non-terminal agreements.
- `FreeSeats(P, S_req)` = `FreeCount(P, S_req) - reserved_seats[P]`.

### 2.3 Agreement (Updated for G1, G2)
Added capacity-tracking fields per admitted agreement:
```
AgreementCapacity := {
  tier            : Tier,          -- derived from V_eff = max(amount, pair_volume_window + amount) (M-07)
  req_arb_stake   : TokenAmount,   -- S_arb(amount) = min(max(floor(amount * β_arb), S_arb_min), S_arb_max)
  cap_reserved    : TokenAmount,   -- κ_cap * (k(tier) + k'(tier)) * req_arb_stake (G1)
  seats_reserved  : uint32         -- k(tier) + k'(tier) (G1)
}
```
Admission preconditions checked atomically in `e_create`:
1. **Minimum Amount (`F4`):** `amount ≥ A_min` (**FREE**, `[RECOMMENDED] = 50 USDC`).
2. **Dynamic Direct-Bribery & Liquidity Ceiling (`G2`):** `amount ≤ V_protocol_max(c, tier)` (Section 5.1 & Section 8).
3. **Escalation Chain Capacity Admission (`G1`):** Both Round-1 local sortition entropy (`M-02`) and full worst-case R1+R2 capital & headcount capacity across `(c, P_R2, GLOBAL)` must be available before admitting the deal (Section 4.2). If capacity is insufficient, **`e_create` REVERTS (rejects)** rather than queueing on-chain.

### 2.4 Milestone
> **`[OPEN, v1.0]` (`G-03`):** Milestone Sub-FSM transition table and per-milestone slashing remain deferred to v1.0.

### 2.5 Dispute
Retained from v0.4, with **G2(a)** rule adding `r1_pool : PoolId` and `r1_panel : Set<Address>` so Round 2 is strictly disjoint from Round 1.

---

## 3. Agreement State Machine

State set `S = { DRAFT, LOCKED, IN_PROGRESS, REVIEW, DISPUTE, APPEALABLE, CLOSED, EXPIRED, RESOLVED }`.
Transitions match v0.4 except the **G1**, **G2**, **G3** updates in the table below:

| # | Current | Event | Next | Updated Preconditions & Economic Effect (`v0.4 → v0.5`) |
|---|---|---|---|---|
| 1 | `∅` | `e_create` | `DRAFT` | **G1 + G2:** `amount ≥ A_min`, **`amount ≤ V_protocol_max(c, tier)`**, `CapCheck(c, tier, amount) = TRUE` (otherwise **revert**, no queue); reserves `cap_reserved` & `seats_reserved` on `GLOBAL`/chain pools; `seller_deposit` transferred |
| 3b | `DRAFT` | `e_cancel_exec` | `EXPIRED` | Retained `M-09` (`t_now ≥ cancel_requested_at + T_cancel_delay`), refunds `seller_deposit`, **G1: releases `cap_reserved` & `seats_reserved`** |
| 4,6,9 | `DRAFT`/`LOCKED`/`IN_PROGRESS` | `e_timeout` | `EXPIRED` | Retained `v0.4` (`deadline_defaults` incremented only on #6/#9 per **F5**), **G1: releases `cap_reserved` & `seats_reserved`** |
| 10 | `REVIEW` | `e_confirm` | `CLOSED` | Retained `v0.4` (`protocol_fee` normal split to Treasury/pools), **G1: releases `cap_reserved` & `seats_reserved`** |
| 11 | `REVIEW` | `e_timeout` | `CLOSED` | `t_now ≥ submit_time + T_review`: `party_a` receives `amount - protocol_fee + seller_deposit`; **G3:** if `msg.sender ∉ {party_a, party_b}`, keeper receives `k_pay = min(R_keeper_max, protocol_fee)` and `dao_treasury` receives **`protocol_fee - k_pay`**; if `msg.sender ∈ {party_a, party_b}`, `k_pay = 0` and `100% protocol_fee` goes to `dao_treasury`; **G1: releases capacity** |
| 14 | `APPEALABLE` | `e_appeal` | `DISPUTE` | **G2(a):** sets `round = 2`, **`panel_R2` drawn unconditionally from a pool disjoint from `r1_pool` (`Parent`/`GLOBAL`, or `GLOBAL \ r1_panel` if R1 resolved at `GLOBAL`)**, independent of `OVERSAMPLE` |
| 15a | `DISPUTE` | `e_dispute_timeout` | `RESOLVED` | `round = 1 ∧ esc_level = 2 ∧ t_now ≥ opened_at + T_dispute_max` — **F1 50/50 split unchanged** (after G1, reachable only via active quorum sabotage, never passive pool exhaustion); **G1: releases capacity** |
| 15b,16,17 | `APPEALABLE`/`DISPUTE` | `e_finalize`/`e_resolve`/`e_timeout` | `RESOLVED` | Retained `v0.4` (`R1_UPHELD` on R2 timeout, `DelayComp` on R2 uphold), **G1: releases `cap_reserved` & `seats_reserved`** |

> **Capacity Release Invariant (G1):** Every transition entering a terminal state `{CLOSED, EXPIRED, RESOLVED}` deterministically releases `cap_reserved` and `seats_reserved`.

---

## 4. Escrow, Capacity Admission, and Keeper Economics (G1, G3)

### 4.1 Bounded Keeper Incentive on Auto-Confirm (G3)
- On `REVIEW --e_timeout--> CLOSED`:
  ```
  protocol_fee = floor(Agreement.amount * φ)
  IF msg.sender ∈ {Agreement.party_a, Agreement.party_b} THEN
      keeper_payout = 0
  ELSE
      keeper_payout = min(R_keeper_max, protocol_fee)
  treasury_excess = protocol_fee - keeper_payout
  ```
  where `R_keeper_max` is **FREE** (`[RECOMMENDED] ∈ [2, 5] USDC`) and `A_min` is **FREE** (`[RECOMMENDED] = 50 USDC`).
- When `A_min = 50 USDC` and `φ = 0.01`, `protocol_fee ≥ 0.50 USDC ≤ R_keeper_max`, preserving `100%` per-deal non-negative keeper fee on small deals (`V ≤ R_keeper_max / φ`), while capping single-transaction MEV/kickback rent on large deals at `R_keeper_max` and returning excess fee to `dao_treasury`.
- Addresses `party_a` and `party_b` are strictly barred from receiving `keeper_payout` on their own agreement (`keeper_payout = 0` or caller revert).

### 4.2 Pool Capacity Formula & Rejection Policy (G1)
Let agreement `(c, V, tier)` require stake per arbitrator seat:
```
S_req(V) = min(max(floor(V * β_arb), S_arb_min), S_arb_max)
```
Let `k = k(tier)` and `k' = k'(tier)` (`(5,17), (7,23), (9,29)`). Let `κ_cap ≥ 1` (**FREE**) be the reserve headroom factor accounting for partial-redraw / concurrent lockups (`[RECOMMENDED] κ_cap = 1.25–1.50`).

Define worst-case capacity demand of the agreement:
```
Seats_res(tier) = k(tier) + k'(tier)
Cap_res(V, tier) = κ_cap * Seats_res(tier) * S_req(V)
```
`e_create` admits the agreement **iff all three checks hold** (`CapCheck = TRUE`):
1. **Local Round-1 Pool Check (`M-02` + liquidity):**
   `FreeCount(c, S_req(V)) ≥ OVERSAMPLE_R1 * k(tier)` (where `OVERSAMPLE_R1 = 2`, **FREE**).
2. **Disjoint Round-2 Appeal Pool Check (`G2`):**
   For disjoint pool `P_R2(c) = c.parent` (if `c.parent ≠ GLOBAL` and `FreeCount(c.parent, S_req(V)) ≥ OVERSAMPLE_R2 * k'(tier)`) else `GLOBAL`:
   - If `P_R2(c) ≠ GLOBAL`: `FreeCount(P_R2(c), S_req(V)) - reserved_seats[P_R2(c)] ≥ OVERSAMPLE_R2 * k'(tier)`.
   - In all cases, `GLOBAL` must have disjoint headroom above R1 + concurrent reservations.
3. **Escalation Chain Aggregate Free Capital Check (`GLOBAL`):**
   ```
   FreeCap(GLOBAL, S_req(V))   ≥ Cap_res(V, tier)
   FreeSeats(GLOBAL, S_req(V)) ≥ Seats_res(tier)     (+ redraw headroom)
   ```
   Here `FreeCap(GLOBAL, S_req(V)) = TotalEligibleStake(GLOBAL, S_req(V)) - reserved_cap[GLOBAL]` and `FreeSeats(GLOBAL, S_req(V)) = CountEligible(GLOBAL, S_req(V)) - reserved_seats[GLOBAL]`.

**Why Reject Instead of On-Chain Queue (`G1` Justification):**
If `CapCheck = FALSE`, `e_create` **reverts immediately** rather than placing the agreement in an on-chain queue. Maintaining an on-chain FIFO queue would (i) lock `seller_deposit` for unbounded duration, (ii) introduce queue-stuffing griefing via low-cost queued `DRAFT` churn, (iii) require keeper cranking and re-check races during `e_accept`, and (iv) violate clean finite waiting bounds. Rejection keeps the FSM deadlock-free (`PROVEN-IN-MODEL`), leaves seller liquidity liquid, and delegates waitlisting cleanly to off-chain UX indexers.

**Passive Split Prevention:** Because every open deal reserves `Seats_res = k + k'` and `Cap_res = κ_cap (k + k') S_req` against `GLOBAL`, passive capital shortage at `esc_level = 2` is impossible within the capacity invariant (`PROVEN-IN-MODEL`). The last-resort **F1 50/50 split (`#15a`)** remains unchanged and can now trigger **only** via active arbitrator quorum withholding/sabotage.

---

## 5. Arbitration Mechanism (G2 & F3 Evaluation)

### 5.1 Disjoint Round-2 Appeal, `OVERSAMPLE` Assessment, and Dynamic Ceiling (G2)
- **Panel Sizes (Unchanged per G2(a)):** `k ∈ {5, 7, 9}` (R1), `k' = 3k + 2 ∈ {17, 23, 29}` (R2).
- **Mandatory Disjoint Pool Routing (G2(a)):**
  - Round 2 ALWAYS selects `k'` arbitrators from a pool **disjoint** from the pool that adjudicated Round 1:
    - R1 in `Category` → R2 in `Category.parent` (if eligible disjoint pool exists) or `GLOBAL`.
    - R1 in `Category.parent` → R2 in `GLOBAL \ panel_R1`.
    - R1 in `GLOBAL` → R2 in `GLOBAL \ panel_R1`.
  - No agreement may adjudicate both Round 1 and Round 2 in the same local `Category` pool, eliminating the `V4-09` small captured pool regression (`N=36` staying local under `OVERSAMPLE = 2×`).
- **Role of `OVERSAMPLE` After G2:**
  `OVERSAMPLE` (`2×`, **FREE**) is **removed as a routing selector** for R2 escalation, but is **retained solely as a sortition-entropy & non-reveal redraw buffer** (`|E(P)| ≥ OVERSAMPLE · k_panel`). Removing `OVERSAMPLE` completely (`1×`) would make single panels deterministic upon admission and leave zero unpicked seats for partial `e_redraw`.
- **Dynamic `V_protocol_max(c, tier)` (G2(b)):**
  Let $q_1 = \text{OVERSAMPLE}_{\text{R1}} \cdot k(T)$, $q_2 = \text{OVERSAMPLE}_{\text{R2}} \cdot k'(T) + \text{reserved\_seats}(P_{\text{R2}})$, and let $S_{(q)}(P)$ denote the $q$-th largest free stake among active eligible arbitrators in pool $P$ ($0$ if $|E_{\text{free}}(P)| < q$). Denote $S_{\text{cap}}(c, T) = \min\bigl(S_{(q_1)}(c),\; S_{(q_2)}(P_{\text{R2}})\bigr)$. Because arbitrator stake saturates at $S_{\text{arb\_max}}$, define:
  $$S_{\text{liq\_eff}}(c, T) = \min\bigl(S_{\text{arb\_max}},\; S_{\text{cap}}(c, T)\bigr)$$
  $$V_{\text{liq\_max}}(c, T) = \begin{cases} S_{\text{cap}}(c, T) / \beta_{\text{arb}}, & \text{if } S_{\text{cap}}(c, T) < S_{\text{arb\_max}} \\ +\infty, & \text{if } S_{\text{cap}}(c, T) \ge S_{\text{arb\_max}} \end{cases}$$
  Combined with the direct-bribery ceiling `(m1(T) + m2(T)·λ)·S_liq_eff` (where `m1 = ⌈k/2⌉, m2 = ⌈k'/2⌉, λ = 0.25`):
  $$V_{\text{protocol\_max}}(c, T) = \min\!\Bigl(8.75 \cdot S_{\text{arb\_max}},\;\; (m_1(T) + m_2(T)\lambda)\cdot S_{\text{liq\_eff}}(c, T),\;\; V_{\text{liq\_max}}(c, T)\Bigr)$$
  *(Note: When `β_arb ≥ 0.20`, `V_liq_max = S_liq_eff / β_arb ≤ 5.0 · S_liq_eff ≤ (m1 + m2·λ)·S_liq_eff`, so liquidity itself binds before the direct-bribery multiplier `5.25/7.00/8.75`, except when stake saturates at `S_arb_max`! Conversely, if `β_arb = 0.10`, the direct-bribery factor `(m1 + m2·λ)·S_liq_eff` can be violated below `S_arb_max / β_arb` unless `(m1+m2·λ)·β_arb ≥ 1` or explicit direct-bribery capping is applied. See `[RECOMMENDED] β_arb ≥ 0.20` or explicit min-cap.)*

### 5.2 Commit–Reveal & F3 Status Classification ("Дополнительно")
- **FSM Rule (F3):** `tally_sealed = TRUE` holds in state transitions whenever `valid_votes < Q_arb` (`Inv_F3TallySealedUntilQuorum`, `PROVEN-IN-MODEL` inside the abstract state machine).
- **Analysis of Deferred-Reveal Alternative Without Threshold Cryptography:**
  Suppose the contract splits dispute resolution cleanly into **Phase 1 (Commit + Commit-Only Redraw until `k` valid commits)** and **Phase 2 (Public Plaintext Reveal)** so all reveals happen only after all commit windows (including redrawn seats) close:
  1. *What it solves:* Commit-stage replacement arbitrators see **zero** votes before committing.
  2. *Why it FAILS full F3 equivalence on open EVM:*
     - Plaintext `reveal()` transactions in Phase 2 publish individual votes `(v_A, v_B)` sequentially into public mempool / `calldata`.
     - If any committed juror defaults on `reveal()` leaving `< Q_arb` reveals (non-reveal rate `p_unrev > 0`):
       - **Without post-reveal redraw:** quorum failure spikes (from `O(p_unrev^3)` to `P(Binom(k, 1 - p_unrev) < Q_arb)`), causing higher F1 escalation rates and longer commit latency `(+Δt · k_commit_redraws)` plus higher offline abandonment.
       - **With post-reveal redraw:** newly drawn arbitrators observe all previously decrypted Phase-2 `calldata` votes — breaking **F3** identically to v0.3!
       - **Even without post-reveal redraw:** an attacker observing early plaintext reveals in Phase 2 can conditionally bribe already-committed-but-unrevealed jurors to **withhold** their `reveal()` (`reveal-abort` griefing) to kill quorum cheaply!
  - **Specification Decision:** Deferred-reveal reduces pre-reveal redraw exposure, **but full F3 intermediate tally secrecy is achievable on public EVM ONLY with threshold/timelock encryption** (or L2 encrypted mempool). F3 is therefore classified in **§9 Implementation Requirements** and rated **`SUPPORTED`** overall (**`PROVEN-IN-MODEL` strictly as an FSM rule, NOT as EVM privacy**).

---

## 6. Reputation System

Unchanged from v0.4 (`E6` subjective rating + **F5** objective volume-weighted `deadline_defaults` on `LOCKED / IN_PROGRESS --e_timeout--> EXPIRED` + **M-08** `V_arb_min`).

---

## 7. DAO Governance & Security Properties

Unchanged from v0.4 (`P1–P4`), with `V ≤ V_protocol_max(c, tier)` bound dynamically by **G2(b)** and capacity admitted by **G1**.

---

## 8. Applicability Boundaries («Границы применимости») — Narrow Scope

NoKing Protocol v0.5 enforces two hard on-chain bounds in `e_create`:
1. **Economic Scope — Direct Bribery Only (Independent Vote-Buying Model):**
   `amount ≤ V_protocol_max(c, tier)` ensures that **direct, unconditional vote-buying** across Round 1 and Round 2 (`m1 + m2·λ` majority arbitrators) costs strictly more than `V` when arbitrator stake `S_arb(V)` meets tier requirements (at `S_arb_max = 1000 USDC` and full liquidity: `$5,250` Tier 1, `$7,000` Tier 2, `$8,750` Tier 3; dynamically scaled down under constrained pool liquidity per **G2(b)**).
2. **Capacity Bound (G1):**
   Open simultaneous agreement exposure cannot exceed `FreeCap(GLOBAL) / κ_cap`. Excess agreements are rejected (`revert`) in `e_create`.

**Explicit Non-Guarantees (Mandatory Disclosure):**
1. **`p + ε` / Dark DAO Smart-Contract Bribery (`FALSIFIED`):** Conditional smart-contract bribes reduce an attacker's net cost upon success to `O((m1 + m2)·ε)` (`~$12–$20`), yielding `100%` error rate when funded at **ANY** value ceiling `V_protocol_max`, regardless of `S_arb_max`. Dynamic `V_protocol_max` does **NOT** defend against `p + ε`.
2. **Correlated Collusion `f_mal > 1/3` (`FALSIFIED` above ~30–35%):** Disjoint R2 panels (`G2`) protect only if the parent/global pool is cleaner than a compromised local category; if both local and parent pools are captured (`f_mal ≥ 40%`), error rates converge to the captured-pool rate.
3. **Focal Equilibrium Non-Uniqueness (`FALSIFIED`):** Honest voting remains a *focal Schelling equilibrium*, not a unique Nash equilibrium.
4. **Behavioral Hypotheses:** All quantitative error/liquidity/keeper metrics depend conditionally on assumed behavioral parameters (`herd`, `p_unrev`, `η`, capital distributions, `gas`, collusion).

---

## 9. Implementation Requirements (Outside FSM Verification)

*(New section per Y1: protocol properties that hold at FSM level or are necessary on target EVM L2, but CANNOT be proven solely by TLA+ state transitions.)*

| ID | Requirement | Why FSM Does Not Guarantee EVM Correctness | Target Platform Obligation | Verification Status |
|---|---|---|---|---|
| **IR-01 (F3)** | **Threshold / Timelock Vote Decryption** | Plaintext `reveal()` transactions expose votes in public mempool / `calldata`; deferred commit-then-reveal still leaks during partial Phase-2 reveals if post-reveal redraw or reveal-withholding occurs | Implement BLS threshold decryption committee or Drand/timelock encryption so `(v_A, v_B)` decrypts only once `commits ≥ Q_arb` (or batched single-block reveal) | `SUPPORTED` *(FSM rule `PROVEN-IN-MODEL`; EVM privacy `UNVERIFIED` until crypto audit)* |
| **IR-02 (G1/G2)** | **O(1) / O(log N) Stake-Indexed Pool Accounting** | Iterating over `E(P)` order statistics `S_{(q)}` on EVM hits block gas limits for large pools | Maintain Fenwick / red-black order-statistic tree (or tiered stake buckets matching `Tier 1–3`) updated on stake/lock/release | `UNVERIFIED` *(gas & Solidity audit needed)* |
| **IR-03 (G3)** | **Sybil-Keeper Competition & Gas Floor** | Blocking `{party_a, party_b}` on-chain does not stop `party_a` from invoking `e_timeout` from a fresh EOA (`sybil_a`) to extract `R_keeper_max` | Cap net extractable rent via low `R_keeper_max ∈ [$2, $5]` + public MEV keeper competition (`priority fee` erosion) | `SUPPORTED` *(bounded residual gain `≤ R_keeper_max - gas`)* |
| **IR-04 (M-07)** | **Bounded Ring-Buffer Split-Guard (`T_split_window`)** | Unbounded historical tranche lists can OOG; must prune/overwrite O(1) slots | Constant-size rolling bucket accumulator per pair `(party_a, party_b)` | `UNVERIFIED` *(Solidity audit needed)* |
| **IR-05 (VRF)** | **Unbiasable Sortition Entropy (Chainlink VRF / RANDAO+VDF)** | Validator/sequencer block-hash grinding can skew panel selection | Use verifiable VRF with stake-weighted Fenwick Sum-Tree (`OVERSAMPLE ≥ 2×`) | `UNVERIFIED` *(external oracle dependency)* |

---

## 10. Parameter Reference (`v0.5`)

| Parameter | Symbol | Status | `[RECOMMENDED]` Value / Range | Conditional Justification |
|---|---|---|---|---|
| Capacity headroom factor (**G1**) | `κ_cap` | **FREE** | `[1.25, 1.50]` | Covers R1+R2 `(k+k')` worst-case seats + redraw buffer |
| Rejected capacity action (**G1**) | — | **Fixed G1** | **Immediate revert** in `e_create` | Zero state bloat / griefing vs on-chain queue |
| Keeper timeout reward cap (**G3**) | `R_keeper_max` | **FREE** | **`[2, 5] USDC`** | Preserves 100% fee on `$50` (`$0.50`) while bounding MEV/Sybil kickback on `$8.75k` |
| Arb stake ratio & cap (**G2**) | `β_arb`, `S_arb_max` | **FREE** | `β_arb = 0.20`, `S_arb_max ∈ [500, 1000]` | Ensures `(m1+m2·λ)·β_arb ≥ 1` (`1.05 V..1.75 V`) below stake saturation |
| Oversample factor (**G2**) | `OVERSAMPLE` | **FREE** | **`2×`** *(entropy/redraw buffer only; NOT R2 routing gate)* | R2 always disjoint from R1; `2×` preserves sortition entropy |
| Dynamic ceiling (**G2**) | `V_protocol_max(c, T)` | **FREE formula** | `min(8.75·S_max, (m1+m2λ)·S_liq, V_liq_max)` | Protects against direct bribery up to available tier liquidity |
| Min deal, escalation, unrev slash, F5 | `A_min, ΔR, λ_unrev, θ_def` | **FREE** | `A_min = 50`, `λ_unrev ∈ [0.5, 0.75]`, `θ_default_max = 0.05` | Retained from v0.4 (`Exp 5–7`) |
| Deferred modules (`G-03`, `G-04`) | — | **`[OPEN, v1.0]`** | Unchanged | Milestone Sub-FSM & `D_reg` withdrawal outside v0.5 |
