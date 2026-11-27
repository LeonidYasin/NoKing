"""
NoKing Protocol Verification v0.3 — W0, W4, W5 Simulation Suite
Implements:
  - Exp A (W0.1): Unified baseline comparison v0.1 vs v0.2 vs v0.3
  - Exp B (W0.2): Mechanism-by-mechanism ablation study
  - Exp C (W4 / E3): lambda_unrev sweep (honest loss vs sabotage deterrence)
  - Exp D (W4 / E2): Arbitrator liquidity across 3 capital distributions & S_arb_max tiers
  - Exp E (W4 / E4+E5): Keeper pool balance across A_min & review timeout rates
  - Exp F (W5 / E6): Reputation v0.3 (loser ban, EXPIRED rating, unique counterparties)
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

SEEDS = list(range(100, 120))  # 20 independent seeds


def ci95(arr):
    arr = np.asarray(arr, dtype=float)
    mean = float(np.mean(arr))
    if len(arr) <= 1:
        return mean, 0.0
    return mean, float(1.96 * np.std(arr, ddof=1) / np.sqrt(len(arr)))


def simulate_round(rng, flags, k, commit_reveal, use_quorum, Q_arb,
                   max_redraws=1, partial_redraw=False,
                   eta=0.05, p_unrev=0.08, herd_prob=0.60):
    """
    Unified panel simulator supporting ablation toggles.
    True state is 'A'. Malicious arbitrators vote 'B'.
    Returns ('FOR_A' | 'FOR_B' | 'NO_DECISION').
    """
    n = len(flags)
    if not use_quorum:
        # v0.1 Def 5.2: FOR_A iff vA > k/2 else FOR_B (no redraws)
        chosen = rng.choice(n, size=k, replace=False)
        rng.shuffle(chosen)
        vA, vB = 0, 0
        for idx in chosen:
            if flags[idx]:
                vB += 1
            elif rng.random() < p_unrev:
                pass  # ABSTAIN
            elif (not commit_reveal) and (vA + vB > 0) and (rng.random() < herd_prob):
                if vB > vA:
                    vB += 1
                elif vA > vB:
                    vA += 1
                else:
                    if rng.random() < (1 - eta):
                        vA += 1
                    else:
                        vB += 1
            else:
                if rng.random() < (1 - eta):
                    vA += 1
                else:
                    vB += 1
        return "FOR_A" if vA > k / 2.0 else "FOR_B"

    # Quorum mode (v0.2 / v0.3)
    vA, vB = 0, 0
    used = set()
    for att in range(1 + max_redraws):
        if partial_redraw and att > 0:
            # E3: only replace missing (unrevealed) seats, keeping revealed votes!
            need = k - (vA + vB)
            if need <= 0:
                # Tie with full reveal -> redraw 1 tiebreaker or full reset if tie
                need = k
                vA, vB = 0, 0
                avail = np.arange(n)
            else:
                avail = np.array([i for i in range(n) if i not in used])
                if len(avail) < need:
                    avail = np.arange(n)
            chosen = rng.choice(avail, size=need, replace=False)
            for c in chosen:
                used.add(int(c))
        else:
            vA, vB = 0, 0
            chosen = rng.choice(n, size=k, replace=False)
            used = set(int(c) for c in chosen)
            rng.shuffle(chosen)

        for idx in chosen:
            if flags[idx]:
                vB += 1
            elif rng.random() < p_unrev:
                pass
            elif (not commit_reveal) and (vA + vB > 0) and (rng.random() < herd_prob):
                if vB > vA:
                    vB += 1
                elif vA > vB:
                    vA += 1
                else:
                    if rng.random() < (1 - eta):
                        vA += 1
                    else:
                        vB += 1
            else:
                if rng.random() < (1 - eta):
                    vA += 1
                else:
                    vB += 1

        if (vA + vB >= Q_arb) and (vA != vB):
            return "FOR_A" if vA > vB else "FOR_B"

    return "NO_DECISION"


def exp_a_unified_baseline():
    """W0.1: Compare v0.1, v0.2, v0.3 on identical unified scenarios (N=60 and N=36)."""
    rows = []
    n_disputes = 300
    k, k_app = 5, 17
    Q1, Q2 = 3, 9
    fractions = np.linspace(0.0, 0.60, 13)

    for N_pool in [60, 36]:
        for f_mal in fractions:
            M = int(round(N_pool * f_mal))
            flags = np.array([True] * M + [False] * (N_pool - M))
            # Parent/global pool for E1 escalation: size 80, malicious share diluted to 0.5*f_mal
            N_par = 80
            M_par = int(round(N_par * (0.5 * f_mal)))
            par_flags = np.array([True] * M_par + [False] * (N_par - M_par))

            metrics = {ver: {"wrong": [], "fallback": [], "blocked_app": []} for ver in ["v0.1", "v0.2", "v0.3"]}

            for seed in SEEDS:
                for ver in ["v0.1", "v0.2", "v0.3"]:
                    rng = np.random.default_rng(seed)
                    w, fb, ba = 0, 0, 0
                    for _ in range(n_disputes):
                        if ver == "v0.1":
                            r1 = simulate_round(rng, flags, k, commit_reveal=False, use_quorum=False, Q_arb=Q1)
                            if r1 == "FOR_B":
                                if N_pool >= 3 * k_app:
                                    r2 = simulate_round(rng, flags, k_app, commit_reveal=False, use_quorum=False, Q_arb=Q2)
                                    if r2 == "FOR_B":
                                        w += 1
                                else:
                                    w += 1
                                    ba += 1
                        elif ver == "v0.2":
                            r1 = simulate_round(rng, flags, k, commit_reveal=True, use_quorum=True, Q_arb=Q1, max_redraws=1)
                            if r1 == "NO_DECISION":
                                fb += 1
                            elif r1 == "FOR_B":
                                if N_pool >= 3 * k_app:
                                    r2 = simulate_round(rng, flags, k_app, commit_reveal=True, use_quorum=True, Q_arb=Q2, max_redraws=1)
                                    if r2 == "FOR_B":
                                        w += 1
                                    elif r2 == "NO_DECISION":
                                        fb += 1
                                else:
                                    fb += 1
                                    ba += 1
                        else:  # v0.3 (E1 + E3 partial redraw)
                            r1 = simulate_round(rng, flags, k, commit_reveal=True, use_quorum=True, Q_arb=Q1,
                                                max_redraws=1, partial_redraw=True)
                            if r1 == "NO_DECISION":
                                # E1: Escalate to parent pool before 50/50 split!
                                r_esc = simulate_round(rng, par_flags, k, commit_reveal=True, use_quorum=True, Q_arb=Q1,
                                                       max_redraws=1, partial_redraw=True)
                                if r_esc == "FOR_B":
                                    r1 = "FOR_B"
                                elif r_esc == "NO_DECISION":
                                    fb += 1
                            if r1 == "FOR_B":
                                # Appeal: try category pool if >=51, else escalate to parent pool; if R2 still fails -> E1 keeps R1 verdict!
                                app_pool = flags if N_pool >= 3 * k_app else par_flags
                                r2 = simulate_round(rng, app_pool, k_app, commit_reveal=True, use_quorum=True, Q_arb=Q2,
                                                    max_redraws=1, partial_redraw=True)
                                if r2 == "FOR_B":
                                    w += 1
                                elif r2 == "NO_DECISION":
                                    # E1 R2 rule: Round 1 verdict (FOR_B) stands! No D3 compromise!
                                    w += 1
                                    ba += 1

                    metrics[ver]["wrong"].append(w / n_disputes)
                    metrics[ver]["fallback"].append(fb / n_disputes)
                    metrics[ver]["blocked_app"].append(ba / n_disputes)

            for ver in ["v0.1", "v0.2", "v0.3"]:
                mw, cw = ci95(metrics[ver]["wrong"])
                mf, cf = ci95(metrics[ver]["fallback"])
                mb, cb = ci95(metrics[ver]["blocked_app"])
                rows.append({
                    "N_pool": N_pool, "f_mal": round(float(f_mal), 3), "version": ver,
                    "wrong_mean": mw, "wrong_ci95": cw,
                    "fallback_mean": mf, "fallback_ci95": cf,
                    "blocked_app_mean": mb, "blocked_app_ci95": cb,
                })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "expA_unified_v01_v02_v03.csv", index=False)
    return df


def exp_b_ablation():
    """W0.2: Isolate individual contribution of each mechanism at N=60 across f_mal."""
    rows = []
    N_pool = 60
    n_disputes = 300
    k, k_app = 5, 17
    Q1, Q2 = 3, 9
    configs = [
        ("0. Bare v0.1 (R1 only, Open, Def5.2 bug)", False, False, False, 0, False),
        ("1. +Appeal only (Open, Def5.2 bug)",       True,  False, False, 0, False),
        ("2. +Commit-Reveal only (R1, Def5.2 bug)",  False, True,  False, 0, False),
        ("3. +Quorum Q=3 only (R1, Open)",           False, False, True,  0, False),
        ("4. +CR + Quorum + Redraw (R1 only)",       False, True,  True,  1, True),
        ("5. Full Stack (Appeal+CR+Quorum+Redraw)",  True,  True,  True,  1, True),
    ]

    for f_mal in [0.10, 0.20, 0.30, 0.40, 0.50]:
        M = int(round(N_pool * f_mal))
        flags = np.array([True] * M + [False] * (N_pool - M))
        for label, use_app, use_cr, use_q, redraws, partial in configs:
            w_runs, fb_runs = [], []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 100)
                w, fb = 0, 0
                for _ in range(n_disputes):
                    r1 = simulate_round(rng, flags, k, commit_reveal=use_cr, use_quorum=use_q,
                                        Q_arb=Q1, max_redraws=redraws, partial_redraw=partial)
                    if r1 == "NO_DECISION":
                        fb += 1
                    elif r1 == "FOR_B":
                        if use_app:
                            r2 = simulate_round(rng, flags, k_app, commit_reveal=use_cr, use_quorum=use_q,
                                                Q_arb=Q2, max_redraws=redraws, partial_redraw=partial)
                            if r2 == "FOR_B":
                                w += 1
                            elif r2 == "NO_DECISION":
                                fb += 1
                        else:
                            w += 1
                w_runs.append(w / n_disputes)
                fb_runs.append(fb / n_disputes)
            mw, cw = ci95(w_runs)
            mf, cf = ci95(fb_runs)
            rows.append({
                "f_mal": f_mal, "config": label,
                "wrong_mean": mw, "wrong_ci95": cw,
                "no_decision_mean": mf, "no_decision_ci95": cf,
            })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "expB_ablation.csv", index=False)
    return df


def exp_c_lambda_unrev():
    """W4 / E3: Evaluate lambda_unrev in (0.25, 1.0] for honest disconnect EV vs sabotage cost."""
    rows = []
    V = 1000.0
    beta = 0.10
    S_arb = beta * V  # $100
    R_arb = 5.0       # baseline reward per dispute
    k = 5
    for lam_unrev in [0.25, 0.40, 0.50, 0.75, 1.00]:
        for p_disc in [0.02, 0.05, 0.10]:
            # Honest arb EV per case (assuming 95% majority match when online):
            # Online prob (1-p_disc): 95% gets R_arb + 0.05*0.25*S_arb*something, 5% loses 0.25*S_arb
            # Offline prob p_disc: loses lam_unrev * S_arb
            ev_online = 0.95 * R_arb - 0.05 * (0.25 * S_arb)
            ev_honest = (1.0 - p_disc) * ev_online - p_disc * (lam_unrev * S_arb)
            # Sabotage cost to break Q_arb=3 (3 seats) over 1 initial + 1 redraw = 6 seats:
            sab_cost_1 = 3 * lam_unrev * S_arb
            sab_cost_2 = 6 * lam_unrev * S_arb
            rows.append({
                "lambda_unrev": lam_unrev,
                "p_honest_disconnect": p_disc,
                "honest_arb_ev_usd": round(ev_honest, 2),
                "sabotage_cost_1attempt_pctV": round(100 * sab_cost_1 / V, 2),
                "sabotage_cost_2attempts_pctV": round(100 * sab_cost_2 / V, 2),
                "deters_dishonest_buyer_50pct": sab_cost_2 >= 0.50 * V,
            })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "expC_lambda_unrev.csv", index=False)
    return df


def exp_d_liquidity_tiers():
    """W4 / E2: Arbitrator liquidity across 3 capital hypotheses & S_arb_max caps."""
    rows = []
    N_arbs = 80
    cap_hyps = [("Low ($400 med)", 400, 1.0), ("Mid ($600 med)", 600, 1.0), ("Pro ($2000 med)", 2000, 1.1)]
    deal_values = [100, 500, 1000, 2500, 5000, 10000, 25000, 50000]
    beta = 0.20

    for hname, med, sig in cap_hyps:
        for cap_name, S_max in [("Uncapped (v0.2)", 1e9), ("Cap $500", 500.0), ("Cap $1000", 1000.0)]:
            for V in deal_values:
                # Tiered panel sizes per E2
                k1 = 5 if V <= 5000 else (7 if V <= 15000 else 9)
                k2 = 3 * k1 + 2
                S_req = min(beta * V, S_max)
                r1_fail, r2_fail, liq_cnt = [], [], []
                for seed in SEEDS:
                    rng = np.random.default_rng(seed + 500)
                    caps = rng.lognormal(mean=np.log(med), sigma=sig, size=N_arbs)
                    n_liq = int(np.sum(caps >= S_req))
                    liq_cnt.append(n_liq)
                    r1_fail.append(1.0 if n_liq < 3 * k1 else 0.0)
                    r2_fail.append(1.0 if n_liq < 3 * k2 else 0.0)
                ml, cl = ci95(liq_cnt)
                mr1, cr1 = ci95(r1_fail)
                mr2, cr2 = ci95(r2_fail)
                rows.append({
                    "capital_hyp": hname, "stake_policy": cap_name, "deal_value": V,
                    "k1": k1, "k2": k2, "S_req": S_req,
                    "liquid_arbs_mean": ml, "liquid_arbs_ci95": cl,
                    "r1_shortage_prob": mr1, "r2_shortage_prob": mr2,
                })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "expD_liquidity_tiers.csv", index=False)
    return df


def exp_e_keeper_amin():
    """W4 / E4+E5: Keeper pool solvency across A_min & REVIEW timeout rate."""
    rows = []
    n_deals = 1000
    for A_min in [10.0, 25.0, 50.0, 100.0, 250.0, 500.0]:
        for p_rev in [0.10, 0.20, 0.30, 0.40]:
            def_10pct, def_100pct_rev = [], []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 900)
                deals = np.clip(rng.lognormal(mean=np.log(80), sigma=0.9, size=n_deals), A_min, 5000.0)
                bal_10 = 0.0
                bal_100 = 0.0
                for V in deals:
                    if rng.random() < 0.10:
                        continue  # EXPIRED paid from seller penalty per D7
                    fee = 0.01 * V
                    bal_10 += 0.10 * fee
                    if rng.random() < p_rev:
                        bal_10 -= 0.50
                        bal_100 += fee - 0.50  # 100% of protocol_fee on REVIEW timeout goes to keeper
                    else:
                        bal_100 += 0.10 * fee
                def_10pct.append(-bal_10)
                def_100pct_rev.append(-bal_100)
            m10, c10 = ci95(def_10pct)
            m100, c100 = ci95(def_100pct_rev)
            rows.append({
                "A_min": A_min, "review_timeout_rate": p_rev,
                "deficit_10pct_split_mean": m10, "deficit_10pct_ci95": c10,
                "deficit_100pct_on_timeout_mean": m100, "deficit_100pct_ci95": c100,
            })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "expE_keeper_amin.csv", index=False)
    return df


def exp_f_reputation_v03():
    """W5 / E6: Reputation trajectories with EXPIRED penalty & loser-ban."""
    N_warmup, V_ref = 20.0, 50.0
    rows = []
    for prior in [2.5, 3.0]:
        for m in [2.0, 3.0, 5.0]:
            # Trajectory 1: Honest $25 seller, 20 deals, 0 defaults
            # Trajectory 2: Honest $25 seller with 1 EXPIRED default at deal #10 (rated r=1)
            # Trajectory 3: Malicious buyer loses dispute -> blocked in v0.3 vs rates 1* in v0.2
            def eval_deals(deals):
                raw, wsum = 0.0, 0.0
                for idx, (r, V) in enumerate(deals, 1):
                    w = (1.0 - math.exp(-idx / N_warmup)) * min(1.0, V / V_ref)
                    raw += r * w
                    wsum += w
                return (raw + m * prior) / (wsum + m)

            d_clean = [(5.0, 25.0)] * 20
            d_exp = [(5.0, 25.0)] * 9 + [(1.0, 25.0)] + [(5.0, 25.0)] * 10
            d_revenge = [(5.0, 50.0)] * 9 + [(1.0, 50.0)]  # v0.2 revenge on deal 10
            d_e6 = [(5.0, 50.0)] * 9                       # v0.3 E6 loser blocked
            rows.append({
                "prior": prior, "m": m,
                "clean_20_at_25": round(eval_deals(d_clean), 4),
                "with_1_expired_at_25": round(eval_deals(d_exp), 4),
                "v02_after_loser_revenge": round(eval_deals(d_revenge), 4),
                "v03_e6_loser_blocked": round(eval_deals(d_e6), 4),
                "sybil_5_unique_reg_capital": 5 * 10.0,
            })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "expF_reputation_v03.csv", index=False)
    return df


def make_plots(dfA, dfB, dfC, dfD, dfE):
    plt.rcParams.update({"font.size": 10, "figure.dpi": 150})

    # Fig 1: W0.1 Unified v0.1 vs v0.2 vs v0.3
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11.8, 4.7), sharey=True)
    colors = {"v0.1": "#d95f02", "v0.2": "#7570b3", "v0.3": "#1b9e77"}
    for ax, Np, ttl in [(ax1, 60, "Pool N=60 (>=51)"), (ax2, 36, "Pool N=36 (<51)")]:
        sub = dfA[dfA["N_pool"] == Np]
        for ver in ["v0.1", "v0.2", "v0.3"]:
            s = sub[sub["version"] == ver]
            ax.errorbar(s["f_mal"] * 100, s["wrong_mean"] * 100, yerr=s["wrong_ci95"] * 100,
                        label=f"{ver} Wrong (%)", color=colors[ver], marker="o", markersize=4, capsize=3)
            if ver in ["v0.2", "v0.3"]:
                ax.plot(s["f_mal"] * 100, s["fallback_mean"] * 100, linestyle="--", marker="^", markersize=3.5,
                        color=colors[ver], alpha=0.75, label=f"{ver} Fallback/50-50 (%)")
        ax.axvline(50, color="red", linestyle=":", alpha=0.7)
        ax.set_xlabel("Malicious Arbitrator Share (%)")
        ax.set_title(ttl)
        ax.grid(True, alpha=0.3)
        ax.legend(fontsize=7.5, loc="upper left")
    ax1.set_ylabel("Rate (%)")
    fig.suptitle("W0.1 Unified Baseline: v0.1 vs v0.2 vs v0.3 (Identical Parameters, 20 seeds, 95% CI)")
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig1_unified_v01_v02_v03.png")
    plt.close(fig)

    # Fig 2: W0.2 Ablation at f_mal=0.30 and 0.40
    fig, ax = plt.subplots(figsize=(9.5, 4.8))
    sub30 = dfB[dfB["f_mal"] == 0.30]
    sub40 = dfB[dfB["f_mal"] == 0.40]
    x = np.arange(len(sub30))
    w = 0.36
    ax.bar(x - w/2, sub30["wrong_mean"] * 100, w, yerr=sub30["wrong_ci95"] * 100, capsize=3,
           label="f_mal = 30% Wrong (%)", color="#1b9e77")
    ax.bar(x + w/2, sub40["wrong_mean"] * 100, w, yerr=sub40["wrong_ci95"] * 100, capsize=3,
           label="f_mal = 40% Wrong (%)", color="#d95f02")
    ax.set_xticks(x)
    ax.set_xticklabels([c.split("(")[0].strip() for c in sub30["config"]], rotation=18, ha="right", fontsize=8.5)
    ax.set_ylabel("Wrong Verdict Rate (%)")
    ax.set_title("W0.2 Ablation Study: Marginal Contribution of Each Mechanism (N=60, 20 seeds, 95% CI)")
    ax.grid(True, axis="y", alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig2_ablation.png")
    plt.close(fig)

    # Fig 3: W4 Liquidity across 3 capital hypotheses & S_arb_max
    fig, axes = plt.subplots(1, 3, figsize=(13, 4.3), sharey=True)
    for ax, (hname, _, _) in zip(axes, [("Low ($400 med)", 0, 0), ("Mid ($600 med)", 0, 0), ("Pro ($2000 med)", 0, 0)]):
        sub = dfD[dfD["capital_hyp"] == hname]
        for pol, col in [("Uncapped (v0.2)", "#e41a1c"), ("Cap $1000", "#ff7f00"), ("Cap $500", "#377eb8")]:
            s = sub[sub["stake_policy"] == pol]
            ax.plot(s["deal_value"], s["r2_shortage_prob"] * 100, marker="o", markersize=4, color=col, label=f"R2 {pol}")
            ax.plot(s["deal_value"], s["r1_shortage_prob"] * 100, linestyle="--", marker="x", markersize=4, color=col, label=f"R1 {pol}")
        ax.set_xscale("log")
        ax.set_title(hname)
        ax.set_xlabel("Deal Value V (USDC)")
        ax.grid(True, alpha=0.3)
    axes[0].set_ylabel("Shortage Probability (%)")
    axes[2].legend(fontsize=6.8, loc="upper left")
    fig.suptitle("W4/E2 Arbitrator Liquidity Crunch Across 3 Capital Hypotheses & S_arb_max")
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig3_liquidity_hypotheses.png")
    plt.close(fig)

    # Fig 4: W4/E4+E5 Keeper Deficit vs A_min
    fig, ax = plt.subplots(figsize=(8.2, 4.6))
    for p_rev, col in [(0.10, "#1b9e77"), (0.20, "#377eb8"), (0.30, "#d95f02"), (0.40, "#e41a1c")]:
        sub = dfE[dfE["review_timeout_rate"] == p_rev]
        ax.errorbar(sub["A_min"], sub["deficit_10pct_split_mean"], yerr=sub["deficit_10pct_ci95"],
                    marker="o", color=col, capsize=3, label=f"10% fee split, p_rev={int(p_rev*100)}%")
    sub30 = dfE[dfE["review_timeout_rate"] == 0.30]
    ax.plot(sub30["A_min"], sub30["deficit_100pct_on_timeout_mean"], linestyle="--", marker="s", color="black",
            label="100% fee on auto-confirm, p_rev=30%")
    ax.axhline(0, color="black", linewidth=0.9)
    ax.set_xlabel("Minimum Deal Amount A_min (USDC)")
    ax.set_ylabel("Keeper Pool Deficit / 1000 Deals (USDC)")
    ax.set_title("W4/E5 Keeper Pool Deficit vs A_min (20 seeds, 95% CI)")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig4_keeper_amin.png")
    plt.close(fig)


def main():
    dfA = exp_a_unified_baseline()
    dfB = exp_b_ablation()
    dfC = exp_c_lambda_unrev()
    dfD = exp_d_liquidity_tiers()
    dfE = exp_e_keeper_amin()
    dfF = exp_f_reputation_v03()
    make_plots(dfA, dfB, dfC, dfD, dfE)

    summary = {
        "seeds": SEEDS,
        "w01_N60_f30": dfA[(dfA["N_pool"] == 60) & (dfA["f_mal"] == 0.3)].to_dict(orient="records"),
        "w01_N36_f30": dfA[(dfA["N_pool"] == 36) & (dfA["f_mal"] == 0.3)].to_dict(orient="records"),
        "w02_ablation_f30": dfB[dfB["f_mal"] == 0.30].to_dict(orient="records"),
        "w04_keeper_p30": dfE[dfE["review_timeout_rate"] == 0.30].to_dict(orient="records"),
    }
    with open(BASE_DIR / "summary_v03.json", "w") as f:
        json.dump(summary, f, indent=2)
    print("SIMULATION_V03_COMPLETE")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
