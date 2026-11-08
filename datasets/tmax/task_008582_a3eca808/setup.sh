#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy

    mkdir -p /home/user/data
    mkdir -p /home/user/analysis

    cat << 'EOF' > /home/user/setup.py
import numpy as np
import os

np.random.seed(42)
A = np.random.rand(50, 50)
np.random.seed(43)
B = np.random.rand(50, 50) + 0.5 * np.eye(50)

np.savetxt('/home/user/data/matrix_A.csv', A, delimiter=',')
np.savetxt('/home/user/data/matrix_B.csv', B, delimiter=',')

uA, sA, vhA = np.linalg.svd(A)
uB, sB, vhB = np.linalg.svd(B)

P = sA / np.sum(sA)
Q = sB / np.sum(sB)

kl_P_Q = np.sum(P * np.log(P / Q))
kl_Q_P = np.sum(Q * np.log(Q / P))
sym_kl = kl_P_Q + kl_Q_P

with open('/home/user/expected_divergence.log', 'w') as f:
    f.write(f"Symmetric KL: {sym_kl:.4f}\n")

with open('/home/user/expected_plot.txt', 'w') as f:
    for i in range(5):
        stars = '*' * int(sA[i])
        f.write(f"Index {i}: {stars}\n")
EOF

    python3 /home/user/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
