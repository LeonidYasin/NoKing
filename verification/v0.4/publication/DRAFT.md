# NoKing: A Game-Theoretic and Formal Verification Study of Decentralized Escrow with Escalating Commit–Reveal Arbitration

> **Status:** Research Draft (`v0.4`) — includes **only** claims backed by bounded `PROVEN-IN-MODEL` proofs (with explicit bounds) or `SUPPORTED` empirical/Monte Carlo parameter sweeps (with conditional behavioral ranges). Negative results and impossibilities are reported explicitly.

---

## 1. Problem Formulation

Trustless peer-to-peer commerce on programmable blockchains requires resolving physical/off-chain delivery disputes without trusted central intermediaries. NoKing combines:
1. A 9-state escrow finite-state machine (`DRAFT → LOCKED → IN_PROGRESS → REVIEW → CLOSED/EXPIRED/DISPUTE → APPEALABLE → RESOLVED`) with seller collateral (`αV`), buyer auto-confirm deadlines (`T_review`), and keeper incentives.
2. Two-tier VRF sortition arbitration (`k ∈ {5,7,9}` in Round 1, `k' = 3k + 2` in Round 2) with commit–reveal, quorum `Q_arb > k/2`, and a 3-level Round-1 escalation chain (`Category → Parent → GLOBAL`) with growing arbitrator rewards prior to a last-resort 50/50 fallback (**F1**).
3. A multi-dimensional on-chain reputation vector combining value-weighted Bayesian subjective ratings (`m, prior, V_ref`) with an objective seller deadline-default reliability score (**F5**).

---

## 2. Formal FSM Model & Verification (`PROVEN-IN-MODEL`)

We model the v0.4 state machine in TLA+ (`NoKingV04.tla`) and its 2-deal concurrent shared-liquidity variant (`NoKingV04_TwoDeals.tla`), checked exhaustively with `TLC2 Version 2.19` under bounded parameters:
- **Properties Verified:** Exact fund conservation (`balA + balB + balArb + balKeeper + balTreasury + escReserve + escrows = TotalInitial`), non-negativity, `payout_count ≤ 1`, zero-vote exclusion (`v_A + v_B ≥ Q_arb ∧ v_A ≠ v_B`), strict deadline mutual exclusion, Round-2 non-compromise finality (`r1_verdict` upheld on Round-2 quorum failure), sealed intermediate tally prior to quorum (**F3**), `100%` `REVIEW` auto-confirm keeper routing (**F4**), seller-only `deadline_defaults` (**F5**), and bounded liveness (`Prop_EventuallyTerminal`).
- **Exhaustive Bounded Verification:** Exhaustive TLC checking over `1 177 344` distinct states (`k=3, Q=2, T_dispute_max=4`) and `305 424` distinct states (`k=5, Q=3`) for a single agreement, plus `141 314` distinct states (`232 854` generated, depth `29`) for the 2-deal concurrent shared-liquidity model (`InitArb = 60`, `PanelCost = 30`), confirms cross-deal escrow isolation, exact conservation, and bounded liveness even when simultaneous disputes starve the shared arbitrator pool and force F1 escalation.
- **Vacuity & Mutation Testing:** After auditing tautological deadline invariants uncovered in v0.2/v0.3, all non-tautological state invariants and `12/12` deliberate protocol mutants (`M1_DropF1Escalation` through `M12_DropTimeoutsDeadlock`) are killed by TLC.

---

## 3. Game-Theoretic & Simulation Results

### 3.1 Analytical Bounds (`PROVEN-IN-MODEL` within game assumptions)
- **Symmetrized Threshold Neutrality:** Paying majority arbitrators an identical `D_dispute`-sized bonus from the losing party (`D_dispute` on `FOR_A`; `seller_deposit` remainder on `FOR_B`) sets the indifference belief threshold at exact `p* = 0.5000` for any `(V, β_arb, S_arb_max)`.
- **Tiered Direct-Bribery Ceiling (`F2`):** Under stake cap `S_arb(V) = min(βV, S_arb_max)`, direct majority bribery across Round 1 and Round 2 (`λ = 0.25`) exceeds deal value `V` if and only if `V ≤ (m_1 + m_2 λ) · S_arb_max`: at `S_arb_max = $1 000`, this yields **`$5 250`** (Tier 1, `k=5/17`), **`$7 000`** (Tier 2, `k=7/23`), and **`$8 750`** (Tier 3, `k=9/29`), enforced at `e_create` as `V_protocol_max`.

