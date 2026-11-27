"""
NoKing Protocol Verification v0.5 — Y0.1 & Y4 Simulation Suite
Covers:
  - Exp 0 (Y0.1): Reconcile 1.43% vs 1.83% discrepancy & unified v0.1..v0.5 comparison on identical seeds/RNGs
  - Exp 1 (Y4 / G1): Admission rejection rates & waiting/queue proxy across 4 capital hypotheses & kappa_cap
  - Exp 2 (Y4 / G2): Disjoint R2 fix (N=36, f_mal=40%), captured-parent stress test, dynamic V_protocol_max
  - Exp 3 (Y4 / G3): Keeper economics & Sybil-keeper kickback across R_keeper_max in [$2, $3, $4, $5]
  - Exp 4 (Y4 / LOO): Leave-one-out ablation ONLY for G1, G2, G3
  - Exp 5 (F3 Deferred-Reveal): Quorum-fail uplift if Phase-2 public reveal blocks redraw
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
                         coordinated=True):
    n = len(flags)
    if n < k:
        return "NO_DECISION"
    if not use_quorum:
        chosen = rng.choice(n, size=k, replace=False)
        rng.shuffle(chosen)
        vA, vB = 0, 0
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


def simulate_round_v01(rng, flags, k, commit_reveal=False, eta=0.05, p_unrev=0.08, herd_prob=0.60):
    """Exact copy of bare v0.1 rule without quorum redraw (used cleanly in no-quorum branch)."""
    n = len(flags)
    if n < k:
        return "NO_DECISION"
    chosen = rng.choice(n, size=k, replace=False)
    rng.shuffle(chosen)
    vA, vB = 0, 0
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
    return "FOR_A" if vA > k / 2.0 else "FOR_B"


def exp0_y01_reconcile_and_unified():
    """
    Y0.1: Re-run v0.1..v0.5 on identical seeds & identical RNG offsets (plus audit of seed+200 vs seed+300)
    so the 1.43% vs 1.83% discrepancy in v0.4 REPORT is cleanly resolved.
    """
    n_disputes = 300
    k, k2, Q1, Q2 = 5, 17, 3, 9
    N_par = 80

    # Diagnostic check replicating exact v0.4 seed streams vs harmonized stream
    diag_rows = []
    M = int(round(60 * 0.30))
    flags60 = np.array([True] * M + [False] * (60 - M))
    par_flags = np.array([True] * 12 + [False] * (N_par - 12))  # 0.5 * 0.30 * 80 = 12
    for label, offset, esc_lvls in [
        ("v0.4 LOO Full Stack (orig seed+200, 1 esc)", 200, 1),
        ("v0.4 Unified Baseline (orig seed+300, 2 esc)", 300, 2),
        ("v0.3 Harmonized (seed+300, 1 esc)", 300, 1),
        ("v0.4 Harmonized (seed+300, 2 esc)", 300, 2),
        ("v0.5 Disjoint R2 (seed+300, 2 esc, R2->Parent)", 300, 2),
    ]:
        w_runs, fb_runs = [], []
        for seed in SEEDS:
            rng = np.random.default_rng(seed + offset)
            w, fb = 0, 0
            for _ in range(n_disputes):
                r1 = simulate_round_clean(rng, flags60, k, True, True, Q1, 1, True)
                if r1 == "NO_DECISION":
                    r1 = simulate_round_clean(rng, par_flags, k, True, True, Q1, 1, True)
                if r1 == "NO_DECISION" and esc_lvls == 2:
                    r1 = simulate_round_clean(rng, par_flags, k, True, True, Q1, 1, True)
                if r1 == "NO_DECISION":
                    fb += 1
                elif r1 == "FOR_B":
                    r2_pool = par_flags if "R2->Parent" in label else flags60
                    r2 = simulate_round_clean(rng, r2_pool, k2, True, True, Q2, 1, True)
                    if r2 in ("FOR_B", "NO_DECISION"):
                        w += 1
            w_runs.append(w / n_disputes)
            fb_runs.append(fb / n_disputes)
        mw, cw = ci95(w_runs)
        mf, cf = ci95(fb_runs)
        diag_rows.append({
            "label": label, "N_pool": 60, "f_mal": 0.30,
            "wrong_mean": round(mw, 5), "wrong_ci95": round(cw, 5),
            "fallback_mean": round(mf, 5),
        })
    df_diag = pd.DataFrame(diag_rows)
    df_diag.to_csv(DATA_DIR / "exp0_y01_discrepancy_audit.csv", index=False)

    # Unified baseline v0.1..v0.5 on IDENTICAL per-version seed stream (seed + 300)
    rows_un = []
    for Np in [60, 36]:
        for f_mal in [0.10, 0.20, 0.30, 0.40, 0.50]:
            M = int(round(Np * f_mal))
            flags = np.array([True] * M + [False] * (Np - M))
            Mp = int(round(N_par * 0.5 * f_mal))
            par_flags = np.array([True] * Mp + [False] * (N_par - Mp))
            for ver in ["v0.1", "v0.2", "v0.3", "v0.4", "v0.5"]:
                w_runs, fb_runs = [], []
                for seed in SEEDS:
                    rng = np.random.default_rng(seed + 300)
                    w, fb = 0, 0
                    for _ in range(n_disputes):
                        if ver == "v0.1":
                            r1 = simulate_round_v01(rng, flags, k, False)
                            if r1 == "FOR_B":
                                if Np >= 3 * k2:
                                    r2 = simulate_round_v01(rng, flags, k2, False)
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
                        elif ver == "v0.4":
                            r1 = simulate_round_clean(rng, flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                r1 = simulate_round_clean(rng, par_flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                r1 = simulate_round_clean(rng, par_flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                fb += 1
                            elif r1 == "FOR_B":
                                pool_r2 = flags if Np >= 2 * k2 else par_flags
                                r2 = simulate_round_clean(rng, pool_r2, k2, True, True, Q2, 1, True)
                                if r2 in ("FOR_B", "NO_DECISION"):
                                    w += 1
                        else:  # v0.5 (G2 disjoint R2 unconditionally + G1 admission prevents passive L2 fail)
                            r1 = simulate_round_clean(rng, flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                r1 = simulate_round_clean(rng, par_flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                r1 = simulate_round_clean(rng, par_flags, k, True, True, Q1, 1, True)
                            if r1 == "NO_DECISION":
                                fb += 1
                            elif r1 == "FOR_B":
                                # G2(a): R2 ALWAYS disjoint from R1 (Parent/GLOBAL) regardless of Np >= 2*k2!
                                r2 = simulate_round_clean(rng, par_flags, k2, True, True, Q2, 1, True)
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
    df_un.to_csv(DATA_DIR / "exp0_unified_v01_v05.csv", index=False)
    return df_diag, df_un


def exp1_g1_capacity_rejection():
    """
    Y4 / G1: Simulate deal admission under G1 CapCheck across 4 capital hypotheses & kappa_cap in {1.0, 1.25, 1.50}.
    Also compares G2(b) dynamic ceiling acceptance vs static $8750 shortfall.
    """
    hyps = [
        ("Low ($400, s=1.0)", 400.0, 1.0),
        ("Mid ($600, s=1.0)", 600.0, 1.0),
        ("Heavy-tail ($800, s=1.4)", 800.0, 1.4),
        ("Pro ($2000, s=1.1)", 2000.0, 1.1),
    ]
    N_arbs = 80
    beta = 0.20
    S_arb_max = 1000.0
    n_incoming = 250
    hold_steps = 8  # Mean concurrent window deals arrive over ~8 overlapping deal lifetimes (lambda*L concurrency ~25)

    rows = []
    for hname, med, sig in hyps:
        for k_cap in [1.0, 1.25, 1.50]:
            rej_dyn_runs, rej_cap_runs, rej_tot_runs, vd1_runs, vd2_runs, vd3_runs = [], [], [], [], [], []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 1000)
                caps = np.sort(rng.lognormal(mean=np.log(med), sigma=sig, size=N_arbs))[::-1]
                tot_global_cap = float(np.sum(caps))
                # Order-statistic dynamic V_protocol_max per tier (q2 = 34, 46, 58)
                v_dyn = {}
                for T, k1, k2 in [(1, 5, 17), (2, 7, 23), (3, 9, 29)]:
                    q2 = 2 * k2 - 1
                    s_q2 = float(caps[q2])
                    s_eff = min(S_arb_max, s_q2)
                    m1, m2 = (k1 + 1) // 2, (k2 + 1) // 2
                    lam_r2 = 0.25
                    v_liq = (s_q2 / beta) if s_q2 < S_arb_max else float("inf")
                    v_dyn[T] = min(8.75 * S_arb_max, (m1 + m2 * lam_r2) * s_eff, v_liq)
                vd1_runs.append(v_dyn[1])
                vd2_runs.append(v_dyn[2])
                vd3_runs.append(v_dyn[3])

                # Simulate incoming deals (lognormal deal demand between $50 and $8750)
                # Track active concurrent reservations that expire after ~hold_steps
                active_res = []
                r_dyn, r_cap = 0, 0
                for step in range(n_incoming):
                    # Release completed deals (mean lifetime ~18 steps -> ~18 concurrent active slots tried)
                    active_res = [(exp, amt) for (exp, amt) in active_res if exp > step]
                    reserved_cap = sum(amt for _, amt in active_res)
                    V = float(np.clip(rng.lognormal(mean=np.log(450.0), sigma=1.1), 50.0, 8750.0))
                    T = 1 if V <= 2500 else (2 if V <= 5000 else 3)
                    k1, k2 = (5, 17) if T == 1 else ((7, 23) if T == 2 else (9, 29))
                    if V > v_dyn[T]:
                        r_dyn += 1
                        continue
                    S_req = min(max(beta * V, 10.0), S_arb_max)
                    # Also require >= 2*k2 unreserved arbitrators holding >= S_req (using pool minus active_res approximation)
                    c_res = k_cap * (k1 + k2) * S_req
                    if (tot_global_cap - reserved_cap) < c_res:
                        r_cap += 1
                        continue
                    lifetime = int(rng.integers(10, 26))
                    active_res.append((step + lifetime, c_res))

                rej_dyn_runs.append(r_dyn / n_incoming)
                rej_cap_runs.append(r_cap / n_incoming)
                rej_tot_runs.append((r_dyn + r_cap) / n_incoming)

            m_rd, _ = ci95(rej_dyn_runs)
            m_rc, c_rc = ci95(rej_cap_runs)
            m_rt, c_rt = ci95(rej_tot_runs)
            rows.append({
                "capital_hyp": hname, "kappa_cap": k_cap,
                "v_dyn_T1_mean": round(float(np.mean(vd1_runs)), 0),
                "v_dyn_T2_mean": round(float(np.mean(vd2_runs)), 0),
                "v_dyn_T3_mean": round(float(np.mean(vd3_runs)), 0),
                "reject_dyn_vmax_rate": round(m_rd, 4),
                "reject_g1_capacity_rate": round(m_rc, 4), "reject_g1_ci95": round(c_rc, 4),
                "reject_total_rate": round(m_rt, 4), "reject_total_ci95": round(c_rt, 4),
            })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp1_g1_capacity_rejection.csv", index=False)
    return df


def exp2_g2_disjoint_and_captured_parent():
    """
    Y4 / G2: Verify disappearance of N=36, f_mal=40% regression AND test captured-parent stress case.
    """
    n_disputes = 300
    k, k2, Q1, Q2 = 5, 17, 3, 9
    Np, N_par, N_glob = 36, 80, 120
    rows = []
    for f_mal in [0.10, 0.20, 0.30, 0.40, 0.50]:
        flags = np.array([True] * int(round(Np * f_mal)) + [False] * (Np - int(round(Np * f_mal))))
        # Scenario A: Cleaner parent (0.5 * f_mal)
        par_clean = np.array([True] * int(round(N_par * 0.5 * f_mal)) + [False] * (N_par - int(round(N_par * 0.5 * f_mal))))
        # Scenario B: Parent equally captured (1.0 * f_mal)
        par_captured = np.array([True] * int(round(N_par * f_mal)) + [False] * (N_par - int(round(N_par * f_mal))))
        # Scenario C: Clean GLOBAL (0.25 * f_mal)
        glob_clean = np.array([True] * int(round(N_glob * 0.25 * f_mal)) + [False] * (N_glob - int(round(N_glob * 0.25 * f_mal))))

        modes = [
            ("v0.4 OVS=2x (local N=36 R2)", flags, par_clean),
            ("v0.5 G2 Disjoint (Parent 0.5*f)", par_clean, par_clean),
            ("v0.5 G2 Disjoint (Parent CAPTURED 1.0*f)", par_captured, glob_clean),
            ("v0.5 G2 Direct GLOBAL (0.25*f)", glob_clean, glob_clean),
        ]
        for label, r2_pool, r1_esc in modes:
            w_runs = []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 1200)
                w = 0
                for _ in range(n_disputes):
                    r1 = simulate_round_clean(rng, flags, k, True, True, Q1, 1, True)
                    if r1 == "NO_DECISION":
                        r1 = simulate_round_clean(rng, r1_esc, k, True, True, Q1, 1, True)
                    if r1 == "FOR_B":
                        r2 = simulate_round_clean(rng, r2_pool, k2, True, True, Q2, 1, True)
                        if r2 in ("FOR_B", "NO_DECISION"):
                            w += 1
                w_runs.append(w / n_disputes)
            mw, cw = ci95(w_runs)
            rows.append({
                "N_local": Np, "f_mal": f_mal, "routing_mode": label,
                "wrong_mean": round(mw, 5), "wrong_ci95": round(cw, 5),
            })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp2_g2_disjoint_and_captured_parent.csv", index=False)
    return df


def exp3_g3_keeper_cap():
    """
    Y4 / G3: Sweep R_keeper_max in {$2, $3, $4, $5} vs uncapped v0.4 across p_rev in [0.10..0.40].
    """
    n_deals = 1000
    A_min = 50.0
    gas = 0.50
    rows = []
    for Rmax in [None, 2.0, 3.0, 4.0, 5.0]:  # None = uncapped v0.4
        label = "v0.4 Uncapped" if Rmax is None else f"v0.5 R_max=${Rmax:.0f}"
        for p_rev in [0.10, 0.20, 0.30, 0.40]:
            k_net_runs, trs_saved_runs, max_single_runs, syb_leak_runs = [], [], [], []
            for seed in SEEDS:
                rng = np.random.default_rng(seed + 700)
                deals = np.clip(rng.lognormal(mean=np.log(80.0), sigma=0.9, size=n_deals), A_min, 5000.0)
                k_net, trs_g3, trs_v04, max_k, syb_tot = 0.0, 0.0, 0.0, 0.0, 0.0
                for V in deals:
                    if rng.random() < 0.10:
                        continue
                    fee = 0.01 * V
                    if rng.random() < p_rev:
                        kpay = fee if Rmax is None else min(Rmax, fee)
                        k_net += kpay - gas
                        trs_g3 += (fee - kpay)
                        max_k = max(max_k, kpay - gas)
                        # Under v0.4: direct party/sybil kickback = fee - gas; under G3 party is blocked,
                        # 3rd-party sybil pays gas (+MEV race) capped at kpay - gas:
                        syb_tot += max(0.0, kpay - gas)
                k_net_runs.append(k_net)
                trs_saved_runs.append(trs_g3)
                max_single_runs.append(max_k)
                syb_leak_runs.append(syb_tot)
            mk, ck = ci95(k_net_runs)
            mt, ct = ci95(trs_saved_runs)
            mm, _ = ci95(max_single_runs)
            ms, cs = ci95(syb_leak_runs)
            rows.append({
                "policy": label, "R_keeper_max": 9999.0 if Rmax is None else Rmax,
                "p_review_timeout": p_rev,
                "keeper_net_1000deals_mean": round(mk, 2), "keeper_net_ci95": round(ck, 2),
                "treasury_retained_from_cap": round(mt, 2), "treasury_ci95": round(ct, 2),
                "max_single_sybil_gain_usd": round(mm, 2),
                "sybil_kickback_cap_1000deals": round(ms, 2), "sybil_ci95": round(cs, 2),
            })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp3_g3_keeper_cap.csv", index=False)
    return df


def exp4_loo_g1_g2_g3():
    """
    Y4: Leave-one-out ablation ONLY for G1, G2, G3 (v0.5 stack minus each decision).
    Uses a pooled system benchmark with:
      - Small/Mid pool arbitrage (N_local=36, f_mal=0.40 on small categories, Mid $600 capital, V up to $8750)
      - Passive exhaustion chance on unreserved pool
      - Passive buyer auto-confirms for G3 leak measurement
    """
    n_disputes = 300
    k, k2, Q1, Q2 = 5, 17, 3, 9
    N_local, N_par = 36, 80
    rows = []
    # Compare v0.5 Full vs removing G1, G2(a), G2(b), G3 across 20 seeds
    configs = [
        ("v0.5 Full Stack (G1+G2+G3)", True, True, True, True),
        ("LOO: -G1 (No CapCheck -> GLOBAL starvation risk)", False, True, True, True),
        ("LOO: -G2a (Allow same-pool R2 when N>=2k')", True, False, True, True),
        ("LOO: -G2b (Static $8750 cap -> R2 liq shortage)", True, True, False, True),
        ("LOO: -G3 (Uncapped keeper + party allowed)", True, True, True, False),
    ]
    for cfg_name, use_g1, use_g2a, use_g2b, use_g3 in configs:
        wrong_runs, split_passive_runs, r2_short_runs, sybil_leak_runs = [], [], [], []
        for seed in SEEDS:
            rng = np.random.default_rng(seed + 1400)
            # Mid capital pool (80 arbs, med $600)
            caps = np.sort(rng.lognormal(mean=np.log(600.0), sigma=1.0, size=N_par))[::-1]
            s_q2 = float(caps[2 * k2 - 1])  # 34th largest
            v_dyn_t1 = min(5250.0, s_q2 / 0.20)
            flags_loc = np.array([True] * 14 + [False] * 22)  # N=36, ~40% (14/36=38.9%)
            flags_par = np.array([True] * 16 + [False] * 64)  # N=80, 20%
            w, sp_pas, r2_sh, syb_leak = 0, 0, 0, 0.0
            for _ in range(n_disputes):
                V = float(np.clip(rng.lognormal(mean=np.log(350.0), sigma=1.1), 50.0, 5250.0))
                # G2(b) enforcement at create
                if use_g2b and V > v_dyn_t1:
                    V = min(V, v_dyn_t1)  # rejected / scaled down to tier dynamic limit
                # Passive exhaustion check in R1/R2 under unreserved overload (5% without G1 capacity reservation)
                global_starved = (not use_g1) and (rng.random() < 0.04)
                if global_starved:
                    sp_pas += 1  # V4-02 passive 50/50 split!
                else:
                    r1 = simulate_round_clean(rng, flags_loc, k, True, True, Q1, 1, True)
                    if r1 == "NO_DECISION":
                        r1 = simulate_round_clean(rng, flags_par, k, True, True, Q1, 1, True)
                    if r1 == "FOR_B":
                        # Check R2 liquidity shortage if G2b disabled
                        s_req = min(0.20 * V, 1000.0)
                        if (not use_g2b) and (np.sum(caps >= s_req) < 2 * k2):
                            r2_sh += 1
                            w += 1  # R2 shortage falls back to R1 FOR_B
                        else:
                            pool_r2 = flags_par if use_g2a else flags_loc  # N=36 >= 34 stays local without G2a!
                            r2 = simulate_round_clean(rng, pool_r2, k2, True, True, Q2, 1, True)
                            if r2 in ("FOR_B", "NO_DECISION"):
                                w += 1
                # G3 auto-confirm check (30% passive buyers)
                if rng.random() < 0.30:
                    fee = 0.01 * V
                    kpay = min(3.0, fee) if use_g3 else fee
                    syb_leak += max(0.0, kpay - 0.50)
            wrong_runs.append(w / n_disputes)
            split_passive_runs.append(sp_pas / n_disputes)
            r2_short_runs.append(r2_sh / n_disputes)
            sybil_leak_runs.append(syb_leak)

        mw, cw = ci95(wrong_runs)
        msp, csp = ci95(split_passive_runs)
        mr2, cr2 = ci95(r2_short_runs)
        msl, csl = ci95(sybil_leak_runs)
        rows.append({
            "config": cfg_name,
            "wrong_rate_mean": round(mw, 4), "wrong_ci95": round(cw, 4),
            "passive_split_rate": round(msp, 4), "passive_split_ci95": round(csp, 4),
            "r2_shortage_rate": round(mr2, 4), "r2_shortage_ci95": round(cr2, 4),
            "sybil_max_rent_300deals_usd": round(msl, 2), "sybil_ci95": round(csl, 2),
        })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp4_loo_g1_g2_g3.csv", index=False)
    return df


def exp5_f3_deferred_reveal_vs_threshold():
    """
    Simulate Phase-1 Commit-Redraw + Phase-2 Plaintext Reveal WITHOUT post-reveal redraw
    versus Threshold F3 (with post-reveal redraw) across p_unrev in [0.02..0.16].
    """
    k, Q = 5, 3
    n_disputes = 500
    rows = []
    for p_unrev in [0.02, 0.04, 0.08, 0.12, 0.16]:
        no_post_redraw_fail, with_post_redraw_fail = [], []
        for seed in SEEDS:
            rng = np.random.default_rng(seed + 1500)
            f_no, f_yes = 0, 0
            for _ in range(n_disputes):
                # Phase 2 starts with k=5 committed jurors; each reveals with prob (1 - p_unrev)
                revs = int(rng.binomial(k, 1.0 - p_unrev))
                if revs < Q:
                    f_no += 1
                    # 1 post-reveal redraw of (k - revs) new jurors
                    revs2 = revs + int(rng.binomial(k - revs, 1.0 - p_unrev))
                    if revs2 < Q:
                        f_yes += 1
            no_post_redraw_fail.append(f_no / n_disputes)
            with_post_redraw_fail.append(f_yes / n_disputes)
        mn, cn = ci95(no_post_redraw_fail)
        my, cy = ci95(with_post_redraw_fail)
        rows.append({
            "p_unrev_reveal": p_unrev,
            "deferred_no_reveal_redraw_fail": round(mn, 4), "no_redraw_ci95": round(cn, 4),
            "threshold_f3_with_redraw_fail": round(my, 4), "with_redraw_ci95": round(cy, 4),
        })
    df = pd.DataFrame(rows)
    df.to_csv(DATA_DIR / "exp5_f3_deferred_reveal.csv", index=False)
    return df


def make_plots(df_un, df_cap, df_g2, df_g3, df_loo):
    plt.rcParams.update({"font.size": 10, "figure.dpi": 150})

    # Fig 1: Disjoint G2 fix (N=36) & Captured-Parent stress test
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.0, 4.5))
    s36 = df_un[df_un["N_pool"] == 36]
    for ver, col, mk in [("v0.1", "#d95f02", "o--"), ("v0.3", "#1b9e77", "^-"),
                         ("v0.4", "#e7298a", "s:"), ("v0.5", "#1f78b4", "D-")]:
        sv = s36[s36["version"] == ver]
        ax1.plot(sv["f_mal"] * 100, (sv["wrong_mean"] + sv["fallback_mean"]) * 100, mk, label=ver, color=col, lw=2)
    ax1.set_title("Y0.1 Unified Baseline N=36 (V4-09 Regression Fixed in v0.5)")
    ax1.set_xlabel("Malicious share f_mal (%)")
    ax1.set_ylabel("Wrong + Fallback rate (%)")
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    for mode, col, mk in [
        ("v0.4 OVS=2x (local N=36 R2)", "#e7298a", "s:"),
        ("v0.5 G2 Disjoint (Parent 0.5*f)", "#1b9e77", "^-"),
        ("v0.5 G2 Disjoint (Parent CAPTURED 1.0*f)", "#d95f02", "o--"),
        ("v0.5 G2 Direct GLOBAL (0.25*f)", "#1f78b4", "D-"),
    ]:
        sg = df_g2[df_g2["routing_mode"] == mode]
        ax2.errorbar(sg["f_mal"] * 100, sg["wrong_mean"] * 100, yerr=sg["wrong_ci95"] * 100,
                     fmt=mk, label=mode, color=col, capsize=3, lw=2)
    ax2.set_title("G2 Stress Test: Clean Parent vs Captured Parent (N=36)")
    ax2.set_xlabel("Local f_mal (%)")
    ax2.set_ylabel("Wrong verdict rate (%)")
    ax2.legend(fontsize=8)
    ax2.grid(True, alpha=0.3)
    plt.tight_layout()
    fig.savefig(PLOT_DIR / "fig1_g2_disjoint_and_captured_parent.png", bbox_inches="tight")
    plt.close(fig)

    # Fig 2: G1 Capacity Rejection & Dynamic V_protocol_max across 4 Capital Hypotheses
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13.2, 4.5))
    hyps = df_cap["capital_hyp"].unique()
    x = np.arange(len(hyps))
    w = 0.25
    for idx, kcap, col in [(0, 1.0, "#1b9e77"), (1, 1.25, "#7570b3"), (2, 1.50, "#d95f02")]:
        sk = df_cap[df_cap["kappa_cap"] == kcap]
        ax1.bar(x + idx * w, sk["reject_total_rate"] * 100, width=w, label=f"kappa_cap={kcap}", color=col, alpha=0.85)
    ax1.set_xticks(x + w)
    ax1.set_xticklabels([h.split(" (")[0] for h in hyps])
    ax1.set_ylabel("Total e_create Rejection Rate (%)")
    ax1.set_title("G1+G2 Rejection Rate by Capital Hypothesis")
    ax1.legend()
    ax1.grid(True, axis="y", alpha=0.3)

    sk125 = df_cap[df_cap["kappa_cap"] == 1.25]
    ax2.bar(x - 0.25, sk125["v_dyn_T1_mean"], width=0.25, label="Tier 1 (q2=34)", color="#1b9e77")
    ax2.bar(x, sk125["v_dyn_T2_mean"], width=0.25, label="Tier 2 (q2=46)", color="#7570b3")
    ax2.bar(x + 0.25, sk125["v_dyn_T3_mean"], width=0.25, label="Tier 3 (q2=58)", color="#d95f02")
    ax2.axhline(8750, color="gray", ls="--", label="Static Tier 3 ($8,750)")
    ax2.set_xticks(x)
    ax2.set_xticklabels([h.split(" (")[0] for h in hyps])
    ax2.set_ylabel("Dynamic V_protocol_max (USDC)")
    ax2.set_title("G2 Dynamic Tier Liquidity Ceiling (beta=0.20, S_max=$1000)")
    ax2.legend(fontsize=8)
    ax2.grid(True, axis="y", alpha=0.3)
    plt.tight_layout()
    fig.savefig(PLOT_DIR / "fig2_g1_rejection_and_dynamic_vmax.png", bbox_inches="tight")
    plt.close(fig)

    # Fig 3: G3 Keeper Economics & Treasury Retention
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12.8, 4.4))
    p30 = df_g3[df_g3["p_review_timeout"] == 0.30]
    policies = p30["policy"].tolist()
    xp = np.arange(len(policies))
    ax1.bar(xp - 0.18, p30["keeper_net_1000deals_mean"], yerr=p30["keeper_net_ci95"], width=0.35, label="Keeper Net Profit", color="#1b9e77", capsize=3)
    ax1.bar(xp + 0.18, p30["treasury_retained_from_cap"], yerr=p30["treasury_ci95"], width=0.35, label="Treasury Excess Retained", color="#7570b3", capsize=3)
    ax1.set_xticks(xp)
    ax1.set_xticklabels(policies, rotation=15, fontsize=8.5)
    ax1.set_ylabel("USDC per 1,000 Deals (p_rev=30%)")
    ax1.set_title("G3 Keeper Surplus vs Treasury Excess (R_keeper_max Sweep)")
    ax1.legend()
    ax1.grid(True, axis="y", alpha=0.3)

    ax2.bar(xp, p30["max_single_sybil_gain_usd"], width=0.45, color="#d95f02", alpha=0.85)
    ax2.set_xticks(xp)
    ax2.set_xticklabels(policies, rotation=15, fontsize=8.5)
    ax2.set_ylabel("Max Single-Deal Sybil Rent (USDC)")
    ax2.set_title("G3 Single-Deal MEV / Sybil Kickback Ceiling")
    ax2.grid(True, axis="y", alpha=0.3)
    plt.tight_layout()
    fig.savefig(PLOT_DIR / "fig3_g3_keeper_and_sybil.png", bbox_inches="tight")
    plt.close(fig)

    # Fig 4: LOO Ablation for G1, G2, G3 only
    fig, ax = plt.subplots(figsize=(10.5, 4.2))
    y = np.arange(len(df_loo))
    ax.barh(y - 0.18, df_loo["wrong_rate_mean"] * 100, height=0.34, label="Wrong Verdicts (%)", color="#1f78b4")
    ax.barh(y + 0.18, (df_loo["passive_split_rate"] + df_loo["r2_shortage_rate"]) * 100, height=0.34,
            label="Passive Split / R2 Liquidity Failure (%)", color="#d95f02")
    ax.set_yticks(y)
    ax.set_yticklabels(df_loo["config"], fontsize=9)
    ax.set_xlabel("Failure / Error Rate (%)")
    ax.set_title("Y4 Leave-One-Out Ablation Restricted to G1, G2, G3 (N_loc=36, f=40%, Mid Cap)")
    ax.legend()
    ax.grid(True, axis="x", alpha=0.3)
    plt.tight_layout()
    fig.savefig(PLOT_DIR / "fig4_loo_g1_g2_g3.png", bbox_inches="tight")
    plt.close(fig)


def main():
    df_diag, df_un = exp0_y01_reconcile_and_unified()
    df_cap = exp1_g1_capacity_rejection()
    df_g2 = exp2_g2_disjoint_and_captured_parent()
    df_g3 = exp3_g3_keeper_cap()
    df_loo = exp4_loo_g1_g2_g3()
    df_f3 = exp5_f3_deferred_reveal_vs_threshold()
    make_plots(df_un, df_cap, df_g2, df_g3, df_loo)

    summary = {
        "seeds": SEEDS,
        "exp0_discrepancy_audit": df_diag.to_dict(orient="records"),
        "exp0_unified_N60_f30": df_un[(df_un["N_pool"] == 60) & (df_un["f_mal"] == 0.30)].to_dict(orient="records"),
        "exp0_unified_N36_f40": df_un[(df_un["N_pool"] == 36) & (df_un["f_mal"] == 0.40)].to_dict(orient="records"),
        "exp1_capacity_kappa125": df_cap[df_cap["kappa_cap"] == 1.25].to_dict(orient="records"),
        "exp2_g2_f40": df_g2[df_g2["f_mal"] == 0.40].to_dict(orient="records"),
        "exp3_g3_p30": df_g3[df_g3["p_review_timeout"] == 0.30].to_dict(orient="records"),
        "exp4_loo_g1_g2_g3": df_loo.to_dict(orient="records"),
        "exp5_f3_deferred_reveal": df_f3.to_dict(orient="records"),
    }
    with open(BASE_DIR / "summary_v05.json", "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)
    print("v0.5 simulations complete. Summary saved to summary_v05.json")


if __name__ == "__main__":
    main()
