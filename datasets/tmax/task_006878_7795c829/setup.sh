#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_spectrum.py
import numpy as np

np.random.seed(123)
data = np.exp(-np.arange(1000) / 200.0) + np.random.normal(0, 0.1, 1000)
data = np.abs(data) # Ensure positive

with open("/home/user/spectrum.txt", "w") as f:
    for val in data:
        f.write(f"{val:.6f}\n")
EOF

    python3 /home/user/generate_spectrum.py

    chmod -R 777 /home/user
