#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/analyze_primers.py
import numpy as np
import sys
import time

def process_matrix(filepath):
    # Simulate reading primer k-mer frequencies
    X = np.loadtxt(filepath)
    # Compute covariance
    C = X @ X.T

    # The agent needs to replace this Cholesky with SVD
    # L = np.linalg.cholesky(C)
    # return np.sum(L)

    # Original bugged code:
    L = np.linalg.cholesky(C)
    return np.sum(L)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(1)
    # simulate some artificial processing time to make profiling non-zero
    time.sleep(0.01)
    try:
        val = process_matrix(sys.argv[1])
        print(f"Result: {val}")
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
EOF
    chmod +x /home/user/analyze_primers.py

    python3 -c "
import numpy as np
import os
np.random.seed(42)
for i in range(1, 101):
    X = np.random.rand(10, 5)
    np.savetxt(f'/home/user/data/batch_{i}.txt', X)
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
