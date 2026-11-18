#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/generate_csvs.py
import os
import random

random.seed(42)

# endpoint_id: (baseline_mean, candidate_mean, stddev)
endpoints = {
    1: (100.0, 101.0, 5.0),   # Not degraded (Z < 2.58)
    2: (50.0, 65.0, 4.0),     # Degraded (High Z)
    3: (200.0, 190.0, 10.0),  # Improved
    4: (120.0, 126.0, 8.0),   # Degraded (Z = (6) / sqrt(64/100 + 64/100) = 6 / 1.13 = 5.3)
    5: (300.0, 302.0, 20.0)   # Not degraded
}

def generate_csv(filename, is_candidate):
    with open(filename, 'w') as f:
        f.write("endpoint_id,run_id,cpu_time_ms,mem_usage_mb,disk_io_kb\n")
        for ep, (b_mean, c_mean, stddev) in endpoints.items():
            mean = c_mean if is_candidate else b_mean
            for run_id in range(1, 101):
                cpu = max(1.0, random.gauss(mean, stddev))
                mem = random.uniform(100.0, 500.0)
                io = random.uniform(0.0, 50.0)
                f.write(f"{ep},{run_id},{cpu:.2f},{mem:.2f},{io:.2f}\n")

generate_csv('/home/user/baseline.csv', is_candidate=False)
generate_csv('/home/user/candidate.csv', is_candidate=True)
EOF

    python3 /tmp/generate_csvs.py
    rm /tmp/generate_csvs.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
