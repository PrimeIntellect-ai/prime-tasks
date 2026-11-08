#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import random
import csv

random.seed(123)

os.makedirs('/home/user', exist_ok=True)

# Generate synthetic data: Y = 10.0 + 5.5 * X1 - 2.3 * X2 + noise
data = []
for i in range(1, 101):
    x1 = random.uniform(0, 10)
    x2 = random.uniform(0, 10)
    noise = random.gauss(0, 1)
    y = 10.0 + 5.5 * x1 - 2.3 * x2 + noise
    data.append([i, x1, x2, y])

# Introduce missing values
data[15][3] = '' # Missing Y
data[42][1] = '' # Missing X1
data[77][2] = '' # Missing X2

# Calculate mean and std of Y before outliers (just roughly, to inject outliers)
y_vals = [row[3] for row in data if row[3] != '']
mu = sum(y_vals) / len(y_vals)
std = (sum((y - mu)**2 for y in y_vals) / len(y_vals))**0.5

# Introduce outliers (> 2.0 std)
data[10][3] = mu + 3.5 * std
data[85][3] = mu - 2.8 * std
data[50][3] = mu + 2.1 * std

with open('/home/user/raw_experiment.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['ID', 'X1', 'X2', 'Y'])
    for row in data:
        writer.writerow(row)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chmod -R 777 /home/user
