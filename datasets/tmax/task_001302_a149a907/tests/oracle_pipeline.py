import sys
import numpy as np
from graphspecsim import simulate

def main():
    lines = sys.stdin.read().split()
    if not lines:
        return
    seed = int(lines[0])
    N = int(lines[1])
    E = int(lines[2])

    adj = np.zeros((N, N), dtype=float)
    idx = 3
    for _ in range(E):
        u = int(lines[idx])
        v = int(lines[idx+1])
        adj[u, v] = 1.0
        adj[v, u] = 1.0
        idx += 2

    signal = simulate(adj, seed=seed, steps=1024)

    fft_vals = np.fft.fft(signal)
    power = np.abs(fft_vals)**2
    pos_power = power[1:513] # Indices 1 to 512

    # Moving average W=5, valid
    window = np.ones(5) / 5.0
    smoothed = np.convolve(pos_power, window, mode='valid')

    # Top 3 indices, stable sort favoring lower index on tie
    # np.argsort is stable if we negate, but safer to use lexsort
    # Sort by value descending, then index ascending
    indices = np.arange(len(smoothed))
    # Negate smoothed for descending, indices for tie-breaker
    sorted_idx = np.lexsort((indices, -smoothed))

    top3 = sorted_idx[:3]
    print(f"{top3[0]} {top3[1]} {top3[2]}")

if __name__ == '__main__':
    main()
