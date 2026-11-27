"""
NoKing Protocol v0.5 — Game Theory & Mechanism Design Analysis (Y3)
Covers:
  - Y3.1: F1 acceptance condition after G1 (4 party types + arbitrator farming + dynamic cap)
  - Y3.2: G1 Capacity-Filling DoS economics (DRAFT-churn vs LOCKED hold + break-even fee ratio)
  - Y3.3: G3 Bounded Keeper & residual Sybil-Keeper extraction across R_keeper_max in [2..5]
  - Y3.4: Dynamic V_protocol_max(c, tier) analytical order-statistic formula & beta_arb condition
  - Y3.5: Explicit theorem boundaries (p+epsilon & NE non-uniqueness)
"""

import math


def hdr(title):
    print("\n" + "=" * 82)
    print(title)
    print("=" * 82)


def normal_ppf(p):
    """Inverse standard normal CDF approximation (Peter Acklam) for lognormal order stats."""
    # Coefficients
    a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
         1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
    b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
         6.680131188771972e+01, -1.328068155288572e+01]
    c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
         -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
    d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
         3.754408661907416e+00]
    plow = 0.02425
    phigh = 1.0 - plow
    if p < plow:
        q = math.sqrt(-2.0 * math.log(p))
        return (((((c[0]*q + c[1])*q + c[2])*q + c[3])*q + c[4])*q + c[5]) / (
            ((((d[0]*q + d[1])*q + d[2])*q + d[3])*q + 1.0))
    if p > phigh:
        q = math.sqrt(-2.0 * math.log(1.0 - p))
        return -(((((c[0]*q + c[1])*q + c[2])*q + c[3])*q + c[4])*q + c[5]) / (
            ((((d[0]*q + d[1])*q + d[2])*q + d[3])*q + 1.0))
    q = p - 0.5
    r = q * q
    return (((((a[0]*r + a[1])*r + a[2])*r + a[3])*r + a[4])*r + a[5]) * q / (
        (((((b[0]*r + b[1])*r + b[2])*r + b[3])*r + b[4])*r + 1.0))


