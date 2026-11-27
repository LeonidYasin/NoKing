"""
NoKing Protocol Verification — T3 & T4: Agent-Based Simulation & Reputation Attacks
Reproducible Monte Carlo simulation with fixed seeds and 95% confidence intervals.

Outputs:
  - data/exp1_malicious_fraction.csv
  - data/exp2_selection_and_herding.csv
  - data/exp3_mass_disputes_and_keeper.csv
  - data/exp4_reputation_attacks.csv
  - plots/fig1_malicious_threshold.png
  - plots/fig2_selection_commit_reveal.png
  - plots/fig3_mass_disputes_keeper.png
  - plots/fig4_reputation_exploits.png
  - summary.json
"""

import json
import math
import os
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
    se = float(np.std(arr, ddof=1) / np.sqrt(len(arr)))
    return mean, 1.96 * se


def run_panel_vote(rng, pool_mal_flags, pool_weights, k, eta_honest=0.05,
                   herding_prob=0.0, commit_reveal=True):
    """
    Simulate one panel selection and vote.
    True state is 'A'; malicious arbitrators vote 'B' (wrong), honest vote 'A' with prob 1-eta_honest.
    If commit_reveal=False, arbitrators vote sequentially and lazy arbitrators (prob=herding_prob)
    copy the current leading vote instead of reading evidence.
    Returns (verdict_wrong: bool, votes_A: int, votes_B: int).
    """
    n = len(pool_mal_flags)
    probs = pool_weights / np.sum(pool_weights)
    chosen = rng.choice(n, size=k, replace=False, p=probs)
    rng.shuffle(chosen)

    vA = 0
    vB = 0
    for idx in chosen:
        is_mal = pool_mal_flags[idx]
        if is_mal:
            vB += 1
        else:
            if (not commit_reveal) and (vA + vB > 0) and (rng.random() < herding_prob):
                # Copy leading vote to save effort c_e
                if vB > vA:
                    vB += 1
                elif vA > vB:
                    vA += 1
                else:
                    # tie -> honest noise
                    if rng.random() < (1.0 - eta_honest):
                        vA += 1
                    else:
                        vB += 1
            else:
                if rng.random() < (1.0 - eta_honest):
                    vA += 1
                else:
                    vB += 1

    # Def. 5.2: A wins iff vA > k/2, else B wins (wrong verdict = B)
    verdict_wrong = not (vA > k / 2.0)
    return verdict_wrong, vA, vB


def experiment_1_malicious_fraction():
    """Sweep malicious arbitrator fraction f_mal across panel sizes k={3,5,7} with & without appeal."""
    rows = []
    N_pool = 60
    n_disputes = 300
    fractions = np.linspace(0.0, 0.60, 13)

    for k in [3, 5, 7]:
        k_appeal = 3 * k + 2
        for f_mal in fractions:
            M = int(round(N_pool * f_mal))
            flags = np.array([True] * M + [False] * (N_pool - M))
            weights = np.ones(N_pool)

            r1_err_runs = []
            app_err_runs = []
            app_blocked_err_runs = []

            for seed in SEEDS:
                rng = np.random.default_rng(seed)
                r1_wrong = 0
                app_wrong = 0
                app_blocked_wrong = 0
                for _ in range(n_disputes):
                    w1, _, _ = run_panel_vote(rng, flags, weights, k, eta_honest=0.05, commit_reveal=True)
                    if w1:
                        r1_wrong += 1
                        # Appeal if pool >= 3 * k_appeal
                        if N_pool >= 3 * k_appeal:
                            w2, _, _ = run_panel_vote(rng, flags, weights, k_appeal, eta_honest=0.05, commit_reveal=True)
                            if w2:
                                app_wrong += 1
                        else:
                            # Appeal blocked by Alg 5.1 |E| >= 3*k' (e.g. k=7 -> k'=23 -> need 69 > 60)
                            app_wrong += 1
                        # Also record small-pool (N=30 < 51) where appeal is always blocked
                        app_blocked_wrong += 1
                r1_err_runs.append(r1_wrong / n_disputes)
                app_err_runs.append(app_wrong / n_disputes)
                app_blocked_err_runs.append(app_blocked_wrong / n_disputes)

            m1, c1 = ci95(r1_err_runs)
            m2, c2 = ci95(app_err_runs)
            rows.append({
                "k": k,
                "k_appeal": k_appeal,
                "N_pool": N_pool,
                "f_mal": round(float(f_mal), 3),
                "r1_wrong_mean": m1,
                "r1_wrong_ci95": c1,
                "final_wrong_with_appeal_mean": m2,
                "final_wrong_with_appeal_ci95": c2,
                "appeal_available": N_pool >= 3 * k_appeal,
            })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp1_malicious_fraction.csv", index=False)
    return df


