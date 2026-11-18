#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip parallel
    pip3 install pytest

    cat << 'EOF' > /tmp/setup.py
import os
import random
import csv

os.makedirs('/home/user/data_prep', exist_ok=True)

random.seed(42)
raw_path = '/home/user/data_prep/raw_data.csv'
ref_path = '/home/user/data_prep/reference.csv'
expected_anomalies_path = '/home/user/data_prep/expected_anomalies.txt'

raw_data = []
ref_data = []
expected_anomalies = []

for i in range(1, 100001):
    a = random.uniform(1.0, 10.0)
    b = random.uniform(-50.0, 50.0)
    x = random.uniform(0.0, 100.0)
    y = a * x + b

    raw_data.append([i, f"{y:.6f}", f"{a:.6f}", f"{b:.6f}"])

    # Determine anomaly status
    rand_val = random.random()
    if rand_val < 0.0005:
        # Missing from reference entirely (~50 items)
        expected_anomalies.append(i)
    elif rand_val < 0.0010:
        # Altered in reference (diff > 0.01) (~50 items)
        ref_data.append([i, f"{x + random.choice([0.05, -0.05, 0.1, -0.1]):.6f}"])
        expected_anomalies.append(i)
    else:
        # Normal
        ref_data.append([i, f"{x:.6f}"])

expected_anomalies.sort()

with open(raw_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'y', 'a', 'b'])
    writer.writerows(raw_data)

with open(ref_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'x'])
    writer.writerows(ref_data)

# Save ground truth for automated testing
with open(expected_anomalies_path, 'w') as f:
    for anomaly_id in expected_anomalies:
        f.write(f"{anomaly_id}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
