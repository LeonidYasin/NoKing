"""
NoKing Protocol Verification v0.2 — V4 & V5: Agent-Based Simulation & Reputation Analysis
Directly compares v0.1 vs v0.2 on identical seeds (100..119, 20 runs) and identical scales.

Outputs:
  - data/exp1_v01_vs_v02_malicious.csv
  - data/exp2_arbitrator_liquidity_crunch.csv
  - data/exp3_keeper_d7_comparison.csv
  - data/exp4_reputation_d11_grid.csv
  - plots/fig1_v01_vs_v02_malicious.png
  - plots/fig2_liquidity_crunch.png
  - plots/fig3_keeper_d7.png
  - plots/fig4_reputation_d11.png
  - summary_v02.json
"""

import json
import math
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
PLOT_DIR = BASE_DIR / "plots"
DATA_DIR.mkdir(parents=True, exist_ok=True)
PLOT_DIR.mkdir(parents=True, exist_ok=True)

SEEDS = list(range(100, 120))  # Exact same 20 seeds as v0.1!


def ci95(arr):
    arr = np.asarray(arr, dtype=float)
    mean = float(np.mean(arr))
    if len(arr) <= 1:
        return mean, 0.0
    return mean, float(1.96 * np.std(arr, ddof=1) / np.sqrt(len(arr)))


def vote_v01(rng, flags, k, eta=0.05, herd_prob=0.60, abst_prob=0.10):
    """v0.1 literal: open voting (herding), Def 5.2 (FOR_A iff vA > k/2 else FOR_B)."""
    chosen = rng.choice(len(flags), size=k, replace=False)
    rng.shuffle(chosen)
    vA, vB = 0, 0
    for idx in chosen:
        if flags[idx]:
            vB += 1
        elif rng.random() < abst_prob:
            pass
        elif (vA + vB > 0) and (rng.random() < herd_prob):
            if vB > vA:
                vB += 1
            elif vA > vB:
                vA += 1
            else:
                vA += 1 if rng.random() < (1 - eta) else 0
                if vA == 0 and vB == 0:
                    vB += 1
        else:
            if rng.random() < (1 - eta):
                vA += 1
            else:
                vB += 1
    return ("FOR_A" if vA > k / 2.0 else "FOR_B")


def vote_v02(rng, flags, k, Q_arb, eta=0.05, unrev_prob=0.10, max_attempts=2):
    """
    v0.2: Commit-reveal (zero herding), quorum Q_arb among revealed votes, redraws up to max_attempts.
    Returns 'FOR_A', 'FOR_B', or 'COMPROMISE' (D3 timeout if all attempts tie or miss quorum).
    """
    for _ in range(max_attempts):
        chosen = rng.choice(len(flags), size=k, replace=False)
        vA, vB = 0, 0
        for idx in chosen:
            if flags[idx]:
                # Malicious arbitrators reveal FOR_B (or could strategically withhold, tested separately)
                vB += 1
            else:
                if rng.random() < unrev_prob:
                    pass  # UNREVEALED
                elif rng.random() < (1 - eta):
                    vA += 1
                else:
                    vB += 1
        if (vA + vB >= Q_arb) and (vA != vB):
            return "FOR_A" if vA > vB else "FOR_B"
    return "COMPROMISE"