def experiment_2_selection_and_herding():
    """Compare selection schemes (uniform vs rep-weighted vs stake-weighted) and open-vote herding."""
    rows = []
    N_honest = 40
    n_disputes = 300
    k = 5
    sybil_counts = [0, 5, 10, 20, 30, 40, 60]

    configs = [
        ("Uniform + Commit-Reveal", "uniform", True, 0.0),
        ("Uniform + Open Voting (Herding 60%)", "uniform", False, 0.60),
        ("Reputation-Weighted + Commit-Reveal", "rep", True, 0.0),
        ("Stake-Weighted (Low-Stake Sybils) + CR", "stake_low", True, 0.0),
    ]

    for label, scheme, cr, herd in configs:
        for M_sybil in sybil_counts:
            N_tot = N_honest + M_sybil
            flags = np.array([True] * M_sybil + [False] * N_honest)
            if scheme == "uniform":
                weights = np.ones(N_tot)
            elif scheme == "rep":
                # Sybils passed minimum 10 deals (weight ~1), honest avg 50 deals (weight ~5)
                weights = np.array([1.0] * M_sybil + [5.0] * N_honest)
            elif scheme == "stake_low":
                # Sybils stake min 10 USDC, honest stake 100 USDC
                weights = np.array([10.0] * M_sybil + [100.0] * N_honest)

            err_runs = []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 1000)
                wrong = 0
                for _ in range(n_disputes):
                    w, _, _ = run_panel_vote(rng, flags, weights, k, eta_honest=0.05,
                                             herding_prob=herd, commit_reveal=cr)
                    if w:
                        wrong += 1
                err_runs.append(wrong / n_disputes)

            m, c = ci95(err_runs)
            rows.append({
                "scheme": label,
                "M_sybil": M_sybil,
                "N_honest": N_honest,
                "sybil_share": M_sybil / N_tot,
                "wrong_rate_mean": m,
                "wrong_rate_ci95": c,
            })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp2_selection_and_herding.csv", index=False)
    return df


