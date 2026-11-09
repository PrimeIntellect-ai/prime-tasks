#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv
    pip3 install pytest pandas numpy

    mkdir -p /home/user/data/samples

    cat << 'EOF' > /tmp/setup.py
import os
import numpy as np
import pandas as pd

os.makedirs('/home/user/data/samples', exist_ok=True)
np.random.seed(42)

# Baseline (Normal data around 0,0)
baseline = pd.DataFrame({
    'sensor_x': np.random.normal(0, 1, 1000),
    'sensor_y': np.random.normal(0, 1, 1000)
})
baseline.to_csv('/home/user/data/baseline.csv', index=False)

# Samples
samples = {
    'sample_1.csv': np.random.normal(0, 1, 100),
    'sample_2.csv': np.random.normal(5, 2, 100),
    'sample_3.csv': np.random.normal(0.5, 1, 100),
    'sample_4.csv': np.random.normal(-5, 1.5, 100),
    'sample_5.csv': np.random.normal(-0.2, 0.8, 100)
}

for name, x_vals in samples.items():
    y_vals = np.random.normal(0, 1, 100) if '1' in name or '3' in name or '5' in name else np.random.normal(5, 2, 100)
    df = pd.DataFrame({'sensor_x': x_vals, 'sensor_y': y_vals})
    df.to_csv(f'/home/user/data/samples/{name}', index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
