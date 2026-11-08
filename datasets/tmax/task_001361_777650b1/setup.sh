#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        cmake \
        make \
        wget \
        tar

    pip3 install pytest pandas

    # Download and vendor simdjson v3.6.0
    mkdir -p /app
    wget -qO /tmp/simdjson.tar.gz https://github.com/simdjson/simdjson/archive/refs/tags/v3.6.0.tar.gz
    tar -xzf /tmp/simdjson.tar.gz -C /app
    mv /app/simdjson-3.6.0 /app/simdjson
    rm /tmp/simdjson.tar.gz

    # Perturb the CMakeLists.txt
    sed -i 's/CXX_STANDARD 17/CXX_STANDARD 11/g' /app/simdjson/CMakeLists.txt
    sed -i 's/CXX_STANDARD 20/CXX_STANDARD 11/g' /app/simdjson/CMakeLists.txt
    # Ensure the exact string is present for the test
    echo 'set(CMAKE_CXX_STANDARD 11)' >> /app/simdjson/CMakeLists.txt

    # Setup directories
    mkdir -p /home/user/data
    mkdir -p /home/user/src
    mkdir -p /home/user/bin
    mkdir -p /home/user/output

    # Generate data
    cat << 'EOF' > /tmp/gen_data.py
import json
import csv

server_meta = [
    {"server_id": "srv-01", "tier": "frontend", "max_changes_per_min": 50},
    {"server_id": "srv-02", "tier": "backend", "max_changes_per_min": 30},
    {"server_id": "srv-03", "tier": "db", "max_changes_per_min": 20},
]

with open("/home/user/data/server_meta.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["server_id", "tier", "max_changes_per_min"])
    writer.writeheader()
    writer.writerows(server_meta)

records = []
ground_truth = []

# Window 1: 1700000000
# srv-01: 55 changes (Storm)
for i in range(55):
    records.append({"timestamp": 1700000000 + i, "server_id": "srv-01", "config_key": "k", "new_value": "v"})
ground_truth.append({"server_id": "srv-01", "window_start": 1700000000, "change_count": 55})

# srv-02: 10 changes (No storm)
for i in range(10):
    records.append({"timestamp": 1700000000 + i, "server_id": "srv-02", "config_key": "k", "new_value": "v"})

# Invalid records (should be ignored)
records.append({"timestamp": 1699999999, "server_id": "srv-01", "config_key": "k", "new_value": "v"})
records.append({"timestamp": 1700000010, "server_id": "srv-unknown", "config_key": "k", "new_value": "v"})
records.append({"timestamp": 1700000010, "server_id": "srv-01", "new_value": "v"})

# Window 2: 1700000060
# srv-03: 25 changes (Storm)
for i in range(25):
    records.append({"timestamp": 1700000060 + i, "server_id": "srv-03", "config_key": "k", "new_value": "v"})
ground_truth.append({"server_id": "srv-03", "window_start": 1700000060, "change_count": 25})

with open("/home/user/data/config_changes.jsonl", "w") as f:
    for r in records:
        f.write(json.dumps(r) + "\n")

with open("/tmp/ground_truth.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["server_id", "window_start", "change_count"])
    writer.writeheader()
    writer.writerows(ground_truth)
EOF

    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
