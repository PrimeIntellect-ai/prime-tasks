#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

# Set seed for reproducibility and generate synthetic TFBS data
np.random.seed(42)
# Bimodal distribution simulating two highly active transcription regions
positions = np.concatenate([
    np.random.normal(20000, 5000, 300), 
    np.random.normal(70000, 8000, 200)
])

# Write to file
with open("/home/user/tfbs_positions.txt", "w") as f:
    for p in positions:
        f.write(f"{int(p)}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
