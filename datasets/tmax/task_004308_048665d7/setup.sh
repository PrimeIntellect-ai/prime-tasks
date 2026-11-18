#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user/spectro_graphs
    cd /home/user/spectro_graphs

    cat << 'EOF' > setup.py
import json
import numpy as np
import csv
from scipy.sparse.csgraph import shortest_path

np.random.seed(42)

def generate_connected_graph(n):
    adj = np.zeros((n, n))
    # Create a spanning tree to ensure connectivity
    for i in range(1, n):
        j = np.random.randint(0, i)
        adj[i, j] = 1
        adj[j, i] = 1
    # Add some random edges
    for _ in range(n):
        i, j = np.random.randint(0, n, 2)
        if i != j:
            adj[i, j] = 1
            adj[j, i] = 1
    return adj.tolist()

molecules = []
stable_ids = []

for i in range(15):
    mol_id = f"mol_{i}"
    n_nodes = np.random.randint(10, 25)
    adj = generate_connected_graph(n_nodes)

    # Generate signal
    t = np.linspace(0, 10, 1024)
    freq = np.random.uniform(0.5, 3.0)
    clean_signal = np.sin(2 * np.pi * freq * t) * np.random.uniform(5, 15)
    noise = np.random.normal(0, 5, 1024)
    raw_signal = (clean_signal + noise).tolist()

    molecules.append({
        "id": mol_id,
        "adjacency_matrix": adj,
        "raw_signal": raw_signal
    })

    # 10 out of 15 are stable
    if i % 3 != 0:
        stable_ids.append(mol_id)

with open('molecules.json', 'w') as f:
    json.dump(molecules, f)

with open('reference.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id'])
    for sid in stable_ids:
        writer.writerow([sid])

# Ground truth calculation
W_list = []
P_list = []

for mol in molecules:
    if mol['id'] not in stable_ids:
        continue

    # Wiener Index
    dist_matrix = shortest_path(csgraph=np.array(mol['adjacency_matrix']), directed=False, unweighted=True)
    W = np.sum(dist_matrix) / 2
    W_list.append(W)

    # Signal processing
    sig = np.array(mol['raw_signal'])
    fft_vals = np.fft.fft(sig)
    fft_vals[20:1004] = 0
    denoised = np.real(np.fft.ifft(fft_vals))
    P = np.max(denoised)
    P_list.append(P)

X = np.column_stack((np.ones(len(W_list)), W_list))
y = np.array(P_list)

cond = np.linalg.cond(X)
beta = np.linalg.lstsq(X, y, rcond=None)[0][1]

with open('.ground_truth.json', 'w') as f:
    json.dump({"beta": round(beta, 4), "condition_number": round(cond, 4)}, f)

EOF

    python3 setup.py
    rm setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
