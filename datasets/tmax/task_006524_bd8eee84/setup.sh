#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import random

random.seed(42)
start_ts = 1700000000
end_ts = 1700003600 # 1 hour

raw_file = "/home/user/raw_sensors.csv"

# Generate data
data = []
for ts in range(start_ts, end_ts):
    # random chance to skip generating any data for this second
    if random.random() < 0.2:
        continue

    for s_id in range(1, 6):
        # 10% chance to drop sensor for this second
        if random.random() < 0.1:
            continue

        # Value base
        val = 20.0 + (s_id * 5.0) + random.uniform(-2.0, 2.0)

        # 2% chance for out of bounds
        if random.random() < 0.02:
            val = random.choice([-100.0, 200.0])

        data.append((ts, s_id, val))

        # 5% chance for exact duplicate timestamp
        if random.random() < 0.05:
            data.append((ts, s_id, val + random.uniform(-1, 1)))

data.sort(key=lambda x: x[0])

os.makedirs("/home/user", exist_ok=True)
with open(raw_file, "w") as f:
    for row in data:
        f.write(f"{row[0]},{row[1]},{row[2]:.4f}\n")

# Compute Truth
valid_data = []
last_ts_per_sensor = {1:-1, 2:-1, 3:-1, 4:-1, 5:-1}

for r in data:
    ts, s_id, val = r
    if val < -50.0 or val > 150.0:
        continue
    if ts == last_ts_per_sensor[s_id]:
        continue
    last_ts_per_sensor[s_id] = ts
    valid_data.append((ts, s_id, val))

buckets = {}
global_min = min(r[0] for r in valid_data) // 60 * 60
global_max = max(r[0] for r in valid_data) // 60 * 60

for r in valid_data:
    ts, s_id, val = r
    b_ts = (ts // 60) * 60
    if b_ts not in buckets:
        buckets[b_ts] = {1:[], 2:[], 3:[], 4:[], 5:[]}
    buckets[b_ts][s_id].append(val)

last_val = {1: -999.0, 2: -999.0, 3: -999.0, 4: -999.0, 5: -999.0}

truth_file = "/home/user/expected_processed.csv"
with open(truth_file, "w") as f:
    for b_ts in range(global_min, global_max + 60, 60):
        for s_id in range(1, 6):
            if b_ts in buckets and len(buckets[b_ts][s_id]) > 0:
                avg = sum(buckets[b_ts][s_id]) / len(buckets[b_ts][s_id])
                last_val[s_id] = avg
            f.write(f"{b_ts},{s_id},{last_val[s_id]:.2f}\n")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
