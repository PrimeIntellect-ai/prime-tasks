#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv python3-numpy
    pip3 install pytest

    mkdir -p /home/user/data/candidates

    cat << 'EOF' > /tmp/setup_data.py
import numpy as np
import os

np.random.seed(42)
n_points = 1000
x = np.linspace(0, 100, n_points) + np.random.normal(0, 0.1, n_points)

# Reference data
with open('/home/user/data/reference.txt', 'w') as f:
    for val in x:
        f.write(f"{val}\n")

# Candidate A (m=1.05, c=0.2)
y_a = 1.05 * x + 0.2 + np.random.normal(0, 0.01, n_points)
# Candidate B (m=0.98, c=-0.1)
y_b = 0.98 * x - 0.1 + np.random.normal(0, 0.01, n_points)
# Candidate C (m=1.002, c=0.005) - BEST MATCH
y_c = 1.002 * x + 0.005 + np.random.normal(0, 0.01, n_points)
# Candidate D (m=1.0, c=1.5)
y_d = 1.0 * x + 1.5 + np.random.normal(0, 0.01, n_points)

candidates = {'run_alpha.txt': y_a, 'run_beta.txt': y_b, 'run_gamma.txt': y_c, 'run_delta.txt': y_d}

for name, y in candidates.items():
    with open(f'/home/user/data/candidates/{name}', 'w') as f:
        for val in y:
            f.write(f"{val}\n")
EOF
    python3 /tmp/setup_data.py
    rm /tmp/setup_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
