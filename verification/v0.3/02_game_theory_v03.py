"""
NoKing Protocol Verification v0.3 — W3: Game-Theoretic Analysis (E1, E2, E3, Symmetrization)
Computes:
  1. W3.1: E1 50/50 split incentives for all 4 participant types vs sabotage cost
  2. W3.2: Direct bribery limit V_safe_max under S_arb_max and deal tiers
  3. W3.3: Focal threshold p* before vs after reward symmetrization
"""


def main():
    lam = 0.25

    print("=== W3.1: E1 50/50 SPLIT INCENTIVES FOR ALL 4 PARTICIPANT TYPES ===")
    # Parameters: alpha = 0.10 (seller_deposit), sigma = 0.50, delta = 0.05 (D_dispute), phi = 0.01
    # In E1 fallback: amount split 50/50 (0.50V each); both lose D_dispute (0.05V from B, 0.05V from A's seller_deposit).
    # Net change (Fallback - Honest Outcome) as fraction of V:
    print("Type 1 (Honest Seller, w=A):   Honest = +1.090V (0.99V + 0.10V dep) | E1 = +0.550V (0.50V + 0.05V dep) => Gain = -0.540V")
    print("Type 2 (Honest Buyer, w=B):    Honest = +1.100V (V + 0.05V pen + 0.05V D) | E1 = +0.450V (0.50V - 0.05V D) => Gain = -0.650V")
    print("Type 3 (Dishonest Buyer, w=A): Honest = -1.050V (keeps goods) | E1 = -0.550V (keeps goods + 0.50V refund) => Gross Stalling Gain = +0.500V")
    print("Type 4 (Dishonest Seller,w=B): Honest =  0.000V (loses 0.10V dep) | E1 = +0.550V (0.50V + 0.05V dep) => Gross Stalling Gain = +0.550V")
    print("  (Even if seller forfeits 100% of seller_deposit in E1, Dishonest Seller still gains +0.500V from 50/50 split!)")

    print("\n--- Sabotage Cost Thresholds for E1 Round 1 (Cat + Parent Pool Escalation) ---")
    k = 5
    for Q_arb in [3, 4]:
        s_break = k - Q_arb + 1
        for beta in [0.10, 0.20]:
            for lam_unrev in [0.25, 0.50, 0.75, 1.00]:
                # 2 attempts in category + 2 attempts in parent = 4 * s_break seat-sabotages
                # vs 1 attempt in category only (if parent fails passively)
                c_4att = 4 * s_break * lam_unrev * beta
                c_2att = 2 * s_break * lam_unrev * beta
                print(f"Q={Q_arb}(break={s_break}), beta={beta:.2f}, lam_unrev={lam_unrev:.2f}: "
                      f"C_sab(2 att)={c_2att:.3f}V | C_sab(4 att w/ esc)={c_4att:.3f}V | "
                      f"Deters Buyer(+0.50V)? {c_4att>=0.50} | Deters Seller(+0.55V)? {c_4att>=0.55}")

    print("\n=== W3.2: DIRECT BRIBERY BOUND V_safe_max UNDER S_arb_max & TIERS (E2) ===")
    tiers = [
        ("Tier 1 (k=5, k'=17)",  5, 17),
        ("Tier 2 (k=7, k'=23)",  7, 23),
        ("Tier 3 (k=9, k'=29)",  9, 29),
    ]
    for name, k1, k2 in tiers:
        m1 = k1 // 2 + 1
        m2 = k2 // 2 + 1
        mult = m1 + m2 * lam
        for S_max in [250, 500, 1000, 2500]:
            v_safe_max = mult * S_max
            r1_cap = k1 * S_max
            r2_cap = k2 * S_max
            print(f"{name}, S_max=${S_max:4d} => m1+m2*lam={mult:5.2f} => V_safe_max=${v_safe_max:8.1f} "
                  f"(R1 lock=${r1_cap:5d}, R2 lock=${r2_cap:6d})")

    print("\n=== W3.3: FOCAL THRESHOLD p* BEFORE VS AFTER REWARD SYMMETRIZATION ===")
    V = 1000.0
    D_disp = 0.05 * V
    R_arb = 1.0  # $1 base
    m_maj = 3
    for beta in [0.05, 0.10, 0.20]:
        S_arb = beta * V
        p_before = (R_arb + lam * S_arb) / (2 * (R_arb + lam * S_arb) + D_disp / m_maj)
        # After symmetrization: winner's side never pays D_disp, loser's side ALWAYS pays D_disp to arbs
        # Payoff FOR_A = R_arb + D_disp/m_maj if maj=A else -lam*S_arb
        # Payoff FOR_B = R_arb + D_disp/m_maj if maj=B else -lam*S_arb
        p_after = (R_arb + D_disp / m_maj + lam * S_arb) / (2 * (R_arb + D_disp / m_maj + lam * S_arb))
        print(f"V=${V:.0f}, beta={beta:.2f}, S_arb=${S_arb:5.0f}: p*_before={p_before:.4f} (bias={0.5-p_before:+.4f}) "
              f"-> p*_after={p_after:.4f} (bias={0.5-p_after:+.4f})")


if __name__ == "__main__":
    main()
