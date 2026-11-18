#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/factorize.py
#!/usr/bin/env python3
import sys
import numpy as np
import scipy.linalg

if len(sys.argv) != 2:
    print("Usage: factorize.py <seed>")
    sys.exit(1)

seed = int(sys.argv[1])
np.random.seed(seed)

# Generate a 50x50 matrix
A = np.random.randn(50, 50)

# Introduce near-singular matrices deterministically based on seed
if seed % 7 == 0:
    A[1] = A[0] + np.random.randn(50) * 1e-14

cond = np.linalg.cond(A)

try:
    # Artificially enforce failure for high condition numbers to simulate the scenario
    if cond > 1e11:
        raise scipy.linalg.LinAlgError("Singular matrix")
    P, L, U = scipy.linalg.lu(A)
    print(f"SUCCESS {cond}")
except scipy.linalg.LinAlgError:
    print(f"FAIL {cond}")
EOF

    chmod +x /home/user/factorize.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
