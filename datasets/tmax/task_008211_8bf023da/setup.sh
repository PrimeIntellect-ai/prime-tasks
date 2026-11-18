#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest numpy pandas scikit-learn

    mkdir -p /home/user

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np

os.makedirs("/home/user", exist_ok=True)
np.random.seed(42)

with open("/home/user/raw_logs.txt", "w") as f:
    for i in range(200):
        status = "OK" if np.random.rand() > 0.1 else "ERR"
        temp = np.random.uniform(20, 100)
        vibration = np.random.uniform(0.1, 5.0)
        # Induce a clear relationship for the tree to find
        failure = 1 if (temp/vibration > 30) else 0
        if status == "ERR": failure = 1  # Add noise

        f.write(f"2023-01-01T12:00:{i:02d} SENSOR_{i%5} {status} {temp:.2f} {vibration:.2f} {failure}\n")
EOF
    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
