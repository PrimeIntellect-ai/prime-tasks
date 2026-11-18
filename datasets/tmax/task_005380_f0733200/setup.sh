#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest numpy

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np

# Set seed for reproducibility
np.random.seed(42)

# Generate train data: Normal distribution N(0, 1)
train_data = np.random.normal(0, 1, 1000)

# Generate val data: Normal distribution N(0.1, 1) - slight shift
val_data = np.random.normal(0.1, 1, 800)

with open('/home/user/train_data.txt', 'w') as f:
    for val in train_data:
        f.write(f"{val:.6f}\n")

with open('/home/user/val_data.txt', 'w') as f:
    for val in val_data:
        f.write(f"{val:.6f}\n")
EOF

    python3 /home/user/generate_data.py
    rm /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
