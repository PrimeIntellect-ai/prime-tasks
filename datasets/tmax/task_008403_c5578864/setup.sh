#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy pandas scipy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup_task.py
import numpy as np
import pandas as pd
import os

def generate_data():
    np.random.seed(42)
    fs = 100.0  # Sample rate 100 Hz
    t = np.arange(0, 10, 1/fs) # 1000 points
    # Frequencies: 5 Hz and 12 Hz
    # Weights: bias=5.0, cos(5Hz)=2.0, sin(5Hz)=-1.5, cos(12Hz)=0.0, sin(12Hz)=3.0
    y = 5.0 + 2.0 * np.cos(2 * np.pi * 5 * t) - 1.5 * np.sin(2 * np.pi * 5 * t) + 3.0 * np.sin(2 * np.pi * 12 * t)
    # Add minor noise
    y += np.random.normal(0, 0.1, len(t))

    df = pd.DataFrame({'t': t, 'y': y})
    df.to_csv('/home/user/sensor_data.csv', index=False)

if __name__ == "__main__":
    generate_data()
EOF

    python3 /tmp/setup_task.py
    rm /tmp/setup_task.py

    chmod -R 777 /home/user
