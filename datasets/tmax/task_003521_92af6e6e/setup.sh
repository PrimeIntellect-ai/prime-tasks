#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import random
import math

random.seed(42)

def generate_data(filename, start_ts, end_ts, base_temp, missing_prob=0.1, drift_factor=0.0):
    with open(filename, 'w') as f:
        f.write("timestamp,temperature\n")
        ts = start_ts
        while ts < end_ts:
            if random.random() > missing_prob:
                temp = base_temp + math.sin(ts / 3600.0) * 5.0 + random.uniform(-0.5, 0.5)
                temp += (ts - start_ts) * drift_factor
                f.write(f"{ts},{temp:.2f}\n")
            ts += int(random.expovariate(1.0 / 120.0))

generate_data('/home/user/sensor_a.csv', 1600000000, 1600086400, 20.0, 0.2, 0.0)
generate_data('/home/user/sensor_b.csv', 1600001000, 1600086000, 20.0, 0.3, 0.0001)
EOF

    python3 /tmp/generate_data.py

    chmod -R 777 /home/user
