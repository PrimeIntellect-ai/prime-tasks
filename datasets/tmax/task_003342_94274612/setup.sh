#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import csv
import numpy as np
import json
import os

os.makedirs('/home/user/etl', exist_ok=True)

np.random.seed(42)
timestamps = np.arange(1, 101)
values = 2.5 * timestamps + 10 + np.random.normal(0, 5, 100)

# Inject anomalies
values[20] = 500.0  # index 20 -> t=21
values[75] = -400.0 # index 75 -> t=76

with open('/home/user/sensor_data.csv', 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'value'])
    for t, v in zip(timestamps, values):
        writer.writerow([t, v])

# Calculate ground truth
mean_v = np.mean(values)
std_v = np.std(values) # Population standard deviation

anomalies = []
normal_t = []
normal_v = []

for t, v in zip(timestamps, values):
    if abs(v - mean_v) > 2 * std_v:
        anomalies.append((t, v))
    else:
        normal_t.append(t)
        normal_v.append(v)

# Write expected anomalies file (for verification)
with open('/home/user/expected_anomalies.csv', 'w') as f:
    writer = csv.writer(f)
    writer.writerow(['timestamp', 'value'])
    for t, v in anomalies:
        writer.writerow([t, v])

# Calculate linear regression on normal data
normal_t = np.array(normal_t)
normal_v = np.array(normal_v)

slope = np.sum((normal_t - np.mean(normal_t)) * (normal_v - np.mean(normal_v))) / np.sum((normal_t - np.mean(normal_t))**2)
intercept = np.mean(normal_v) - slope * np.mean(normal_t)

with open('/home/user/expected_regression.json', 'w') as f:
    json.dump({"slope": slope, "intercept": intercept}, f)

EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
