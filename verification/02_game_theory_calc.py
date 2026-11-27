"""
NoKing Protocol Verification — T2: Game-Theoretic & Numerical Bounds Analysis
Computes exact Nash threshold asymmetries, bribery costs (p+epsilon & direct),
hypergeometric Sybil/collusion capture probabilities, and rational ignorance bounds.
"""

import math
from dataclasses import dataclass
from typing import List, Tuple


def comb(n: int, k: int) -> int:
    if k < 0 or k > n:
        return 0
    return math.comb(n, k)


def hypergeom_capture_prob(N: int, M: int, k: int) -> float:
    """Exact probability that >= (k+1)//2 out of k drawn without replacement are from M attackers."""
    need = k // 2 + 1
    total = comb(N, k)
    if total == 0:
        return 0.0
    prob = 0.0
    for j in range(need, min(k, M) + 1):
        prob += comb(M, j) * comb(N - M, k - j) / total
    return prob


def pro_seller_threshold(R_arb: float, S_arb: float, lam: float, D_dispute: float, m_A: int) -> float:
    """
    Threshold belief p_i = Pr(majority votes FOR_A) above which voting FOR_A beats FOR_B.
    In NoKing Sec 5.5:
      FOR_A pays R_arb + D_dispute / m_A (if majority) or -lam * S_arb (if minority).
      FOR_B pays R_arb (if majority) or -lam * S_arb (if minority) [D_dispute refunded to B].
    """
    num = R_arb + lam * S_arb
    den = 2 * R_arb + 2 * lam * S_arb + (D_dispute / m_A)
    return num / den


def main():
    print("=== 1. ASYMMETRIC FOCAL THRESHOLD (Sec 5.5 FOR_A vs FOR_B payout asymmetry) ===")
    lam = 0.25
    for V in [100, 1000, 10000]:
        D_dispute = 0.05 * V
        R_arb = 0.003 * V / 3.0  # 30% of 1% protocol fee split among 3 majority arbs
        for S_arb in [10.0, 50.0, 100.0]:
            p_star = pro_seller_threshold(R_arb, S_arb, lam, D_dispute, m_A=3)
            print(f"V={V:5d} USDC, D_disp={D_dispute:6.1f}, R_arb={R_arb:5.2f}, S_arb={S_arb:5.1f} => p* = {p_star:.4f} (bias = {0.5 - p_star:+.4f})")

    print("\n=== 2. DIRECT BRIBERY VS DEAL VALUE (Round 1 k + Appeal k'=3k+2) ===")
    # Corollary 5.6 claims cost exceeds max recoverable value for "any realistic dispute amount"
    for k in [5, 7]:
        k_app = 3 * k + 2
        m1 = k // 2 + 1
        m2 = k_app // 2 + 1
        for S_arb in [10, 50, 100, 500]:
            # Direct bribe: pay m1 arbitrators in R1 at least (lam*S_arb + R_arb) or S_arb if appeal could overturn,
            # plus m2 arbitrators in R2 to guarantee R2 upholds R1 (so R1 is NOT overturned!).
            # Minimum coordinated direct bribe (if R2 is also bribed so R1 keeps stake, cost per bribed arb = eps -> 0,
            # or conservatively compensating full stake at risk S_arb + opp cost):
            # Conservative upper bound on minimum bribe needed per arbitrator if uncoordinated:
            eps = 1.0
            cost_coordinated = (m1 + m2) * eps  # pure p+eps / coordinated equilibrium switch
            cost_stake_backed = m1 * (S_arb + eps) + m2 * (lam * S_arb + eps)
            print(f"k={k}, k'={k_app}, S_arb={S_arb:3d} => min_bribe_slots={m1}+{m2}={m1+m2}, "
                  f"p+eps_realized≈${cost_coordinated:.0f}, conservative_direct_bribe=${cost_stake_backed:.0f} "
                  f"(profitable for V > ${cost_stake_backed/0.95:.0f})")

    print("\n=== 3. HYPERGEOMETRIC SYBIL/COLLUSION CAPTURE PROBABILITY ===")
    for k in [5, 7, 17]:
        print(f"\n-- Panel size k = {k} (majority >= {k//2 + 1}) --")
        for N in [15, 30, 51, 100, 300]:
            if N < k:
                continue
            row = [f"N={N:3d}"]
            for f in [0.10, 0.20, 0.30, 0.40, 0.50]:
                M = round(N * f)
                p = hypergeom_capture_prob(N, M, k)
                row.append(f"f={f:.0%}(M={M}): {p:.4f}")
            print(" | ".join(row))

    print("\n=== 4. RATIONAL IGNORANCE BOUND (R_arb + lam*S_arb >= c_e / min(q, 1-q)) ===")
    for c_e in [2.0, 5.0, 10.0]:
        for q in [0.5, 0.7, 0.8, 0.9]:
            req = c_e / min(q, 1.0 - q)
            min_S_if_R1 = max(0.0, (req - 1.0) / lam)
            print(f"c_e=${c_e:4.1f}, prior_q={q:.1f} => min (R_arb + 0.25*S_arb) >= ${req:6.2f} "
                  f"(if R_arb=$1, need S_arb >= ${min_S_if_R1:6.1f})")

    print("\n=== 5. SYBIL ARBITRATOR COST (Sec 2.1 + 5.2 + 9) ===")
    D_reg = 10.0
    n_deals = 10
    v_min = 0.01  # No minimum deal size in spec!
    gas_per_tx = 0.01
    sunk_per_sybil = n_deals * (0.01 * v_min + 3 * gas_per_tx)  # create/accept/start/submit/confirm ~3-5 txs
    print(f"Per Sybil (v_min=${v_min}, 10 deals): locked capital=${D_reg:.2f}, sunk fee+gas≈${sunk_per_sybil:.2f}")
    for N_honest in [15, 30, 50]:
        M_sybils = N_honest  # 50% of pool
        print(f"Pool N_honest={N_honest} + {M_sybils} Sybils (f=50%): "
              f"locked=${M_sybils*D_reg:.0f}, sunk≈${M_sybils*sunk_per_sybil:.1f}, "
              f"P(capture k=5)={hypergeom_capture_prob(N_honest+M_sybils, M_sybils, 5):.4f}, "
              f"P(capture k'=17)={hypergeom_capture_prob(N_honest+M_sybils, M_sybils, 17):.4f}")


if __name__ == "__main__":
    main()
