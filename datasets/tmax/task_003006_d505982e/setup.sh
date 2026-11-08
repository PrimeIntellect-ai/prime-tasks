#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data

    cat << 'EOF' > /tmp/setup.py
import os
import json
import numpy as np
import pandas as pd

os.makedirs('/home/user/data', exist_ok=True)

# Generate Time array
dt = 0.01 # 100 Hz sampling rate
time = np.arange(0, 10, dt) # 1000 points

np.random.seed(42)

# Frequencies for each segment
freqs = [5.0, 12.5, 20.0, 35.0]

# Generate spatial data
data = {'time': time}
for i in range(100):
    seg_idx = i // 25
    f = freqs[seg_idx]
    # Signal with dominant freq + some noise and minor harmonics
    signal = np.sin(2 * np.pi * f * time) + 0.2 * np.sin(2 * np.pi * (f*2) * time) + np.random.normal(0, 0.5, len(time))
    data[f'x_{i}'] = signal

df = pd.DataFrame(data)
df.to_csv('/home/user/data/sensor_readings.csv', index=False)

# Create baseline (with slight deviations so differences aren't 0)
baseline = {
    "seg_0": 5.0,
    "seg_1": 12.0,
    "seg_2": 19.5,
    "seg_3": 34.0
}
with open('/home/user/data/baseline.json', 'w') as f:
    json.dump(baseline, f)
EOF

    python3 /tmp/setup.py

    chmod -R 777 /home/user
