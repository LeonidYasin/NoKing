# NoKing: Formal State-Machine and Economic Analysis of Decentralized Escrow with Escalating Commit–Reveal Arbitration

> **Status:** Research & Protocol Pre-Release Draft (`v0.5`) — strictly distinguishes bounded `PROVEN-IN-MODEL` state-machine / algebraic properties (with explicit bounds) from conditional `SUPPORTED` agent-based simulation findings, explicit `FALSIFIED` impossibilities, and `UNVERIFIED` implementation dependencies.

---

## Abstract *(186 words)*

We study **NoKing**, a peer-to-peer escrow and crowdsourced arbitration protocol for off-chain delivery disputes. Starting from naive optimistic escrow rules vulnerable to fund conservation leaks, deadline races, Round-1 split incentives, Round-2 pool starvation, intermediate vote leakage, and keeper MEV kickbacks, we iteratively refine the design across five audited versions (`v0.1–v0.5`). The `v0.5` specification combines: (1) a 9-state escrow finite-state machine with capacity admission control and reservation (**G1**), two-phase draft cancellation, and seller-only objective deadline-default accounting; (2) three-level Round-1 escalation (`Category → Parent → GLOBAL`) with growing juror rewards prior to last-resort 50/50 splitting; and (3) unconditional disjoint-pool appeals with a dynamic liquidity-aware ceiling `V_protocol_max` (**G2**) plus capped, party-excluded keeper bounties (**G3**). Exhaustive bounded model checking (`TLC2`, up to `1,775,352` states single-deal and `756,203` states two-deal concurrent capacity contention) and 13/13 killed specification mutants verify safety, conservation, and passive-exhaustion immunity within model bounds (`PROVEN-IN-MODEL`). Conversely, our mechanism analysis proves strict limits: honest voting is only focal rather than unique, `p + ε` smart-contract bribes induce `100%` errors at any ceiling, intermediate vote secrecy (F3) requires threshold/timelock cryptography on transparent EVMs, and zero-fee `DRAFT` admission permits leveraged capacity DoS (`V5-01`).

---

## 1. Problem Formulation

Decentralized marketplaces for physical or off-chain goods cannot verify delivery cryptographically on-chain. An escrow protocol must therefore couple deterministic collateral state transitions with human subjective arbitration while defending against rational manipulation by buyers, sellers, keepers, and bribed jurors:
1. **FSM Integrity:** Guarantee conservation of escrowed principal (`V`), seller bond (`αV`), dispute deposits, and arbitrator stakes without deadlocks, double payouts, or timing races.
2. **Bribery & Sabotage Resistance Limits:** Ensure neither direct vote-buying nor intentional quorum sabotage (forcing symmetric 50/50 splits) yields positive expected profit below an explicitly stated protocol ceiling.
3. **Liquidity & Keeper Sustainability:** Prevent large agreements from entering arbitration panels that local pools cannot seat under bounded stake distributions, while keeping keeper maintenance profitable at minimum deal sizes (`A_min = 50 USDC`) without creating uncapped MEV kickbacks.

---

## 2. Formal & Economic Model

### 2.1 Agreement State Machine (`v0.5`)
Nine states: `S = { DRAFT, LOCKED, IN_PROGRESS, REVIEW, DISPUTE, APPEALABLE, CLOSED, EXPIRED, RESOLVED }`.
- **Admission (`e_create`, G1 + G2):** Admits deal `(c, V, tier)` iff `V ≥ A_min`, `V ≤ V_protocol_max(c, tier)`, and `CapCheck(c, tier, V)` confirms free local sortition entropy (`2·k`) plus `GLOBAL` / disjoint R2 capacity `Cap_res = κ_cap·(k + k')·S_req(V)`. Insufficient capacity triggers **immediate revert** (no on-chain queue); admitted deals hold `cap_reserved` until reaching any terminal state.
- **Dispute Resolution & Escalation (F1, G2):** Round 1 draws `k ∈ {5, 7, 9}` jurors with commit–reveal quorum `Q_arb > k/2`. Quorum/pool failure escalates `Category (0) → Parent (1) → GLOBAL (2)` with increasing juror rewards (`ΔR`) and permanent re-selection bans for non-revealing jurors. Appeal (`Round 2`, `k' = 3k + 2 ∈ {17, 23, 29}`) **always** selects from a pool disjoint from the Round-1 pool (**G2(a)**); Round-2 timeout preserves `r1_verdict` rather than splitting 50/50.
- **Keeper Auto-Confirm (`G3`):** `REVIEW --e_timeout--> CLOSED` pays `min(R_keeper_max, protocol_fee)` to non-party callers and routes any excess to `dao_treasury` (`k_pay = 0` for `party_a/party_b`).

