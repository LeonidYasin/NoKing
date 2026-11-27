"""
NoKing Protocol v0.4 — Game Theory & Mechanism Design Analysis (X3)
Computes exact analytical metrics for:
  - X3.1: F1 3-level escalation incentives for 4 party types + arbitrator reward-farming
  - X3.2: Tier bribery caps V_protocol_max with S_arb_max and OVERSAMPLE=2x (direct vs p+epsilon)
  - X3.3: F3 sealed-tally partial redraw vs leaked intermediate tally
"""

import math


def print_header(title):
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


def main():
    print_header("X3.1: F1 ESCALATION INCENTIVES (4 PARTY TYPES + ARBITRATOR FARMING)")
    alpha = 0.10
    delta = 0.05
    phi = 0.01
    sigma = 0.50

    # Delay cost: opportunity cost r_apr over deltaT days
    r_apr = 0.08  # 8% annualized capital cost
    days_delay = 6.0  # 3 levels * 2 days
    delay_cost_rate = r_apr * (days_delay / 365.0)

    honest_seller = 1.0 - phi + alpha
    split_seller = 0.50 + alpha - delta - delay_cost_rate
    honest_buyer = 1.0 + sigma * alpha + delta
    split_buyer = 0.50 - delta - delay_cost_rate
    dish_buyer_honest = -delta  # net vs goods value 1.0: goods(1) - price(1) - disp(0.05) = -0.05
    dish_buyer_split = 0.50 - 1.0 - delta + 1.0 - delay_cost_rate  # keeps goods(1) + 0.50V refund - V - 0.05V
    dish_seller_honest = 0.0
    dish_seller_split = 0.50 + alpha - delta - delay_cost_rate

    print(f"Delay cost over {days_delay}d at {r_apr*100:.1f}% APR: {delay_cost_rate*100:.4f}% V")
    print(f"1. Honest Seller   (omega=A): honest={honest_seller:+.4f}V, F1_split={split_seller:+.4f}V, gain={split_seller-honest_seller:+.4f}V")
    print(f"2. Honest Buyer    (omega=B): honest={honest_buyer:+.4f}V, F1_split={split_buyer:+.4f}V, gain={split_buyer-honest_buyer:+.4f}V")
    print(f"3. Dishonest Buyer (omega=A): honest={dish_buyer_honest:+.4f}V, F1_split={dish_buyer_split:+.4f}V, gross_gain={dish_buyer_split-dish_buyer_honest:+.4f}V")
    print(f"4. Dishonest Seller(omega=B): honest={dish_seller_honest:+.4f}V, F1_split={dish_seller_split:+.4f}V, gross_gain={dish_seller_split-dish_seller_honest:+.4f}V")

    # Active sabotage cost across L=3 escalation levels, r=2 attempts/level = 6 quorum breaks
    beta = 0.10
    lam_unrev = 0.50
    S_arb_max = 1000.0
    for name, k, Q, L, r in [("Tier 1 (3 levels x 2 att = 6)", 5, 3, 3, 2),
                             ("Tier 2 (3 levels x 2 att = 6)", 7, 4, 3, 2),
                             ("Tier 3 (3 levels x 2 att = 6)", 9, 5, 3, 2)]:
        seats_to_break = k - Q + 1
        N_att = L * r
        c_sab_slope = N_att * seats_to_break * lam_unrev * beta
        c_sab_max = N_att * seats_to_break * lam_unrev * S_arb_max
        v_sab_limit = c_sab_max / (dish_seller_split - dish_seller_honest)
        print(f"  {name}: break/att={seats_to_break}, C_sab/V(uncapped)={c_sab_slope:.2f}V, "
              f"C_sab_max=${c_sab_max:,.0f}, deters +0.55V up to V=${v_sab_limit:,.0f}")

    # Arbitrator Reward-Farming boundary (X3.1a)
    print("\n--- X3.1a Arbitrator Reward-Farming Condition ---")
    for V in [100, 1000, 5000]:
        S_arb = min(max(beta * V, 10.0), S_arb_max)
        for N_pool in [20, 40, 80]:
            k = 5
            q_re = k / N_pool
            max_dR_unrev = (lam_unrev * S_arb) / q_re
            print(f"  V=${V:4d}, S_arb=${S_arb:5.0f}, N={N_pool:2d}: q_redraw={q_re:.3f}, "
                  f"max safe step DeltaR (if unrev penalty applies) = ${max_dR_unrev:7.2f}; "
                  f"if decline is UNSLASHED & pool stalls: safe DeltaR = $0.00!")

    print_header("X3.2: DIRECT BRIBERY & p+eps WITH S_arb_max AND OVERSAMPLE=2x")
    lam = 0.25
    eps = 1.0
    tiers = [("Tier 1", 5, 17, 2500), ("Tier 2", 7, 23, 5000), ("Tier 3", 9, 29, 8750)]
    for S_max in [500.0, 1000.0]:
        print(f"\nS_arb_max = ${S_max:,.0f}:")
        for tname, k, k2, t_cap in tiers:
            m1 = (k + 1) // 2
            m2 = (k2 + 1) // 2
            mult = m1 + m2 * lam
            v_safe = mult * S_max
            dark_dao_escrow = k * S_max + k2 * lam * S_max
            p_eps_cost = (m1 + m2) * eps
            print(f"  {tname:6s} (k={k},k'={k2:2d}, 2x minPool={2*k:2d}/{2*k2:2d}): "
                  f"m1+m2*lam={mult:5.2f}, V_safe_max=${v_safe:8,.0f}, "
                  f"DarkDAO_escrow=${dark_dao_escrow:9,.0f}, p+eps_actual~=${p_eps_cost:.0f}")

    print_header("X3.3: F3 SEALED TALLY VS LEAKED REDRAW BRIBERY COST")
    # Suppose k=5, Q=3. Attacker wants FOR_B when true is A. 2 seats unrevealed, 3 revealed.
    # Under leaked v0.3: if vA=2, vB=1, attacker knows he needs 2 of 2 replacement seats? No, if vA=1,vB=2?
    # Wait: if vA=1, vB=1, unrev=3? Wait Q=3 means valid_votes < 3 triggers redraw, so at most 2 valid votes!
    # Cases with valid < Q=3: (2A,0B), (1A,1B), (0A,2B), (1A,0B), (0A,1B), (0A,0B).
    # If leaked (2A,0B): 3 seats missing; winning FOR_B requires flipping impossible?Wait: to reach FOR_B total needs vB >= 3,
    # so out of 3 missing seats must buy ALL 3 FOR_B (to get 3B vs 2A)! Cost = 3 * bribe.
    # If leaked (0A,2B): attacker only needs 1 of 3 seats! Cost = 1 * bribe (saves 67%!).
    # Under F3 (sealed tally): attacker does not know if prior was (2A,0B) or (1A,1B) or (0A,2B);
    # to guarantee FOR_B across unknown valid < 3 worst-case (2A,0B), must bribe ALL r = k - valid_commits seats!
    for valid_c in [0, 1, 2]:
        missing = 5 - valid_c
        # If worst-case valid votes were all A, to guarantee vB > vA attacker needs missing seats -> max(ceil((5+1)/2), valid_c + 1)
        need_sealed = min(missing, valid_c + 1 if valid_c + 1 > (valid_c + missing) / 2 else missing)
        # Specifically: vA <= valid_c, total votes = 5, so vB_new >= valid_c + 1 -> guarantee requires vB_new = valid_c + 1?
        # Wait if valid_c = 2: 2A -> need 3 new B out of 3 missing! If valid_c = 1: 1A -> need 2 new B (since 4 missing: wait 2 vs 1+2=3A!).
        # Exact worst-case FOR_B guarantee: vB_new > vA_old + (missing - vB_new) => 2*vB_new > 5 => vB_new >= 3 ALWAYS!
        print(f"  Prior valid={valid_c}, missing={missing}: worst-case guarantee under F3 needs vB_new >= 3 (cost 3 bribes) "
              f"vs under leaked v0.3 (0A,{valid_c}B) only {3-valid_c} bribes!")


if __name__ == "__main__":
    main()