def exp1_v01_vs_v02():
    """Compare v0.1 vs v0.2 across malicious fraction f_mal for N=60 and N=36 (appeal pool constraint)."""
    rows = []
    n_disputes = 300
    k = 5
    k_app = 17
    Q1, Q2 = 3, 9
    fractions = np.linspace(0.0, 0.60, 13)

    for N_pool in [60, 36]:
        for f_mal in fractions:
            M = int(round(N_pool * f_mal))
            flags = np.array([True] * M + [False] * (N_pool - M))

            v01_wrong, v01_dead = [], []
            v02_wrong, v02_comp = [], []

            for seed in SEEDS:
                rng1 = np.random.default_rng(seed)
                rng2 = np.random.default_rng(seed)
                w1, d1 = 0, 0
                w2, c2 = 0, 0

                for _ in range(n_disputes):
                    # --- v0.1 ---
                    res1 = vote_v01(rng1, flags, k)
                    if res1 == "FOR_B":
                        if N_pool >= 3 * k_app:
                            res1_app = vote_v01(rng1, flags, k_app)
                            if res1_app == "FOR_B":
                                w1 += 1
                        else:
                            # Appeal blocked in v0.1 -> stuck / cannot overturn
                            w1 += 1
                            d1 += 1

                    # --- v0.2 ---
                    res2 = vote_v02(rng2, flags, k, Q1)
                    if res2 == "COMPROMISE":
                        c2 += 1
                    elif res2 == "FOR_B":
                        if N_pool >= 3 * k_app:
                            res2_app = vote_v02(rng2, flags, k_app, Q2)
                            if res2_app == "FOR_B":
                                w2 += 1
                            elif res2_app == "COMPROMISE":
                                c2 += 1
                        else:
                            # Under D3, failed appeal assembly -> COMPROMISE (never deadlocks, but erases R1!)
                            c2 += 1

                v01_wrong.append(w1 / n_disputes)
                v01_dead.append(d1 / n_disputes)
                v02_wrong.append(w2 / n_disputes)
                v02_comp.append(c2 / n_disputes)

            m_v01, c_v01 = ci95(v01_wrong)
            m_v02, c_v02 = ci95(v02_wrong)
            m_comp, c_comp = ci95(v02_comp)
            rows.append({
                "N_pool": N_pool,
                "appeal_pool_ok": N_pool >= 3 * k_app,
                "f_mal": round(float(f_mal), 3),
                "v01_wrong_mean": m_v01,
                "v01_wrong_ci95": c_v01,
                "v02_wrong_mean": m_v02,
                "v02_wrong_ci95": c_v02,
                "v02_compromise_mean": m_comp,
                "v02_compromise_ci95": c_comp,
            })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp1_v01_vs_v02_malicious.csv", index=False)
    return df


def exp2_liquidity_crunch():
    """
    Test D4 proportional stake S_arb = beta * V against realistic arbitrator USDC liquidity.
    Pool of 80 eligible arbitrators with lognormal liquid USDC (median $600, sigma=1.0).
    Measures effective liquid pool size and D3 Compromise fallback probability!
    """
    rows = []
    N_total_arbs = 80
    deal_values = [100, 500, 1000, 2500, 5000, 10000, 25000]
    betas = [0.05, 0.10, 0.20]

    for beta in betas:
        for V in deal_values:
            S_req = beta * V
            eff_n_runs, r1_fail_runs, r2_fail_runs = [], [], []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 500)
                # Arbitrator liquid capital available for staking in a single dispute
                capitals = rng.lognormal(mean=np.log(600), sigma=1.0, size=N_total_arbs)
                n_liq = int(np.sum(capitals >= S_req))
                eff_n_runs.append(n_liq)
                r1_fail_runs.append(1.0 if n_liq < 15 else 0.0)
                r2_fail_runs.append(1.0 if n_liq < 51 else 0.0)

            mn, cn = ci95(eff_n_runs)
            mr1, cr1 = ci95(r1_fail_runs)
            mr2, cr2 = ci95(r2_fail_runs)
            rows.append({
                "beta_arb": beta,
                "deal_value": V,
                "S_arb_required": S_req,
                "liquid_arbs_mean": mn,
                "liquid_arbs_ci95": cn,
                "r1_shortage_prob": mr1,
                "r1_shortage_ci95": cr1,
                "r2_appeal_shortage_prob": mr2,
                "r2_appeal_shortage_ci95": cr2,
            })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp2_arbitrator_liquidity_crunch.csv", index=False)
    return df


