#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > /home/user/gen_data.py
import csv
import random

random.seed(42)

servers = ["SRV-A", "SRV-B", "SRV-C"]
data = []

for srv in servers:
    base_temp = 70.0 if srv != "SRV-B" else 82.0
    base_lat = 45.0 if srv != "SRV-C" else 120.0

    # 100 records per server
    timestamps = sorted(random.sample(range(1600000000, 1600005000), 100))

    valid_lats = []

    for i, ts in enumerate(timestamps):
        # Generate temp with some spikes
        temp = base_temp + random.uniform(-5, 5)
        if random.random() < 0.1:
            temp += 15.0 # Spike

        # Generate latency
        lat = base_lat + random.uniform(-10, 20)

        # Missing temp (ensure first/last are valid)
        if 0 < i < 99 and random.random() < 0.15:
            temp_str = ""
        else:
            temp_str = f"{temp:.2f}"

        # Missing latency
        if random.random() < 0.1:
            lat_str = ""
        else:
            lat_str = f"{lat:.2f}"
            valid_lats.append(lat)

        data.append({
            "timestamp": ts,
            "server_id": srv,
            "cpu_temp": temp_str,
            "memory_mb": random.randint(2048, 8192),
            "latency_ms": lat_str
        })

# Shuffle data
random.shuffle(data)

with open("/home/user/sensor_logs.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["timestamp", "server_id", "cpu_temp", "memory_mb", "latency_ms"])
    writer.writeheader()
    for row in data:
        writer.writerow(row)
EOF

    python3 /home/user/gen_data.py

    chmod -R 777 /home/user
