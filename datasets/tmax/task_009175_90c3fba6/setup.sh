#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy

    # Create user and home directory
    useradd -m -s /bin/bash user || true

    # Generate initial state data
    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs("/home/user/data", exist_ok=True)
np.random.seed(123)
coords = np.cumsum(np.random.randn(50, 3) * 3.0, axis=0)

with open("/home/user/data/protein.pdb", "w") as f:
    for i, c in enumerate(coords):
        f.write(f"ATOM  {i+1:>5}  CA  ALA A {i+1:>4}    {c[0]:>8.3f}{c[1]:>8.3f}{c[2]:>8.3f}  1.00 20.00           C\n")
EOF
    python3 /tmp/setup.py
    rm /tmp/setup.py

    # Set permissions
    chmod -R 777 /home/user