def exp3_keeper_d7():
    """Compare keeper pool deficit per 1000 deals: v0.1 vs v0.2 (D7 under D9-A and D9-B)."""
    rows = []
    n_deals = 1000
    review_timeout_rates = [0.05, 0.10, 0.20, 0.30, 0.40]

    for p_rev_to in review_timeout_rates:
        def_v01, def_v02_d9a, def_v02_d9b = [], [], []
        for seed in SEEDS:
            rng = np.random.default_rng(seed + 900)
            deals = np.clip(rng.lognormal(mean=np.log(80), sigma=0.9, size=n_deals), 10.0, 5000.0)
            b_v01 = 0.0
            b_d9a = 0.0
            b_d9b = 0.0
            for V in deals:
                if rng.random() < 0.10:
                    # EXPIRED timeout
                    # v0.1: keeper_pool pays 0.50 with 0 inflow
                    b_v01 -= 0.50
                    # v0.2 D7: paid from seller's penalty (0.05*V), 0 keeper_pool deficit!
                    continue
                fee_share = 0.001 * V  # 10% of 1% fee
                b_v01 += fee_share
                b_d9a += fee_share
                b_d9b += fee_share
                if rng.random() < p_rev_to:
                    b_v01 -= 0.50
                    # Under D9-A, buyer has no deposit; keeper_pool still covers 0.50 (unless charged to seller!)
                    b_d9a -= 0.50
                    # Under D9-B (buyer_deposit exists), keeper paid from buyer_deposit -> 0 deficit!
                    b_d9b -= 0.0

            def_v01.append(-b_v01)
            def_v02_d9a.append(-b_d9a)
            def_v02_d9b.append(-b_d9b)

        m1, c1 = ci95(def_v01)
        m2, c2 = ci95(def_v02_d9a)
        m3, c3 = ci95(def_v02_d9b)
        rows.append({
            "review_timeout_rate": p_rev_to,
            "v01_deficit_mean": m1, "v01_deficit_ci95": c1,
            "v02_d9a_deficit_mean": m2, "v02_d9a_deficit_ci95": c2,
            "v02_d9b_deficit_mean": m3, "v02_d9b_deficit_ci95": c3,
        })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp3_keeper_d7_comparison.csv", index=False)
    return df


def exp4_reputation_d11():
    """
    Test D11 reputation formula across (m, prior, V_ref) for:
      - Sybil 10 micro-deals ($0.01)
      - 1-tx $0.01 dormancy reset after 730 days
      - Honest small seller ($25/deal, 20 deals, 5 stars) vs Rich whale ($2000/deal, 5 deals, 5 stars)
    """
    N_warmup = 20.0
    T_decay = 365.0
    rows = []

    for V_ref in [50.0, 200.0]:
        for prior in [2.5, 3.0]:
            for m in [2.0, 5.0, 10.0, 20.0]:
                def score_traj(deals_list):
                    raw, wsum = 0.0, 0.0
                    for idx, (r, V) in enumerate(deals_list, 1):
                        w = (1.0 - math.exp(-idx / N_warmup)) * min(1.0, V / V_ref)
                        raw += r * w
                        wsum += w
                    return (raw + m * prior) / (wsum + m), wsum

                # 1. Sybil: 10 deals at $0.01 (5 stars)
                syb_10, _ = score_traj([(5.0, 0.01)] * 10)
                # 2. Honest small seller: 20 deals at $25 (5 stars)
                small_20, _ = score_traj([(5.0, 25.0)] * 20)
                # 3. Honest normal seller: 20 deals at $100 (5 stars)
                norm_20, _ = score_traj([(5.0, 100.0)] * 20)
                # 4. Rich newcomer: 5 deals at $1000 (5 stars)
                rich_5, _ = score_traj([(5.0, 1000.0)] * 5)
                # 5. Dormant account (rating 4.9 with wsum=30, raw=147) after 730 days + ONE $0.01 deal
                d_fac = 2.0 ** (-730.0 / T_decay)  # 0.25 exact half-life!
                raw_dec = 147.0 * d_fac
                w_dec = 30.0 * d_fac
                w_micro = (1.0 - math.exp(-51.0 / N_warmup)) * min(1.0, 0.01 / V_ref)
                after_reset = (raw_dec + 5.0 * w_micro + m * prior) / (w_dec + w_micro + m)
                before_reset = (raw_dec + m * prior) / (w_dec + m)

                rows.append({
                    "V_ref": V_ref, "prior": prior, "m": m,
                    "sybil_10_micro": round(syb_10, 4),
                    "small_20_at_25usd": round(small_20, 4),
                    "norm_20_at_100usd": round(norm_20, 4),
                    "rich_5_at_1000usd": round(rich_5, 4),
                    "dormant_730d": round(before_reset, 4),
                    "after_micro_reset": round(after_reset, 4),
                })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp4_reputation_d11_grid.csv", index=False)
    return df


