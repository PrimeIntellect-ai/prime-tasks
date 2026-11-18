#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc
    pip3 install pytest numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import csv
import numpy as np

os.makedirs('/home/user', exist_ok=True)

# Generate train.csv
# 80 rows: 20 rows per fold.
np.random.seed(42)
train_ids = list(range(1, 81))
train_values = np.random.normal(loc=50.0, scale=5.0, size=80)

# Inject anomalies
anomaly_indices = [5, 12, 25, 37, 45, 58, 62, 75]
is_anomaly = [0] * 80
for idx in anomaly_indices:
    is_anomaly[idx] = 1
    # Make them obvious anomalies
    train_values[idx] = train_values[idx] + np.random.choice([-1, 1]) * np.random.uniform(20, 30)

with open('/home/user/train.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'value', 'is_anomaly'])
    for i in range(80):
        writer.writerow([train_ids[i], f"{train_values[i]:.2f}", is_anomaly[i]])

# Generate test.csv
# 40 rows
test_ids = list(range(101, 141))
test_values = np.random.normal(loc=50.0, scale=5.0, size=40)

# Inject some anomalies that should be filtered out
test_anomaly_indices = [3, 15, 22, 38]
for idx in test_anomaly_indices:
    test_values[idx] = test_values[idx] + np.random.choice([-1, 1]) * np.random.uniform(20, 30)

with open('/home/user/test.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'value'])
    for i in range(40):
        writer.writerow([test_ids[i], f"{test_values[i]:.2f}"])
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
