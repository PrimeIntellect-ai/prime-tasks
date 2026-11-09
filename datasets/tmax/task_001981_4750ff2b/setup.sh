#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/simulate.py
#!/usr/bin/env python3
import sys
import numpy as np

if len(sys.argv) != 3:
    print("Usage: simulate.py <topology> <dt>")
    sys.exit(1)

topology = sys.argv[1]
dt = float(sys.argv[2])
T = 20.0

N = 5
k = 20.0
m = 1.0

A = np.zeros((N, N))
if topology == 'ring':
    for i in range(N):
        A[i, (i+1)%N] = 1
        A[(i+1)%N, i] = 1
elif topology == 'star':
    for i in range(1, N):
        A[0, i] = 1
        A[i, 0] = 1
else:
    sys.exit(1)

D = np.diag(np.sum(A, axis=1))
L = D - A

pos = np.zeros(N)
vel = np.zeros(N)
pos[0] = 1.0

steps = int(T / dt)
for i in range(steps):
    t = i * dt
    print(f"{t:.4f} " + " ".join(f"{p:.4f}" for p in pos))

    acc = - (k / m) * np.dot(L, pos)
    # Buggy Forward Euler:
    pos = pos + vel * dt
    vel = vel + acc * dt
EOF

    chmod +x /home/user/simulate.py
    chmod -R 777 /home/user