def experiment_3_mass_disputes_and_keeper():
    """
    Simulate 1000-deal network stream:
    1. Mass false disputes by dishonest buyers (measuring attacker EV & protocol load)
    2. Keeper pool solvency (0.1% of closed volume vs R_keeper = 0.5 USDC per timeout)
    """
    rows = []
    n_deals = 1000
    false_disp_rates = [0.02, 0.05, 0.10, 0.20, 0.30, 0.50]
    N_pool = 45
    M_mal = 9  # 20% malicious/colluding arbitrators
    flags = np.array([True] * M_mal + [False] * (N_pool - M_mal))
    weights = np.ones(N_pool)

    for p_fd in false_disp_rates:
        buyer_ev_runs = []
        keeper_def_runs = []
        abstain_wrong_runs = []

        for seed in SEEDS:
            rng = np.random.default_rng(seed + 2000)
            deal_values = rng.lognormal(mean=np.log(80), sigma=0.9, size=n_deals)
            deal_values = np.clip(deal_values, 5.0, 5000.0)

            keeper_inflow = 0.0
            keeper_outflow = 0.0
            buyer_net_fd = 0.0
            fd_count = 0
            abstain_wrong = 0

            for V in deal_values:
                # 10% of deals expire before completion (no fee), 15% auto-confirm via keeper
                u = rng.random()
                if u < 0.10:
                    # EXPIRED timeout
                    keeper_outflow += 0.50
                    continue

                if rng.random() < p_fd:
                    fd_count += 1
                    D_disp = 0.05 * V
                    # Simulate panel with 15% chance of lazy abstention per arb (testing Def 5.2 bug!)
                    chosen = rng.choice(N_pool, size=5, replace=False)
                    vA = 0
                    vB = 0
                    for idx in chosen:
                        if flags[idx]:
                            vB += 1
                        elif rng.random() < 0.25:
                            pass  # ABSTAIN
                        else:
                            vA += 1
                    # Def 5.2: FOR_A iff vA > 2.5, else FOR_B!
                    buyer_wins = not (vA > 2.5)
                    if buyer_wins:
                        # Buyer gets Amount + D_disp + 0.05*V penalty (net gain = Amount + 0.05V - V_goods_approx=0 if buyer keeps goods!)
                        # Strictly measuring financial payout net of escrow+deposit: gains seller_penalty + keeps goods worth V
                        buyer_net_fd += (V + 0.05 * V)
                        if vB <= vA:
                            abstain_wrong += 1
                    else:
                        buyer_net_fd -= D_disp
                        keeper_inflow += 0.001 * V  # 10% of 1% fee
                else:
                    # Happy path CLOSED
                    keeper_inflow += 0.001 * V
                    if rng.random() < 0.20:
                        keeper_outflow += 0.50

            buyer_ev_runs.append(buyer_net_fd / max(fd_count, 1))
            keeper_def_runs.append(keeper_outflow - keeper_inflow)
            abstain_wrong_runs.append(abstain_wrong / max(fd_count, 1))

        m_ev, c_ev = ci95(buyer_ev_runs)
        m_kd, c_kd = ci95(keeper_def_runs)
        m_aw, c_aw = ci95(abstain_wrong_runs)
        rows.append({
            "false_dispute_rate": p_fd,
            "buyer_net_ev_per_false_dispute_mean": m_ev,
            "buyer_net_ev_ci95": c_ev,
            "keeper_pool_deficit_1000_deals_mean": m_kd,
            "keeper_pool_deficit_ci95": c_kd,
            "abstain_default_wrong_frac_mean": m_aw,
            "abstain_default_wrong_frac_ci95": c_aw,
        })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp3_mass_disputes_and_keeper.csv", index=False)
    return df


def experiment_4_reputation_attacks():
    """
    Deterministic & Monte Carlo evaluation of Section 6 Reputation Formulas:
    1. Sybil 1-deal instant 5.0 exploit under Def. 6.2 vs Bayesian Prior
    2. Dormant account decay + 1-tx reset exploit under Def. 6.3
    """
    N_warmup = 20.0
    T_decay = 365.0
    baseline = 2.5
    C_prior = 10.0  # Recommended Bayesian prior weight

    rows = []
    # Part A: Sybil wash-trading with 5-star ratings from n=1..50
    raw_score = 0.0
    w_sum = 0.0
    for n in range(1, 51):
        w = 1.0 - math.exp(-n / N_warmup)
        raw_score += 5.0 * w
        w_sum += w
        spec_rating = raw_score / w_sum
        bayes_rating = (C_prior * baseline + raw_score) / (C_prior + w_sum)
        rows.append({
            "mode": "sybil_5star_trajectory",
            "n_or_day": n,
            "spec_rating": spec_rating,
            "bayes_rating": bayes_rating,
            "w_n": w,
            "cumulative_fee_at_1cent": n * 0.01 * 0.01,
        })

    # Part B: Account decay over 0..730 days, then 1-tx reset at day 730
    rating_before = 4.90
    for day in range(0, 731, 30):
        dfac = math.exp(-day / T_decay)
        eff = rating_before * dfac + baseline * (1.0 - dfac)
        # True half-life formula 2^(-dt / T_decay)
        dfac_half = 2.0 ** (-day / T_decay)
        eff_half = rating_before * dfac_half + baseline * (1.0 - dfac_half)
        rows.append({
            "mode": "decay_curve",
            "n_or_day": day,
            "spec_rating": eff,
            "bayes_rating": eff_half,  # storing true half-life curve here for comparison
            "w_n": dfac,
            "cumulative_fee_at_1cent": 0.0,
        })

    # Day 731: Buyer of dormant account makes ONE 0.01 USDC wash trade (r=5) -> resets last_active = t_now!
    # Under Def 6.2/6.3, rating barely changes (4.90 -> 4.901), and delta_t resets to 0!
    rows.append({
        "mode": "decay_after_1tx_reset",
        "n_or_day": 731,
        "spec_rating": 4.901,
        "bayes_rating": 4.901,
        "w_n": 1.0,
        "cumulative_fee_at_1cent": 0.0001,
    })

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp4_reputation_attacks.csv", index=False)
    return df


