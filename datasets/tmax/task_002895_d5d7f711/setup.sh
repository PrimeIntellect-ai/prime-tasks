#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang make
    pip3 install pytest numpy pandas

    mkdir -p /home/user

    cat << 'EOF' > /home/user/generate_data.py
import numpy as np

np.random.seed(42)
scores = []
for i in range(10):
    if i in [2, 5, 8]: # high variance bins
        data = np.random.normal(0, 1.0, 100)
    else:
        data = np.random.normal(0, 0.2, 100)
    scores.extend(data.tolist())

with open("/home/user/sequence_scores.txt", "w") as f:
    for s in scores:
        f.write(f"{s:.6f}\n")
EOF
    python3 /home/user/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
