#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    # Generate raw_logs.txt
    cat << 'EOF' > /tmp/generate_logs.py
import os
import numpy as np

# Ground truth data generation
np.random.seed(42)
valid_latencies = np.random.normal(50, 5, 100)

log_lines = []
for i, val in enumerate(valid_latencies):
    log_lines.append(f"[2023-10-12 10:14:{i%60:02d}] GET /api/v1/users | status: 200 | latency_ms: {val:.4f}\n")

# Inject corrupted lines
corruptions = [
    "[2023-10-12 10:15:01] GET /api/v1/users | status: 500 | latency_ms: NaN\n",
    "[2023-10-12 10:15:02] GET /api/v1/users | status: 404 | latency_ms: null\n",
    "[2023-10-12 10:15:03] GET /api/v1/users | status: 200 | latency_ms: \n",
    "[2023-10-12 10:15:04] GET /api/v1/users | status: 200 | latency_ms: corrupted\n"
]
log_lines = log_lines[:20] + corruptions[:2] + log_lines[20:80] + corruptions[2:] + log_lines[80:]

with open('/home/user/raw_logs.txt', 'w') as f:
    f.writelines(log_lines)
EOF

    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    chmod -R 777 /home/user