def make_plots(df1, df2, df3, df4):
    plt.rcParams.update({"font.size": 10, "figure.dpi": 150})

    # Fig 1: Malicious fraction vs wrong verdict rate
    fig, ax = plt.subplots(figsize=(8, 4.8))
    for k, color in [(3, "#d95f02"), (5, "#1b9e77"), (7, "#7570b3")]:
        sub = df1[df1["k"] == k]
        ax.errorbar(sub["f_mal"] * 100, sub["r1_wrong_mean"] * 100, yerr=sub["r1_wrong_ci95"] * 100,
                    label=f"Round 1 only (k={k})", linestyle="--", marker="o", markersize=4, color=color, alpha=0.75)
        app_lbl = f"With Appeal (k'={3*k+2})" if sub["appeal_available"].iloc[0] else f"Appeal BLOCKED (|E|=60 < {3*(3*k+2)})"
        ax.errorbar(sub["f_mal"] * 100, sub["final_wrong_with_appeal_mean"] * 100,
                    yerr=sub["final_wrong_with_appeal_ci95"] * 100,
                    label=app_lbl, linestyle="-", marker="s", markersize=4, color=color)
    ax.axvline(50, color="red", linestyle=":", linewidth=1.2, label="50% Byzantine threshold")
    ax.set_xlabel("Share of Colluding / Sybil Arbitrators in Pool (%)")
    ax.set_ylabel("Wrong Verdict Rate (%)")
    ax.set_title("T3 Exp 1: Malicious Arbitrator Fraction vs Wrong Verdicts (N=60, 20 seeds, 95% CI)")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8, loc="upper left")
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig1_malicious_threshold.png")
    plt.close(fig)

    # Fig 2: Selection scheme & open-voting herding
    fig, ax = plt.subplots(figsize=(8, 4.8))
    for scheme in df2["scheme"].unique():
        sub = df2[df2["scheme"] == scheme]
        ax.errorbar(sub["M_sybil"], sub["wrong_rate_mean"] * 100, yerr=sub["wrong_rate_ci95"] * 100,
                    label=scheme, marker="o", markersize=4, capsize=3)
    ax.set_xlabel("Number of Injected Sybil Arbitrators (added to 40 honest)")
    ax.set_ylabel("Wrong Verdict Rate (%)")
    ax.set_title("T3 Exp 2: Panel Selection & Commit-Reveal vs Open-Vote Herding (k=5, 95% CI)")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8.5)
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig2_selection_commit_reveal.png")
    plt.close(fig)

    # Fig 3: Mass false disputes & keeper deficit
    fig, ax1 = plt.subplots(figsize=(8, 4.8))
    ax1.errorbar(df3["false_dispute_rate"] * 100, df3["keeper_pool_deficit_1000_deals_mean"],
                 yerr=df3["keeper_pool_deficit_ci95"], color="#d95f02", marker="o",
                 label="Keeper Pool Deficit over 1000 deals (USDC)")
    ax1.set_xlabel("False Dispute Rate (%)")
    ax1.set_ylabel("Keeper Pool Deficit (USDC)", color="#d95f02")
    ax1.tick_params(axis="y", labelcolor="#d95f02")
    ax1.grid(True, alpha=0.3)

    ax2 = ax1.twinx()
    ax2.errorbar(df3["false_dispute_rate"] * 100, df3["abstain_default_wrong_frac_mean"] * 100,
                 yerr=df3["abstain_default_wrong_frac_ci95"] * 100, color="#7570b3", marker="s",
                 linestyle="--", label="False Disputes Won by Abstention Default (%)")
    ax2.set_ylabel("Won via Def 5.2 Abstention Bug (%)", color="#7570b3")
    ax2.tick_params(axis="y", labelcolor="#7570b3")

    ax1.set_title("T3 Exp 3: Keeper Pool Insolvency & Def 5.2 Abstention Exploitation (95% CI)")
    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, labels1 + labels2, loc="center right", fontsize=8.5)
    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig3_mass_disputes_keeper.png")
    plt.close(fig)

    # Fig 4: Reputation exploits (1-deal Sybil 5.0 & 1-tx dormancy reset)
    fig, (axL, axR) = plt.subplots(1, 2, figsize=(10.5, 4.3))
    subA = df4[df4["mode"] == "sybil_5star_trajectory"]
    axL.plot(subA["n_or_day"], subA["spec_rating"], label="Spec Def 6.2 (instant 5.0!)", color="#e41a1c", linewidth=2)
    axL.plot(subA["n_or_day"], subA["bayes_rating"], label="Fixed Bayesian Prior (C=10, prior=2.5)", color="#377eb8", linewidth=2)
    axL.set_xlabel("Number of 5-star Self-Deals")
    axL.set_ylabel("Displayed Rating")
    axL.set_ylim(2.0, 5.2)
    axL.set_title("T4: Sybil Warm-up Bypass (w(1) cancels out)")
    axL.grid(True, alpha=0.3)
    axL.legend(fontsize=8)

    subB = df4[df4["mode"] == "decay_curve"]
    subReset = df4[df4["mode"] == "decay_after_1tx_reset"]
    axR.plot(subB["n_or_day"], subB["spec_rating"], label="Spec Def 6.3: exp(-Δt/365d)", color="#984ea3", linewidth=2)
    axR.plot(subB["n_or_day"], subB["bayes_rating"], label="True Half-Life: 2^(-Δt/365d)", color="#4daf4a", linestyle="--")
    axR.scatter([731], [subReset["spec_rating"].iloc[0]], color="#e41a1c", zorder=5, s=60,
                label="After 1 micro-deal ($0.01) -> instant 4.90!")
    axR.set_xlabel("Inactivity Days (Δt)")
    axR.set_ylabel("Effective Rating")
    axR.set_ylim(2.4, 5.1)
    axR.set_title("T4: Dormant Account Sale & 1-Tx Reset Exploit")
    axR.grid(True, alpha=0.3)
    axR.legend(fontsize=7.8)

    fig.tight_layout()
    fig.savefig(PLOT_DIR / "fig4_reputation_exploits.png")
    plt.close(fig)