### 2.2 Behavioral & Economic Model Assumptions
Game-theoretic bounds analyze unilateral payoff deviations (`α=0.10, δ=0.05, φ=0.01, σ=0.50, λ=0.25, λ_unrev=0.50`) and rational bribe prices. Agent-based Monte Carlo sweeps (`SEEDS = 100..119`, `20` independent runs, `95%` CI) treat human parameters as **conditional hypotheses**: default herding `herd = 0.60`, non-reveal `p_unrev = 0.08`, signal error `η = 0.05`, and lognormal arbitrator capital distributions (`Low $400`, `Mid $600`, `Heavy-tail $800`, `Pro $2000`, `N=80`).

---

## 3. Verified Properties and Results

### 3.1 Bounded State-Machine Verification (`PROVEN-IN-MODEL`, with Explicit Bounds)
Checked exhaustively via `TLC2 Version 2.19` (`OpenJDK 17.0.21.1`) in [`verification/v0.5/01_fsm/`](../01_fsm/README.md):
- **Single-Agreement Bounded Safety & Liveness:** [`v05_base.cfg`](../01_fsm/v05_base.cfg) (`PanelSize=3, Q_arb=2, T_dispute_max=4` with partial `RedrawPanel` enabled) across **`1,775,352` generated / `1,114,168` distinct states** (depth `35`, `0` errors), alongside [`v05_panel5.cfg`](../01_fsm/v05_panel5.cfg) (`PanelSize=5, Q_arb=3, Amount=100, V_protocol_max=8750, V_liq_max=5000, ProtocolFee=5, R_keeper_max=2, CapReq=80, T_dispute_max=3, MaxTime=15`) across **`454,910` generated / `272,792` distinct states** (depth `28`, `0` errors), [`atk_v05.cfg`](../01_fsm/atk_v05.cfg), `replay_1..5`, and local-empty [`replay_6_local_empty.cfg`](../01_fsm/replay_6_local_empty.cfg) (`113,690` / `68,198` distinct states), verify exact fund conservation, non-negative balances, `payout_count ≤ 1`, zero-vote exclusion, non-tautological deadline mutual exclusion, **G1** reservation & passive-`GLOBAL`-shortage split impossibility (`Inv_G1NoPassiveExhaustionSplit`), **G2** disjoint Round-2 routing & dynamic ceiling, **G3** keeper cap & party exclusion, **F3** sealed-tally FSM state (`Inv_F3TallySealedUntilQuorum`), **F5** seller-only `deadline_defaults`, and temporal exit (`Prop_EventuallyTerminal`).
- **Two-Deal Concurrent Capacity Contention:** [`twodeals_v05.cfg`](../01_fsm/twodeals_v05.cfg) (`CapReq=35, MaxArbCap=60`) verifies mutual exclusion when Deal 2 waits for Deal 1 termination/release and subsequent termination across **`756,203` generated / `491,115` distinct states** (depth `39`); [`twodeals_concurrent_v05.cfg`](../01_fsm/twodeals_concurrent_v05.cfg) (`CapReq=45, MaxArbCap=100`) verifies simultaneous disputes across **`416,568` generated / `217,559` distinct states** (`0` errors).
- **Mutation Testing:** All **`12/12`** single-deal mutants ([`NoKingV05_Mutants.tla`](../01_fsm/NoKingV05_Mutants.tla)) plus two-deal no-reserve mutant `td_mutant_5_no_reserve` are killed by TLC.

