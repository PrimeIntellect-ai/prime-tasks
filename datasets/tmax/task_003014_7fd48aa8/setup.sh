#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import numpy as np
import pandas as pd
import os

np.random.seed(42)
time = np.linspace(0, 100, 101)
P0 = 10
r = 0.05
K = 500
P_true = K / (1 + ((K - P0) / P0) * np.exp(-r * time))
noise = np.random.normal(0, 5, 101)
signal = P_true + noise

# Add some high frequency noise to justify filtering
high_freq = 15 * np.sin(2 * np.pi * 0.4 * time)
signal += high_freq

df = pd.DataFrame({'time': time, 'signal': signal})
df.to_csv('/home/user/probe_signal.csv', index=False)
EOF

    python3 /tmp/setup.py
    chmod -R 777 /home/user
