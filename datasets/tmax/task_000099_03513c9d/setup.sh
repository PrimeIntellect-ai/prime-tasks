#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential
    pip3 install pytest numpy

    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/opt/cargo/bin:$PATH"
    chmod -R 777 /opt/rustup /opt/cargo

    mkdir -p /home/user/data/reference
    mkdir -p /home/user/data/simulation

    cat << 'EOF' > /home/user/data/generate.py
import numpy as np
import csv
import os

np.random.seed(123)
t = np.linspace(0, 1, 1000, endpoint=False)

# Reference data: 50 Hz + noise
for i in range(100):
    freq = np.random.normal(50, 2)
    amp = np.sin(2 * np.pi * freq * t) + np.random.normal(0, 0.5, 1000)
    with open(f"/home/user/data/reference/ref_{i}.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["time", "amplitude"])
        for j in range(1000):
            writer.writerow([t[j], amp[j]])

# Simulation data: 50 Hz + occasional 200 Hz artifacts
for i in range(100):
    freq = np.random.normal(50, 2)
    amp = np.sin(2 * np.pi * freq * t) + np.random.normal(0, 0.5, 1000)
    if np.random.rand() < 0.2:
        amp += 2.0 * np.sin(2 * np.pi * 200 * t)  # Strong artifact
    with open(f"/home/user/data/simulation/sim_{i}.csv", "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["time", "amplitude"])
        for j in range(1000):
            writer.writerow([t[j], amp[j]])
EOF

    python3 /home/user/data/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