### 3.2 Analytical Direct-Bribery & Sabotage Bounds (`PROVEN-IN-MODEL` within Game Model)
- **Narrow `V_protocol_max` Direct-Bribery Protection ([`02_game_theory_v05.py`](../02_game_theory_v05.py)):** Define liquidity order statistic $S_{\text{cap}}(c, T) = \min(S_{(2k)}(c), S_{(2k')}(P_{\text{R2}}))$ and $S_{\text{liq\_eff}} = \min(S_{\text{arb\_max}}, S_{\text{cap}})$. Under **direct unconditional vote-buying** across Round 1 and Round 2 (`λ = 0.25`) and **`β_arb ≥ 0.20`** (ensuring $(m_1 + m_2\lambda)\beta_{\text{arb}} \ge 1.05 > 1$ below saturation), rational direct bribery costs strictly more than `V` iff `V ≤ V_protocol_max(c, T) = min(8.75·S_arb_max, (m_1+m_2λ)S_liq_eff, V_liq_max)`. At `S_arb_max = $1,000` (`N=80`), Tier 1–3 ceilings equal `$2,449 / $1,686 / $1,130` (`Low $400`), `$3,673 / $2,528 / $1,695` (`Mid $600`), `$5,250 / $3,148 / $1,798` (`Heavy-tail $800`), and `$5,250 / $7,000 / $8,750` (`Pro $2,000`). **This ceiling protects ONLY against independent vote-buying; it provides ZERO protection against conditional `p + ε` bribery.**
- **Conditional F1 Sabotage Deterrence After G1:** Under G1 capacity guarantees (`C_sab > 0`), active 6-attempt sabotage costs `9.0 / 12.0 / 15.0 · S_req(V)`, exceeding dishonest-seller split gain (`+0.5487 V`) by **`3.12×–5.47×`** across all `S_liq_eff ∈ [$300, $1,000]`, while saboteur re-entry bans yield negative arbitrator farming EV (`-λ_unrev·S_arb < 0`).

### 3.3 Conditional Monte Carlo Results (`SUPPORTED`, Explicit Ranges)
- **Fixing Small-Pool Appeal Regression (`V4-09`, [`exp0_unified_v01_v05.csv`](../03_simulation/data/exp0_unified_v01_v05.csv)):** On `N_local = 36, f_mal = 40%` (conditional on `herd = 0.60, p_unrev = 0.08, η = 0.05` and cleaner `Parent` at `0.5·f_mal`), **G2(a)** drops wrong + fallback outcomes from **`9.43% ± 0.75%`** (`v0.4`) back to **`0.32% ± 0.11%`** (`v0.5`), matching `v0.3` (`0.32%`) while avoiding all Round-2 local trapping.
- **Admission Price of G1 + G2 (`κ_cap = 1.25`, [`exp1_g1_capacity_rejection.csv`](../03_simulation/data/exp1_g1_capacity_rejection.csv)):** Total `e_create` rejection rate across `$50–$8,750` demand is **`18.08% ± 1.78%`** (`Low $400`), **`8.48% ± 0.89%`** (`Mid $600`), **`3.72% ± 0.76%`** (`Heavy-tail`), and **`0.54% ± 0.41%`** (`Pro $2,000`).
- **Marginal Ablation of G1–G3 ([`exp4_loo_g1_g2_g3.csv`](../03_simulation/data/exp4_loo_g1_g2_g3.csv), `N_loc=36, f=40%, Mid`):** Removing **G1** introduces `+3.67%` passive `GLOBAL` shortage splits; removing **G2(a)** spikes errors `+9.51` pp (`0.17% → 9.68%`); removing **G2(b)** adds `0.67%` R2 liquidity failures; removing **G3** increases Sybil/MEV kickback potential `3.0×` (`$168.80 → $507.19` per 300 deals).
- **Bounded Keeper Economics (`G3`, [`exp3_g3_keeper_cap.csv`](../03_simulation/data/exp3_g3_keeper_cap.csv)):** Under `φ = 1%, gas = $0.50, A_min = 50, p_rev = 30%`, `R_keeper_max ∈ [$2, $5]` yields positive keeper net profit (`+$143.69` to `+$194.29 / 1,000` deals), retains `+$62.46` (`$2`) down to `+$11.87` (`$5`) for `dao_treasury`, and caps maximum single-deal Sybil-keeper extraction at **`$1.50–$4.50`** (vs `$87.00` on `$8,750` in v0.4).

---

## 4. Limitations and Negative Results (Mandatory Disclosure)

1. **Honest Voting Is Focal, Never Unique (`FALSIFIED`):** Unanimous conformist strategies (`all FOR_A`, `all FOR_B`) remain strict Nash equilibria in one-shot coordination; honest sorting relies on off-chain Schelling salience plus positive effort margin `R_arb + λ·S_arb > c_e / min(q, 1-q)`.
2. **Irreducibility of `p + ε` / Dark DAO Bribery (`FALSIFIED`):** Conditional smart-contract bribes reduce an attacker's net cost upon success to `O((m1 + m2)·ε)` (`~$12–$20`), producing **`100.0%` wrong verdicts when funded** at **any** value ceiling `V_protocol_max`. Stake scaling cannot defend transparent on-chain voting against Dark DAOs.
3. **Dynamic Ceiling & Capacity Throughput Limits (`G1 + G2`):** No direct-bribery guarantee exists above `V_protocol_max(c, T)` (and **even below `S_arb_max`**, setting `β_arb < 0.1905` renders direct Tier-1 bribery `< 1.0 V`, [`02_game_theory.md`](../02_game_theory.md) `V5-03`). Under Low capital (`$400`), G1+G2 rejects `12%–24%` of incoming demand (`κ_cap = 1.0–1.5`).
4. **Zero-Fee `DRAFT` Capacity DoS (`V5-01`, `SUPPORTED`):** Because `e_cancel_exec` / `TimeoutDraft` currently refunds `100%` of `seller_deposit`, an attacker opening `$5,001` (`Tier 3`) fake `DRAFT`s achieves **`95.0×` leverage** — blocking `$100,000` pool capacity with `$1,500` collateral at `~$3.33/day` gas + APR unless `DRAFT` cancellation fees or `e_accept`-deferred reservation are adopted.
5. **Captured Parent & Shared `T_dispute_max` Boundaries (`V5-02, V5-04`):** Disjoint Round-2 appeals (`G2`) fail if the parent pool is equally corrupted (`12.73% ± 1.02%` errors at `f_parent = 40%`). Moreover, sharing a single `T_dispute_max` clock across `L0→L1→L2` allows `L0` stalls to exhaust `GLOBAL`'s time window (`V5-02`).
6. **F3 Platform Dependency (`SUPPORTED`, `IR-01`):** Public EVM plaintext `reveal()` leaks votes via mempool/`calldata`. Simply deferring all reveals until after commit-redraw fails if reveal-stage `e_redraw` is enabled (still leaks `calldata`) or disabled (raises quorum failure `0.57%–3.15%`, `exp5_f3_deferred_reveal.csv`, while remaining open to reveal-withholding bribes). **True F3 secrecy requires threshold/timelock decryption.**
7. **Dependence on Behavioral Hypotheses & Unimplemented Solidity:** All agent-simulation metrics assume uncalibrated human parameters (`herd`, `p_unrev`, `η`, lognormal wealth). No Solidity contracts, Fenwick/order-statistic gas benchmarks (`IR-02`), threshold reveal crypto (`IR-01`), or live pilot data yet exist (`UNVERIFIED`).

---

## 5. Related Work

| System / Paper | Reference *(verified primary source metadata)* | Comparison to NoKing `v0.5` |
|---|---|---|
| **Kleros** | Lesaege, C., Ast, F., George, W. *Kleros Short Paper* (2018 / v1.0.7 2019) | Token-curated PNK court with coherent-voting rewards & exponential appeal sizes; lacks NoKing's physical-escrow FSM, F1 3-level pool escalation, G1 capacity reservation, and objective seller `deadline_defaults` (F5). |
| **Aragon Court** | Cuende, L., Izquierdo, J. / Aragon Network (`aragon/whitepaper`, 2017–2020) | Opt-in digital jurisdiction (`ANJ`/`ANT` stake-weighted sortition, commit–reveal, escalating juries); governance-oriented rather than paired with merchant auto-confirm keeper caps (G3) and per-tier dynamic caps `V_protocol_max` (G2). |
| **UMA Optimistic Oracle & DVM** | Risk Labs / UMA contributors (Cai, R., Lambur, H., Lu, A. et al.), *UMA Data Verification Mechanism: Adding Economic Guarantees to Blockchain Oracles* (2019) | Enforces `CoC > PfC` (Cost of Corruption > Profit from Corruption) over token-holder DVM votes; analogous to NoKing's direct-bribery ceiling `(m1 + m2·λ)·S_liq_eff`, whereas NoKing bounds per-agreement ticket size `V ≤ V_protocol_max` rather than relying on global token market cap alone. |
| **Augur** | Peterson, J., Krug, J. et al. *Augur: A Decentralized Oracle and Prediction Market Platform* (arXiv, 2015; v2.0 2018) | Pioneered crowdsourced reporting with escalating dispute rounds and fork-based resolution; prediction-market resolution rather than two-party merchant collateral & buyer-protection escrow FSM. |
| **Schelling Focal Points** | Schelling, T. C. *The Strategy of Conflict* (1960) | Theoretical basis for salience-driven non-cooperative coordination (`p^* = 0.5`); explains why NoKing's honest voting equilibrium is *focal* yet non-unique (`all FOR_A / FOR_B`). |
| **`p + ε` & Dark DAOs** | Buterin, V. *The P + epsilon Attack* (Ethereum Blog, 2015); Daian, P., Kell, T., Miers, I., Juels, A. *On-Chain Vote Buying and the Rise of Dark DAOs* (IC3, 2018) | Demonstrates that public on-chain vote receipts allow trustless conditional bribes (`p + ε` / Dark DAOs), proving why transparent commit–reveal cannot eliminate vote-buying solely via stake caps. |
| **Decentralized ODR Surveys** | Ast, F., Deffains, B. *When Online Dispute Resolution Meets Blockchain: The Birth of Decentralized Justice*, *Stanford Journal of Blockchain Law & Policy* (2021) | Frames crowdsourced blockchain justice against legacy ODR bottlenecks for low-value cross-border claims (`A_min = 50 USDC` target market in NoKing). |

*(Note: exact bibliographic URLs or DOI numbers not directly retrieved in this session are omitted rather than guessed; full bibliography links to be confirmed by author before camera-ready release.)*

---

## 6. Open Questions & Five Questions for `ethresear.ch`

### Open Protocol Questions (`v0.6 / v1.0`)
- Closing **V5-01** (`DRAFT`-churn capacity DoS: `e_accept` reservation vs non-refundable reservation fee) and **V5-02** (guaranteed `T_l2_min` time floor upon escalating to `GLOBAL`).
- Selecting practical L2 threshold/timelock decryption (**IR-01**) and `O(log N)` stake order-statistic indexing (**IR-02**).
- Specifying Milestone Sub-FSM (`G-03`), `D_reg` refund rules (`G-04`), and empirical calibration via closed testnet trials.

### 5 Questions to Ask `ethresear.ch` Readers
1. **Threshold Decryption on L2s (`IR-01`):** For small jury panels (`k = 5–9`) with a 24h reveal window, is an external timelock network (e.g., Drand) or an optimistic fraud-proofed committee decryptor less brittle in production L2 deployments than committee DKG?
2. **Capacity Reservation DoS vs. UX (`G1 / V5-01`):** To block `95×`-leveraged `DRAFT`-churn capacity starvation without ruining buyer UX, is it better to defer G1 capacity reservation until `e_accept` (risking occasional failed accepts) or keep `e_create` reservation backed by a small non-refundable reservation fee?
3. **Counter-Mitigations to Dark DAOs on Transparent Chains:** Given `p + ε` bribes achieve `100%` subversion once vote proofs are linkable, which privacy primitive (MACI-style key rerandomization vs. TEE attestation vs. juror KYC rotation) offers the best cost/assumption trade-off for marketplace courts?
4. **Order-Statistic Indexing vs. Fixed Collateral Buckets (`IR-02`):** Rather than maintaining an expensive on-chain order-statistic tree to compute $S_{(2k')}$ for dynamic `V_protocol_max`, does bucketed discrete stake counting (`$250 / $500 / $1,000` tiers) introduce any new boundary manipulation vectors?
5. **Captured Local-Parent Hierarchy (`G2 / V5-04`):** In hierarchical category courts (`Category → Parent → GLOBAL`), how should contracts detect correlated capture of a parent category early enough to route appeals directly to `GLOBAL` without enabling cheap griefing of specialized categories?