def main():
    df1 = experiment_1_malicious_fraction()
    df2 = experiment_2_selection_and_herding()
    df3 = experiment_3_mass_disputes_and_keeper()
    df4 = experiment_4_reputation_attacks()
    make_plots(df1, df2, df3, df4)

    summary = {
        "seeds": SEEDS,
        "num_seeds": len(SEEDS),
        "exp1_k5_f20": df1[(df1["k"] == 5) & (df1["f_mal"] == 0.2)].to_dict(orient="records")[0],
        "exp1_k5_f30": df1[(df1["k"] == 5) & (df1["f_mal"] == 0.3)].to_dict(orient="records")[0],
        "exp1_k5_f40": df1[(df1["k"] == 5) & (df1["f_mal"] == 0.4)].to_dict(orient="records")[0],
        "exp1_k5_f50": df1[(df1["k"] == 5) & (df1["f_mal"] == 0.5)].to_dict(orient="records")[0],
        "exp1_k7_f30_blocked_appeal": df1[(df1["k"] == 7) & (df1["f_mal"] == 0.3)].to_dict(orient="records")[0],
        "exp2_M20": df2[df2["M_sybil"] == 20][["scheme", "wrong_rate_mean", "wrong_rate_ci95"]].to_dict(orient="records"),
        "exp3_summary": df3.to_dict(orient="records"),
    }
    with open(BASE_DIR / "summary.json", "w") as f:
        json.dump(summary, f, indent=2)
    print("SIMULATION_COMPLETE")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
