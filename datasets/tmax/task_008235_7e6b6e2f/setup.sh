#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libeigen3-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np

np.random.seed(42)
N = 50
A = np.zeros((N, N))
edges = []
for i in range(N):
    for j in range(i+1, N):
        if np.random.rand() < 0.2:
            A[i,j] = A[j,i] = 1
            edges.append((i,j))

D = np.diag(np.sum(A, axis=1))
L = D - A

vals, vecs = np.linalg.eigh(L)
X = vecs[:, 1:3]

true_w = np.array([2.5, -1.5])
y = X @ true_w + np.random.randn(N) * 0.1

with open('/home/user/graph.txt', 'w') as f:
    for u, v in edges:
        f.write(f"{u} {v}\n")

with open('/home/user/y.txt', 'w') as f:
    for val in y:
        f.write(f"{val}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
