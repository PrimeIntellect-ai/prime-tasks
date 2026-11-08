#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest numpy

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import os

os.makedirs('/home/user', exist_ok=True)
np.random.seed(42)

inputs = np.random.randn(100, 10).astype(np.float32)
weights = np.random.randn(10, 3).astype(np.float32)
# Reshape bias to (1, 3) so it saves as 1 row with 3 columns
bias = np.random.randn(1, 3).astype(np.float32)

np.savetxt('/home/user/input.csv', inputs, delimiter=',', fmt='%.6f')
np.savetxt('/home/user/weights.csv', weights, delimiter=',', fmt='%.6f')
np.savetxt('/home/user/bias.csv', bias, delimiter=',', fmt='%.6f')

# Ground truth computation
out = np.dot(inputs, weights) + bias
out = np.maximum(out, 0) # ReLU
dist = np.linalg.norm(out - out[0], axis=1)
dist[0] = np.inf # Exclude self
top5 = np.argsort(dist)[:5]

with open('/home/user/expected_top5.txt', 'w') as f:
    for idx in top5:
        f.write(f"{idx}\n")
EOF
    python3 /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
