#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo libopenblas-dev pkg-config binutils
    pip3 install pytest numpy pandas pyinstaller

    mkdir -p /app/dataset

    # Create the oracle script
    cat << 'EOF' > /tmp/oracle.py
import sys
import numpy as np

def main():
    if len(sys.argv) != 2:
        return
    edges = []
    with open(sys.argv[1], 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                edges.append((int(parts[0]), int(parts[1])))
    if not edges:
        print("0.0,0.0,0.0,0.0,0.0")
        return
    max_node = max(max(u, v) for u, v in edges)
    n = max_node + 1
    A = np.zeros((n, n), dtype=float)
    for u, v in edges:
        A[u, v] = 1.0
        A[v, u] = 1.0
    s = np.linalg.svd(A, compute_uv=False)
    s = np.sort(s)[::-1]
    features = list(s[:5])
    while len(features) < 5:
        features.append(0.0)
    print(",".join(f"{x:.6f}" for x in features))

if __name__ == "__main__":
    main()
EOF

    # Compile to a binary
    python3 -m PyInstaller --onefile /tmp/oracle.py --distpath /app --name oracle_extractor
    strip /app/oracle_extractor
    rm -rf /tmp/oracle* build oracle_extractor.spec

    # Generate dataset
    cat << 'EOF' > /tmp/gen.py
import os
import random

os.makedirs('/app/dataset', exist_ok=True)
random.seed(42)
for i in range(500):
    num_nodes = random.randint(3, 20)
    num_edges = random.randint(num_nodes - 1, num_nodes * 2)
    with open(f'/app/dataset/graph_{i}.txt', 'w') as f:
        for _ in range(num_edges):
            u = random.randint(0, num_nodes - 1)
            v = random.randint(0, num_nodes - 1)
            if u != v:
                f.write(f"{u} {v}\n")
EOF
    python3 /tmp/gen.py
    rm /tmp/gen.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
