#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential
    pip3 install pytest numpy

    mkdir -p /app
    cd /app
    wget https://github.com/lucasmaystre/svdlibc/archive/refs/heads/master.tar.gz
    tar -xzf master.tar.gz
    mv svdlibc-master svdlibc
    rm master.tar.gz

    # Remove -lm from Makefile to simulate the broken state
    sed -i 's/-lm//g' /app/svdlibc/Makefile

    mkdir -p /home/user/corpora/clean /home/user/corpora/evil
    mkdir -p /hidden/eval/clean /hidden/eval/evil

    # Generate synthetic data
    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
import os

np.random.seed(42)
dim = 50
n_anchors = 10
n_clean = 100
n_evil = 20

anchors = np.random.randn(n_anchors, dim)
np.savetxt("/home/user/corpora/anchors.txt", anchors, fmt="%.6f")

for i in range(5):
    # Clean vectors
    clean = np.random.randn(n_clean, dim) * 5.0
    np.savetxt(f"/home/user/corpora/clean/clean_{i}.csv", clean, fmt="%.6f")
    np.savetxt(f"/hidden/eval/clean/clean_{i}.csv", clean, fmt="%.6f")

    # Evil vectors (close to anchors)
    evil = anchors[np.random.choice(n_anchors, n_evil)] + np.random.randn(n_evil, dim) * 0.1
    np.savetxt(f"/home/user/corpora/evil/evil_{i}.csv", evil, fmt="%.6f")
    np.savetxt(f"/hidden/eval/evil/evil_{i}.csv", evil, fmt="%.6f")
EOF

    python3 /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /hidden /app/svdlibc
