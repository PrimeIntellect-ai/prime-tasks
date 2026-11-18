#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc sed
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_dataset.py
import os
import numpy as np

# Set random seed for reproducibility
np.random.seed(42)

# Generate dataset
X = np.linspace(1, 100, 100)
noise = np.random.normal(0, 5, 100)
Y = 3.5 * X + 10 + noise

# Write dataset.csv
csv_path = "/home/user/dataset.csv"
with open(csv_path, "w") as f:
    f.write("Feature_X,Target_Y\n")
    for x, y in zip(X, Y):
        f.write(f"{x:.4f},{y:.4f}\n")
EOF

    python3 /tmp/generate_dataset.py
    rm /tmp/generate_dataset.py

    chmod -R 777 /home/user
