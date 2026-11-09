#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ python3-numpy
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_data.py
import numpy as np
import os

# Set seed for reproducible data generation
np.random.seed(123)

N = 1024
t = np.arange(N)
# Base latency of 15.0ms
# Periodic spike at frequency bin 42
# Random noise
latency = 15.0 + 3.0 * np.sin(2 * np.pi * 42 * t / N) + np.random.normal(0, 1.5, N)

with open("/home/user/perf_trace.txt", "w") as f:
    for val in latency:
        f.write(f"{val:.6f}\n")
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
