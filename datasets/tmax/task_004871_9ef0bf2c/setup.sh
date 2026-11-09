#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/data.csv
x,weight
0.1,1.5
0.15,-0.2
0.4,3.1
0.45,0.5
0.4,1.1
0.8,2.0
0.82,-1.0
0.9,0.5
EOF

    cat << 'EOF' > /home/user/fit_model.py
import numpy as np
import scipy.linalg
import csv

def assemble_and_solve(N, data_file):
    # Assemble 1D Laplacian
    dx = 1.0 / (N - 1)
    A = np.zeros((N, N))
    for i in range(N):
        A[i, i] = 2.0 / dx
        if i > 0: A[i, i-1] = -1.0 / dx
        if i < N-1: A[i, i+1] = -1.0 / dx
    # Dirichlet BC at boundaries (modify A to keep it symmetric positive definite)
    A[0, 0] = 1.0 / dx; A[0, 1] = 0.0
    A[N-1, N-1] = 1.0 / dx; A[N-1, N-2] = 0.0

    # Read data
    contributions = []
    with open(data_file, 'r') as f:
        reader = csv.reader(f)
        next(reader) # skip header
        for row in reader:
            x, w = float(row[0]), float(row[1])
            idx = int(round(x * (N - 1)))
            contributions.append((idx, w))

    # Bug: using a set for unique indices destroys original order,
    # causing non-deterministic floating point accumulation.
    b = np.zeros(N)
    unique_indices = set([c[0] for c in contributions])
    for idx in unique_indices:
        # Sum all weights for this index
        s = 0.0
        for c_idx, w in contributions:
            if c_idx == idx:
                s += w
        b[idx] = s

    # Generic solve
    x = np.linalg.solve(A, b)
    return A, x

if __name__ == "__main__":
    A, x = assemble_and_solve(15, 'data.csv')
    print("Done.")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
