#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest numpy

    mkdir -p /home/user/analysis
    cd /home/user

    cat << 'EOF' > /home/user/setup_data.py
import numpy as np
import csv

np.random.seed(42)

# Generate 20x10 telemetry matrix
A = np.random.rand(20, 10) * 100

# Perform SVD to know the ground truth
U, S, Vt = np.linalg.svd(A, full_matrices=False)
v = Vt[0, :] # First right singular vector

# Transform to distribution P
P = np.abs(v)
P = P / np.sum(P)

# Generate baseline distribution Q
Q = np.random.rand(10)
Q = Q / np.sum(Q)

# Save to CSV
np.savetxt('/home/user/telemetry.csv', A, delimiter=',')
np.savetxt('/home/user/baseline.csv', Q[np.newaxis, :], delimiter=',')

# Compute KL
KL = np.sum(P * np.log(P / Q))
with open('/home/user/expected_kl.txt', 'w') as f:
    f.write(f"{KL:.6f}\n")
EOF

    python3 /home/user/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
