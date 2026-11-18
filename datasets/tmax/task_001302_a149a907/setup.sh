#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-numpy python3-setuptools
    pip3 install pytest

    mkdir -p /app/GraphSpecSim-1.0.0/graphspecsim

    cat << 'EOF' > /app/GraphSpecSim-1.0.0/setup.py
from setuptools import setup, find_packages
setup(name='GraphSpecSim', version='1.0.0', packages=find_packages(), install_requires=['numpy'])
EOF

    cat << 'EOF' > /app/GraphSpecSim-1.0.0/graphspecsim/__init__.py
from .simulator import simulate
EOF

    cat << 'EOF' > /app/GraphSpecSim-1.0.0/graphspecsim/simulator.py
import numpy as np

def simulate(adj_matrix, seed, steps):
    np.random.seed(seed)
    N = adj_matrix.shape[0]
    state = np.random.uniform(-1, 1, N)
    output = np.zeros(steps)
    for i in range(steps):
        # PERTURBATION HERE: np.random.norm instead of normal
        noise = np.random.norm(0, 1, N)
        state = adj_matrix.dot(state) / (N + 1) + noise
        output[i] = np.sum(state)
    return output
EOF

    cat << 'EOF' > /app/oracle_pipeline.py
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
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
