# NoKing: Bounded State-Machine and Economic Analysis of Decentralized Escrow with Escalating Commit–Reveal Arbitration

> **Status:** Pre-Publication Working Draft (`v0.5`) — strictly separates bounded `PROVEN-IN-MODEL` state-machine / algebraic claims (with explicit bounds and log references) from conditional `SUPPORTED` agent-simulation results, explicit `FALSIFIED` counterexamples, and `UNVERIFIED` implementation dependencies. Authored iteratively (`v0.1–v0.5`) with an AI agent under author direction without independent human audit or Solidity code.

---

## Abstract *(196 words)*

We analyze **NoKing**, a peer-to-peer escrow and crowdsourced arbitration protocol for off-chain delivery disputes developed across versions `v0.1–v0.5` using AI-assisted formalization and agent-based simulation directed by the author; because the same AI agent wrote the specification, TLA+ models, and simulator without independent human audit or smart-contract implementation, all claims carry explicit validity limits (Section 5). The `v0.5` design couples a 9-state escrow machine—featuring pool-capacity reservation (`G1`), two-phase draft cancellation, and seller-only deadline-default tracking—with 3-level Round-1 escalation, mandatory disjoint-pool appeals with a dynamic liquidity cap `V_protocol_max` (`G2`), and capped party-excluded keeper bounties (`G3`). Bounded `TLC2` checking over `1,114,168` distinct single-deal states (`k=3`) and `491,115` distinct two-deal states (`G1` contention), alongside `13/13` killed mutants, yields `PROVEN-IN-MODEL` elimination of passive quorum splits caused specifically by insufficient *reserved stake capacity*; however, `G1` does not prevent quorum failure from juror non-reveal or abandonment. Under uncalibrated behavioral assumptions, disjoint appeals reduce wrong verdicts from `9.43%` to `0.32%` (`N=36, f=40%`) only when the parent pool is half as corrupted (`0.5·f`). Finally, `V_protocol_max` resists direct unconditional vote-buying only: `p + ε` Dark DAO bribes cause `100%` error at any ceiling, honest voting is non-unique, and public-EVM vote secrecy (`F3`) remains an unimplemented cryptographic requirement.

---

## 1. Problem Formulation

Decentralized marketplaces for off-chain or physical delivery cannot verify fulfillment cryptographically on-chain. An escrow protocol must pair deterministic collateral state transitions with crowdsourced arbitration while bounding rational manipulation under explicit threat models:
1. **FSM Integrity:** Enforce principal, collateral, and arbitrator-stake conservation without deadlocks, double payouts, or deadline overlap races inside bounded state models.
2. **Economic Manipulation Limits:** bound both *direct unconditional vote-buying* (independent bribery per seat) and *intentional quorum sabotage* toward Round-1 50/50 splits, while acknowledging attacks outside the stake model (conditional `p + ε` bribes).
3. **Capacity & Keeper Sustainability:** Reject agreements when pool liquidity cannot staff both Round 1 and disjoint appeals, while funding auto-confirm keepers at minimum deal size (`A_min = 50 USDC`) without enabling unbounded single-deal MEV extraction.

---

## 2. Methodology and Threats to Validity

### 2.1 Iterative AI-Assisted Development Workflow (`v0.1–v0.5`)
Across iterations `v0.1` through `v0.5`, development followed a recurring human-in-the-loop cycle:
1. The author issued a constrained design or verification specification task (including feature-freeze rules in `v0.5`).
2. An AI coding agent drafted or revised the protocol specification, formalized the TLA+ state machine, coded analytical game-theory scripts and Monte Carlo simulations, and executed checks.
3. The author inspected outputs for methodological flaws, inflated statuses, or unmodeled attack vectors and issued targeted revision tasks for the next version.