def make_plots(df1, df2, df3, df4):
    plt.rcParams.update({"font.size": 10, "figure.dpi": 150})

    # Fig 1: v0.1 vs v0.2 malicious fraction (N=60 and N=36)
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11.5, 4.6), sharey=True)
    for ax, Np, title in [(ax1, 60, "Adequate Pool (N=60 >= 51)"), (ax2, 36, "Small Pool (N=36 < 51: Appeal Blocked)")]:
        sub = df1[df1["N_pool"] == Np]
        ax.errorbar(sub["f_mal"] * 100, sub["v01_wrong_mean"] * 100, yerr=sub["v01_wrong_ci95"] * 100,
                    label="v0.1 Wrong Verdict (%)", color="#d95f02", marker="o", capsize=3)
        ax.errorbar(sub["f_mal"] * 100, sub["v02_wrong_mean"] * 100, yerr=sub["v02_wrong_ci95"] * 100,
                    label="v0.2 Wrong Verdict (%)", color="#1b9e77", marker="s", capsize=3)
        ax.errorbar(sub["f_mal"] * 100, sub["v02_compromise_mean"] * 100, yerr=sub["v02_compromise_ci95"] * 100,
                    label="v0.2 D3 Compromise (%)", color="#7570b3", linestyle="--", marker="^", capsize=3)
        ax.axvline(50, color="red", linestyle=":", alpha=0.7)
        ax.set_xlabel("Malicious Arbitrator Share (%)")
        ax.set_title(title)
        ax.grid(True, alpha=0.3)
        ax.legend(fontsize=8)
    ax1.set_ylabel("Outcome Rate (%)")
    fig.suptitle("V4 Exp 1: v0.1 vs v0.2 Under Malicious Arbitrators (k=5, k'=17, 20 seeds, 95% CI)")
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig1_v01_vs_v02_malicious.png")
    plt.close(fig)

    # Fig 2: D4 Liquidity Crunch
    fig, ax = plt.subplots(figsize=(8.2, 4.8))
    for beta, col in [(0.05, "#1b9e77"), (0.10, "#d95f02"), (0.20, "#e41a1c")]:
        sub = df2[df2["beta_arb"] == beta]
        ax.plot(sub["deal_value"], sub["r2_appeal_shortage_prob"] * 100,
                label=f"Appeal Blocked (|E_liq|<51), beta={beta:.2f}", marker="o", color=col)
        ax.plot(sub["deal_value"], sub["r1_shortage_prob"] * 100,
                label=f"R1 Blocked (|E_liq|<15), beta={beta:.2f}", linestyle="--", marker="x", color=col)
    ax.set_xscale("log")
    ax.set_xlabel("Deal Value V (USDC, log scale)")
    ax.set_ylabel("Probability Pool Cannot Form -> D3 Compromise (%)")
    ax.set_title("V4 Exp 2: D4 Arbitrator Liquidity Crunch (N=80, median cap=$600)")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=7.8)
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig2_liquidity_crunch.png")
    plt.close(fig)

    # Fig 3: Keeper D7
    fig, ax = plt.subplots(figsize=(8, 4.6))
    ax.errorbar(df3["review_timeout_rate"] * 100, df3["v01_deficit_mean"], yerr=df3["v01_deficit_ci95"],
                label="v0.1 Deficit (1000 deals)", marker="o", color="#d95f02", capsize=3)
    ax.errorbar(df3["review_timeout_rate"] * 100, df3["v02_d9a_deficit_mean"], yerr=df3["v02_d9a_deficit_ci95"],
                label="v0.2 D7 under D9-A (buyer_deposit=0)", marker="s", color="#7570b3", capsize=3)
    ax.errorbar(df3["review_timeout_rate"] * 100, df3["v02_d9b_deficit_mean"], yerr=df3["v02_d9b_deficit_ci95"],
                label="v0.2 D7 under D9-B (mutual deposit)", marker="^", color="#1b9e77", capsize=3)
    ax.axhline(0, color="black", linewidth=0.8)
    ax.set_xlabel("REVIEW Auto-Confirm Timeout Rate (%)")
    ax.set_ylabel("Keeper Pool Deficit per 1000 Deals (USDC)")
    ax.set_title("V4 Exp 3: Keeper Pool Deficit — v0.1 vs v0.2 D7 (20 seeds, 95% CI)")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8.5)
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig3_keeper_d7.png")
    plt.close(fig)

    # Fig 4: D11 Reputation sensitivity (V_ref=50, prior=2.5)
    sub4 = df4[(df4["V_ref"] == 50.0) & (df4["prior"] == 2.5)]
    fig, ax = plt.subplots(figsize=(8, 4.6))
    ax.plot(sub4["m"], sub4["sybil_10_micro"], marker="o", label="Sybil: 10 deals @ $0.01 (5★)")
    ax.plot(sub4["m"], sub4["small_20_at_25usd"], marker="s", label="Honest Small: 20 deals @ $25 (5★)")
    ax.plot(sub4["m"], sub4["norm_20_at_100usd"], marker="^", label="Honest Normal: 20 deals @ $100 (5★)")
    ax.plot(sub4["m"], sub4["rich_5_at_1000usd"], marker="d", label="Rich Newcomer: 5 deals @ $1000 (5★)")
    ax.plot(sub4["m"], sub4["after_micro_reset"], marker="x", linestyle="--", label="Dormant 2yr + $0.01 Reset")
    ax.set_xlabel("Bayesian Smoothing Strength m")
    ax.set_ylabel("Smoothed Rating (V_ref=50, prior=2.5)")
    ax.set_title("V5 Exp 4: D11 Reputation Sensitivity vs Sybil & Cold Start")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig4_reputation_d11.png")
    plt.close(fig)


def main():
    df1 = exp1_v01_vs_v02()
    df2 = exp2_liquidity_crunch()
    df3 = exp3_keeper_d7()
    df4 = exp4_reputation_d11()
    make_plots(df1, df2, df3, df4)

    summary = {
        "seeds": SEEDS,
        "exp1_N60_f30": df1[(df1["N_pool"] == 60) & (df1["f_mal"] == 0.3)].to_dict(orient="records")[0],
        "exp1_N36_f30": df1[(df1["N_pool"] == 36) & (df1["f_mal"] == 0.3)].to_dict(orient="records")[0],
        "exp2_V10000": df2[df2["deal_value"] == 10000].to_dict(orient="records"),
        "exp3_rate20": df3[df3["review_timeout_rate"] == 0.20].to_dict(orient="records")[0],
        "exp4_sample": df4[(df4["V_ref"] == 50.0) & (df4["prior"] == 2.5)].to_dict(orient="records"),
    }
    with open(BASE_DIR / "summary_v02.json", "w") as f:
        json.dump(summary, f, indent=2)
    print("SIMULATION_V02_COMPLETE")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
