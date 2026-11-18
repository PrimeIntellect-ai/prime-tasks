#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-h5py python3-numpy python3-scipy gcc
    pip3 install pytest

    mkdir -p /app/bin

    # Create hidden python script that performs the actual logic
    cat << 'EOF' > /app/bin/.hidden_solver.py
import sys
import h5py
import numpy as np

def solve(in_file, out_file):
    with h5py.File(in_file, 'r') as fin, h5py.File(out_file, 'w') as fout:
        for key in fin.keys():
            A = fin[key]['A'][:]
            b = fin[key]['b'][:]
            U, S, Vt = np.linalg.svd(A)
            S_inv = np.zeros_like(S)
            mask = S >= 0.05
            S_inv[mask] = 1.0 / S[mask]
            x = Vt.T @ np.diag(S_inv) @ U.T @ b
            grp = fout.create_group(key)
            grp.create_dataset('x', data=x)

if __name__ == '__main__':
    solve(sys.argv[1], sys.argv[2])
EOF

    # Create C wrapper and compile it as a stripped binary
    cat << 'EOF' > /tmp/solver.c
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "python3 /app/bin/.hidden_solver.py %s %s", argv[1], argv[2]);
    return system(cmd);
}
EOF
    gcc -O2 -s /tmp/solver.c -o /app/bin/legacy_solver
    rm /tmp/solver.c

    useradd -m -s /bin/bash user || true

    # Generate sample inputs
    cat << 'EOF' > /tmp/gen_samples.py
import h5py
import numpy as np

with h5py.File('/home/user/sample_inputs.h5', 'w') as f:
    for i in range(5):
        grp = f.create_group(f"system_{i}")
        U, _ = np.linalg.qr(np.random.randn(15, 15))
        V, _ = np.linalg.qr(np.random.randn(15, 15))
        S = np.diag(np.linspace(0.01, 2.0, 15))
        A = U @ S @ V.T
        b = np.random.randn(15)
        grp.create_dataset("A", data=A)
        grp.create_dataset("b", data=b)
EOF
    python3 /tmp/gen_samples.py
    rm /tmp/gen_samples.py

    chmod -R 777 /home/user
