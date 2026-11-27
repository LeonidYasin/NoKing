"""
NoKing Protocol Verification v0.2 — V3: Game-Theoretic Analysis (D2, D3, D4, D5)
Computes:
  1. Scale-invariant pro-seller bias p* under proportional stake S_arb = beta_arb * V
  2. Direct bribery threshold beta_crit = 1 / (m1 + m2 * lambda) & locked arbitrator capital
  3. p + epsilon conditional bribe capital vs realized cost
  4. D3 Compromise manipulation EV vs quorum sabotage cost
"""

import math


def main():
    lam = 0.25
    k1, k2 = 5, 17
    m1, m2 = k1 // 2 + 1, k2 // 2 + 1  # 3, 9

    print("=== 1. ASYMMETRIC FOCAL THRESHOLD p* UNDER D4 PROPORTIONAL STAKE ===")
    for V in [100, 1000, 10000]:
        D_disp = 0.05 * V
        R_arb = 0.001 * V  # 0.3% / 3
        for beta in [0.05, 0.10, 0.20, 0.30]:
            S_arb = beta * V
            num = R_arb + lam * S_arb
            den = 2 * (R_arb + lam * S_arb) + D_disp / m1
            p_star = num / den
            print(f"V={V:5d}, beta={beta:.2f}, S_arb={S_arb:7.1f} => p* = {p_star:.4f} (bias = {0.5 - p_star:+.4f})")

    print("\n=== 2. DIRECT BRIBERY THRESHOLD & TOTAL ARBITRATOR CAPITAL LOCKED ===")
    beta_crit = 1.0 / (m1 + m2 * lam)
    print(f"Critical proportional stake ratio beta_crit (k={k1}, k'={k2}, lam={lam}): {beta_crit:.4f} ({beta_crit*100:.2f}% of V per arb)")
    for beta in [0.05, 0.10, 0.15, 0.20, 0.25, 0.30]:
        cost_ratio = (m1 + m2 * lam) * beta
        cap_r1 = k1 * beta
        cap_r2 = k2 * beta
        cap_tot = (k1 + k2) * beta
        profitable = "NO (C_direct > V for all V)" if cost_ratio > 1.0 else f"YES (net profit {(1-cost_ratio)*100:.1f}% of V)"
        print(f"beta={beta:.2f}: C_direct/V={cost_ratio:.3f}, R1_locked={cap_r1:.2f}V, R2_locked={cap_r2:.2f}V, "
              f"Total_locked={cap_tot:.2f}V | Bribe_profitable? {profitable}")

    print("\n=== 3. p + epsilon ATTACK: CAPITAL LOCKUP VS REALIZED COST ===")
    for V in [1000, 10000]:
        R_arb = 0.001 * V
        for beta in [0.10, 0.20]:
            S_arb = beta * V
            # Attacker must cover R1 full stake loss (if appeal overturns) + R2 minority slash + R_arb
            dark_dao_cap = k1 * (R_arb + S_arb + 1.0) + k2 * (R_arb + lam * S_arb + 1.0)
            realized_cost = (m1 + m2) * 1.0  # epsilon = $1 per bribed seat if attack succeeds
            print(f"V={V:5d}, beta={beta:.2f}: DarkDAO_escrow=${dark_dao_cap:8.1f} ({dark_dao_cap/V:.2f}x V), "
                  f"Realized_cost_on_success≈${realized_cost:.0f}")

    print("\n=== 4. D3 COMPROMISE MANIPULATION INCENTIVES VS SABOTAGE COST ===")
    # Dishonest buyer keeps goods worth V and stalls/sabotages into D3 Compromise:
    # Honest FOR_A payoff = V_goods - V - 0.05V = -0.05V (loss of 1.05V relative to keeping V + 0.05V)
    # D3 Compromise payoff = V_goods + 0 (V and D_disp refunded!) -> gain = +1.05V!
    # Guilty seller facing FOR_B loses 0.10V; under D3 Compromise gets 0.10V back -> gain = +0.10V!
    for Q_arb in [3, 4, 5]:
        sabotage_seats_r1 = k1 - Q_arb + 1  # number of non-reveals to break quorum Q_arb
        for beta in [0.05, 0.10, 0.20]:
            # Cost to bribe `sabotage_seats` to NOT reveal (compensating missed reveal slash lam*S_arb)
            # Note: under D5, redraws can occur up to T_dispute_max; assume r_attempts redraws
            for attempts in [1, 2]:
                sab_cost_ratio = attempts * sabotage_seats_r1 * lam * beta
                buyer_net_gain = 1.05 - sab_cost_ratio
                seller_net_gain = 0.10 - sab_cost_ratio
                print(f"k={k1}, Q_arb={Q_arb} (break={sabotage_seats_r1} seats), beta={beta:.2f}, redraws={attempts}: "
                      f"Sabotage_cost={sab_cost_ratio:.3f}V | Buyer_EV={buyer_net_gain:+.3f}V | Seller_EV={seller_net_gain:+.3f}V")

    print("\n=== 5. ARBITRATOR CAPITAL CONSTRAINT FOR LARGE DEALS (V=$10,000-$50,000) ===")
    for V in [1000, 10000, 50000]:
        for beta in [0.10, 0.20]:
            s_each = beta * V
            pool_min_r2 = 51 * s_each  # 3 * 17 arbitrators must exist and hold liquid capital
            print(f"V=${V:5d}, beta={beta:.2f} => S_arb=${s_each:7.0f}/arb | "
                  f"R1_locked=${5*s_each:7.0f}, R2_locked=${17*s_each:8.0f}, Eligible_pool_liquidity(51 arbs)=${pool_min_r2:9.0f}")


if __name__ == "__main__":
    main()