def main():
    hdr("Y3.1: F1 ACCEPTANCE AFTER G1 (NO PASSIVE EXHAUSTION + DYNAMIC CEILING)")
    alpha, delta, phi, sigma = 0.10, 0.05, 0.01, 0.50
    r_apr, days_delay = 0.08, 6.0
    delay_cost = r_apr * (days_delay / 365.0)
    dish_seller_gain = (0.50 + alpha - delta - delay_cost) - 0.0  # +0.5487 V
    dish_buyer_gain = (0.50 - 1.0 - delta + 1.0 - delay_cost) - (-delta)  # +0.4987 V

    print(f"Delay cost (6d @ 8% APR): {delay_cost*100:.4f}% V")
    print(f"Honest Seller gain from split:    {(0.50 + alpha - delta - delay_cost) - (1.0 - phi + alpha):+.4f} V")
    print(f"Honest Buyer gain from split:     {(0.50 - delta - delay_cost) - (1.0 + sigma*alpha + delta):+.4f} V")
    print(f"Dishonest Buyer gain from split:  {dish_buyer_gain:+.4f} V")
    print(f"Dishonest Seller gain from split: {dish_seller_gain:+.4f} V")
    print("Under G1 admission: passive GLOBAL shortage (C_sab=0) is BLOCKED by CapCheck in e_create.")

    lam_unrev = 0.50
    lam_r2 = 0.25
    beta = 0.20
    S_arb_max = 1000.0
    print(f"\nActive 6-attempt sabotage check across S_liq_eff in [$300, $1000] (beta={beta}, lam_unrev={lam_unrev}):")
    tiers = [("Tier 1", 5, 3, 17), ("Tier 2", 7, 4, 23), ("Tier 3", 9, 5, 29)]
    for tname, k, Q, k2 in tiers:
        m1, m2 = (k + 1) // 2, (k2 + 1) // 2
        bribe_mult = m1 + m2 * lam_r2
        seats_brk = k - Q + 1
        sab_mult = 6 * seats_brk * lam_unrev  # 9.0, 12.0, 15.0 * S_arb
        # Compare max active sabotage C_sab against split gain 0.5487 * V at V = V_protocol_max
        for S_liq in [300.0, 600.0, 1000.0]:
            v_bribe_cap = bribe_mult * S_liq
            v_liq_cap = (S_liq / beta) if S_liq < S_arb_max else float("inf")
            v_dyn = min(8.75 * S_arb_max, v_bribe_cap, v_liq_cap)
            s_at_vdyn = min(beta * v_dyn, S_liq)
            c_sab = sab_mult * s_at_vdyn
            split_profit = dish_seller_gain * v_dyn
            print(f"  {tname} (S_liq=${S_liq:4.0f}): V_dyn=${v_dyn:6,.0f}, C_sab=${c_sab:8,.0f} vs +0.5487V=${split_profit:6,.0f} (ratio {c_sab/split_profit:.2f}x)")

    hdr("Y3.2: G1 CAPACITY-FILLING DoS ECONOMICS (DRAFT-CHURN VS LOCKED HOLD)")
    free_global_cap = 100000.0  # Suppose $100k free GLOBAL capacity
    k_cap = 1.25
    r_apr_dos = 0.08
    t_accept_days = 1.0  # 24h DRAFT window
    gas_cycle = 0.50
    for V, k1, k2 in [(50.0, 5, 17), (500.0, 5, 17), (2500.0, 5, 17), (5001.0, 9, 29), (8750.0, 9, 29)]:
        S_req = min(max(beta * V, 10.0), S_arb_max)
        cap_per_deal = k_cap * (k1 + k2) * S_req
        n_deals_needed = math.ceil(free_global_cap / cap_per_deal)
        # Mode A: DRAFT-churn (attacker only puts seller_deposit = alpha * V; 0% protocol cancel fee in v0.4/v0.5!)
        capital_draft = n_deals_needed * (alpha * V)
        leverage_draft = (n_deals_needed * cap_per_deal) / capital_draft
        daily_cost_draft = capital_draft * (r_apr_dos / 365.0) + n_deals_needed * (2 * gas_cycle / t_accept_days)
        # Mode B: Self-deal LOCKED -> CLOSED (1.10 * V locked + 1% fee on close every Deadline=7d)
        capital_locked = n_deals_needed * ((1.0 + alpha) * V)
        daily_cost_locked = capital_locked * (r_apr_dos / 365.0) + (n_deals_needed * 0.01 * V) / 7.0
        # Minimum non-refundable cancel/reservation fee rate delta_dos to make daily_cost >= D_honest (say $500/day lost fees)
        d_honest_day = 500.0
        min_fee_per_draft = d_honest_day / n_deals_needed
        min_fee_pct_of_V = (min_fee_per_draft / V) * 100.0
        print(f"  V=${V:7.2f} (k+k'={k1+k2:2d}, S_req=${S_req:6.1f}): Cap/deal=${cap_per_deal:9,.0f}, Deals={n_deals_needed:3d} | "
              f"DRAFT lock=${capital_draft:8,.0f} (lev={leverage_draft:4.1f}x, cost=${daily_cost_draft:5.2f}/d) | "
              f"LOCKED lock=${capital_locked:9,.0f} (cost=${daily_cost_locked:6.2f}/d) | "
              f"Break-even cancel fee vs $500/d dmg: {min_fee_pct_of_V:.3f}% V")

    hdr("Y3.3: G3 KEEPER CAP (R_keeper_max in [$2..$5]) & SYBIL-KEEPER RESIDUAL COST")
    gas = 0.50
    for V in [50.0, 200.0, 500.0, 1000.0, 2500.0, 5000.0, 8750.0]:
        fee = 0.01 * V
        line = f"  V=${V:5.0f} (fee=${fee:5.2f}): v0.4_sybil_net=${fee-gas:5.2f}"
        for Rmax in [2.0, 3.0, 4.0, 5.0]:
            kpay = min(Rmax, fee)
            syb_net = kpay - gas
            trs = fee - kpay
            line += f" | Rmax=${Rmax:.0f}: syb=${syb_net:4.2f}, trs=${trs:5.2f}"
        print(line)

    hdr("Y3.4: DYNAMIC V_protocol_max ORDER-STATISTIC FORMULA (N=80, OVERSAMPLE=2x)")
    N_arbs = 80
    ovs = 2.0
    hyps = [("Low ($400, s=1.0)", 400.0, 1.0),
            ("Mid ($600, s=1.0)", 600.0, 1.0),
            ("Heavy-tail ($800, s=1.4)", 800.0, 1.4),
            ("Pro ($2000, s=1.1)", 2000.0, 1.1)]
    for hname, med, sig in hyps:
        vals = []
        for tname, k1, Q1, k2 in tiers:
            q2 = int(ovs * k2)
            # q-th largest in sample of N has upper rank q / (N+1) -> lower quantile 1 - q/(N+1)
            p_low = 1.0 - (q2 / (N_arbs + 1.0))
            s_q2 = med * math.exp(sig * normal_ppf(p_low))
            s_eff = min(S_arb_max, s_q2)
            m1, m2 = (k1 + 1) // 2, (k2 + 1) // 2
            v_liq_cap = (s_q2 / beta) if s_q2 < S_arb_max else float("inf")
            v_dyn = min(8.75 * S_arb_max, (m1 + m2 * lam_r2) * s_eff, v_liq_cap)
            vals.append(f"{tname} (q2={q2}, S_q2=${s_q2:6.0f}): V_dyn=${v_dyn:5,.0f}")
        print(f"  {hname:27s} -> " + " | ".join(vals))

    print("\n  Check beta_arb condition below S_arb_max: direct-bribery safety (m1+m2*lam)*beta >= 1")
    for b in [0.10, 0.15, 0.20, 0.25]:
        print(f"    beta={b:.2f}: T1={5.25*b:.3f}V, T2={7.00*b:.3f}V, T3={8.75*b:.3f}V "
              f"({'ALL >= 1.0V (SAFE)' if 5.25*b >= 1.0 else 'BELOW 1.0V IN TIER 1 (NEEDS MIN CAP)!'})")


if __name__ == "__main__":
    main()
