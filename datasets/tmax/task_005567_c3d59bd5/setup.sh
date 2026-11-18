#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import json
import numpy as np

# Ground truth parameters
A_true = 5.0
k_true = 0.5
np.random.seed(42)

data = []
for _ in range(200):
    t = np.random.uniform(0, 2)
    x = np.random.uniform(0, 1)
    # Clean T
    T = A_true * np.exp(-k_true * t) * np.sin(np.pi * x)
    # Add noise
    T_noisy = T + np.random.normal(0, 0.1)

    data.append({
        "time": float(t),
        "position": float(x),
        "temperature": float(T_noisy)
    })

with open("/home/user/sensor_data.json", "w") as f:
    json.dump(data, f, indent=2)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
