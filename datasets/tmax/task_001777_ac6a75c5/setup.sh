#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ libeigen3-dev python3-numpy
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /tmp/generate_data.py
import random

random.seed(42)
primer = "ATGCGATCG"
bases = ['A', 'C', 'G', 'T']

with open('/home/user/binding_data.txt', 'w') as f:
    for i in range(500):
        # 90% have the correct primer
        if random.random() < 0.9:
            seq = primer + "".join(random.choices(bases, k=20))
        else:
            seq = "".join(random.choices(bases, k=29))

        score = random.uniform(0.0, 10.0)
        f.write(f"{seq},{score:.3f}\n")
EOF

python3 /tmp/generate_data.py

cat << 'EOF' > /tmp/verify.py
import numpy as np
import itertools
import sys

def get_kmers():
    return [''.join(p) for p in itertools.product('ACGT', repeat=3)]

kmers = get_kmers()
kmer_to_idx = {k: i for i, k in enumerate(kmers)}

X = []
y = []

with open('/home/user/binding_data.txt', 'r') as f:
    for line in f:
        seq, score = line.strip().split(',')
        if seq.startswith('ATGCGATCG'):
            trimmed = seq[9:]
            counts = [0] * 64
            for i in range(len(trimmed) - 2):
                kmer = trimmed[i:i+3]
                counts[kmer_to_idx[kmer]] += 1
            X.append(counts)
            y.append(float(score))

X = np.array(X, dtype=float)
y = np.array(y, dtype=float)

# Ridge regression: w = (X^T X + lambda I)^-1 X^T y
lam = 2.0
I = np.eye(64)
w = np.linalg.inv(X.T @ X + lam * I) @ X.T @ y

expected_output = {kmers[i]: f"{w[i]:.4f}" for i in range(64)}

# Now read the agent's output
agent_output = {}
try:
    with open('/home/user/kmer_weights.csv', 'r') as f:
        for line in f:
            if not line.strip(): continue
            k, v = line.strip().split(',')
            agent_output[k] = float(v)
except Exception as e:
    print(f"Failed to read output: {e}")
    sys.exit(1)

# Compare
for k in kmers:
    if k not in agent_output:
        print(f"Missing k-mer in output: {k}")
        sys.exit(1)

    expected_val = float(expected_output[k])
    agent_val = agent_output[k]

    if abs(expected_val - agent_val) > 1e-3:
        print(f"Mismatch for {k}: expected {expected_val}, got {agent_val}")
        sys.exit(1)

print("Pass")
sys.exit(0)
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