### 2.2 Internal Validation Safeguards
Because the **same AI agent authored both the specification and the verification artifacts**, self-validation bias is a primary methodological risk. Four safeguards were enforced before finalizing `v0.5`:
- **Mutation Testing:** `12` single-deal mutants ([`NoKingV05_Mutants.tla`](../01_fsm/NoKingV05_Mutants.tla)) and `1` concurrent two-deal mutant ([`NoKingV05_TwoDeals_Mutants.tla`](../01_fsm/NoKingV05_TwoDeals_Mutants.tla)) inject deliberate regressions across **G1–G3**, F1, F3, F5, zero-vote exclusion, and deadlock recovery; all `13/13` are caught by TLC.
- **Invariant Vacuity Checks & Retractions:** Using `TLC2 -coverage 1`, every invariant antecedent was verified to execute non-vacuously. Earlier `v0.1`/`v0.2` deadline-race claims (`fixed_all` lacking the invariant; `v02_d9a/b` arithmetic tautologies) were formally retracted in `v0.4` ([`X0_methodology.md`](../../v0.4/X0_methodology.md)) and replaced by state-predicate invariants (`Inv_NoDeadlineRace`, `Inv_NoSimultaneousEnablement`).
- **Unified RNG Harmonization (`v0.1–v0.5`):** Cross-version error regressions in `v0.4` (`1.43%` unified vs `1.83%` ablation) were inspected to isolate seed-offset drift (`seed+300` vs `seed+200`) and re-run on identical RNG streams ([`Y0_reporting_fixes.md`](../Y0_reporting_fixes.md)).
- **Ablation & Behavioral Sweeps:** Leave-one-out ablations in [`exp2_leave_one_out_ablation.csv`](../../v0.4/03_simulation/data/exp2_leave_one_out_ablation.csv) and [`exp4_loo_g1_g2_g3.csv`](../03_simulation/data/exp4_loo_g1_g2_g3.csv) plus sweeps over `herd`, `p_unrev`, and `η` expose where individual components lose effectiveness.

### 2.3 Remaining Threats to Validity
1. **Single-Agent Shared Blind Spots:** Any misinterpretation shared between the agent's reading of the spec and its encoding in TLA+/Python can survive both checks simultaneously.
2. **No Independent Human Audit:** No third-party formal-methods reviewer, cryptographer, or Solidity security auditor has verified [`exchange-spec-v0.5.md`](../../../protocol/specs/exchange-spec-v0.5.md) or any model.
3. **Bounded Verification Scope:** Exhaustive `TLC2` runs check finite `Amount = 100`, `MaxTime ∈ [10, 15]`, small panels (`k=3, 5`), and at most `2` concurrent deals; arbitrary `N`-deal concurrency and integer arithmetic edge cases are not proven.
4. **Uncalibrated Human Parameters & Absent Implementation:** All simulation probabilities (`herd`, `p_unrev`, `η`, lognormal wealth distributions) are synthetic hypotheses; no Solidity smart contracts or L2 gas/MEV measurements exist.

---

## 3. Protocol Model & Core Properties

### 3.1 Formal State-Machine Results (`PROVEN-IN-MODEL`, Bounded)
We model [`exchange-spec-v0.5.md`](../../../protocol/specs/exchange-spec-v0.5.md) in TLA+ ([`NoKingV05.tla`](../01_fsm/NoKingV05.tla) and [`NoKingV05_TwoDeals.tla`](../01_fsm/NoKingV05_TwoDeals.tla)) and check exhaustively via `TLC2 Version 2.19` (`OpenJDK 17.0.21.1`):

| Configuration | Bounds (key constants) | Generated States | Distinct States | Depth | Outcome | TLC Log |
|---|---|---|---|---|---|---|
| Single-deal `v05_base` | `PanelSize=3, Q_arb=2, Amount=100, V_liq_max=5000, ProtocolFee=5, R_keeper_max=2, CapReq=80, T_dispute_max=4, MaxTime=16` | `1,775,352` | **`1,114,168`** | `35` | `0` errors (`PROVEN-IN-MODEL`) | [`v05_base.log`](../01_fsm/logs/v05_base.log) |
| Single-deal `v05_panel5` | `PanelSize=5, Q_arb=3, T_dispute_max=3, MaxTime=15` | `454,910` | **`272,792`** | `28` | `0` errors (`PROVEN-IN-MODEL`) | [`v05_panel5.log`](../01_fsm/logs/v05_panel5.log) |
| Attacks & `v0.1` replays `1..5` | Same as `v05_panel5` (`atk_v05`, `replay_1..5`) | `454,910` | **`272,792`** | `28` | `0` errors (`PROVEN-IN-MODEL`) | [`atk_v05.log`](../01_fsm/logs/atk_v05.log) |
| Local pools empty `replay_6` | `pool_l0_ok=FALSE, pool_l1_ok=FALSE, G1 => pool_l2_ok=TRUE` | `113,690` | **`68,198`** | `28` | `0` errors (`PROVEN-IN-MODEL`) | [`replay_6_local_empty.log`](../01_fsm/logs/replay_6_local_empty.log) |
| Two-deal admission contention | `Deals={1,2}, CapReq=35, MaxArbCap=60, PanelSize=3, ArbStake=10, MaxTime=12` | `756,203` | **`491,115`** | `39` | `0` errors (`PROVEN-IN-MODEL`) | [`twodeals_v05.log`](../01_fsm/logs/twodeals_v05.log) |
| Two-deal parallel disputes | `Deals={1,2}, CapReq=45, MaxArbCap=100, PanelSize=2, ArbStake=10, MaxTime=10` | `416,568` | **`217,559`** | `34` | `0` errors (`PROVEN-IN-MODEL`) | [`twodeals_concurrent_v05.log`](../01_fsm/logs/twodeals_concurrent_v05.log) |

