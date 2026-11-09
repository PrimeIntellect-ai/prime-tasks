import sys
import numpy as np
from scipy.integrate import solve_ivp
import seq_affinity

def solve_ode(k):
    def system(t, y):
        A, B = y
        dA = k * B - 0.1 * A**2
        dB = -k * B + 0.1 * A
        return [dA, dB]
    sol = solve_ivp(system, [0, 10], [0.0, 1.0], rtol=1e-6, atol=1e-8)
    return sol.y[0, -1]

def main():
    with open(sys.argv[1], 'r') as f:
        seqs = [line.strip() for line in f if line.strip()]

    A_10_vals = []
    for seq in seqs:
        k = seq_affinity.calculate_k(seq)
        A_10 = solve_ode(k)
        A_10_vals.append(A_10)

    A_10_vals = np.array(A_10_vals)
    mean_val = np.mean(A_10_vals)

    np.random.seed(42)
    n_bootstraps = 10000
    bootstrapped_means = []
    for _ in range(n_bootstraps):
        sample = np.random.choice(A_10_vals, size=len(A_10_vals), replace=True)
        bootstrapped_means.append(np.mean(sample))

    ci_lower = np.percentile(bootstrapped_means, 2.5)
    ci_upper = np.percentile(bootstrapped_means, 97.5)

    print(f"{mean_val:.4f},{ci_lower:.4f},{ci_upper:.4f}")

if __name__ == '__main__':
    main()
