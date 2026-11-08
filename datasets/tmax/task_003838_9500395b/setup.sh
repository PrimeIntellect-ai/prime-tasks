#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/solve_mixture.py
import numpy as np

# A, B, C GC-contents
gc_probs = np.array([[0.75, 0.25, 0.25], 
                     [0.25, 0.75, 0.75], 
                     [1.0, 1.0, 1.0]]) # Sum of weights = 1
obs = np.array([0.40, 0.60, 1.0])

try:
    weights = np.linalg.solve(gc_probs, obs)
    print(weights)
except np.linalg.LinAlgError as e:
    print(f"Failed to solve: {e}")
EOF

    chmod +x /home/user/solve_mixture.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
