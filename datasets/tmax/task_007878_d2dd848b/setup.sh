#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip r-base
    pip3 install pytest pandas numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import pandas as pd
import numpy as np
import os

np.random.seed(123)
n = 1000
timestamp = pd.date_range("2023-01-01", periods=n, freq="H")
sensor_A = np.sin(np.linspace(0, 20, n)) + np.random.normal(0, 0.1, n)
sensor_B = np.random.normal(50, 5, n)

# Inject missing values into A
missing_idx = np.random.choice(n, 50, replace=False)
sensor_A[missing_idx] = np.nan

# Inject outliers into B
outlier_idx = np.random.choice(n, 10, replace=False)
sensor_B[outlier_idx] = np.random.choice([150, -50], 10)

# target
# Compute target using the ground truth 'clean' sensor_A so that interpolation approaches it
true_A = np.sin(np.linspace(0, 20, n)) + np.random.normal(0, 0.1, n)
target = 2.5 * true_A + 0.5 * sensor_B + np.random.normal(0, 1, n)

df = pd.DataFrame({"timestamp": timestamp, "sensor_A": sensor_A, "sensor_B": sensor_B, "target": target})
df.to_csv("/home/user/sensor_data.csv", index=False)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
