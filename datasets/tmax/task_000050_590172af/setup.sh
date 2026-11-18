#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy h5py networkx

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import h5py
import numpy as np
import networkx as nx

np.random.seed(42)

# Generate 1000 nodes, 1024 samples each
signals = np.random.randn(1000, 1024)

# Create a graph with a clear largest connected component
G = nx.erdos_renyi_graph(1000, 0.002, seed=42)
edges = np.array(G.edges())

with h5py.File('/home/user/data.h5', 'w') as f:
    f.create_dataset('signals', data=signals)
    f.create_dataset('edges', data=edges)

EOF

    python3 /home/user/generate_data.py

    cat << 'EOF' > /home/user/aggregate_power.py
import h5py
import numpy as np
import networkx as nx
from multiprocessing.dummy import Pool
import time
import random

def get_peak_power(signal):
    time.sleep(random.uniform(0, 0.001)) # Exacerbate race conditions for floating point sum order
    fft_vals = np.fft.rfft(signal)
    return np.max(np.abs(fft_vals))

def main():
    with h5py.File('/home/user/data.h5', 'r') as f:
        signals = f['signals'][:]
        edges = f['edges'][:]

    G = nx.Graph()
    G.add_edges_from(edges)
    largest_cc = max(nx.connected_components(G), key=len)

    # Bug: Unordered set iteration and unordered imap
    cc_signals = [signals[i] for i in largest_cc]

    total_power = 0.0
    with Pool(4) as pool:
        for power in pool.imap_unordered(get_peak_power, cc_signals):
            total_power += power

    print(f"{total_power:.12f}")

if __name__ == '__main__':
    main()
EOF

    chmod -R 777 /home/user
