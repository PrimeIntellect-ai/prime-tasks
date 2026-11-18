#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import os
import numpy as np

os.makedirs("/home/user", exist_ok=True)

# Generate a synthetic field with frequency variations
A = np.zeros((256, 256))
for i in range(256):
    for j in range(256):
        A[i,j] = np.sin(i * j / 500.0) + np.cos((i + j) / 20.0)

np.savetxt("/home/user/field_data.csv", A, delimiter=",", fmt="%.6f")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
