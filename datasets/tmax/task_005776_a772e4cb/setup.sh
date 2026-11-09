#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data
    mkdir -p /home/user/results

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

# Set deterministic seed
np.random.seed(42)

# 1. Generate and save weights (4x20)
weights = np.random.randn(4, 20)
np.savetxt("/home/user/data/weights.csv", weights.flatten(), delimiter=",", fmt="%.8f")

# 2. Generate and save sequences
bases = ['A', 'C', 'G', 'T']
base_map = {'A': 0, 'C': 1, 'G': 2, 'T': 3}
seqs = []
for _ in range(100):
    seq = "".join(np.random.choice(bases, 20))
    seqs.append(seq)

with open("/home/user/data/sequences.txt", "w") as f:
    f.write("\n".join(seqs) + "\n")

# 3. Calculate stable sums to generate the gold standard
X = []
for seq in seqs:
    w = [weights[base_map[b], i] for i, b in enumerate(seq)]
    w.sort()
    X.append(sum(w))
X = np.array(X)

# Generate gold standard with a specific slope and intercept + noise
Y = 2.5 * X + 1.2 + np.random.randn(100) * 0.1
np.savetxt("/home/user/data/gold_standard.txt", Y, delimiter=",", fmt="%.8f")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
