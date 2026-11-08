#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        libhdf5-dev \
        libopenblas-dev \
        curl \
        build-essential \
        pkg-config

    pip3 install pytest h5py numpy

    export RUSTUP_HOME=/opt/rust
    export CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    chmod -R 777 /opt/rust
    export PATH="/opt/rust/bin:${PATH}"

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > generate_data.py
import h5py
import numpy as np
import random

np.random.seed(42)
random.seed(42)

N = 1000
seq_len = 100

# Generate random sequences
nucleotides = ['A', 'C', 'G', 'T']
sequences = []
for _ in range(N):
    seq = "".join(random.choices(nucleotides, k=seq_len))
    sequences.append(seq.encode('ascii'))

# Create a diagonally dominant 4x4 matrix to ensure it's easily invertible
A = np.random.rand(4, 4)
for i in range(4):
    A[i, i] += 4.0

with h5py.File('raw_data.h5', 'w') as f:
    f.create_dataset('sequences', data=np.array(sequences))
    f.create_dataset('interaction_matrix', data=A)

# Compute expected output for verification
expected_features = []
for seq in sequences:
    seq_str = seq.decode('ascii')
    counts = [seq_str.count(n) for n in nucleotides]
    b = np.array(counts, dtype=np.float64) / seq_len
    x = np.linalg.solve(A, b)
    expected_features.append(x)

expected_features = np.array(expected_features)
means = np.mean(expected_features, axis=0)
with open('expected_means.txt', 'w') as f:
    f.write(",".join(f"{m:.6f}" for m in means))
EOF

    python3 generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