**Scope of Bounded Verification:** Within these bounds, `TLC2` establishes exact fund conservation, `payout_count ≤ 1`, zero-vote exclusion, non-tautological deadline exclusion, **G1** reservation lifecycle and absence of passive `GLOBAL` *stake-capacity* exhaustion (`Inv_G1NoPassiveExhaustionSplit`, [`v05_base.log`](../01_fsm/logs/v05_base.log)), **G2** disjoint Round-2 routing (`Inv_G2DisjointR2Pool`), **G3** keeper cap (`≤ R_keeper_max`) and party exclusion, **F5** seller-only `deadline_defaults`, and temporal termination (`Prop_EventuallyTerminal`).  
**What G1 Does NOT Establish:** `G1` prevents passive `50/50` splits caused by *unfunded `GLOBAL` arbitrator stake capacity* (`pool_l2_ok = FALSE` in FSM). It does **not** guarantee arbitrator attendance or commit-reveal participation (`p_unrev`, `p_attempt_fail`): if active panels repeatedly fail quorum or time out across escalation steps, `TimeoutR1Split5050` remains reachable (`2,856` occurrences in [`v05_base.log`](../01_fsm/logs/v05_base.log)).

### 3.2 Analytical Economic Bounds (`PROVEN-IN-MODEL` Formula vs. `SUPPORTED` Numerical Ceilings)
- **Analytical Direct-Bribery Ceiling (`PROVEN-IN-MODEL` within Independent Vote-Buying Model, [`02_game_theory.md`](../02_game_theory.md) §4):** Let $S_{\text{cap}}(c, T) = \min\bigl(S_{(2k)}(c),\; S_{(2k')}(P_{\text{R2}})\bigr)$ denote the minimum $(2k)$-th / $(2k')$-th free arbitrator stake in Round 1 / disjoint Round 2, $S_{\text{liq\_eff}} = \min(S_{\text{arb\_max}}, S_{\text{cap}})$, and $V_{\text{liq\_max}} = S_{\text{cap}}/\beta_{\text{arb}}$ when $S_{\text{cap}} < S_{\text{arb\_max}}$ ($+\infty$ otherwise). Under **direct unconditional vote-buying** across Round 1 and Round 2 ($\lambda = 0.25$) and **`β_arb ≥ 0.20`**, bribery cost exceeds deal value $V$ within:
  $$V_{\text{protocol\_max}}(c, T) = \min\Bigl(8.75 \cdot S_{\text{arb\_max}},\;\; (m_1(T) + m_2(T)\lambda)\cdot S_{\text{liq\_eff}}(c, T),\;\; V_{\text{liq\_max}}(c, T)\Bigr)$$
  - *Mandatory `β_arb` Condition (`V5-03`):* Below `S_arb_max`, linear stake $S_{\text{req}} = \beta_{\text{arb}} V$ satisfies $(m_1 + m_2\lambda)\beta_{\text{arb}} \ge 1$ in Tier 1 (`5.25·β_arb ≥ 1`) **if and only if `β_arb ≥ 1/5.25 ≈ 0.1905`** ([`02_game_theory_v05.out`](../02_game_theory_v05.out)). Setting `β_arb = 0.10` yields direct-bribery costs `0.525 V < V` in Tier 1 (`V5-03`).
  - *Threat-Model Restriction:* This formula applies **strictly to independent direct bribery**; it provides **no mitigation against conditional `p + ε` / Dark DAO bribery**.
- **Capital-Dependent Dynamic Ceilings (`SUPPORTED`, Conditional on Lognormal Wealth Hypotheses, `N=80, β_arb=0.20, S_arb_max=$1,000`):** From order-statistic quantiles ([`02_game_theory_v05.out`](../02_game_theory_v05.out)), illustrative Tier 1 / Tier 2 / Tier 3 ceilings are **`$2,449 / $1,686 / $1,130`** (`Low $400, σ=1.0`), **`$3,673 / $2,528 / $1,695`** (`Mid $600, σ=1.0`), **`$5,250 / $3,148 / $1,798`** (`Heavy-tail $800, σ=1.4`), and **`$5,250 / $7,000 / $8,750`** (`Pro $2,000, σ=1.1`). Because concrete values depend on uncalibrated stake distributions, all numerical ceiling figures hold status **`SUPPORTED`**.
- **Conditional F1 Sabotage Ratio (`SUPPORTED` / `PROVEN-IN-MODEL` Cost Ratio):** Within dynamic $V_{\text{protocol\_max}}$ (assuming G1 capacity and 6 non-stalled escalation attempts, $\beta=0.20, \lambda_{\text{unrev}}=0.50$), active quorum-sabotage penalties ($9.0\text{–}15.0 \cdot S_{\text{req}}$) exceed dishonest-seller split gain (`+0.5487 V` with 6d delay at 8% APR) by **`3.12×–5.47×`** across $S_{\text{liq\_eff}} \in [\$300, \$1\,000]$ ([`02_game_theory_v05.out`](../02_game_theory_v05.out)).

### 3.3 Conditional Simulation Results (`SUPPORTED`, `SEEDS = 100..119`, `95%` CI)
Default behavioral hypothesis unless swept: `herd = 0.60, p_unrev = 0.08, η = 0.05`.

1. **Dependence of G2 Disjoint-Appeal Gains on Parent-Pool Cleanliness ([`exp0_unified_v01_v05.csv`](../03_simulation/data/exp0_unified_v01_v05.csv) & [`exp2_g2_disjoint_and_captured_parent.csv`](../03_simulation/data/exp2_g2_disjoint_and_captured_parent.csv)):**
   **G2 improves verdict accuracy ONLY when the disjoint parent/global pool is cleaner than the compromised local pool.** Specifically, on identical RNG stream `seed+300`:

   | Scenario & Routing Assumption | `v0.4` (`OVS=2×` local) | `v0.5` (`G2` Clean Parent `0.5·f_mal`) | `v0.5` Equal Parent (`1.0·f_mal`) | `v0.5` Direct `GLOBAL` (`0.25·f_mal`) | Artifact |
   |---|---|---|---|---|---|
   | `N_local = 60, f_mal = 30%` | `1.43% ± 0.28%` | **`0.02% ± 0.03%`** | `1.43% ± 0.28%` *(zero gain if parent equally corrupted)* | — | [`exp0_unified_v01_v05.csv`](../03_simulation/data/exp0_unified_v01_v05.csv) |
   | `N_local = 36, f_mal = 40%` (`exp0`) | `9.43% ± 0.75%` *(`V4-09`)* | **`0.32% ± 0.11%`** | — | — | [`exp0_unified_v01_v05.csv`](../03_simulation/data/exp0_unified_v01_v05.csv) |
   | `N_local = 36, f_mal = 40%` (`exp2`, `seed+1200`) | `9.90% ± 0.49%` | **`0.30% ± 0.12%`** | **`12.73% ± 1.02%`** *(parent also captured at `40%`)* | **`0.00% ± 0.00%`** | [`exp2_g2_disjoint_and_captured_parent.csv`](../03_simulation/data/exp2_g2_disjoint_and_captured_parent.csv) |

2. **F1 Split Sensitivity to Arbitrator Non-Participation (`SUPPORTED`, Data from `v0.4` `exp5`):**
   While `G1` eliminates stake-capacity shortages in `GLOBAL`, real juror attempt failures (`p_attempt_fail`, covering non-reveal or panel timeouts) were **not re-simulated in `v0.5`**; under the `v0.4` F1 escalation model ([`exp5_escalation_rewards.csv`](../../v0.4/03_simulation/data/exp5_escalation_rewards.csv), 3 levels × 2 attempts):
   - `p_attempt_fail = 0.05` or `0.15` → `0.0%` final 50/50 split rate (`0.0015` / `0.0247` mean escalations per dispute).
   - `p_attempt_fail = 0.30` → **`0.05% ± 0.05%`** (additive `+$5`) and **`0.07% ± 0.06%`** (multiplicative `1.5×`) 50/50 splits.
   - `p_attempt_fail = 1.0` *(not simulated; analytical consequence noted in [`REPORT_v0.4.md`](../../v0.4/REPORT_v0.4.md))* → deterministic **`100%`** fallthrough to `#15a` 50/50 split regardless of `G1` capacity.
3. **Throughput Price of G1 + G2 (`κ_cap = 1.25`, [`exp1_g1_capacity_rejection.csv`](../03_simulation/data/exp1_g1_capacity_rejection.csv)):** Across lognormal `$50–$8,750` demand (`N=80`), total `e_create` rejection rates are **`18.08% ± 1.78%`** (`Low $400`), **`8.48% ± 0.89%`** (`Mid $600`), **`3.72% ± 0.76%`** (`Heavy-tail`), and **`0.54% ± 0.41%`** (`Pro $2,000`).
4. **G1–G3 Marginal Ablation (`N_loc=36, f=40%, Mid Cap`, [`exp4_loo_g1_g2_g3.csv`](../03_simulation/data/exp4_loo_g1_g2_g3.csv)):** From `v0.5` baseline (`0.17%` wrong, `0%` passive split, `0%` R2 shortage, `$168.80` keeper rent cap/300 deals), removing `G1` adds `+3.67%` passive splits (in unreserved starvation stress test), removing `G2(a)` raises errors `+9.51` pp (`9.68%`), removing `G2(b)` adds `0.67%` R2 liquidity failure, and removing `G3` raises Sybil rent exposure `3.0×` (`$507.19`).
5. **G3 Bounded Keeper Economics ([`exp3_g3_keeper_cap.csv`](../03_simulation/data/exp3_g3_keeper_cap.csv)):** At `φ=1%, gas=$0.50, A_min=50, p_rev=30%`, `R_keeper_max ∈ [$2, $5]` keeps honest keeper net surplus positive (`+$143.69` to `+$194.29 / 1,000` deals), retains `+$62.46` (`$2`) to `+$11.87` (`$5`) for `dao_treasury`, and caps maximum single-deal Sybil extraction at **`$1.50–$4.50`** (vs `$87.00` on `$8,750` in v0.4).

---

## 4. Limitations and Negative Results (Mandatory Disclosure)

1. **Non-Uniqueness of Honest Equilibrium (`FALSIFIED`):** Conformist strategies (`all FOR_A`, `all FOR_B`) remain strict Nash equilibria in one-shot coordination. Honest voting is only a *focal Schelling equilibrium* contingent on effort condition `R_arb + λ·S_arb > c_e / min(q, 1-q)`.
2. **`p + ε` / Dark DAO Bribery (`FALSIFIED`):** Conditional smart-contract bribes reduce an attacker's net cost upon success to `O((m1 + m2)·ε)` (`~$12–$20`, [`02_game_theory_v04.out`](../../v0.4/02_game_theory_v04.out)), causing **`100.0%` wrong verdicts when funded** ([`exp3_coalitions.csv`](../../v0.4/03_simulation/data/exp3_coalitions.csv)) at **any** `V_protocol_max`.
3. **Capacity Limits & `V5-01` Zero-Fee `DRAFT` Capacity DoS (`SUPPORTED`):** In [`02_game_theory_v05.out`](../02_game_theory_v05.out), because `e_cancel_exec` / `TimeoutDraft` currently refunds `100%` of `seller_deposit`, an attacker locking only `$1,500` across three `$5,001` (`Tier 3`) `DRAFT` agreements consumes `$142,500` (> `$100k` capacity) at **`95.0×` leverage** for `~$3.33/day` (8% APR + L2 gas). *Proposed v0.6 Direction (unimplemented hypothesis):* defer `G1` capacity reservation from `e_create` to `e_accept` (keeping `e_create` check advisory/non-binding); qualitatively this removes zero-buyer-collateral DoS and requires full `(1 + α)V` (`1.10 V`) escrow lockup per slot instead of `αV` (`0.10 V`), shrinking capital leverage roughly an order of magnitude alongside a `DRAFT`/`LOCKED` cycle cost (exact revised attack cost not re-simulated; see [`NOTES.md`](NOTES.md)).
4. **`V5-02` Shared `T_dispute_max` Timer Starvation (`FALSIFIED` under shared-clock stalls):** Found in initial `TwoDeals` TLC tracing: because `L0→L1→L2` share one `opened_at + T_dispute_max`, stalling on `L0` until expiry leaves `0` time ticks for `GLOBAL` (`L2`) before `TimeoutR1Split5050`. *Proposed v0.6 Direction (unimplemented hypothesis):* enforce separate per-escalation-level minimum commit/reveal timers bounded by an overall outer deadline cap.
5. **Disjoint-Pool Vulnerability to Parent Capture (`SUPPORTED`):** As shown in Section 3.3, if `Category.parent` is equally compromised (`40%`), G2 routing gives `12.73%` errors (`V5-04`).
6. **Public-EVM Failure of Non-Cryptographic F3 (`SUPPORTED` / `IR-01`):** Simply deferring plaintext reveals until commit-redraw closes still leaks partial Phase-2 `calldata` if reveal-stage `e_redraw` is enabled, or raises quorum failures (`0.57%–3.15%`, [`exp5_f3_deferred_reveal.csv`](../03_simulation/data/exp5_f3_deferred_reveal.csv)) if disabled, while failing to stop reveal-withholding bribes. **End-to-end F3 secrecy remains an unimplemented threshold/timelock cryptography requirement.**
7. **Behavioral Hypothesis Dependence & Absent Implementation (`UNVERIFIED`):** Simulation inputs (`herd`, `p_unrev`, `η`, lognormal wealth) are uncalibrated hypotheses; Solidity contracts, order-statistic gas indexing (`IR-02`), and live pilots do not exist.

---

## 5. Related Work

Comparisons below reflect public documentation as verified at the stated status level; exhaustive verification of every auxiliary extension or governance fork in external protocols is beyond this draft.

| System / Paper | Reference (status) | Comparison to NoKing `v0.5` |
|---|---|---|
| **Kleros** | Lesaege, C., Ast, F., George, W. *Kleros Short Paper* (`v1.0.7`, Sept 2019; initial 2018), [`kleros.io`](https://kleros.io/) — **`PARTIAL`** *(metadata & site verified; full PDF section numbers to be checked by author)* | Uses stake-weighted subcourts, commit–reveal Schelling voting, and expanding appeal juries. Based on public Short Paper descriptions, NoKing adds a tightly coupled 9-state physical-delivery escrow FSM, explicit capacity reservation (`G1`), and seller `deadline_defaults` tracking (`F5`). |
| **Aragon Court** | Aragon Project (`github.com/aragon/aragon-court`, `github.com/aragon/whitepaper`) — **`UNVERIFIED — проверить автору`** *(repository exists, but canonical standalone court whitepaper title/author attribution & publication year could not be confirmed; individual authors omitted)* | Based on public documentation, operates as an opt-in digital jurisdiction using stake-activated jurors, commit–reveal Schelling voting, and multi-round appeals; differs from NoKing's merchant-focused dynamic per-tier collateral caps (`V_protocol_max`) and keeper timeout caps (`G3`). |
| **UMA Optimistic Oracle & DVM** | Lambur, H., Lu, A., Cai, R. *UMA Data Verification Mechanism: Adding Economic Guarantees to Blockchain Oracles*, Risk Labs Technical Report, July 2019, [`UMA-DVM-oracle-whitepaper.pdf`](https://github.com/UMAprotocol/whitepaper/blob/master/UMA-DVM-oracle-whitepaper.pdf) — **`CHECKED`** *(authors, title, date, GitHub PDF URL confirmed)* | Establishes explicit Cost-of-Corruption > Profit-from-Corruption (`CoC > PfC`) guarantees over token-holder DVM votes. To our knowledge, whereas UMA anchors `CoC` to DVM token market capitalization, NoKing caps individual agreement ticket size via `V_protocol_max` against sorted panel stakes. |
| **Augur** | Peterson, J., Krug, J. et al. *Augur: A Decentralized Oracle and Prediction Market Platform*, [`arXiv:1501.01042`](https://arxiv.org/abs/1501.01042) (2015; v2.0 2018) — **`PARTIAL`** *(v1 arXiv ID/title/lead authors checked; full v2 co-author list `UNVERIFIED`)* | Introduces escalating decentralized dispute rounds culminating in market forking for oracle outcomes; targets prediction-market resolution rather than two-party delivery collateral and buyer review keepers. |
| **Schelling Focal Points** | Schelling, T. C. *The Strategy of Conflict*, Harvard University Press, 1960 (ISBN `9780674840300` / `9780674840317`) — **`CHECKED`** | Establishes non-cooperative focal-point salience; motivates why NoKing's `$p^*=0.5$` honest equilibrium is *focal* yet mathematically non-unique. |
| **`p + ε` Attack** | Buterin, V. *The P + epsilon Attack*, Ethereum Foundation Blog, Jan 28, 2015, [`blog.ethereum.org`](https://blog.ethereum.org/2015/01/28/p-epsilon-attack) — **`CHECKED`** | Formalizes conditional smart-contract bribes that invert Schelling incentives; explains why `V_protocol_max` cannot defend against conditional bribery. |
| **Dark DAOs** | Daian, P., Kell, T., Miers, I., Juels, A. *On-Chain Vote Buying and the Rise of Dark DAOs*, *Hacking, Distributed* / IC3, July 2, 2018 (`hackingdistributed.com`, archived) — **`PARTIAL`** *(authors, title, date verified; original host offline, archive URL to confirm)* | Demonstrates how public vote receipts and TEEs automate trustless bribery cartels (`100%` subversion when funded in our `Exp 3` model). |
| **Decentralized ODR** | Ast, F., Deffains, B. *When Online Dispute Resolution Meets Blockchain: The Birth of Decentralized Justice*, *Stanford Journal of Blockchain Law & Policy*, 2021, [`stanford-jblp.pubpub.org`](https://stanford-jblp.pubpub.org/pub/birth-of-decentralized-justice) — **`CHECKED`** | Contextualizes decentralized arbitration for low-value cross-border claims aligned with NoKing's `A_min = 50 USDC` scope. |

---

## 6. Open Questions & Five Questions for `ethresear.ch`

### Open Protocol Questions (`v0.6 / v1.0`)
- Addressing `V5-01` (shifting `G1` reservation to `e_accept` vs charging non-refundable `DRAFT` fees) and `V5-02` (per-level escalation deadlines bounded by global cap).
- Selecting threshold/timelock decryption (`IR-01`) and gas-bounded order-statistic indexing (`IR-02`).
- Specifying Milestone Sub-FSM (`G-03`), `D_reg` withdrawal (`G-04`), and empirical calibration via closed testnet pilots.

### 5 Questions for `ethresear.ch` Readers
1. **Threshold Decryption on L2s (`IR-01`):** For small jury panels (`k = 5–9`) and 24h reveal windows, is external timelock decryption (e.g., Drand) or an optimistic fraud-proofed committee less fragile in L2 production than small-committee DKG?
2. **Capacity Reservation Timing (`G1 / V5-01`):** Moving `G1` reservation from `e_create` to `e_accept` stops zero-buyer-collateral `DRAFT` capacity DoS, at the risk of accepted-stage capacity rejections; which UX trade-off works better in live escrow protocols?
3. **Mitigating Dark DAOs Beyond Stake Caps:** Given `p + ε` defeats direct-bribery caps completely (`100%` error), which practical privacy primitive (MACI-style key rerandomization vs TEEs vs juror identity rotation) imposes the lowest trust overhead for marketplace courts?
4. **Discrete Stake Buckets vs Order-Statistic Trees (`IR-02`):** Rather than maintaining an exact on-chain order-statistic tree for $S_{(2k')}$, does discrete tier bucketing (`$250 / $500 / $1,000`) introduce exploitable step-boundary gaming?
5. **Correlated Parent Capture (`G2 / V5-04`):** In hierarchical category pools (`Category → Parent → GLOBAL`), can contracts detect parent-pool capture early enough to bypass `Parent` directly to `GLOBAL` without enabling cheap griefing of vertical courts?

---

## 7. Claims and Evidence

| Claim | Status | Conditions & Boundaries | Artifact |
|---|---|---|---|
| NoKing `v0.5` single-deal FSM safety, conservation, & bounded liveness hold (`k=3`: `1,114,168` distinct; `k=5`: `272,792` distinct) | `PROVEN-IN-MODEL` | Bounded `Amount=100, MaxTime∈[15,16]`; AI-written spec/model, no human audit | [`v05_base.log`](../01_fsm/logs/v05_base.log), [`v05_panel5.log`](../01_fsm/logs/v05_panel5.log) |
| G1 blocks passive `GLOBAL` *stake-capacity* exhaustion (`C_sab=0` capacity split unreachable) across 1 & 2 deals (`491,115` & `217,559` distinct) | `PROVEN-IN-MODEL` | Bounded capacity `CapReq=35/45`; **does not** prevent splits from juror non-reveal/timeouts | [`twodeals_v05.log`](../01_fsm/logs/twodeals_v05.log), [`twodeals_concurrent_v05.log`](../01_fsm/logs/twodeals_concurrent_v05.log) |
| All `13/13` deliberate protocol mutants (`G1–G3`, F1, F3, F5, zero-vote, deadlock) fail TLC checks | `PROVEN-IN-MODEL` | Fixed mutant configurations (`mutant_1..12`, `td_mutant_5`) | [`NoKingV05_Mutants.tla`](../01_fsm/NoKingV05_Mutants.tla), [`mutant_1.log`](../01_fsm/logs/mutant_1.log) |
| Direct unconditional vote-buying exceeds `V` iff `V ≤ V_protocol_max(c, T)` with `β_arb ≥ 0.20` (`5.25·β_arb ≥ 1`) | `PROVEN-IN-MODEL` | Independent direct bribery only; **fails** below `β=0.1905` (`V5-03`) and against `p+ε` | [`02_game_theory.md`](../02_game_theory.md), [`02_game_theory_v05.out`](../02_game_theory_v05.out) |
| Active 6-attempt F1 sabotage penalties exceed `+0.5487 V` split gain by `3.12×–5.47×` | `SUPPORTED` *(cost formula)* | Assumes `β=0.20, λ_unrev=0.50`, 6 attempts completed (`V5-02`), `S_liq∈[$300,$1k]` | [`02_game_theory_v05.out`](../02_game_theory_v05.out) |
| Dynamic `V_protocol_max` ceilings (`$2,449/$1,686/$1,130` Low; `$3,673/$2,528/$1,695` Mid; `$5,250/$7,000/$8,750` Pro) | `SUPPORTED` | Lognormal capital hypotheses (`N=80, σ∈[1.0,1.4]`), `S_arb_max=$1,000` | [`02_game_theory_v05.out`](../02_game_theory_v05.out), [`exp1_g1_capacity_rejection.csv`](../03_simulation/data/exp1_g1_capacity_rejection.csv) |
| G2 cuts `N=36, f=40%` errors `9.43% → 0.32%` (`1.43% → 0.02%` at `N=60, f=30%`) | `SUPPORTED` | **Only** if parent pool is cleaner (`0.5·f_mal`); equal parent gives `1.43%`, captured parent gives `12.73%` | [`exp0_unified_v01_v05.csv`](../03_simulation/data/exp0_unified_v01_v05.csv), [`exp2_g2_disjoint_and_captured_parent.csv`](../03_simulation/data/exp2_g2_disjoint_and_captured_parent.csv) |
| F1 50/50 split frequency under juror failure rates (`p_attempt_fail ∈ {0.15, 0.30}` → `0.0% / 0.05%–0.07%`) | `SUPPORTED` | From `v0.4` simulation (`exp5`); not re-run in `v0.5`; `p_attempt_fail=1.0` gives `100%` analytically | [`exp5_escalation_rewards.csv`](../../v0.4/03_simulation/data/exp5_escalation_rewards.csv), [`REPORT_v0.4.md`](../../v0.4/REPORT_v0.4.md) |
| G1+G2 admission rejection rate (`18.08%` Low, `8.48%` Mid, `3.72%` Heavy-tail, `0.54%` Pro) | `SUPPORTED` | Synthetic arrival/hold process, `κ_cap=1.25`, `N=80`, `20` seeds | [`exp1_g1_capacity_rejection.csv`](../03_simulation/data/exp1_g1_capacity_rejection.csv) |
| G3 keeps keeper profit positive (`+$143.69..+$194.29 / 1k` deals) while capping single-deal Sybil rent (`$1.50–$4.50`) | `SUPPORTED` | `R_keeper_max∈[$2,$5], φ=1%, gas=$0.50, A_min=50, p_rev=30%` | [`exp3_g3_keeper_cap.csv`](../03_simulation/data/exp3_g3_keeper_cap.csv) |
| Honest voting equilibrium uniqueness; resistance to `p + ε` / Dark DAO (`100%` error when funded) | `FALSIFIED` | Unanimous conformism is strict NE; `p+ε` subverts at `$12–$20` | [`02_game_theory_v04.out`](../../v0.4/02_game_theory_v04.out), [`exp3_coalitions.csv`](../../v0.4/03_simulation/data/exp3_coalitions.csv) |
| Shared `T_dispute_max` prevents L0 stalls from starving `GLOBAL` (`V5-02`); zero-fee `DRAFT` resists DoS (`V5-01`) | `FALSIFIED` / `SUPPORTED` | Initial TLC trace starved L2; `95.0×` leverage `$3.33/d` DoS against `$100k` pool | [`05_new_issues.md`](../05_new_issues.md), [`02_game_theory_v05.out`](../02_game_theory_v05.out) |
| EVM secrecy of intermediate tally (`F3` / `IR-01`), order-stat gas (`IR-02`), Solidity & live calibration | `UNVERIFIED` | Deferred `reveal` leaks `calldata` or adds `0.57%–3.15%` quorum fails; no Solidity code exists | [`exp5_f3_deferred_reveal.csv`](../03_simulation/data/exp5_f3_deferred_reveal.csv), [`exchange-spec-v0.5.md`](../../../protocol/specs/exchange-spec-v0.5.md) |
