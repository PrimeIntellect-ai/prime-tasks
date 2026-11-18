#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/generate_data.py
import os
import csv
import random

random.seed(42)
data_path = "/home/user/sensor_data.csv"

# Generate deterministic dirty data
rows = [["Temperature", "Pressure", "Humidity"]]
for i in range(200):
    # Temperature
    if random.random() < 0.1:
        t = "" # missing
    elif random.random() < 0.05:
        t = random.uniform(60, 100) # outlier
    else:
        t = random.uniform(10, 30)

    # Pressure
    if random.random() < 0.1:
        p = ""
    elif random.random() < 0.05:
        p = random.uniform(700, 799) # outlier
    else:
        # Induce slight correlation with temp if valid
        if t != "" and t <= 50:
            p = 900 + (t * 5) + random.uniform(-20, 20)
        else:
            p = random.uniform(950, 1050)

    # Humidity
    if random.random() < 0.15:
        h = ""
    else:
        h = random.uniform(30, 70)

    rows.append([
        round(t, 2) if t != "" else "",
        round(p, 2) if p != "" else "",
        round(h, 2) if h != "" else ""
    ])

with open(data_path, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerows(rows)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    mkdir -p /home/user/etl_pipeline
    chmod -R 777 /home/user
