#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest h5py numpy scipy networkx

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/generate_data.py
import h5py
import numpy as np

np.random.seed(42)
with h5py.File('/home/user/sim_data.h5', 'w') as f:
    for i in range(200):
        magnitude = 10 ** np.random.uniform(-5, 5)
        t = np.linspace(0, 10, 1000)
        signal = magnitude * np.sin(2 * np.pi * 1.5 * t) + np.random.normal(0, magnitude * 0.1, 1000)
        f.create_dataset(f'node_{i}', data=signal)
EOF
    python3 /home/user/generate_data.py

    cat << 'EOF' > /home/user/analyze.py
import h5py
import numpy as np
from scipy.optimize import minimize
import networkx as nx

def evaluate_threshold(thresh, file_path):
    thresh_val = thresh[0]
    with h5py.File(file_path, 'r') as f:
        G = nx.Graph()
        # BUG: set() iteration order is non-deterministic across runs due to PYTHONHASHSEED
        nodes = set(f.keys())

        for n in nodes:
            G.add_node(n, signal=f[n][:])

        total_energy = 0.0
        # Floating point addition order changes based on the unordered set iteration
        for n in nodes:
            sig = G.nodes[n]['signal']
            sig_masked = np.where(np.abs(sig) > thresh_val, sig, 0)
            sp = np.fft.fft(sig_masked)
            energy = np.sum(np.abs(sp)**2)
            total_energy += energy

    return -total_energy

if __name__ == "__main__":
    res = minimize(evaluate_threshold, x0=[0.5], args=('/home/user/sim_data.h5',), method='Nelder-Mead', options={'xatol': 1e-8, 'fatol': 1e-8})
    print(f"Optimized Threshold: {res.x[0]:.6f}")
EOF

    rm /home/user/generate_data.py
    chmod -R 777 /home/user
