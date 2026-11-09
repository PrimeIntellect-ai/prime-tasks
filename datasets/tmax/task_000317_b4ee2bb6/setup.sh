#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random

random.seed(42)

log_path = '/home/user/raw_metrics.log'
records = []

# Base timestamp
t = 1700000000

# Generate records
for i in range(1000):
    timestamp = t + random.randint(0, 300)
    metric_code = random.choice([1, 2, 3])
    if metric_code == 1:
        value = random.uniform(10.0, 99.9)
    elif metric_code == 2:
        value = random.uniform(500.0, 8000.0)
    else:
        value = random.uniform(0.0, 1500.0)

    # Randomly drop some disk metrics to test the 0.00 default requirement
    if metric_code == 3 and random.random() < 0.2:
        continue

    records.append((timestamp, metric_code, value))

# Shuffle so they are interleaved and unsorted
random.shuffle(records)

with open(log_path, 'w') as f:
    for r in records:
        f.write(f"{r[0]} {r[1]} {r[2]:.4f}\n")

# Compute truth
buckets = {}
for r in records:
    b = r[0] - (r[0] % 60)
    if b not in buckets:
        buckets[b] = {1: 0.0, 2: 0.0, 3: 0.0}
    if r[2] > buckets[b][r[1]]:
        buckets[b][r[1]] = r[2]

truth_path = '/home/user/expected_aggregated.csv'
with open(truth_path, 'w') as f:
    for b in sorted(buckets.keys()):
        f.write(f"{b},{buckets[b][1]:.2f},{buckets[b][2]:.2f},{buckets[b][3]:.2f}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
