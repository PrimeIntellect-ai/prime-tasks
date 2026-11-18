#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ python3-numpy
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/generate_data.py
import numpy as np

np.random.seed(42)
n = 1000
timestamps = np.arange(n)

# Generate true signal
true_signal = np.sin(timestamps * 0.05) * 10 + 20

# Generate reference (very clean, slightly noisy)
reference = true_signal + np.random.normal(0, 0.1, n)

# Generate raw (noisy, missing, outliers)
raw = true_signal + np.random.normal(0, 2.0, n)
# Inject missing
raw[np.random.choice(n, 50, replace=False)] = np.nan
# Inject outliers
raw[np.random.choice(n, 20, replace=False)] += 50.0
raw[np.random.choice(n, 20, replace=False)] -= 50.0

with open('/home/user/reference_sensor.csv', 'w') as f:
    for t, v in zip(timestamps, reference):
        f.write(f"{t},{v:.4f}\n")

with open('/home/user/raw_sensor.csv', 'w') as f:
    for t, v in zip(timestamps, raw):
        if np.isnan(v):
            f.write(f"{t},NaN\n")
        else:
            f.write(f"{t},{v:.4f}\n")
EOF

python3 /home/user/generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
