#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest numpy scipy

    mkdir -p /app

    cat << 'EOF' > /app/.hidden_sim.py
import sys
import numpy as np
import scipy.linalg
import time

def main():
    if len(sys.argv) < 2:
        return
    with open(sys.argv[1], 'r') as f:
        lines = f.read().split()

    if not lines: return
    N = int(lines[0])
    idx = 1
    masses = np.array([float(x) for x in lines[idx:idx+N]])
    idx += N

    A = np.zeros((N, N))
    for i in range(N):
        for j in range(N):
            A[i, j] = float(lines[idx])
            idx += 1

    K = np.zeros((N, N))
    for i in range(N):
        for j in range(N):
            if i != j:
                K[i, j] = -A[i, j]
        K[i, i] = np.sum(A[i, :]) - A[i, i]

    M = np.diag(masses)

    vals = scipy.linalg.eigh(K, M, eigvals_only=True)
    vals = np.maximum(vals, 0)
    freqs = np.sqrt(vals)
    freqs = np.sort(freqs)

    time.sleep(0.5)
    print(" ".join(f"{x:.6f}" for x in freqs))

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /app/wrapper.c
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "python3 /app/.hidden_sim.py %s", argv[1]);
    return system(cmd);
}
EOF

    gcc /app/wrapper.c -o /app/spectro_sim
    strip -s /app/spectro_sim
    rm /app/wrapper.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
