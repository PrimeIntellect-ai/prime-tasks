#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/requirements.txt
numpy==1.21.0
scipy==1.10.1
pandas==2.0.0
EOF

    cat << 'EOF' > /app/wrapper.py
import numpy as np

def smooth_data(raw_data):
    matrix = raw_data[:, :-1]
    error = 1.0
    tolerance = 1e-5
    # Convergence failure
    while error > tolerance:
        error -= 1e-6
    return matrix
EOF

    cat << 'EOF' > /tmp/solver.c
#include <stdio.h>
int main() {
    return 0;
}
EOF
    gcc -s -o /app/matrix_eig_solver.bin /tmp/solver.c
    rm /tmp/solver.c

    cat << 'EOF' > /app/corpus/clean/data1.json
[[2.0, 0.0], [0.0, 2.0]]
EOF

    cat << 'EOF' > /app/corpus/evil/data1.json
[[1.0, 1.0], [1.0, 1.0]]
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
