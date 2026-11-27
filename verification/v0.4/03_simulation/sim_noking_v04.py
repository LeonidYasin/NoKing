"""
NoKing Protocol Verification v0.4 — X0, X4, X5 Simulation Suite
Covers:
  - Exp 1 (X0.1): Behavioral assumption sensitivity sweep (herd, p_unrev, eta)
  - Exp 2 (X0.2): Leave-one-out & pairwise ablation + unified baseline v0.1..v0.4
  - Exp 3 (X0.3): Coordinated coalitions & p+eps Dark DAO across f_mal in [0.10, 0.50]
  - Exp 4 (X4 / F2): Arbitrator liquidity across 4 capital hypotheses & OVERSAMPLE in {1.5, 2, 3}
  - Exp 5 (X4 / F1): Escalation chain frequencies, accumulated reward, & reward-farming
  - Exp 6 (X4 / F4): Keeper economics at 100% REVIEW fee & A_min sweep
  - Exp 7 (X5 / F5): Reliability value-weighted vs count-based wash dilution
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


def simulate_round_clean(rng, flags, k, commit_reveal, use_quorum, Q_arb,
                         max_redraws=1, partial_redraw=False,
                         eta=0.05, p_unrev=0.08, herd_prob=0.60,
                         coordinated=True, p_eps_bribe=False):
    n = len(flags)
    if n < k:
        return "NO_DECISION"
    if not use_quorum:
        chosen = rng.choice(n, size=k, replace=False)
        rng.shuffle(chosen)
        vA, vB = 0, 0
        for idx in chosen:
            if flags[idx] or p_eps_bribe:
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
        return "FOR_A" if vA > k / 2.0 else "FOR_B"

    vA, vB = 0, 0
    used = set()
    for att in range(1 + max_redraws):
        if partial_redraw and att > 0:
            need = k - (vA + vB)
            if need <= 0:
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
                if coordinated or (rng.random() >= 0.5 * p_unrev):
                    vB += 1
            elif p_eps_bribe:
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


def exp1_behavioral_sensitivity():
    """X0.1: Sensitivity sweep over herd, p_unrev, eta at N=60, f_mal=0.30."""
    rows = []
    N_pool = 60
    f_mal = 0.30
    M = int(round(N_pool * f_mal))
    flags = np.array([True] * M + [False] * (N_pool - M))
    n_disputes = 250
    k, k2, Q1, Q2 = 5, 17, 3, 9

    def eval_point(sweep_name, sweep_val, herd, p_unrev, eta):
        cfgs = [
            ("Bare_v01", False, False, False, 0),
            ("Appeal_only", True, False, False, 0),
            ("CR_only", False, True, False, 0),
            ("Full_Stack", True, True, True, 1),
        ]
        res = {}
        for cname, app, cr, q, red in cfgs:
            runs = []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 10)
                w = 0
                for _ in range(n_disputes):
                    r1 = simulate_round_clean(rng, flags, k, cr, q, Q1, red, True, eta, p_unrev, herd)
                    if r1 == "FOR_B":
                        if app:
                            r2 = simulate_round_clean(rng, flags, k2, cr, q, Q2, red, True, eta, p_unrev, herd)
                            if r2 == "FOR_B":
                                w += 1
                        else:
                            w += 1
                runs.append(w / n_disputes)
            mean_w, ci_w = ci95(runs)
            res[cname] = (mean_w, ci_w)
        rows.append({
            "sweep_param": sweep_name, "param_val": sweep_val,
            "herd": herd, "p_unrev": p_unrev, "eta": eta,
            "bare_wrong": round(res["Bare_v01"][0], 4),
            "appeal_only_wrong": round(res["Appeal_only"][0], 4),
            "appeal_contrib_pp": round((res["Bare_v01"][0] - res["Appeal_only"][0]) * 100, 2),
            "cr_only_wrong": round(res["CR_only"][0], 4),
            "cr_contrib_pp": round((res["Bare_v01"][0] - res["CR_only"][0]) * 100, 2),
            "full_stack_wrong": round(res["Full_Stack"][0], 4),
            "full_stack_ci95": round(res["Full_Stack"][1], 4),
        })

    for h in [0.0, 0.2, 0.4, 0.6, 0.8]:
        eval_point("herd", h, h, 0.08, 0.05)
    for pu in [0.0, 0.04, 0.08, 0.16]:
        eval_point("p_unrev", pu, 0.60, pu, 0.05)
    for et in [0.02, 0.05, 0.10, 0.20]:
        eval_point("eta", et, 0.60, 0.08, et)

    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp1_behavioral_sensitivity.csv", index=False)
    return df


def exp2_leave_one_out_and_unified():
    """X0.2: Leave-one-out ablation + pairwise + unified v0.1..v0.4 across N=60 and N=36."""
    rows_ab = []
    N_pool = 60
    N_par = 80
    n_disputes = 300
    k, k2, Q1, Q2 = 5, 17, 3, 9

    ab_configs = [
        # (name, use_app, use_cr, use_q, redraws, use_esc)
        ("Full Stack (F1+F2+CR+Q+Redraw+App)", True, True, True, 1, True),
        ("LOO: -Appeal (R1 only)", False, True, True, 1, True),
        ("LOO: -Commit-Reveal (Open voting)", True, False, True, 1, True),
        ("LOO: -Quorum (Def5.2 abstention bug)", True, True, False, 0, True),
        ("LOO: -Redraw (No retry before fallback)", True, True, True, 0, True),
        ("LOO: -Escalation F1 (Direct fallback)", True, True, True, 1, False),
        ("Pair: Appeal + Commit-Reveal", True, True, False, 0, False),
        ("Pair: Appeal + Quorum+Redraw (Open)", True, False, True, 1, False),
        ("Pair: CR + Quorum+Redraw (No Appeal)", False, True, True, 1, False),
        ("Base: Bare v0.1", False, False, False, 0, False),
    ]

    for f_mal in [0.20, 0.30, 0.40]:
        M = int(round(N_pool * f_mal))
        flags = np.array([True] * M + [False] * (N_pool - M))
        M_par = int(round(N_par * 0.5 * f_mal))
        par_flags = np.array([True] * M_par + [False] * (N_par - M_par))
        for label, use_app, use_cr, use_q, red, use_esc in ab_configs:
            w_runs, fb_runs = [], []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 200)
                w, fb = 0, 0
                for _ in range(n_disputes):
                    r1 = simulate_round_clean(rng, flags, k, use_cr, use_q, Q1, red, True)
                    if r1 == "NO_DECISION" and use_esc:
                        r1 = simulate_round_clean(rng, par_flags, k, use_cr, use_q, Q1, red, True)
                    if r1 == "NO_DECISION":
                        fb += 1
                    elif r1 == "FOR_B":
                        if use_app:
                            r2 = simulate_round_clean(rng, flags, k2, use_cr, use_q, Q2, red, True)
                            if r2 == "FOR_B":
                                w += 1
                            elif r2 == "NO_DECISION":
                                w += 1  # E1/F1 R1 stands
                        else:
                            w += 1
                w_runs.append(w / n_disputes)
                fb_runs.append(fb / n_disputes)
            mw, cw = ci95(w_runs)
            mf, cf = ci95(fb_runs)
            rows_ab.append({
                "f_mal": f_mal, "config": label,
                "wrong_mean": mw, "wrong_ci95": cw,
                "fallback_mean": mf, "fallback_ci95": cf,
            })

    df_ab = pd.DataFrame(rows_ab)
    df_ab.to_csv(DATA_DIR / "exp2_leave_one_out_ablation.csv", index=False)

    # Unified comparison v0.1..v0.4 on N=60 and N=36 (OVERSAMPLE=2x puts N=36 >= 34 for k'=17!)
    rows_un = []
    for Np in [60, 36]:
        for f_mal in [0.10, 0.20, 0.30, 0.40, 0.50]:
            M = int(round(Np * f_mal))
            flags = np.array([True] * M + [False] * (Np - M))
            Mp = int(round(N_par * 0.5 * f_mal))
            par_flags = np.array([True] * Mp + [False] * (N_par - Mp))
            for ver in ["v0.1", "v0.2", "v0.3", "v0.4"]:
                w_runs, fb_runs = [], []
                for seed in SEEDS:
                    rng = np.random.default_rng(seed + 300)
                    w, fb = 0, 0
                    for _ in range(n_disputes):
                        if ver == "v0.1":
                            r1 = simulate_round_clean(rng, flags, k, False, False, Q1)
                            if r1 == "FOR_B":
                                if Np >= 3 * k2:
                                    r2 = simulate_round_clean(rng, flags, k2, False, False, Q2)
                                    if r2 == "FOR_B":
                                        w += 1
                                else:
                                    w += 1
                        elif ver == "v0.2":
                            r1 = simulate_round_clean(rng, flags, k, True, True, Q1, 1, False)
                            if r1 == "NO_DECISION":
                                fb += 1
                            elif r1 == "FOR_B":
                                if Np >= 3 * k2:
                                    r2 = simulate_round_clean(rng, flags, k2, True, True, Q2, 1, False)
                                    if r2 == "FOR_B":
                                        w += 1
                                    elif r2 == "NO_DECISION":
                                        fb += 1
                                else:
                                    fb += 1
                        elif ver == "v0.3":
                            r1 = simulate_round_clean(rng, flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                r1 = simulate_round_clean(rng, par_flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                fb += 1
                            elif r1 == "FOR_B":
                                pool_r2 = flags if Np >= 3 * k2 else par_flags
                                r2 = simulate_round_clean(rng, pool_r2, k2, True, True, Q2, 1, True)
                                if r2 in ("FOR_B", "NO_DECISION"):
                                    w += 1
                        else:  # v0.4: F1 (2 escalation levels L1+Global), F2 (2x oversample: 34<=36!)
                            r1 = simulate_round_clean(rng, flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                r1 = simulate_round_clean(rng, par_flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                r1 = simulate_round_clean(rng, par_flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                fb += 1
                            elif r1 == "FOR_B":
                                # OVERSAMPLE = 2x -> N_min = 34 -> N=36 fits locally without escalating R2!
                                pool_r2 = flags if Np >= 2 * k2 else par_flags
                                r2 = simulate_round_clean(rng, pool_r2, k2, True, True, Q2, 1, True)
                                if r2 in ("FOR_B", "NO_DECISION"):
                                    w += 1
                    w_runs.append(w / n_disputes)
                    fb_runs.append(fb / n_disputes)
                mw, cw = ci95(w_runs)
                mf, cf = ci95(fb_runs)
                rows_un.append({
                    "N_pool": Np, "f_mal": f_mal, "version": ver,
                    "wrong_mean": mw, "wrong_ci95": cw,
                    "fallback_mean": mf, "fallback_ci95": cf,
                })

    df_un = pd.DataFrame(rows_un)
    df_un.to_csv(DATA_DIR / "exp2_unified_v01_v04.csv", index=False)
    return df_ab, df_un


def exp3_coalitions():
    """X0.3: Independent vs Coordinated Block vs p+epsilon Dark DAO across f_mal in [0.10, 0.50]."""
    rows = []
    N_pool = 60
    n_disputes = 250
    k, k2, Q1, Q2 = 5, 17, 3, 9
    for f_mal in [0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50]:
        M = int(round(N_pool * f_mal))
        flags = np.array([True] * M + [False] * (N_pool - M))
        for mode, coord, p_eps in [
            ("Independent (noisy mal)", False, False),
            ("Coordinated Coalition Block", True, False),
            ("p+epsilon Dark DAO (funded)", True, True),
        ]:
            w_runs = []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 400)
                w = 0
                for _ in range(n_disputes):
                    r1 = simulate_round_clean(rng, flags, k, True, True, Q1, 1, True,
                                              coordinated=coord, p_eps_bribe=p_eps)
                    if r1 == "FOR_B":
                        r2 = simulate_round_clean(rng, flags, k2, True, True, Q2, 1, True,
                                                  coordinated=coord, p_eps_bribe=p_eps)
                        if r2 in ("FOR_B", "NO_DECISION"):
                            w += 1
                w_runs.append(w / n_disputes)
            mw, cw = ci95(w_runs)
            rows.append({
                "f_mal": f_mal, "adversary_mode": mode,
                "wrong_mean": mw, "wrong_ci95": cw,
            })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp3_coalitions.csv", index=False)
    return df


def exp4_oversample_liquidity():
    """X4 / F2: 4 Capital hypotheses x OVERSAMPLE in {1.5, 2.0, 3.0} across Tiers 1-3."""
    rows = []
    N_arbs = 80
    hyps = [
        ("Low ($400 med, s=1.0)", 400, 1.0),
        ("Mid ($600 med, s=1.0)", 600, 1.0),
        ("Heavy-tail ($800 med, s=1.4)", 800, 1.4),
        ("Pro ($2000 med, s=1.1)", 2000, 1.1),
    ]
    beta = 0.20
    S_max = 1000.0
    deals = [500, 2500, 5000, 8750]  # Within F2 V_protocol_max=$8750

    for hname, med, sig in hyps:
        for ovs in [1.5, 2.0, 3.0]:
            for V in deals:
                k1 = 5 if V <= 2500 else (7 if V <= 5000 else 9)
                k2 = 3 * k1 + 2
                S_req = min(beta * V, S_max)
                r1_fail, r2_fail, liq_list = [], [], []
                for seed in SEEDS:
                    rng = np.random.default_rng(seed + 500)
                    caps = rng.lognormal(mean=np.log(med), sigma=sig, size=N_arbs)
                    n_liq = int(np.sum(caps >= S_req))
                    liq_list.append(n_liq)
                    r1_fail.append(1.0 if n_liq < math.ceil(ovs * k1) else 0.0)
                    r2_fail.append(1.0 if n_liq < math.ceil(ovs * k2) else 0.0)
                ml, _ = ci95(liq_list)
                mr1, _ = ci95(r1_fail)
                mr2, cr2 = ci95(r2_fail)
                rows.append({
                    "capital_hyp": hname, "oversample": ovs, "deal_value": V,
                    "k1": k1, "k2": k2, "req_r2_pool": math.ceil(ovs * k2),
                    "S_req": S_req, "liquid_arbs_mean": round(ml, 2),
                    "r1_shortage_prob": mr1, "r2_shortage_prob": mr2, "r2_shortage_ci95": cr2,
                })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp4_oversample_liquidity.csv", index=False)
    return df


def exp5_escalation_and_farming():
    """X4 / F1: Escalation frequency, accumulated reward, & arbitrator reward-farming EV."""
    rows_esc = []
    # Simulate 500 disputes across failure probabilities p_fail_att in [0.05, 0.15, 0.30]
    R_base = 5.0
    delta_R = 5.0  # additive +$5/attempt
    for p_fail in [0.05, 0.15, 0.30]:
        for seed_idx, d_rate in enumerate(["Additive (+$5/step)", "Multiplicative (1.5x^j)"]):
            lvl_counts, rew_list, split_rates = [], [], []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 600 + seed_idx)
                tot_rew, splits, esc_cnt = 0.0, 0, 0
                for _ in range(300):
                    att = 0
                    resolved = False
                    for lvl in range(3):  # L0, L1, L2
                        for _sub in range(2):
                            rew = (R_base + att * delta_R) if seed_idx == 0 else (R_base * (1.5 ** att))
                            if rng.random() >= p_fail:
                                tot_rew += rew
                                resolved = True
                                break
                            att += 1
                        if resolved:
                            break
                        if lvl < 2:
                            esc_cnt += 1
                    if not resolved:
                        splits += 1
                lvl_counts.append(esc_cnt / 300.0)
                rew_list.append(tot_rew / 300.0)
                split_rates.append(splits / 300.0)
            me, ce = ci95(lvl_counts)
            mr, cr = ci95(rew_list)
            ms, cs = ci95(split_rates)
            rows_esc.append({
                "p_attempt_fail": p_fail, "schedule": d_rate,
                "escalations_per_dispute_mean": round(me, 4), "esc_ci95": round(ce, 4),
                "avg_final_reward_usd": round(mr, 2), "rew_ci95": round(cr, 2),
                "final_split_rate": round(ms, 4), "split_ci95": round(cs, 4),
            })
    df_esc = pd.DataFrame(rows_esc)
    df_esc.to_csv(DATA_DIR / "exp5_escalation_rewards.csv", index=False)

    # Reward-farming arbitrage profitability table (X3.1a)
    rows_farm = []
    for V in [100, 1000, 5000]:
        S_arb = min(0.10 * V, 1000.0)
        lam_unrev = 0.50
        for N_pool in [20, 60]:
            q_re = 5.0 / N_pool
            for dR in [5.0, 20.0, 50.0]:
                # Case A: Ban re-entry of saboteur (v0.4 rule) -> EV <= -lam_unrev*S_arb
                ev_v04_ban = -lam_unrev * S_arb
                # Case B: No ban, unrev slashed
                ev_unrev_slash = q_re * dR - lam_unrev * S_arb
                # Case C: Unslashed pre-commit decline
                ev_unslashed_decline = q_re * dR
                rows_farm.append({
                    "V": V, "S_arb": S_arb, "N_pool": N_pool, "DeltaR": dR,
                    "ev_v04_banned": round(ev_v04_ban, 2),
                    "ev_unrev_no_ban": round(ev_unrev_slash, 2),
                    "ev_unslashed_decline": round(ev_unslashed_decline, 2),
                    "farming_profitable_if_unslashed": ev_unslashed_decline > 0,
                })
    df_farm = pd.DataFrame(rows_farm)
    df_farm.to_csv(DATA_DIR / "exp5_reward_farming.csv", index=False)
    return df_esc, df_farm


def exp6_keeper_f4():
    """X4 / F4: 100% protocol_fee on REVIEW timeout across A_min & p_rev."""
    rows = []
    n_deals = 1000
    for A_min in [10.0, 25.0, 50.0, 100.0]:
        for p_rev in [0.10, 0.20, 0.30, 0.40]:
            keeper_net_runs, dao_rev_loss_runs, max_mev_runs = [], [], []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 700)
                deals = np.clip(rng.lognormal(mean=np.log(80), sigma=0.9, size=n_deals), A_min, 5000.0)
                k_net, dao_normal, dao_f4, mev_windfall = 0.0, 0.0, 0.0, 0.0
                for V in deals:
                    if rng.random() < 0.10:
                        continue  # EXPIRED funded from seller penalty
                    fee = 0.01 * V
                    dao_normal += 0.40 * fee
                    if rng.random() < p_rev:
                        # 100% of fee goes to keeper calling e_timeout! Gas cost ~ $0.50
                        k_net += fee - 0.50
                        mev_windfall += max(0.0, fee - 0.50)
                    else:
                        dao_f4 += 0.40 * fee
                keeper_net_runs.append(k_net)
                dao_rev_loss_runs.append(dao_normal - dao_f4)
                max_mev_runs.append(mev_windfall)
            m_k, c_k = ci95(keeper_net_runs)
            m_d, c_d = ci95(dao_rev_loss_runs)
            m_m, _ = ci95(max_mev_runs)
            rows.append({
                "A_min": A_min, "p_review_timeout": p_rev,
                "min_single_deal_surplus_usd": round(0.01 * A_min - 0.50, 2),
                "keeper_net_1000deals_mean": round(m_k, 2), "keeper_net_ci95": round(c_k, 2),
                "dao_treasury_redirect_usd": round(m_d, 2), "dao_redirect_ci95": round(c_d, 2),
                "excess_mev_above_050_usd": round(m_m, 2),
            })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp6_keeper_f4.csv", index=False)
    return df


def exp7_reliability_f5():
    """X5 / F5: Reliability dimension dilution test (value-weighted vs count-based)."""
    V_ref = 50.0
    m_rel = 5.0
    rows = []
    # Seller has 1 real $2000 default (after 10 real $200 deals) and runs wash self-deals at A_min=$50
    for n_wash in [0, 5, 10, 20, 40, 80]:
        wash_fee = n_wash * 50.0 * 0.01
        # Count-based
        cnt_def = 1.0 / (10 + 1 + n_wash + m_rel)
        # Capped weight min(1, V/V_ref): $2000 gets capped to 1.0 -> equal to $50!
        cap_w_comm = 10 * 1.0 + 1.0 + n_wash * 1.0
        cap_def = 1.0 / (cap_w_comm + m_rel)
        # Un-capped volume weight V/V_ref (v0.4 F5): $2000 weighs 40x $50!
        vol_w_def = 2000.0 / V_ref
        vol_w_comm = (10 * 200.0 + 2000.0 + n_wash * 50.0) / V_ref
        vol_def = vol_w_def / (vol_w_comm + m_rel)
        rows.append({
            "wash_deals_at_50": n_wash, "wash_fee_usd": wash_fee,
            "count_based_default_rate": round(cnt_def, 4),
            "capped_weight_default_rate": round(cap_def, 4),
            "v04_volume_weighted_default_rate": round(vol_def, 4),
        })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp7_reliability_f5.csv", index=False)
    return df


def make_plots(df1, df2_ab, df2_un, df3, df4, df6):
    plt.rcParams.update({"font.size": 10, "figure.dpi": 150})

    # Fig 1: Behavioral sensitivity (X0.1)
    fig, axes = plt.subplots(1, 3, figsize=(13.5, 4.3), sharey=True)
    for ax, param, ttl in [
        (axes[0], "herd", "Herding prob (herd)"),
        (axes[1], "p_unrev", "Non-reveal rate (p_unrev)"),
        (axes[2], "eta", "Arbitrator signal error (eta)"),
    ]:
        s = df1[df1["sweep_param"] == param]
        ax.plot(s["param_val"], s["bare_wrong"] * 100, "o--", label="Bare v0.1", color="#7f7f7f")
        ax.plot(s["param_val"], s["cr_only_wrong"] * 100, "s-.", label="+CR only", color="#d95f02")
        ax.plot(s["param_val"], s["appeal_only_wrong"] * 100, "^:", label="+Appeal only", color="#7570b3")
        ax.plot(s["param_val"], s["full_stack_wrong"] * 100, "D-", lw=2.2, label="Full Stack", color="#1b9e77")
        ax.set_title(ttl)
        ax.set_xlabel(param)
        ax.grid(True, alpha=0.3)
    axes[0].set_ylabel("Wrong verdicts (%, N=60, f_mal=30%)")
    axes[2].legend(fontsize=8, loc="upper left")
    fig.suptitle("X0.1 Behavioral Parameter Sensitivity (20 seeds)", y=1.02)
    plt.tight_layout()
    fig.savefig(PLOT_DIR / "fig1_behavioral_sensitivity.png", bbox_inches="tight")
    plt.close(fig)

    # Fig 2: Leave-one-out ablation at f_mal=0.30 & Coalition curves (X0.2 & X0.3)
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.2, 4.8))
    s30 = df2_ab[df2_ab["f_mal"] == 0.30].sort_values("wrong_mean", ascending=True)
    y = np.arange(len(s30))
    ax1.barh(y, s30["wrong_mean"] * 100, xerr=s30["wrong_ci95"] * 100, color="#1b9e77", alpha=0.85, capsize=3)
    ax1.set_yticks(y)
    ax1.set_yticklabels(s30["config"], fontsize=8.5)
    ax1.set_xlabel("Wrong verdicts (%, 95% CI)")
    ax1.set_title("X0.2 Leave-One-Out & Pairwise Ablation (N=60, f=30%)")
    ax1.grid(True, axis="x", alpha=0.3)

    for mode, col, mk in [
        ("Independent (noisy mal)", "#1b9e77", "o-"),
        ("Coordinated Coalition Block", "#d95f02", "s--"),
        ("p+epsilon Dark DAO (funded)", "#e7298a", "^:"),
    ]:
        sc = df3[df3["adversary_mode"] == mode]
        ax2.errorbar(sc["f_mal"] * 100, sc["wrong_mean"] * 100, yerr=sc["wrong_ci95"] * 100,
                     fmt=mk, label=mode, color=col, capsize=3, lw=2)
    ax2.axvline(33.3, color="gray", ls=":", lw=1, label="1/3 threshold")
    ax2.set_xlabel("Malicious / coalition share f_mal (%)")
    ax2.set_ylabel("Wrong verdicts (%)")
    ax2.set_title("X0.3 Coalition & p+epsilon Breakdown Curves")
    ax2.legend(fontsize=8)
    ax2.grid(True, alpha=0.3)
    plt.tight_layout()
    fig.savefig(PLOT_DIR / "fig2_ablation_and_coalitions.png", bbox_inches="tight")
    plt.close(fig)

    # Fig 3: OVERSAMPLE in {1.5x, 2x, 3x} across 4 capital hypotheses (X4 / F2)
    fig, axes = plt.subplots(1, 4, figsize=(14.5, 4.2), sharey=True)
    hyps = df4["capital_hyp"].unique()
    for ax, h in zip(axes, hyps):
        sh = df4[df4["capital_hyp"] == h]
        for ovs, col, mk in [(3.0, "#d95f02", "o--"), (2.0, "#7570b3", "s-"), (1.5, "#1b9e77", "^:")]:
            so = sh[sh["oversample"] == ovs]
            ax.plot(so["deal_value"], so["r2_shortage_prob"] * 100, mk, label=f"OVS={ovs}x", color=col, lw=1.8)
        ax.set_xscale("log")
        ax.set_title(h, fontsize=9)
        ax.set_xlabel("Deal V (USDC, log)")
        ax.grid(True, alpha=0.3)
    axes[0].set_ylabel("Round 2 Liquidity Shortage (%)")
    axes[3].legend(fontsize=8.5, loc="upper left")
    fig.suptitle("X4 / F2: Round-2 Arbitrator Shortage under OVERSAMPLE (S_arb_max=$1000, N=80)", y=1.02)
    plt.tight_layout()
    fig.savefig(PLOT_DIR / "fig3_oversample_liquidity.png", bbox_inches="tight")
    plt.close(fig)

    # Fig 4: Keeper F4 & Unified v0.1..v0.4 (N=36)
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12.2, 4.4))
    for pr, col in [(0.10, "#1b9e77"), (0.20, "#7570b3"), (0.30, "#d95f02"), (0.40, "#e7298a")]:
        sp = df6[df6["p_review_timeout"] == pr]
        ax1.errorbar(sp["A_min"], sp["keeper_net_1000deals_mean"], yerr=sp["keeper_net_ci95"],
                     fmt="o-", label=f"p_rev={int(pr*100)}%", color=col, capsize=3)
    ax1.axhline(0, color="black", ls="--", lw=1)
    ax1.axvline(50, color="gray", ls=":", label="F4 A_min=$50")
    ax1.set_title("X4 / F4: Keeper Net Profit (100% Auto-Confirm Fee)")
    ax1.set_xlabel("A_min (USDC)")
    ax1.set_ylabel("Net Profit / 1000 Deals (USDC)")
    ax1.legend(fontsize=8)
    ax1.grid(True, alpha=0.3)

    s36 = df2_un[df2_un["N_pool"] == 36]
    for ver, col, mk in [("v0.1", "#d95f02", "o--"), ("v0.2", "#7570b3", "s-."),
                         ("v0.3", "#1b9e77", "^-"), ("v0.4", "#1f78b4", "D-")]:
        sv = s36[s36["version"] == ver]
        ax2.plot(sv["f_mal"] * 100, (sv["wrong_mean"] + sv["fallback_mean"]) * 100, mk, label=ver, color=col, lw=2)
    ax2.set_title("Unified Baseline v0.1..v0.4 (Small Pool N=36)")
    ax2.set_xlabel("Malicious Share f_mal (%)")
    ax2.set_ylabel("Wrong + Fallback Rate (%)")
    ax2.legend(fontsize=8.5)
    ax2.grid(True, alpha=0.3)
    plt.tight_layout()
    fig.savefig(PLOT_DIR / "fig4_keeper_f4_and_unified.png", bbox_inches="tight")
    plt.close(fig)


def exp8_f3_sealed_redraw():
    """X4 / F3: Compare attacker seats-to-bribe on leaked v0.3 redraw vs sealed v0.4 F3."""
    rows = []
    # k=5, Q_arb=3. Whenever initial round stops short of Q=3 (valid_votes in {0,1,2}),
    # simulate distribution of (vA, vB) with honest prior probability pA = 1 - eta = 0.85..0.95.
    k = 5
    for p_honest_A in [0.70, 0.85, 0.95]:
        leaked_seats, sealed_worst_seats, win_leaked, win_sealed_budget2 = [], [], [], []
        for seed in SEEDS:
            rng = np.random.default_rng(seed + 800)
            ls_list, ss_list, wl_list, ws_list = [], [], [], []
            for _ in range(500):
                valid = int(rng.choice([0, 1, 2], p=[0.2, 0.4, 0.4]))
                vA = int(rng.binomial(valid, p_honest_A))
                vB = valid - vA
                # To guarantee vB_total >= 3 (strict majority on full 5):
                need_to_guarantee = 3 - vB
                ls_list.append(need_to_guarantee)
                ss_list.append(3)  # Worst-case vB=0 unknown under F3
                # Apples-to-apples certainty comparison with max budget=2 bribes:
                # Leaked v0.3: attacker guarantees flip whenever need_to_guarantee <= 2 (and skips need=3, 0 wasted bribes)
                # F3 sealed: attacker CANNOT guarantee flip with <= 2 bribes (0% guaranteed, vs worst-case 3 required)
                wl_list.append(1.0 if need_to_guarantee <= 2 else 0.0)
                ws_list.append(0.0)  # Cannot deterministically guarantee with budget 2 without knowing vB
            leaked_seats.append(float(np.mean(ls_list)))
            sealed_worst_seats.append(float(np.mean(ss_list)))
            win_leaked.append(float(np.mean(wl_list)))
            win_sealed_budget2.append(float(np.mean(ws_list)))
        ml, cl = ci95(leaked_seats)
        mwl, cwl = ci95(win_leaked)
        mws, cws = ci95(win_sealed_budget2)
        rows.append({
            "p_honest_A": p_honest_A,
            "avg_bribes_needed_leaked_v03": round(ml, 3), "leaked_ci95": round(cl, 3),
            "worst_case_bribes_F3": 3.0,
            "guaranteed_flip_budget2_leaked_v03": round(mwl, 3), "win_leaked_ci95": round(cwl, 3),
            "guaranteed_flip_budget2_F3": round(mws, 3), "win_F3_ci95": round(cws, 3),
        })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp8_f3_sealed_redraw.csv", index=False)
    return df


def main():
    df1 = exp1_behavioral_sensitivity()
    df2_ab, df2_un = exp2_leave_one_out_and_unified()
    df3 = exp3_coalitions()
    df4 = exp4_oversample_liquidity()
    df5_esc, df5_farm = exp5_escalation_and_farming()
    df6 = exp6_keeper_f4()
    df7 = exp7_reliability_f5()
    df8 = exp8_f3_sealed_redraw()
    make_plots(df1, df2_ab, df2_un, df3, df4, df6)

    summary = {
        "seeds": SEEDS,
        "exp1_herd_range": df1[df1["sweep_param"] == "herd"].to_dict(orient="records"),
        "exp2_ablation_f30": df2_ab[df2_ab["f_mal"] == 0.30].to_dict(orient="records"),
        "exp2_unified_f30": df2_un[df2_un["f_mal"] == 0.30].to_dict(orient="records"),
        "exp3_coalitions": df3.to_dict(orient="records"),
        "exp4_mid_v8750": df4[(df4["capital_hyp"].str.startswith("Mid")) & (df4["deal_value"] == 8750)].to_dict(orient="records"),
        "exp5_escalation": df5_esc.to_dict(orient="records"),
        "exp6_keeper_p30": df6[df6["p_review_timeout"] == 0.30].to_dict(orient="records"),
        "exp7_reliability": df7.to_dict(orient="records"),
        "exp8_f3": df8.to_dict(orient="records"),
    }
    with open(DATA_DIR.parent / "summary_v04.json", "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)
    print("Simulations complete. Summary saved to summary_v04.json")


if __name__ == "__main__":
    main()