### 3.2 Mechanism Ablation & Behavioral Sensitivity (`SUPPORTED`, Conditional)
Across 20 Monte Carlo seeds (`SEEDS = 100..119`, `N = 60`, `f_mal = 30%`, `95%` CI):
- **Leave-One-Out Contributions:** From Full Stack (`1.83% ± 0.26%` wrong verdicts), removing **Appeal** increases errors by **`+21.08` pp** (`22.92%`), removing **Commit–Reveal** adds **`+12.95` pp** (`14.78%`), and removing **Quorum** adds **`+2.42` pp** (`4.25%`).
- **Behavioral Conditionality:** Commit–Reveal's benefit depends directly on the assumed herding parameter `herd`: it contributes `0 pp` (`-1.08 pp`) when `herd = 0`, `+10.22 pp` at `herd = 0.6`, and `+14.92 pp` at `herd = 0.8`. Error rates remain below `5%` only when arbitrator signal noise `η ≤ 0.10` (`4.24%`, jumping to `13.42%` at `η = 0.20`) and coordinated coalition share **`f_mal ≤ 30%`** (`1.86%`, rising to `5.68%` at `35%`, `12.62%` at `40%`, and `39.12%` at `50%`).
- **Liquidity vs. Quality Trade-Off (`F2 OVERSAMPLE = 2×`):** Reducing oversampling from `3×` to `2×` removes Round-2 arbitrator shortages in Pro pools up to `$5 000` (`100% → 0%`) and cuts `$8 750` shortages to `15%`, yet leaves Low/Mid pools (`$400–$600` median) at `100%` shortage for `$5k–$8.75k` deals and allows corrupted `N=36` pools (`≥ 34`) to bypass parent-pool escalation (`9.43%` wrong at `f_mal = 40%` vs `0.32%` in v0.3).

---

## 4. Limitations & Negative Results (Mandatory Disclosure)

1. **Non-Uniqueness of Honest Equilibrium (`FALSIFIED`):** Unanimous conformist strategies (`all FOR_A`, `all FOR_B`) remain strict Nash equilibria in one-shot coordination. Honest voting is only a *focal* Schelling equilibrium contingent on off-chain coordination expectations and effort threshold `R_arb + λ·S_arb > c_e / min(q, 1-q)`.
2. **Unavoidable `p + ε` Smart-Contract Bribery (`FALSIFIED`):** On transparent EVM chains, a Dark DAO conditional bribe reduces the attacker's actual successful cost to `~$12–$20` (`m_1 + m_2` times `ε`) regardless of stake cap, inducing `100%` wrong verdicts when funded.
3. **Bounded Protection Ceiling (`M-04` / `F2`):** Above `V_protocol_max` (`$8 750` at `S_arb_max = $1 000`), decentralized arbitration offers no direct-bribery guarantee.
4. **Conditional F1 Disruption Bound (`X3.1`, Partially `FALSIFIED`):** A 3-level escalation chain (`6` attempts) makes *active* Round-1 quorum sabotage unprofitable (`C_sab > 0.55 V`) within `V_protocol_max`, and barring saboteur re-entry blocks arbitrator reward farming (`EV < 0`). However, if passive `GLOBAL` pool exhaustion occurs (`C_sab = 0`), a dishonest seller still gains **`+0.5487 V`** from the final 50/50 split vs `0` honest outcome.
5. **Dependence on Unvalidated Behavioral Assumptions & Absence of Solidity Code:** Simulation parameters (`herd`, `p_unrev`, `η`, capital distributions) are hypotheses without field-trial calibration, and smart-contract gas/MEV details (including F3 threshold decryption and Fenwick Sum-Tree gas bounds) remain unverified in Solidity.

---

## 5. Open Questions for Future Work (`v0.5 / v1.0`)

1. Replacing the last-resort Round-1 50/50 split with an insured fallback fund so dishonest sellers cannot extract `+0.55 V` during global pool exhaustion.
2. Designing threshold/timelock reveal infrastructure on L2 so F3 intermediate tally concealment holds against mempool/calldata observers.
3. Specifying Milestone Sub-FSM (`G-03`), `D_reg` withdrawal (`G-04`), and empirical calibration via closed testnet pilots.
