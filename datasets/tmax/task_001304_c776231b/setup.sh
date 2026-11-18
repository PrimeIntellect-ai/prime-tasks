#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_log.py
import os
import numpy as np

# Ground truth parameters
np.random.seed(42)
TRUE_MU1 = 20.0
TRUE_MU2 = 80.0
W1, W2 = 0.7, 0.3
SIGMA1, SIGMA2 = 5.0, 10.0

# Generate 500 valid latency points
n_valid = 500
latencies = []
for _ in range(n_valid):
    if np.random.rand() < W1:
        latencies.append(np.random.normal(TRUE_MU1, SIGMA1))
    else:
        latencies.append(np.random.normal(TRUE_MU2, SIGMA2))

# Generate the log file
log_path = '/home/user/raw_latency.log'
with open(log_path, 'w') as f:
    valid_idx = 0
    for i in range(1000):
        # Sprinkle in some noise, errors, and different endpoints
        if i % 2 == 0 and valid_idx < n_valid:
            # Valid entry
            f.write(f"[2023-10-24T10:00:00Z] INFO - RequestID: {i} | Status: 200 | Latency: {latencies[valid_idx]:.2f}ms | Endpoint: /api/v1/data\n")
            valid_idx += 1
        elif i % 5 == 0:
            # 500 error
            f.write(f"[2023-10-24T10:00:01Z] ERROR - RequestID: {i} | Status: 500 | Latency: 120.5ms | Endpoint: /api/v1/data\n")
        else:
            # Wrong endpoint
            f.write(f"[2023-10-24T10:00:02Z] INFO - RequestID: {i} | Status: 200 | Latency: 15.0ms | Endpoint: /api/v2/health\n")
EOF

    python3 /tmp/generate_log.py
    rm /tmp/generate_log.py

    chmod -R 777 /home/user
