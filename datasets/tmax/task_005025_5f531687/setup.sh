#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libgsl-dev
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    # Generate the initial dataset
    cat << 'EOF' > /tmp/generate_data.py
import numpy as np

np.random.seed(123)
matrix = np.random.randn(50, 20) * 2.0 + 0.5
# Add a dominant rank-1 component
u = np.linspace(-1, 1, 50)
v = np.sin(np.linspace(0, 3*np.pi, 20))
matrix += np.outer(u, v) * 5.0

with open("/home/user/genomic_signals.txt", "w") as f:
    for row in matrix:
        f.write(" ".join(f"{val:.6f}" for val in row) + "\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
